/**
 * Reads saved field utilization counts (canonical model Section 29F), in user mode.
 *
 * A saved count is the set of rows sharing one Taken At. DateTime fields cannot be grouped, so
 * the latest save is found with a one-row query and its rows read with a second.
 */
public with sharing class FieldUtilizationSelector {
    /** The most rows the page reads for one object's latest save. */
    private static final Integer MAX_ROWS = 10000;

    /** When the latest save for the object was taken, or null. */
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

    /** The object's rows from one save. */
    public static List<Field_Utilization_Snapshot__c> rowsAt(String objectName, Datetime takenAt) {
        return [
            SELECT
                Field_Name__c,
                Field_Label__c,
                Record_Type__c,
                Filled_Count__c,
                Record_Count__c,
                Sampled__c
            FROM Field_Utilization_Snapshot__c
            WHERE Object_Name__c = :objectName AND Taken_At__c = :takenAt
            WITH USER_MODE
            ORDER BY Field_Label__c, Record_Type__c
            LIMIT :MAX_ROWS
        ];
    }
}
