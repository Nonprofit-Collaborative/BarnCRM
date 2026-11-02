/**
 * The chunks of an NPSP household adoption run, and of its undo (X-05, canonical model R-HA3
 * and R-HA4, ADR-NEXT). Started only by `NpspHouseholdAdoptionService`, which has counted,
 * confirmed and checked the permission.
 *
 * Adopt: the candidates are selected as the person who started the run (user mode), at most
 * the confirmed number, in Id order. Each chunk skips an Account the person cannot edit, writes
 * the record type and the four household fields in system mode through `HouseholdWriter`
 * (ADR-0141), writes one journal row per Account saved in the same savepoint, then runs
 * household upkeep on the adopted households. No NPSP field is written.
 *
 * Undo: reads the run's rows still Adopted and puts each Account back, when it still exists,
 * is still a Household and the person can edit it; every row ends Undone or Not Restored.
 *
 * The finish writes one Info entry to the Error Log with the counts.
 */
public with sharing class NpspHouseholdAdoptionBatch implements Database.Batchable<SObject>, Database.Stateful {
    /** Accounts per chunk: one read, one write, one journal insert and their upkeep. */
    public static final Integer CHUNK_SIZE = 100;

    /** The four BarnCRM fields an adoption sets and an undo puts back, and no others. */
    @TestVisible
    private static final List<String> SAVED_FIELDS = new List<String>{
        'Custom_Name__c',
        'Household_Formal_Greeting__c',
        'Household_Informal_Greeting__c',
        'Primary_Contact__c'
    };

    private final String runId;
    private final Boolean undoing;
    private final Boolean keepNames;
    private final Integer runLimit;

    private Integer done = 0;
    private Integer skipped = 0;
    private Integer refused = 0;

    private NpspHouseholdAdoptionBatch(
        String runId,
        Boolean undoing,
        Boolean keepNames,
        Integer runLimit
    ) {
        this.runId = runId;
        this.undoing = undoing;
        this.keepNames = keepNames;
        this.runLimit = runLimit;
    }

    public static NpspHouseholdAdoptionBatch adopt(
        String runId,
        Boolean keepNames,
        Integer limitTo
    ) {
        return new NpspHouseholdAdoptionBatch(runId, false, keepNames, limitTo);
    }

    public static NpspHouseholdAdoptionBatch undo(String runId) {
        return new NpspHouseholdAdoptionBatch(runId, true, false, null);
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        if (undoing) {
            return Database.getQueryLocatorWithBinds(
                'SELECT Id, Account_Id__c, Previous_Record_Type_Id__c, Previous_Values__c ' +
                    'FROM Household_Adoption__c WHERE Run_Id__c = :runId AND Status__c = :adopted ' +
                    'ORDER BY Id',
                new Map<String, Object>{
                    'runId' => runId,
                    'adopted' => NpspHouseholdAdoptionService.STATUS_ADOPTED
                },
                AccessLevel.SYSTEM_MODE
            );
        }
        NpspHouseholdSource source = NpspHouseholdSource.get();
        String condition = source.available() ? source.condition() : '';
        if (String.isBlank(condition)) {
            return Database.getQueryLocatorWithBinds(
                'SELECT Id FROM Account WHERE Id = NULL',
                new Map<String, Object>(),
                AccessLevel.USER_MODE
            );
        }
        Map<String, Object> binds = new Map<String, Object>(source.binds());
        binds.put('runLimit', runLimit);
        return Database.getQueryLocatorWithBinds(
            'SELECT Id FROM Account WHERE ' + condition + ' ORDER BY Id LIMIT :runLimit',
            binds,
            AccessLevel.USER_MODE
        );
    }

    public void execute(Database.BatchableContext context, List<SObject> scope) {
        if (undoing) {
            undoChunk((List<Household_Adoption__c>) scope);
        } else {
            adoptChunk(new Map<Id, SObject>(scope).keySet());
        }
    }

    private void adoptChunk(Set<Id> scopeIds) {
        Id household = HouseholdService.householdRecordTypeId();
        Set<Id> editable = HouseholdSelector.getEditableIds(scopeIds);
        skipped += scopeIds.size() - editable.size();
        List<NpspHouseholdSource.Household> sources = NpspHouseholdSource.get().read(editable);

        Set<Id> primaryIds = new Set<Id>();
        for (NpspHouseholdSource.Household source : sources) {
            primaryIds.add(source.primaryContactId);
        }
        primaryIds.remove(null);
        Map<Id, Contact> primaries = new Map<Id, Contact>(
            [SELECT Id, AccountId FROM Contact WHERE Id IN :primaryIds WITH SYSTEM_MODE]
        );
        Map<Id, Account> before = new Map<Id, Account>(
            [
                SELECT
                    Id,
                    RecordTypeId,
                    Custom_Name__c,
                    Household_Formal_Greeting__c,
                    Household_Informal_Greeting__c,
                    Primary_Contact__c
                FROM Account
                WHERE Id IN :editable
                WITH SYSTEM_MODE
            ]
        );

        List<Account> changes = new List<Account>();
        Map<Id, Household_Adoption__c> journal = new Map<Id, Household_Adoption__c>();
        for (NpspHouseholdSource.Household source : sources) {
            Account previous = before.get(source.accountId);
            if (previous == null || previous.RecordTypeId == household) {
                continue;
            }
            Contact primary = primaries.get(source.primaryContactId);
            Account change = new Account(
                Id = source.accountId,
                RecordTypeId = household,
                Custom_Name__c = keepNames || source.customNaming,
                Household_Formal_Greeting__c = source.formalGreeting,
                Household_Informal_Greeting__c = source.informalGreeting,
                Primary_Contact__c = primary != null &&
                    primary.AccountId == source.accountId
                    ? primary.Id
                    : null
            );
            changes.add(change);
            journal.put(
                source.accountId,
                new Household_Adoption__c(
                    Account_Id__c = source.accountId,
                    Run_Id__c = runId,
                    Previous_Record_Type_Id__c = previous.RecordTypeId,
                    Previous_Values__c = JSON.serialize(savedValues(previous)),
                    Status__c = NpspHouseholdAdoptionService.STATUS_ADOPTED
                )
            );
        }
        if (changes.isEmpty()) {
            return;
        }

        Savepoint savepoint = Database.setSavepoint();
        Map<Id, String> refusals = HouseholdWriter.saveAdoptionChanges(changes);
        for (Id refusedId : refusals.keySet()) {
            journal.remove(refusedId);
        }
        try {
            if (!journal.isEmpty()) {
                Database.insert(journal.values(), true, AccessLevel.SYSTEM_MODE);
            }
        } catch (DmlException e) {
            // An Account is never left adopted without the row that undoes it.
            Database.rollback(savepoint);
            ErrorLogger.log(e, Label.Core_NpspAdoption_ErrorContext);
            refused += changes.size();
            return;
        }
        refused += refusals.size();
        done += journal.size();
        HouseholdService.afterMembershipChange(journal.keySet(), false);
    }

    private void undoChunk(List<Household_Adoption__c> rows) {
        Id household = HouseholdService.householdRecordTypeId();
        Set<Id> accountIds = new Set<Id>();
        for (Household_Adoption__c row : rows) {
            if (String.isNotBlank(row.Account_Id__c)) {
                accountIds.add(Id.valueOf(row.Account_Id__c));
            }
        }
        accountIds.remove(null);
        Map<Id, Account> current = new Map<Id, Account>(
            [SELECT Id, RecordTypeId FROM Account WHERE Id IN :accountIds WITH SYSTEM_MODE]
        );
        Set<Id> editable = HouseholdSelector.getEditableIds(accountIds);

        List<Account> restores = new List<Account>();
        Map<Id, Household_Adoption__c> rowByAccount = new Map<Id, Household_Adoption__c>();
        for (Household_Adoption__c row : rows) {
            Account account = String.isBlank(row.Account_Id__c)
                ? null
                : current.get(Id.valueOf(row.Account_Id__c));
            String note;
            if (account == null) {
                note = Label.Core_NpspAdoption_NoteGone;
            } else if (account.RecordTypeId != household) {
                note = Label.Core_NpspAdoption_NoteNotHousehold;
            } else if (!editable.contains(account.Id)) {
                note = Label.Core_NpspAdoption_NoteNoAccess;
            }
            if (note != null) {
                notRestored(row, note);
                continue;
            }
            restores.add(restoreOf(row));
            rowByAccount.put(account.Id, row);
        }
        Map<Id, String> refusals = HouseholdWriter.saveAdoptionChanges(restores);
        for (Id accountId : rowByAccount.keySet()) {
            Household_Adoption__c row = rowByAccount.get(accountId);
            if (refusals.containsKey(accountId)) {
                notRestored(
                    row,
                    String.format(
                        Label.Core_NpspAdoption_NoteRefused,
                        new List<Object>{ refusals.get(accountId) }
                    )
                );
            } else {
                row.Status__c = NpspHouseholdAdoptionService.STATUS_UNDONE;
                row.Note__c = null;
                done++;
            }
        }
        Database.update(rows, false, AccessLevel.SYSTEM_MODE);
    }

    private void notRestored(Household_Adoption__c row, String note) {
        row.Status__c = NpspHouseholdAdoptionService.STATUS_NOT_RESTORED;
        row.Note__c = note == null ? null : note.left(255);
        refused++;
    }

    /** The Account as it was before adoption: its record type and the four saved fields. */
    @TestVisible
    private static Account restoreOf(Household_Adoption__c row) {
        Account restore = new Account(Id = Id.valueOf(row.Account_Id__c));
        restore.RecordTypeId = String.isBlank(row.Previous_Record_Type_Id__c)
            ? null
            : Id.valueOf(row.Previous_Record_Type_Id__c);
        Map<String, Object> values = String.isBlank(row.Previous_Values__c)
            ? new Map<String, Object>()
            : (Map<String, Object>) JSON.deserializeUntyped(row.Previous_Values__c);
        restore.Custom_Name__c = values.get('Custom_Name__c') == true;
        restore.Household_Formal_Greeting__c = (String) values.get('Household_Formal_Greeting__c');
        restore.Household_Informal_Greeting__c = (String) values.get(
            'Household_Informal_Greeting__c'
        );
        String primary = (String) values.get('Primary_Contact__c');
        restore.Primary_Contact__c = String.isBlank(primary) ? null : Id.valueOf(primary);
        return restore;
    }

    private static Map<String, Object> savedValues(Account previous) {
        Map<String, Object> values = new Map<String, Object>();
        for (String field : SAVED_FIELDS) {
            values.put(field, previous.get(field));
        }
        return values;
    }

    public void finish(Database.BatchableContext context) {
        String summary = undoing
            ? String.format(Label.Core_NpspAdoption_UndoSummary, new List<Object>{ done, refused })
            : String.format(
                  Label.Core_NpspAdoption_RunSummary,
                  new List<Object>{ done, skipped, refused }
              );
        ErrorLogger.logMessage(
            summary,
            Label.Core_NpspAdoption_ErrorContext,
            ErrorLogger.SEVERITY_INFO
        );
    }
}
