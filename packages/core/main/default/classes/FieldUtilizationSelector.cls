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

    /**
     * The object's saved counts, grouped by the hour they were taken and by who saved them.
     *
     * DateTime fields cannot be grouped, but the date functions can, so one group holds every save
     * made by one person in one hour. A group whose first and last Taken At differ holds more than
     * one save; the history class splits those with rowsBetween. Newest groups first, and every
     * group holds at least one save, so the first `maxGroups` groups cover the newest `maxGroups`
     * saves.
     */
    public static List<AggregateResult> groupsByHour(String objectName, Integer maxGroups) {
        return [
            SELECT
                CALENDAR_YEAR(Taken_At__c) y,
                CALENDAR_MONTH(Taken_At__c) mo,
                DAY_IN_MONTH(Taken_At__c) d,
                HOUR_IN_DAY(Taken_At__c) h,
                CreatedById,
                MIN(Taken_At__c) firstAt,
                MAX(Taken_At__c) lastAt,
                COUNT(Id) n,
                COUNT_DISTINCT(Field_Name__c) fieldCount,
                SUM(Filled_Count__c) filled,
                SUM(Record_Count__c) total
            FROM Field_Utilization_Snapshot__c
            WHERE Object_Name__c = :objectName AND Taken_At__c != NULL
            WITH USER_MODE
            GROUP BY
                CALENDAR_YEAR(Taken_At__c),
                CALENDAR_MONTH(Taken_At__c),
                DAY_IN_MONTH(Taken_At__c),
                HOUR_IN_DAY(Taken_At__c),
                CreatedById
            ORDER BY MAX(Taken_At__c) DESC
            LIMIT :maxGroups
        ];
    }

    /** The counts one person saved between two times, thin, for splitting a group of saves. */
    public static List<Field_Utilization_Snapshot__c> rowsBetween(
        String objectName,
        Id savedBy,
        Datetime firstAt,
        Datetime lastAt
    ) {
        return [
            SELECT Taken_At__c, Field_Name__c, Filled_Count__c, Record_Count__c
            FROM Field_Utilization_Snapshot__c
            WHERE
                Object_Name__c = :objectName
                AND CreatedById = :savedBy
                AND Taken_At__c >= :firstAt
                AND Taken_At__c <= :lastAt
            WITH USER_MODE
            LIMIT :MAX_ROWS
        ];
    }

    /** The names of the people who saved, by user Id. */
    public static Map<Id, String> userNames(Set<Id> userIds) {
        Map<Id, String> names = new Map<Id, String>();
        for (User person : [SELECT Name FROM User WHERE Id IN :userIds WITH USER_MODE]) {
            names.put(person.Id, person.Name);
        }
        return names;
    }

    /** The object's rows from one save, by Id only, for deleting it. */
    public static List<Field_Utilization_Snapshot__c> idsAt(String objectName, Datetime takenAt) {
        return [
            SELECT Id
            FROM Field_Utilization_Snapshot__c
            WHERE Object_Name__c = :objectName AND Taken_At__c = :takenAt
            WITH USER_MODE
            LIMIT :MAX_ROWS
        ];
    }
}
