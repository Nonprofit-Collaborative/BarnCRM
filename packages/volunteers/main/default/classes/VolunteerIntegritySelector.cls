/**
 * The reads the Volunteers rules make about what already exists in the org, whoever is saving
 * (R-VJ1, R-VU2, R-VU3). ADR-0021 (system mode for package owned data).
 *
 * `without sharing` and `WITH SYSTEM_MODE`, because each answer is a fact about the org, not
 * about what the saving user may see: hours another staff member entered, which the user cannot
 * see under private sharing, must still keep their job from being deleted; a sign-up the user
 * cannot see must still stop a second one for the same person on the same shift; and an entry
 * attendance already created must still stop a second one. What the user learns is limited to
 * the refusal itself, naming only the shift or job they are saving against. No field of a hidden
 * record is shown, and nothing reaches a dynamic query.
 */
public without sharing class VolunteerIntegritySelector {
    /** How many shifts each of these jobs has. A job with none is absent. */
    public static Map<Id, Integer> countShiftsByJob(Set<Id> jobIds) {
        Map<Id, Integer> counts = new Map<Id, Integer>();
        if (jobIds == null || jobIds.isEmpty()) {
            return counts;
        }
        for (AggregateResult row : [
            SELECT Volunteer_Job__c jobId, COUNT(Id) total
            FROM Volunteer_Shift__c
            WHERE Volunteer_Job__c IN :jobIds
            WITH SYSTEM_MODE
            GROUP BY Volunteer_Job__c
        ]) {
            counts.put((Id) row.get('jobId'), (Integer) row.get('total'));
        }
        return counts;
    }

    /**
     * How many hours entries, of any status, each of these jobs carries. Hours outlive their
     * shift (R-VG3), so they are counted on their own rather than through the shifts.
     */
    public static Map<Id, Integer> countHoursByJob(Set<Id> jobIds) {
        Map<Id, Integer> counts = new Map<Id, Integer>();
        if (jobIds == null || jobIds.isEmpty()) {
            return counts;
        }
        for (AggregateResult row : [
            SELECT Volunteer_Job__c jobId, COUNT(Id) total
            FROM Volunteer_Hours__c
            WHERE Volunteer_Job__c IN :jobIds
            WITH SYSTEM_MODE
            GROUP BY Volunteer_Job__c
        ]) {
            counts.put((Id) row.get('jobId'), (Integer) row.get('total'));
        }
        return counts;
    }

    /** The sign-ups on these shifts that name one of these people, for R-VU2. */
    public static List<Volunteer_Signup__c> selectSignupsFor(
        Set<Id> shiftIds,
        Set<Id> contactIds,
        Set<Id> accountIds
    ) {
        if (shiftIds == null || shiftIds.isEmpty()) {
            return new List<Volunteer_Signup__c>();
        }
        return [
            SELECT Id, Volunteer_Shift__c, Contact__c, Account__c
            FROM Volunteer_Signup__c
            WHERE
                Volunteer_Shift__c IN :shiftIds
                AND (Contact__c IN :contactIds
                OR Account__c IN :accountIds)
            WITH SYSTEM_MODE
        ];
    }

    /** Which of these sign-ups an hours entry already names, for R-VU3. */
    public static Set<Id> selectSignupsWithHours(Set<Id> signupIds) {
        Set<Id> withHours = new Set<Id>();
        if (signupIds == null || signupIds.isEmpty()) {
            return withHours;
        }
        for (Volunteer_Hours__c entry : [
            SELECT Volunteer_Signup__c
            FROM Volunteer_Hours__c
            WHERE Volunteer_Signup__c IN :signupIds
            WITH SYSTEM_MODE
        ]) {
            withHours.add(entry.Volunteer_Signup__c);
        }
        return withHours;
    }
}
