/**
 * The one place package owned household bookkeeping is saved.
 *
 * ADR-0021 (system mode writes for package owned data) is the authority for this class and
 * names it as one of its writers. The household name, the two greetings and the member
 * count are computed by the package: no person types them, and no screen offers them for
 * editing. A staff user saving a contact must not need edit access on them, and an org's
 * own profile, an integration user or a data loader user cannot be given that access by a
 * packaged permission set at all. Writing them with the running user's access therefore
 * turns an ordinary contact save into a raw DML error, which is the failure this class
 * exists to prevent, so these writes run in `AccessLevel.SYSTEM_MODE`.
 *
 * This class is deliberately `with sharing` where ADR-0021 says `without sharing`, and the
 * ADR allows a writer to narrow it: household upkeep never needs to cross sharing, and it
 * must not create, rename or delete a household the running user cannot see, so the
 * narrower declaration is the correct one here.
 *
 * The exception is kept narrow in every other way too:
 *
 * - Only these fields are written here, and only on the Household record type.
 * - No value written here comes from user input: every one is computed by
 *   HouseholdNamingService or counted by HouseholdService. The one exception is
 *   createHouseholdsForUser, a household a person asked for, which exists because no user is
 *   given the Household record type (ADR-0141); it checks the access user mode would
 *   have checked before it saves anything.
 * - Deleting an emptied household, and removing or restoring a membership row, are NOT
 *   covered by the exception: those remove or bring back a record rather than compute a
 *   value, so they run with the user's own access and are logged rather than thrown when
 *   they are refused.
 * - Everything a person types (a contact, a membership row, a move) is saved elsewhere in
 *   user mode, and everything a screen reads is read in user mode.
 */
public with sharing class HouseholdWriter {
    /**
     * Test seam: true sends each new household with a name one character too long for the
     * field, which the platform refuses. A test cannot add a validation rule, and every
     * computed value now fits its field, so this is how a test reaches a refused household
     * creation (R-C1).
     */
    @TestVisible
    private static Boolean refuseCreatesForTest = false;

    /**
     * Creates households the package is making on the user's behalf and returns one save
     * result per household, in the same order.
     *
     * The whole result comes back rather than just the ids, because a household that could
     * not be created leaves a person with no household (R-C1), and only the caller knows
     * which person each row was for. The failure is logged here so that an administrator
     * can find it; the caller puts it on the person's own save so that whoever saved them
     * sees it too.
     *
     * Saved past the org's Account duplicate rules (`allowSave`). A household is made by the
     * package, named from its members, so two families called Garcia are two households that
     * look alike, not a duplicate somebody typed. A blocking Account rule would otherwise refuse
     * the household and, with it, the ordinary save of the person it was for. A rule that
     * reports still reports, and BarnCRM's own duplicate review finds them as for any account.
     */
    public static List<Database.SaveResult> createHouseholds(List<Account> households) {
        if (households == null || households.isEmpty()) {
            return new List<Database.SaveResult>();
        }
        return insertHouseholds(households, householdSaveOptions());
    }

    /**
     * The package's own bookkeeping on a household: computed, never typed, so a person creating
     * a household is not asked for field access on them (see the class header).
     */
    private static final Set<Schema.SObjectField> BOOKKEEPING_FIELDS = new Set<Schema.SObjectField>{
        Account.RecordTypeId,
        Account.Custom_Name__c,
        Account.Member_Count__c,
        Account.Household_Formal_Greeting__c,
        Account.Household_Informal_Greeting__c
    };

    /**
     * Creates households a person asked for: New Household on BarnCRM Home, a split into a new
     * household, sample data, and an import of accounts of the Household record type.
     *
     * No user is given the Household record type (ADR-0141), so the platform refuses
     * a user mode insert of one. These inserts therefore run in system mode, and the checks user
     * mode would have made are made here instead, before anything is saved. The running user
     * must be able to create and edit accounts, must be able to create every field set on the
     * records other than the package's bookkeeping fields, and must have edit access to every
     * existing household in `touchedHouseholdIds` (the households the same change edits, such
     * as the one a split takes people out of). Otherwise a HouseholdException is thrown and
     * nothing is created.
     *
     * Every record is of the Household record type: one with no record type is given it, and
     * one of another record type is refused. Answers one save result per record, in order.
     */
    public static List<Database.SaveResult> createHouseholdsForUser(
        List<Account> households,
        Set<Id> touchedHouseholdIds
    ) {
        return createHouseholdsForUser(households, touchedHouseholdIds, householdSaveOptions());
    }

    /** The same, saved with the caller's options (an import's duplicate rules, all or none). */
    public static List<Database.SaveResult> createHouseholdsForUser(
        List<Account> households,
        Set<Id> touchedHouseholdIds,
        Database.DMLOptions options
    ) {
        if (households == null || households.isEmpty()) {
            return new List<Database.SaveResult>();
        }
        checkCreateAccess(households, touchedHouseholdIds);
        return insertHouseholds(households, options);
    }

    /**
     * True when the running user passes the object checks of createHouseholdsForUser (create
     * and edit on Account) and the org has the Household record type, so a New Household
     * button can be offered.
     */
    public static Boolean canCreateHouseholds() {
        Schema.DescribeSObjectResult account = Schema.SObjectType.Account;
        return account.isCreateable() &&
            account.isUpdateable() &&
            HouseholdService.householdRecordTypeId() != null;
    }

    private static void checkCreateAccess(List<Account> households, Set<Id> touchedHouseholdIds) {
        Id recordTypeId = HouseholdService.householdRecordTypeId();
        if (recordTypeId == null) {
            throw new HouseholdException(Label.Core_Households_ErrorRecordTypeMissing);
        }
        Schema.DescribeSObjectResult account = Schema.SObjectType.Account;
        if (!account.isCreateable() || !account.isUpdateable()) {
            throw new HouseholdException(Label.Core_Households_ErrorCreateNoAccess);
        }
        Map<String, Schema.SObjectField> fields = account.fields.getMap();
        Set<String> checked = new Set<String>();
        for (Account household : households) {
            if (household.RecordTypeId == null) {
                household.RecordTypeId = recordTypeId;
            } else if (household.RecordTypeId != recordTypeId) {
                throw new HouseholdException(Label.Core_Households_ErrorNotAHousehold);
            }
            for (String name : household.getPopulatedFieldsAsMap().keySet()) {
                if (!checked.add(name.toLowerCase())) {
                    continue;
                }
                Schema.SObjectField field = fields.get(name);
                if (
                    field != null &&
                    !BOOKKEEPING_FIELDS.contains(field) &&
                    !field.getDescribe().isCreateable()
                ) {
                    throw new HouseholdException(Label.Core_Households_ErrorCreateNoAccess);
                }
            }
        }
        Set<Id> touched = touchedHouseholdIds == null
            ? new Set<Id>()
            : new Set<Id>(touchedHouseholdIds);
        touched.remove(null);
        if (editableCount(touched) != touched.size()) {
            throw new HouseholdException(Label.Core_Households_ErrorCreateNoHouseholdAccess);
        }
    }

    /** How many of these records the running user can edit, asked 200 at a time. */
    private static Integer editableCount(Set<Id> recordIds) {
        Integer editable = 0;
        Set<Id> batch = new Set<Id>();
        for (Id recordId : recordIds) {
            batch.add(recordId);
            if (batch.size() == 200) {
                editable += HouseholdSelector.getEditableIds(batch).size();
                batch.clear();
            }
        }
        if (!batch.isEmpty()) {
            editable += HouseholdSelector.getEditableIds(batch).size();
        }
        return editable;
    }

    private static List<Database.SaveResult> insertHouseholds(
        List<Account> households,
        Database.DMLOptions options
    ) {
        if (refuseCreatesForTest) {
            Integer tooLong = Account.Name.getDescribe().getLength() + 1;
            for (Account household : households) {
                household.Name = 'x'.repeat(tooLong);
            }
        }
        List<Database.SaveResult> saves = Database.insert(
            households,
            options,
            AccessLevel.SYSTEM_MODE
        );
        logFailures(saves, Label.Core_Households_ErrorContextMembership);
        return saves;
    }

    /**
     * How a new household is saved: each row on its own (one refused household never stops the
     * rest), and past the org's duplicate rules (see createHouseholds).
     */
    @TestVisible
    private static Database.DMLOptions householdSaveOptions() {
        Database.DMLOptions options = new Database.DMLOptions();
        options.optAllOrNone = false;
        options.DuplicateRuleHeader.allowSave = true;
        return options;
    }

    /**
     * The platform's own reason a save was refused, for putting on the record the save was
     * made for. Empty when the save succeeded.
     */
    public static String failureReason(Database.SaveResult save) {
        return save.isSuccess() ? '' : firstMessage(save.getErrors());
    }

    /**
     * Saves computed values on existing households: the name, the two greetings, and the
     * member count.
     */
    public static void updateHouseholds(List<Account> households) {
        updateHouseholdsReportingRefusals(households);
    }

    /**
     * The same, answering the ids of the households the save refused, so a caller can save
     * part of a refused change again (each refusal is logged). A refused save carries no id,
     * so the refused records are found by their position in the list.
     */
    public static Set<Id> updateHouseholdsReportingRefusals(List<Account> households) {
        Set<Id> refused = new Set<Id>();
        if (households == null || households.isEmpty()) {
            return refused;
        }
        List<Database.SaveResult> saves = Database.update(
            households,
            false,
            AccessLevel.SYSTEM_MODE
        );
        logFailures(saves, Label.Core_Households_ErrorContextNaming);
        for (Integer i = 0; i < saves.size(); i++) {
            if (!saves[i].isSuccess()) {
                refused.add(households[i].Id);
            }
        }
        return refused;
    }

    /**
     * Creates the membership rows the package is making on the user's behalf, for a person
     * the org stores as an account.
     */
    public static void createMemberships(List<Household_Member__c> memberships) {
        if (memberships == null || memberships.isEmpty()) {
            return;
        }
        List<Database.SaveResult> saves = Database.insert(
            memberships,
            false,
            AccessLevel.SYSTEM_MODE
        );
        logFailures(saves, Label.Core_Households_ErrorContextMembership);
    }

    /**
     * Contact mode, the household catch-up: points each contact at the household just made
     * for it. Only `AccountId` is sent, and its value is the package's own new household, so
     * the same exception covers it as the trigger's before-insert assignment does. Returns one
     * result per contact; each refusal is logged.
     */
    public static List<Database.SaveResult> linkContactsToHouseholds(List<Contact> links) {
        if (links == null || links.isEmpty()) {
            return new List<Database.SaveResult>();
        }
        List<Database.SaveResult> saves = Database.update(links, false, AccessLevel.SYSTEM_MODE);
        logFailures(saves, Label.Core_Households_ErrorContextMembership);
        return saves;
    }

    /**
     * The membership rows a people merge gives the survivor, and the survivor's rows it makes
     * primary. All or none, in system mode (upkeep, ADR-0021): a row that cannot be written
     * fails the merge, so nothing is lost and the merged-away person's households are
     * untouched, rather than a membership quietly going missing.
     */
    public static void saveMergedMemberships(
        List<Household_Member__c> created,
        List<Household_Member__c> promoted
    ) {
        if (created != null && !created.isEmpty()) {
            Database.insert(created, true, AccessLevel.SYSTEM_MODE);
        }
        if (promoted != null && !promoted.isEmpty()) {
            Database.update(promoted, true, AccessLevel.SYSTEM_MODE);
        }
    }

    /**
     * Settles a household merge's duplicate memberships: the kept rows that take Is Primary,
     * then the duplicate rows removed. System mode (upkeep, ADR-0021), and a refusal is
     * logged rather than thrown so one row cannot stop the rest of the settlement.
     */
    public static void collapseMemberships(
        List<Household_Member__c> promoted,
        List<Household_Member__c> redundant
    ) {
        if (promoted != null && !promoted.isEmpty()) {
            logFailures(
                Database.update(promoted, false, AccessLevel.SYSTEM_MODE),
                Label.Core_Households_ErrorContextMergeSettle
            );
        }
        if (redundant != null && !redundant.isEmpty()) {
            for (
                Database.DeleteResult result : Database.delete(
                    redundant,
                    false,
                    AccessLevel.SYSTEM_MODE
                )
            ) {
                if (!result.isSuccess()) {
                    log(
                        firstMessage(result.getErrors()),
                        Label.Core_Households_ErrorContextMergeSettle
                    );
                }
            }
        }
    }

    /**
     * Removes households the package created that have been left with no members. This one
     * runs with the user's own access, and a refusal is logged rather than thrown, so that
     * tidying up never fails somebody's save.
     */
    public static void deleteHouseholds(List<Account> households) {
        if (households == null || households.isEmpty()) {
            return;
        }
        try {
            List<Database.DeleteResult> deletes = Database.delete(
                households,
                false,
                AccessLevel.USER_MODE
            );
            for (Database.DeleteResult result : deletes) {
                if (!result.isSuccess()) {
                    log(
                        firstMessage(result.getErrors()),
                        Label.Core_Households_ErrorContextMembership
                    );
                }
            }
        } catch (Exception e) {
            ErrorLogger.log(e, Label.Core_Households_ErrorContextMembership);
        }
    }

    /**
     * Removes the membership rows that join a person to their households, on the one path
     * that needs it: the person record itself is being deleted, and a row that survives it
     * would be left naming nobody.
     *
     * Like `deleteHouseholds` this runs with the user's own access rather than in system
     * mode, and a refusal is logged rather than thrown: removing a record is not the
     * package writing one of its own computed values, and tidying up must never fail
     * somebody's save.
     */
    public static void deleteMemberships(List<Household_Member__c> memberships) {
        if (memberships == null || memberships.isEmpty()) {
            return;
        }
        try {
            List<Database.DeleteResult> deletes = Database.delete(
                memberships,
                false,
                AccessLevel.USER_MODE
            );
            for (Database.DeleteResult result : deletes) {
                if (!result.isSuccess()) {
                    log(
                        firstMessage(result.getErrors()),
                        Label.Core_Households_ErrorContextMembership
                    );
                }
            }
        } catch (Exception e) {
            ErrorLogger.log(e, Label.Core_Households_ErrorContextMembership);
        }
    }

    /**
     * Puts back the membership rows that were removed when a person record was deleted,
     * on the same terms as the removal: the user's own access, and a refusal logged.
     */
    public static void undeleteMemberships(List<Household_Member__c> memberships) {
        if (memberships == null || memberships.isEmpty()) {
            return;
        }
        try {
            List<Database.UndeleteResult> restores = Database.undelete(
                memberships,
                false,
                AccessLevel.USER_MODE
            );
            for (Database.UndeleteResult result : restores) {
                if (!result.isSuccess()) {
                    log(
                        firstMessage(result.getErrors()),
                        Label.Core_Households_ErrorContextMembership
                    );
                }
            }
        } catch (Exception e) {
            ErrorLogger.log(e, Label.Core_Households_ErrorContextMembership);
        }
    }

    private static void logFailures(List<Database.SaveResult> saves, String context) {
        for (Database.SaveResult save : saves) {
            if (!save.isSuccess()) {
                log(firstMessage(save.getErrors()), context);
            }
        }
    }

    private static String firstMessage(List<Database.Error> errors) {
        return errors == null || errors.isEmpty() ? '' : errors[0].getMessage();
    }

    private static void log(String message, String context) {
        ErrorLogger.log(
            new HouseholdException(Label.Core_Households_ErrorSaveFailed + ' ' + message),
            context
        );
    }
}
