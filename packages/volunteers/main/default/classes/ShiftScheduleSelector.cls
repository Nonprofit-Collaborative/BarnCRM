/**
 * The shift schedule reads of recurring shifts (V-07, canonical model Section 29T).
 *
 * The schedules are read in user mode: a run works on the schedules its user may see. The
 * schedule's own shifts and their sign-ups are read in system mode, because a duplicate check
 * or a "has anyone signed up" check that missed a record the user cannot see would create a
 * second shift on a day or delete a shift someone is booked on.
 */
public with sharing class ShiftScheduleSelector {
    /**
     * The schedules with these Ids, locked for the rest of the transaction (R-SSC3), so the
     * queued run and the nightly run never create the same day twice.
     */
    public static List<Shift_Schedule__c> lockForRun(Set<Id> scheduleIds) {
        if (scheduleIds == null || scheduleIds.isEmpty()) {
            return new List<Shift_Schedule__c>();
        }
        return [
            SELECT
                Id,
                Job__c,
                Job__r.Name,
                Weekdays__c,
                Every_N_Weeks__c,
                Start_Time__c,
                End_Time__c,
                Start_Date__c,
                End_Date__c,
                Volunteers_Needed__c,
                Location__c,
                Active__c,
                Created_Through__c,
                Rebuild_Pending__c
            FROM Shift_Schedule__c
            WHERE Id IN :scheduleIds
            WITH USER_MODE
            FOR UPDATE
        ];
    }

    /**
     * Every schedule that may still create shifts, and every one a large save left shifts to
     * remove for (Rebuild Pending, R-SSC6), active or not, for the batch.
     */
    public static Database.QueryLocator runnableLocator(Set<Id> onlyIds, Date today) {
        if (onlyIds == null) {
            return Database.getQueryLocator(
                [
                    SELECT Id
                    FROM Shift_Schedule__c
                    WHERE
                        (Active__c = TRUE
                        AND (End_Date__c = NULL
                        OR End_Date__c >= :today))
                        OR Rebuild_Pending__c = TRUE
                    WITH USER_MODE
                    ORDER BY Id
                ]
            );
        }
        return Database.getQueryLocator(
            [
                SELECT Id
                FROM Shift_Schedule__c
                WHERE Id IN :onlyIds AND (Active__c = TRUE OR Rebuild_Pending__c = TRUE)
                WITH USER_MODE
                ORDER BY Id
            ]
        );
    }

    /** These shifts as they are now: their start and status, for a queued removal (R-SSC6). */
    public static List<Volunteer_Shift__c> shiftsById(Set<Id> shiftIds) {
        return [
            SELECT Id, Shift_Schedule__c, Start_Time__c, Status__c
            FROM Volunteer_Shift__c
            WHERE Id IN :shiftIds
            WITH SYSTEM_MODE
        ];
    }

    /** The schedules' shifts starting at or after `fromTime`: their schedule and start. */
    public static List<Volunteer_Shift__c> shiftsFrom(Set<Id> scheduleIds, Datetime fromTime) {
        return [
            SELECT Id, Shift_Schedule__c, Start_Time__c, Status__c
            FROM Volunteer_Shift__c
            WHERE Shift_Schedule__c IN :scheduleIds AND Start_Time__c >= :fromTime
            WITH SYSTEM_MODE
        ];
    }

    /**
     * Of these shifts, the Ids of those with a sign-up record of any status or an hours record.
     * Hours may name a shift with no sign-up, and deleting that shift would clear the hours' only
     * link to the work.
     */
    public static Set<Id> shiftsInUse(Set<Id> shiftIds) {
        Set<Id> inUse = new Set<Id>();
        if (shiftIds == null || shiftIds.isEmpty()) {
            return inUse;
        }
        for (AggregateResult row : [
            SELECT Volunteer_Shift__c shiftId
            FROM Volunteer_Signup__c
            WHERE Volunteer_Shift__c IN :shiftIds
            WITH SYSTEM_MODE
            GROUP BY Volunteer_Shift__c
        ]) {
            inUse.add((Id) row.get('shiftId'));
        }
        for (AggregateResult row : [
            SELECT Volunteer_Shift__c shiftId
            FROM Volunteer_Hours__c
            WHERE Volunteer_Shift__c IN :shiftIds
            WITH SYSTEM_MODE
            GROUP BY Volunteer_Shift__c
        ]) {
            inUse.add((Id) row.get('shiftId'));
        }
        return inUse;
    }

    /** The org's default time zone, which schedule times are read in (R-SSC1). */
    public static String orgTimeZone() {
        // System mode: the organization's own setting, which a user without View Setup may not query.
        return [SELECT TimeZoneSidKey FROM Organization WITH SYSTEM_MODE LIMIT 1].TimeZoneSidKey;
    }
}
