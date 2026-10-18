/**
 * The reads behind the Volunteers Health Check findings (`VolunteersHealthCheckExtension`).
 *
 * `without sharing` and `WITH SYSTEM_MODE`, as `HealthCheckGivingSelector` reads gifts
 * (ADR-0021, ADR-0057): Volunteer Hours are Private, so a count limited by the administrator's
 * own sharing would be a wrong answer, not a narrower one. Each method asserts that the running
 * user may manage settings itself, not only its caller, because that permission is what makes an
 * organization-wide count safe to show. Each count stops at the cap it is given.
 */
public without sharing class VolunteerHealthCheckSelector {
    public class NotAllowedException extends Exception {
    }

    private static void requireManageSettings() {
        if (!HealthCheckService.canManageSettings()) {
            throw new NotAllowedException('Health Check findings need Manage BarnCRM Settings.');
        }
    }

    /** Submitted hours entered before this moment, oldest first. */
    public static List<Volunteer_Hours__c> hoursWaitingSince(Datetime enteredBefore, Integer cap) {
        requireManageSettings();
        return [
            SELECT Id, Name
            FROM Volunteer_Hours__c
            WHERE
                Status__c = :VolunteerHoursService.STATUS_SUBMITTED
                AND CreatedDate < :enteredBefore
            WITH SYSTEM_MODE
            ORDER BY CreatedDate
            LIMIT :cap
        ];
    }

    /** Open shifts that ended before this moment, oldest first. */
    public static List<Volunteer_Shift__c> openShiftsEndedBefore(
        Datetime endedBefore,
        Integer cap
    ) {
        requireManageSettings();
        return [
            SELECT Id, Name
            FROM Volunteer_Shift__c
            WHERE Status__c = :ShiftScheduleService.STATUS_OPEN AND End_Time__c < :endedBefore
            WITH SYSTEM_MODE
            ORDER BY End_Time__c
            LIMIT :cap
        ];
    }

    /**
     * Active schedules that could be short of the horizon: running on or after today, starting by
     * the horizon, and with nothing created yet or created only to before `createdBefore`. The
     * caller compares each with its own End Date.
     */
    public static List<Shift_Schedule__c> schedulesShortOf(
        Date today,
        Date horizon,
        Date createdBefore,
        Integer cap
    ) {
        requireManageSettings();
        return [
            SELECT Id, Name, End_Date__c, Created_Through__c
            FROM Shift_Schedule__c
            WHERE
                Active__c = TRUE
                AND Start_Date__c <= :horizon
                AND (End_Date__c = NULL
                OR End_Date__c >= :today)
                AND (Created_Through__c = NULL
                OR Created_Through__c < :createdBefore)
            WITH SYSTEM_MODE
            ORDER BY Name
            LIMIT :cap
        ];
    }
}
