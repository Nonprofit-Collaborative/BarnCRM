/**
 * Export and import of rollups between orgs as a file (ADR-0136, DLRS parity P12 and D23; it
 * lifts ADR-0082's deferral of moving definitions from a sandbox to production).
 *
 * The file is JSON: a format name, a format version, and each rollup as the Builder edits it
 * (`RollupBuilderController.Draft`) without its record Id, plus its Definition Key, which is how
 * an import matches a rollup the org already has. Last Calculated and Is Package Default are never
 * written. Shipped rollups are neither exported nor imported: every org has them from BarnCRM.
 *
 * An import saves each rollup through the Builder's own checks (`checkedRecord`: R-R10, R-R8), in
 * user mode, one at a time, so a refused rollup stops nothing else and each one is checked against
 * those saved before it. A rollup keeps the Active value its file gives only by passing every
 * check; one that fails a check is not saved at all. Nothing is recalculated by an import.
 */
public with sharing class RollupDefinitionTransfer {
    @TestVisible
    private static final String FORMAT = 'BarnCRM rollups';
    @TestVisible
    private static final Integer FORMAT_VERSION = 1;
    /** What one rollup's checks and save may use at most, kept back so an import stops cleanly. */
    private static final Integer QUERIES_PER_ROLLUP = 15;
    private static final Integer DML_PER_ROLLUP = 5;

    public static final String CREATED = 'created';
    public static final String UPDATED = 'updated';
    public static final String REFUSED = 'refused';
    public static final String NOT_REACHED = 'notReached';

    /** What happened, or would happen, to one rollup in a file. */
    public class TransferRow {
        @AuraEnabled
        public String definitionKey { get; set; }
        @AuraEnabled
        public String name { get; set; }
        /** created, updated, refused or notReached; the page names each in words. */
        @AuraEnabled
        public String outcome { get; set; }
        @AuraEnabled
        public String reason { get; set; }
    }

    /**
     * The file for the rollups chosen, or every rollup an administrator made when none is.
     *
     * @param definitionIds the rollups ticked in the list; empty or null for all of them
     * @return the file's text
     */
    @AuraEnabled
    public static String exportDefinitions(List<Id> definitionIds) {
        try {
            requirePermission();
            Set<Id> chosen = definitionIds == null ? new Set<Id>() : new Set<Id>(definitionIds);
            List<Object> rollups = new List<Object>();
            for (Rollup_Definition__c definition : RollupSelector.selectAllAsUser()) {
                if (
                    definition.Is_Package_Default__c == true ||
                    (!chosen.isEmpty() && !chosen.contains(definition.Id))
                ) {
                    continue;
                }
                Map<String, Object> rollup = (Map<String, Object>) JSON.deserializeUntyped(
                    JSON.serialize(RollupBuilderController.toDraft(definition))
                );
                rollup.remove('recordId');
                rollup.put('definitionKey', definition.Definition_Key__c);
                rollups.add(rollup);
            }
            if (rollups.isEmpty()) {
                throw refusal(Label.Core_RollupBuilder_ExportNothing);
            }
            return JSON.serializePretty(
                new Map<String, Object>{
                    'format' => FORMAT,
                    'version' => FORMAT_VERSION,
                    'rollups' => rollups
                }
            );
        } catch (Exception caught) {
            throw asUserError(caught);
        }
    }

    /**
     * Reads a file and says what it would do to each rollup, or does it.
     *
     * @param fileText the file's text, read in the browser
     * @param save false to say what would happen, true to save
     * @return one row per rollup in the file, in its order
     */
    @AuraEnabled
    public static List<TransferRow> importDefinitions(String fileText, Boolean save) {
        try {
            requirePermission();
            List<Object> rollups = rollupsIn(fileText);
            Set<String> known = ((Map<String, Object>) JSON.deserializeUntyped(
                    JSON.serialize(new RollupBuilderController.Draft())
                ))
                .keySet();
            Set<String> shippedKeys = new Set<String>();
            Map<String, Rollup_Definition_Default__mdt> defaults = Rollup_Definition_Default__mdt.getAll();
            for (Rollup_Definition_Default__mdt shipped : defaults.values()) {
                if (String.isNotBlank(shipped.Definition_Key__c)) {
                    shippedKeys.add(shipped.Definition_Key__c.toLowerCase());
                }
            }
            Map<String, Rollup_Definition__c> byKey = new Map<String, Rollup_Definition__c>();
            for (Rollup_Definition__c definition : RollupSelector.selectAllAsUser()) {
                byKey.put(definition.Definition_Key__c.toLowerCase(), definition);
            }
            Set<String> seen = new Set<String>();
            List<TransferRow> rows = new List<TransferRow>();
            for (Object item : rollups) {
                Map<String, Object> rollup = item instanceof Map<String, Object>
                    ? (Map<String, Object>) item
                    : new Map<String, Object>();
                TransferRow row = new TransferRow();
                row.definitionKey = textOf(rollup.remove('definitionKey'));
                row.name = textOf(rollup.get('name'));
                String key = row.definitionKey == null ? '' : row.definitionKey.toLowerCase();
                Rollup_Definition__c existing = byKey.get(key);
                row.outcome = existing == null ? CREATED : UPDATED;
                rows.add(row);
                if (save == true && !roomForOneMore(rows)) {
                    row.outcome = NOT_REACHED;
                    continue;
                }
                try {
                    if (String.isBlank(key) || key.length() > 80) {
                        throw refusal(Label.Core_RollupBuilder_ImportUnreadable);
                    }
                    if (!seen.add(key)) {
                        throw refusal(Label.Core_RollupBuilder_ImportTwice);
                    }
                    Boolean shipped = existing != null && existing.Is_Package_Default__c == true;
                    if (shipped || shippedKeys.contains(key)) {
                        throw refusal(Label.Core_RollupBuilder_ImportShipped);
                    }
                    Rollup_Definition__c record = checked(rollup, existing, known);
                    if (existing == null) {
                        record.Definition_Key__c = row.definitionKey;
                    }
                    if (save == true) {
                        RollupWriter.saveAsUser(record);
                    }
                } catch (RollupService.RollupServiceException checkFailed) {
                    // Apex names are case-insensitive: a catch variable named like REFUSED hides it.
                    row.outcome = REFUSED;
                    row.reason = checkFailed.getMessage();
                } catch (DmlException saveFailed) {
                    row.outcome = REFUSED;
                    row.reason = saveFailed.getDmlMessage(0);
                } catch (Exception unexpected) {
                    ErrorLogger.log(unexpected, 'RollupDefinitionTransfer');
                    row.outcome = REFUSED;
                    row.reason = Label.Core_Rollups_UnexpectedError;
                }
            }
            return rows;
        } catch (Exception caught) {
            throw asUserError(caught);
        }
    }

    /** The rollups a file holds, or why the file cannot be read. */
    private static List<Object> rollupsIn(String fileText) {
        Object parsed;
        try {
            parsed = JSON.deserializeUntyped(fileText);
        } catch (Exception unreadable) {
            throw refusal(Label.Core_RollupBuilder_ImportNotAFile);
        }
        Map<String, Object> file = parsed instanceof Map<String, Object>
            ? (Map<String, Object>) parsed
            : new Map<String, Object>();
        Object version = file.get('version');
        if (
            !FORMAT.equals(file.get('format')) ||
            !(version instanceof Integer) ||
            !(file.get('rollups') instanceof List<Object>)
        ) {
            throw refusal(Label.Core_RollupBuilder_ImportNotAFile);
        }
        if ((Integer) version > FORMAT_VERSION) {
            throw refusal(Label.Core_RollupBuilder_ImportNewer);
        }
        return (List<Object>) file.get('rollups');
    }

    /**
     * One rollup of the file as a record, after the Builder's checks. An attribute this org's
     * Builder does not know refuses the rollup rather than being dropped, so a file from a newer
     * version never saves a different rollup than the one exported.
     */
    private static Rollup_Definition__c checked(
        Map<String, Object> rollup,
        Rollup_Definition__c existing,
        Set<String> known
    ) {
        List<String> unknown = new List<String>();
        for (String attribute : rollup.keySet()) {
            if (!known.contains(attribute)) {
                unknown.add(attribute);
            }
        }
        if (!unknown.isEmpty()) {
            throw refusal(
                String.format(
                    Label.Core_RollupBuilder_ImportUnknown,
                    new List<String>{ String.join(unknown, ', ') }
                )
            );
        }
        RollupBuilderController.Draft draft;
        try {
            draft = (RollupBuilderController.Draft) JSON.deserialize(
                JSON.serialize(rollup),
                RollupBuilderController.Draft.class
            );
        } catch (JSONException unreadable) {
            throw refusal(Label.Core_RollupBuilder_ImportUnreadable);
        }
        draft.recordId = existing == null ? null : existing.Id;
        return RollupBuilderController.checkedRecord(draft);
    }

    /** Whether one more rollup's checks and save fit in what this transaction has left. */
    private static Boolean roomForOneMore(List<TransferRow> rows) {
        Boolean earlierStopped = rows.size() > 1 && rows[rows.size() - 2].outcome == NOT_REACHED;
        return !earlierStopped &&
            Limits.getQueries() + QUERIES_PER_ROLLUP <= Limits.getLimitQueries() &&
            Limits.getDmlStatements() + DML_PER_ROLLUP <= Limits.getLimitDmlStatements();
    }

    private static String textOf(Object value) {
        return value instanceof String ? ((String) value).trim() : null;
    }

    private static RollupService.RollupServiceException refusal(String message) {
        return new RollupService.RollupServiceException(message);
    }

    private static void requirePermission() {
        if (!BarnCRMPermissions.canManageSettings()) {
            throw refusal(Label.Core_Rollups_ErrorNoPermission);
        }
    }

    /** A message the page can show; anything it cannot explain is logged. */
    private static AuraHandledException asUserError(Exception caught) {
        return UserErrors.wrap(
            caught,
            caught instanceof RollupService.RollupServiceException,
            'RollupDefinitionTransfer',
            Label.Core_Rollups_UnexpectedError
        );
    }
}
