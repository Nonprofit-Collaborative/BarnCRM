/**
 * The Field Utilization tab (canonical model Section 29F, ADR-0101
 * field-utilization-on-demand).
 *
 * The page picks an object, reads its plan (record totals, the fields to count and the latest
 * saved count) in one call, then asks for counts a chunk of fields at a time and fills its table
 * as each returns. Nothing is stored until the person saves. Every method requires
 * `Manage_BarnCRM_Settings`; the counting itself is in user mode (R-FU3).
 */
public with sharing class FieldUtilizationController {
    private static final String PERMISSION = 'Manage_BarnCRM_Settings';

    /** The most snapshot rows one save writes, inside the 10,000 row DML limit. */
    @TestVisible
    private static final Integer MAX_SAVE_ROWS = 9000;

    /** Raised with a message the page shows as it is. */
    public class FieldUtilizationException extends Exception {
    }

    /** One choice in the object picker. */
    public class Option {
        @AuraEnabled
        public String value;
        @AuraEnabled
        public String label;
    }

    /** One field the page will count. */
    public class FieldInfo {
        @AuraEnabled
        public String fieldName;
        @AuraEnabled
        public String fieldLabel;
    }

    /** One field and record type: counted now, saved earlier, or sent back to be saved. */
    public class CountRow {
        @AuraEnabled
        public String key { get; set; }
        @AuraEnabled
        public String fieldName { get; set; }
        @AuraEnabled
        public String fieldLabel { get; set; }
        @AuraEnabled
        public String recordType { get; set; }
        @AuraEnabled
        public String recordTypeLabel { get; set; }
        @AuraEnabled
        public Integer filled { get; set; }
        @AuraEnabled
        public Integer total { get; set; }
        @AuraEnabled
        public Decimal percent { get; set; }
        @AuraEnabled
        public Boolean sampled { get; set; }
    }

    /** What the page needs before it counts. */
    public class Plan {
        @AuraEnabled
        public String objectName;
        @AuraEnabled
        public String objectLabel;
        @AuraEnabled
        public Integer total;
        @AuraEnabled
        public Boolean tooLarge;
        @AuraEnabled
        public Integer largeObjectLimit;
        @AuraEnabled
        public Integer chunkSize;
        @AuraEnabled
        public List<FieldInfo> fields = new List<FieldInfo>();
        @AuraEnabled
        public Datetime previousTakenAt;
        @AuraEnabled
        public List<CountRow> previous = new List<CountRow>();
    }

    /** One chunk's counts, and the labels of fields that could not be counted at all. */
    public class Chunk {
        @AuraEnabled
        public List<CountRow> rows = new List<CountRow>();
        @AuraEnabled
        public List<String> failed = new List<String>();
    }

    /** One saved count in the Snapshot History list. */
    public class SnapshotInfo {
        @AuraEnabled
        public Datetime takenAt;
        @AuraEnabled
        public String savedBy;
        /** How many saved rows (a field once per record type) the save holds. */
        @AuraEnabled
        public Integer rowCount;
        /** How many different fields the save holds. */
        @AuraEnabled
        public Integer fieldCount;
        /** Filled values as a percentage of the records looked at, across the whole save. */
        @AuraEnabled
        public Decimal averagePercent;
    }

    /** The Snapshot History list for one object. */
    public class History {
        @AuraEnabled
        public List<SnapshotInfo> snapshots = new List<SnapshotInfo>();
        /** The most snapshots listed; when the list is this long, older ones are not shown. */
        @AuraEnabled
        public Integer maxSnapshots = FieldUtilizationHistory.MAX_RUNS;
        /** Whether the person may delete snapshots (delete access on the snapshot object). */
        @AuraEnabled
        public Boolean canDelete = false;
    }

    /** Every object the person may count, by label (R-FU1). */
    @AuraEnabled(cacheable=true)
    public static List<Option> listObjects() {
        try {
            requirePermission();
            Map<String, Option> byLabel = new Map<String, Option>();
            for (
                Schema.DescribeSObjectResult described : FieldUtilizationService.offeredObjects()
            ) {
                Option option = new Option();
                option.value = described.getName();
                option.label = described.getLabel();
                byLabel.put(option.label.toLowerCase() + '\u0000' + option.value, option);
            }
            List<String> keys = new List<String>(byLabel.keySet());
            keys.sort();
            List<Option> options = new List<Option>();
            for (String key : keys) {
                options.add(byLabel.get(key));
            }
            return options;
        } catch (Exception caught) {
            throw asUserError(caught, 'Field utilization object list');
        }
    }

    /** The object's totals, fields and latest saved count (R-FU5, R-FU8). */
    @AuraEnabled
    public static Plan getPlan(String objectName) {
        try {
            requirePermission();
            Schema.DescribeSObjectResult described = requireObject(objectName);
            Plan planned = new Plan();
            planned.objectName = described.getName();
            planned.objectLabel = described.getLabel();
            planned.total = FieldUtilizationService.sum(
                FieldUtilizationService.totalsByRecordType(described)
            );
            planned.largeObjectLimit = FieldUtilizationService.largeObjectLimit();
            planned.tooLarge = planned.total > planned.largeObjectLimit;
            planned.chunkSize = planned.total > FieldUtilizationService.LARGE_OBJECT_ROWS
                ? FieldUtilizationService.LARGE_CHUNK_SIZE
                : FieldUtilizationService.CHUNK_SIZE;
            if (!planned.tooLarge && planned.total > 0) {
                for (
                    Schema.DescribeFieldResult field : FieldUtilizationService.countableFields(
                        described
                    )
                ) {
                    FieldInfo info = new FieldInfo();
                    info.fieldName = field.getName();
                    info.fieldLabel = field.getLabel();
                    planned.fields.add(info);
                }
            }
            planned.previousTakenAt = FieldUtilizationSelector.latestRun(planned.objectName);
            if (planned.previousTakenAt != null) {
                RecordTypeLabels labels = new RecordTypeLabels(described);
                for (
                    Field_Utilization_Snapshot__c row : FieldUtilizationSelector.rowsAt(
                        planned.objectName,
                        planned.previousTakenAt
                    )
                ) {
                    planned.previous.add(toRow(row, labels));
                }
            }
            return planned;
        } catch (Exception caught) {
            throw asUserError(caught, 'Field utilization plan');
        }
    }

    /**
     * Counts up to one chunk of the object's fields (R-FU4, R-FU7). The totals are read again
     * here, so no number the page sent becomes a denominator, and the size limit is enforced
     * here too (R-FU5). Names that are not countable fields are ignored.
     */
    @AuraEnabled
    public static Chunk countFields(String objectName, List<String> fieldNames) {
        try {
            requirePermission();
            Schema.DescribeSObjectResult described = requireObject(objectName);
            Chunk result = new Chunk();
            if (fieldNames == null || fieldNames.isEmpty()) {
                return result;
            }
            if (fieldNames.size() > FieldUtilizationService.CHUNK_SIZE) {
                throw new FieldUtilizationException(
                    System.Label.Core_FieldUtilization_UnexpectedError
                );
            }
            Map<String, Integer> totals = FieldUtilizationService.totalsByRecordType(described);
            requireNotTooLarge(FieldUtilizationService.sum(totals));
            Map<String, Schema.DescribeFieldResult> fields = FieldUtilizationService.countableFieldsByName(
                described
            );
            RecordTypeLabels labels = new RecordTypeLabels(described);
            Exception firstFailure;
            for (String fieldName : new Set<String>(fieldNames)) {
                Schema.DescribeFieldResult field = fields.get(fieldName);
                if (field == null) {
                    continue;
                }
                try {
                    for (
                        Field_Utilization_Snapshot__c row : FieldUtilizationService.count(
                            described,
                            field,
                            totals
                        )
                    ) {
                        result.rows.add(toRow(row, labels));
                    }
                } catch (Exception fieldFailure) {
                    firstFailure = firstFailure == null ? fieldFailure : firstFailure;
                    result.failed.add(field.getLabel());
                }
            }
            if (firstFailure != null) {
                ErrorLogger.log(firstFailure, 'Field utilization count: ' + described.getName());
            }
            return result;
        } catch (Exception caught) {
            throw asUserError(caught, 'Field utilization count');
        }
    }

    /**
     * Saves the counts on the page as one set of snapshots (R-FU7). Each row's field and record
     * type are checked against describe; a row that does not match is left out. Returns how
     * many rows were saved.
     */
    @AuraEnabled
    public static Integer saveCounts(String objectName, List<CountRow> rows) {
        try {
            requirePermission();
            Schema.DescribeSObjectResult described = requireObject(objectName);
            List<CountRow> sent = rows == null ? new List<CountRow>() : rows;
            if (sent.size() > MAX_SAVE_ROWS) {
                throw new FieldUtilizationException(
                    String.format(
                        System.Label.Core_FieldUtilization_TooManyRows,
                        new List<Object>{ sent.size(), MAX_SAVE_ROWS }
                    )
                );
            }
            Map<String, Schema.DescribeFieldResult> fields = FieldUtilizationService.countableFieldsByName(
                described
            );
            Map<String, Schema.RecordTypeInfo> recordTypes = described.getRecordTypeInfosByDeveloperName();
            List<Field_Utilization_Snapshot__c> snapshots = new List<Field_Utilization_Snapshot__c>();
            for (CountRow row : sent) {
                Schema.DescribeFieldResult field = row == null ? null : fields.get(row.fieldName);
                Boolean knownType =
                    field != null &&
                    (String.isBlank(row.recordType) || recordTypes.containsKey(row.recordType));
                if (!knownType || row.total == null || row.total <= 0) {
                    continue;
                }
                snapshots.add(
                    FieldUtilizationService.snapshot(
                        described.getName(),
                        field,
                        row.recordType,
                        row.filled,
                        row.total,
                        row.sampled
                    )
                );
            }
            FieldUtilizationService.save(snapshots, System.now());
            return snapshots.size();
        } catch (Exception caught) {
            throw asUserError(caught, 'Save field utilization counts');
        }
    }

    /** The object's newest saved counts, one entry per save, newest first (Snapshot History). */
    @AuraEnabled
    public static History getHistory(String objectName) {
        try {
            requirePermission();
            Schema.DescribeSObjectResult described = requireObject(objectName);
            History listed = new History();
            listed.canDelete = canDeleteSnapshots();
            List<FieldUtilizationHistory.Run> runs = FieldUtilizationHistory.latest(
                described.getName()
            );
            Map<Id, String> names = FieldUtilizationHistory.namesOf(runs);
            for (FieldUtilizationHistory.Run run : runs) {
                SnapshotInfo info = new SnapshotInfo();
                info.takenAt = run.takenAt;
                info.savedBy = names.get(run.savedById);
                info.rowCount = run.rowCount;
                info.fieldCount = run.fieldCount;
                info.averagePercent = run.averagePercent();
                listed.snapshots.add(info);
            }
            return listed;
        } catch (Exception caught) {
            throw asUserError(caught, 'Field utilization history');
        }
    }

    /**
     * The rows of one saved count: to compare the page's count with it, or to show it. Rows
     * come back in the shape of a count row, ordered by field label and record type.
     */
    @AuraEnabled
    public static List<CountRow> getSnapshotRows(String objectName, Datetime takenAt) {
        try {
            requirePermission();
            Schema.DescribeSObjectResult described = requireObject(objectName);
            List<CountRow> rows = new List<CountRow>();
            if (takenAt == null) {
                return rows;
            }
            RecordTypeLabels labels = new RecordTypeLabels(described);
            for (
                Field_Utilization_Snapshot__c row : FieldUtilizationSelector.rowsAt(
                    described.getName(),
                    takenAt
                )
            ) {
                rows.add(toRow(row, labels));
            }
            return rows;
        } catch (Exception caught) {
            throw asUserError(caught, 'Field utilization snapshot rows');
        }
    }

    /**
     * Deletes one saved count: every row of the object that carries the given Taken At. Needs
     * delete access on the snapshot object, and the delete runs in user mode. Returns how many
     * rows were deleted.
     */
    @AuraEnabled
    public static Integer deleteSnapshot(String objectName, Datetime takenAt) {
        try {
            requirePermission();
            Schema.DescribeSObjectResult described = requireObject(objectName);
            if (!canDeleteSnapshots()) {
                throw new FieldUtilizationException(
                    System.Label.Core_FieldUtilization_DeleteNoAccess
                );
            }
            if (takenAt == null) {
                return 0;
            }
            List<Field_Utilization_Snapshot__c> rows = FieldUtilizationSelector.idsAt(
                described.getName(),
                takenAt
            );
            try {
                Database.delete(rows, AccessLevel.USER_MODE);
            } catch (DmlException notAllowed) {
                throw new FieldUtilizationException(
                    System.Label.Core_FieldUtilization_DeleteFailed
                );
            }
            return rows.size();
        } catch (Exception caught) {
            throw asUserError(caught, 'Delete field utilization snapshot');
        }
    }

    /** Record type developer names to the labels the page shows, for one object. */
    private class RecordTypeLabels {
        private Boolean grouped;
        private Map<String, Schema.RecordTypeInfo> byName;

        RecordTypeLabels(Schema.DescribeSObjectResult described) {
            this.grouped = FieldUtilizationService.groupsByRecordType(described);
            this.byName = described.getRecordTypeInfosByDeveloperName();
        }

        String labelOf(String developerName) {
            if (!this.grouped) {
                return '';
            }
            if (String.isBlank(developerName)) {
                return System.Label.Core_FieldUtilization_NoRecordType;
            }
            Schema.RecordTypeInfo info = this.byName.get(developerName);
            return info == null ? developerName : info.getName();
        }
    }

    private static CountRow toRow(Field_Utilization_Snapshot__c snapshot, RecordTypeLabels labels) {
        CountRow row = new CountRow();
        row.fieldName = snapshot.Field_Name__c;
        row.fieldLabel = snapshot.Field_Label__c;
        row.recordType = snapshot.Record_Type__c == null ? '' : snapshot.Record_Type__c;
        row.key = row.fieldName + '|' + row.recordType;
        row.recordTypeLabel = labels.labelOf(snapshot.Record_Type__c);
        row.filled = snapshot.Filled_Count__c == null ? 0 : snapshot.Filled_Count__c.intValue();
        row.total = snapshot.Record_Count__c == null ? 0 : snapshot.Record_Count__c.intValue();
        row.percent = row.total == 0
            ? null
            : (Decimal.valueOf(row.filled) * 100).divide(row.total, 1);
        row.sampled = snapshot.Sampled__c == true;
        return row;
    }

    private static Boolean canDeleteSnapshots() {
        return Field_Utilization_Snapshot__c.SObjectType.getDescribe(
                SObjectDescribeOptions.DEFERRED
            )
            .isDeletable();
    }

    private static Schema.DescribeSObjectResult requireObject(String objectName) {
        Schema.DescribeSObjectResult described = FieldUtilizationService.countable(objectName);
        if (described == null) {
            throw new FieldUtilizationException(
                String.format(
                    System.Label.Core_FieldUtilization_UnknownObject,
                    new List<Object>{ String.isBlank(objectName) ? '' : objectName }
                )
            );
        }
        return described;
    }

    private static void requireNotTooLarge(Integer total) {
        if (total > FieldUtilizationService.largeObjectLimit()) {
            throw new FieldUtilizationException(
                String.format(
                    System.Label.Core_FieldUtilization_TooLarge,
                    new List<Object>{ FieldUtilizationService.largeObjectLimit().format() }
                )
            );
        }
    }

    private static void requirePermission() {
        if (!FeatureManagement.checkPermission(PERMISSION)) {
            throw new FieldUtilizationException(
                System.Label.Core_FieldUtilization_PermissionRequired
            );
        }
    }

    private static AuraHandledException asUserError(Exception caught, String context) {
        return UserErrors.wrap(
            caught,
            caught instanceof FieldUtilizationException,
            context,
            System.Label.Core_FieldUtilization_UnexpectedError
        );
    }
}
