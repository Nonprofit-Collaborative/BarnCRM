/**
 * Reads field utilization snapshots (canonical model Section 29D), in user mode.
 *
 * A run is the set of rows sharing one Taken At. DateTime fields cannot be grouped, so the
 * latest and previous runs are found with two one-row queries rather than a grouped one.
 */
public with sharing class FieldUtilizationSelector {
    /** The most rows the page reads for one object across the two runs it compares. */
    private static final Integer MAX_ROWS = 10000;

    /** The most rows one run's retention pass deletes; the next run takes the rest. */
    private static final Integer MAX_PURGE = 9000;

    /** When the latest run that counted the object started, or null. */
    public static Datetime latestRun(String objectName) {
        List<Field_Utilization_Snapshot__c> rows = [
            SELECT Taken_At__c
            FROM Field_Utilization_Snapshot__c
            WHERE Object_Name__c = :objectName AND Taken_At__c != NULL
            WITH USER_MODE
            ORDER BY Taken_At__c DESC
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0].Taken_At__c;
    }

    /** When the run before the given one started, or null. */
    public static Datetime runBefore(String objectName, Datetime takenAt) {
        if (takenAt == null) {
            return null;
        }
        List<Field_Utilization_Snapshot__c> rows = [
            SELECT Taken_At__c
            FROM Field_Utilization_Snapshot__c
            WHERE Object_Name__c = :objectName AND Taken_At__c < :takenAt
            WITH USER_MODE
            ORDER BY Taken_At__c DESC
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0].Taken_At__c;
    }

    /** The object's rows from the given runs. */
    public static List<Field_Utilization_Snapshot__c> rowsAt(
        String objectName,
        Set<Datetime> runs
    ) {
        return [
            SELECT
                Field_Name__c,
                Field_Label__c,
                Record_Type__c,
                Filled_Count__c,
                Record_Count__c,
                Sampled__c,
                Taken_At__c
            FROM Field_Utilization_Snapshot__c
            WHERE Object_Name__c = :objectName AND Taken_At__c IN :runs
            WITH USER_MODE
            ORDER BY Field_Label__c, Record_Type__c
            LIMIT :MAX_ROWS
        ];
    }

    /** Rows taken before the cutoff, for the retention pass (R-FU7). */
    public static List<Field_Utilization_Snapshot__c> takenBefore(Datetime cutoff) {
        return [
            SELECT Id
            FROM Field_Utilization_Snapshot__c
            WHERE Taken_At__c < :cutoff
            WITH USER_MODE
            LIMIT :MAX_PURGE
        ];
    }
}
