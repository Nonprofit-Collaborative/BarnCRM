/**
 * The reads behind Suggested Volunteers on a shift (V-11), all in user mode: the panel suggests
 * only people, skills, hours and onboarding steps the signed-in user may see, so a user without
 * access to onboarding steps simply gets no onboarding signal.
 */
public with sharing class VolunteerSuggestionSelector {
    /** The shift with what the suggestions need of it, or null when the user cannot see it. */
    public static Volunteer_Shift__c selectShift(Id shiftId) {
        List<Volunteer_Shift__c> found = [
            SELECT Id, Name, Status__c, Start_Time__c, Volunteer_Job__c
            FROM Volunteer_Shift__c
            WHERE Id = :shiftId
            WITH USER_MODE
            LIMIT 1
        ];
        return found.isEmpty() ? null : found[0];
    }

    /** The skills the shift's job asks for. */
    public static Set<Id> requiredSkillIds(Id jobId) {
        Set<Id> ids = new Set<Id>();
        for (Job_Skill__c row : [
            SELECT Skill__c
            FROM Job_Skill__c
            WHERE Job__c = :jobId AND Skill__r.Active__c = TRUE
            WITH USER_MODE
            LIMIT 200
        ]) {
            ids.add(row.Skill__c);
        }
        return ids;
    }

    /**
     * Active volunteers with no sign-up of any status on this shift (a second one would be
     * refused, R-VU2), the most hours first, at most `max`.
     */
    public static List<Contact> selectCandidates(Id shiftId, Integer max) {
        return [
            SELECT Id, Name, Availability_Days__c, Volunteer_Hours_Total__c
            FROM Contact
            WHERE
                Volunteer_Status__c = 'Active'
                AND Id NOT IN (
                    SELECT Contact__c
                    FROM Volunteer_Signup__c
                    WHERE Volunteer_Shift__c = :shiftId AND Contact__c != NULL
                )
            WITH USER_MODE
            ORDER BY Volunteer_Hours_Total__c DESC NULLS LAST, Name ASC
            LIMIT :max
        ];
    }

    /** These people's rows for the given skills, as skills and as interests. */
    public static List<Volunteer_Skill__c> selectSkillRows(Set<Id> contactIds, Set<Id> skillIds) {
        return [
            SELECT Contact__c, Skill__c, Type__c
            FROM Volunteer_Skill__c
            WHERE Contact__c IN :contactIds AND Skill__c IN :skillIds
            WITH USER_MODE
            LIMIT 10000
        ];
    }

    /** Approved hours each of these people gave on the job. */
    public static Map<Id, Decimal> approvedHoursOnJob(Set<Id> contactIds, Id jobId) {
        Map<Id, Decimal> hours = new Map<Id, Decimal>();
        for (AggregateResult row : [
            SELECT Contact__c person, SUM(Hours__c) total
            FROM Volunteer_Hours__c
            WHERE Contact__c IN :contactIds AND Volunteer_Job__c = :jobId AND Status__c = 'Approved'
            WITH USER_MODE
            GROUP BY Contact__c
        ]) {
            hours.put((Id) row.get('person'), (Decimal) row.get('total'));
        }
        return hours;
    }

    /** These people's onboarding steps, newest first, so the first of each Type is the latest. */
    public static List<Volunteer_Requirement__c> selectRequirements(Set<Id> contactIds) {
        if (!Schema.SObjectType.Volunteer_Requirement__c.isAccessible()) {
            return new List<Volunteer_Requirement__c>();
        }
        return [
            SELECT Contact__c, Type__c, Is_Current__c
            FROM Volunteer_Requirement__c
            WHERE Contact__c IN :contactIds
            WITH USER_MODE
            ORDER BY CreatedDate DESC, Id DESC
            LIMIT 10000
        ];
    }
}
