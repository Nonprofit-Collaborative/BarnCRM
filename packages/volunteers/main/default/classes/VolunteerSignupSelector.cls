/**
 * The sign-up reads the shift's Sign-ups panel makes, in user mode: a coordinator sees and
 * changes only the sign-ups of a shift they can see. The integrity checks that must count every
 * sign-up in the org are in `VolunteerIntegritySelector`.
 */
public with sharing class VolunteerSignupSelector {
    /** The shift with what the panel shows of it, or null when the user cannot see it. */
    public static Volunteer_Shift__c selectShift(Id shiftId) {
        List<Volunteer_Shift__c> found = [
            SELECT Id, Name, Volunteers_Needed__c, Status__c
            FROM Volunteer_Shift__c
            WHERE Id = :shiftId
            WITH USER_MODE
            LIMIT 1
        ];
        return found.isEmpty() ? null : found[0];
    }

    /** The shift's sign-ups in the order they were made, at most `max`. */
    public static List<Volunteer_Signup__c> selectForShift(Id shiftId, Integer max) {
        return [
            SELECT
                Id,
                Name,
                Status__c,
                Notes__c,
                Contact__c,
                Contact__r.Name,
                Account__c,
                Account__r.Name
            FROM Volunteer_Signup__c
            WHERE Volunteer_Shift__c = :shiftId
            WITH USER_MODE
            ORDER BY Name ASC
            LIMIT :max
        ];
    }

    /** R-VU4: the sign-ups that fill a place, every one not Cancelled. */
    public static Integer countFilled(Id shiftId) {
        return [
            SELECT COUNT()
            FROM Volunteer_Signup__c
            WHERE
                Volunteer_Shift__c = :shiftId
                AND Status__c != :VolunteerSignupService.STATUS_CANCELLED
            WITH USER_MODE
        ];
    }

    /** The sign-up with this Id, its shift and status, or null when the user cannot see it. */
    public static Volunteer_Signup__c selectById(Id signupId) {
        List<Volunteer_Signup__c> found = [
            SELECT Id, Volunteer_Shift__c, Status__c
            FROM Volunteer_Signup__c
            WHERE Id = :signupId
            WITH USER_MODE
            LIMIT 1
        ];
        return found.isEmpty() ? null : found[0];
    }

    /** How many hours entries the user can see that name this sign-up (R-VU3). */
    public static Integer countHoursFor(Id signupId) {
        return [
            SELECT COUNT()
            FROM Volunteer_Hours__c
            WHERE Volunteer_Signup__c = :signupId
            WITH USER_MODE
        ];
    }
}
