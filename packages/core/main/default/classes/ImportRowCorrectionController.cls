/**
 * The Super Importer Row card (C-49b): one import row's file values beside its corrections and
 * its reason, saving corrections to a rejected row (R-IR4), and retrying that row or every
 * corrected row of its import in place (R-IB17a). See docs/admin-guide/import-rows.md.
 *
 * Reading the row is in user mode, so a person sees only rows of imports they can see.
 * Everything that changes anything checks the Manage BarnCRM Settings custom permission and
 * the batch's retry rules first; the corrections themselves are the package's staging and are
 * written in system mode after those checks (ADR-0021). Raw values are never written.
 */
public with sharing class ImportRowCorrectionController {
    /** Injected by the tests, as ImportController's is. Null in production. */
    @TestVisible
    private static Boolean permissionOverride;

    /** One column of the row: the file's value and its correction, if any. */
    public class ColumnView {
        @AuraEnabled
        public String column;
        @AuraEnabled
        public String fileValue;
        @AuraEnabled
        public String correctedValue;
        @AuraEnabled
        public Boolean corrected;
    }

    /** The row as the card shows it. */
    public class RowView {
        @AuraEnabled
        public String id;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public Integer rowNumber;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public String errorMessage;
        @AuraEnabled
        public String batchId;
        @AuraEnabled
        public String batchName;
        @AuraEnabled
        public List<ColumnView> columns = new List<ColumnView>();
        /** True when this person may correct and retry this row now. */
        @AuraEnabled
        public Boolean canCorrect = false;
        /** Why a rejected row cannot be corrected now, or null. */
        @AuraEnabled
        public String refusal;
        /** How many rejected rows of the import carry corrections. */
        @AuraEnabled
        public Integer fixedCount = 0;
    }

    @AuraEnabled
    public static RowView getRow(Id rowId) {
        try {
            return view(rowId);
        } catch (Exception e) {
            throw UserErrors.wrap(e, 'ImportRowCorrectionController.getRow', true);
        }
    }

    /**
     * Saves the corrections of a rejected row: of the values given (column name to value), only
     * those that differ from the file's value are kept; none clears the corrections.
     */
    @AuraEnabled
    public static RowView saveCorrections(Id rowId, String correctionsJson) {
        try {
            Import_Row__c row = writableRow(rowId);
            Map<String, Object> raw = parse(row.Raw_Values_JSON__c);
            Map<String, Object> given = parse(correctionsJson);
            Map<String, Object> kept = new Map<String, Object>();
            for (String column : given.keySet()) {
                String value = given.get(column) == null ? '' : String.valueOf(given.get(column));
                // equals, not ==, which ignores capitals and would drop a change to them.
                if (raw.containsKey(column) && !value.equals(text(raw.get(column)))) {
                    kept.put(column, value);
                }
            }
            String document = kept.isEmpty() ? null : JSON.serialize(kept);
            if (document != null && document.length() > MAX_CORRECTIONS) {
                throw new ImportException(Label.Core_Import_ErrorCorrectionsTooLong);
            }
            Database.update(
                new Import_Row__c(Id = row.Id, Corrected_Values_JSON__c = document),
                AccessLevel.SYSTEM_MODE
            );
            return view(rowId);
        } catch (Exception e) {
            throw UserErrors.wrap(e, 'ImportRowCorrectionController.saveCorrections', true);
        }
    }

    /** Retries this corrected row in place; returns the job's Id. */
    @AuraEnabled
    public static String retryRow(Id rowId) {
        try {
            Import_Row__c row = writableRow(rowId);
            return ImportBatchService.startRowRetry(row.Import_Batch__c, new Set<Id>{ row.Id });
        } catch (Exception e) {
            throw UserErrors.wrap(e, 'ImportRowCorrectionController.retryRow', true);
        }
    }

    /** Retries every corrected rejected row of this row's import; returns the job's Id. */
    @AuraEnabled
    public static String retryAllFixed(Id rowId) {
        try {
            enforcePermission();
            Import_Row__c row = readRow(rowId);
            return ImportBatchService.startRowRetry(row.Import_Batch__c, null);
        } catch (Exception e) {
            throw UserErrors.wrap(e, 'ImportRowCorrectionController.retryAllFixed', true);
        }
    }

    /** The longest corrections document the field holds. */
    @TestVisible
    private static final Integer MAX_CORRECTIONS = 32768;

    private static RowView view(Id rowId) {
        Import_Row__c row = readRow(rowId);
        RowView result = new RowView();
        result.id = row.Id;
        result.name = row.Name;
        result.rowNumber = row.Row_Number__c == null ? null : row.Row_Number__c.intValue();
        result.status = row.Status__c;
        result.errorMessage = row.Error_Message__c;
        result.batchId = row.Import_Batch__c;
        result.batchName = row.Import_Batch__r.Name;
        Map<String, Object> raw = parse(row.Raw_Values_JSON__c);
        Map<String, Object> corrections = parse(row.Corrected_Values_JSON__c);
        for (String column : raw.keySet()) {
            ColumnView shown = new ColumnView();
            shown.column = column;
            shown.fileValue = text(raw.get(column));
            shown.corrected = corrections.containsKey(column);
            shown.correctedValue = shown.corrected
                ? text(corrections.get(column))
                : shown.fileValue;
            result.columns.add(shown);
        }
        if (ImportRowProcessor.STATUS_REJECTED.equals(row.Status__c)) {
            result.refusal = refusal(row);
            result.canCorrect = result.refusal == null;
            if (result.canCorrect) {
                result.fixedCount = ImportBatchService.fixedRowIds(row.Import_Batch__c, null)
                    .size();
            }
        }
        return result;
    }

    /** Why this rejected row cannot be corrected or retried now, or null. */
    private static String refusal(Import_Row__c row) {
        if (!hasManagePermission()) {
            return Label.Core_Import_ErrorNoPermission;
        }
        return ImportBatchService.rowRetryRefusal(
            ImportBatchSelector.selectById(row.Import_Batch__c)
        );
    }

    /** The row, after every check a change must pass: permission, rejected, retry allowed. */
    private static Import_Row__c writableRow(Id rowId) {
        enforcePermission();
        Import_Row__c row = readRow(rowId);
        if (!ImportRowProcessor.STATUS_REJECTED.equals(row.Status__c)) {
            throw new ImportException(Label.Core_Import_ErrorCorrectOnlyRejected);
        }
        String refused = refusal(row);
        if (refused != null) {
            throw new ImportException(refused);
        }
        return row;
    }

    private static Import_Row__c readRow(Id rowId) {
        List<Import_Row__c> rows = [
            SELECT
                Id,
                Name,
                Row_Number__c,
                Status__c,
                Error_Message__c,
                Raw_Values_JSON__c,
                Corrected_Values_JSON__c,
                Import_Batch__c,
                Import_Batch__r.Name
            FROM Import_Row__c
            WHERE Id = :rowId
            WITH USER_MODE
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw new ImportException(Label.Core_Import_ErrorRowsRemoved);
        }
        return rows[0];
    }

    private static Map<String, Object> parse(String document) {
        if (String.isBlank(document)) {
            return new Map<String, Object>();
        }
        Object parsed = JSON.deserializeUntyped(document);
        return parsed instanceof Map<String, Object>
            ? (Map<String, Object>) parsed
            : new Map<String, Object>();
    }

    private static String text(Object value) {
        return value == null ? '' : String.valueOf(value);
    }

    private static void enforcePermission() {
        if (!hasManagePermission()) {
            throw new ImportException(Label.Core_Import_ErrorNoPermission);
        }
    }

    private static Boolean hasManagePermission() {
        if (permissionOverride != null) {
            return permissionOverride;
        }
        return FeatureManagement.checkPermission('Manage_BarnCRM_Settings');
    }
}
