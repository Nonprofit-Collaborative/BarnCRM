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
    /**
     * Which of these jobs have at least one shift or one hours entry, of any status, for R-VJ1.
     * Hours outlive their shift (R-VG3), so both are asked. Existence, not a count: each query
     * returns at most one row per job however many shifts or entries it has, so deleting many
     * busy jobs at once stays far inside the query row limit.
     */
    public static Set<Id> selectJobIdsInUse(Set<Id> jobIds) {
        Set<Id> inUse = new Set<Id>();
        if (jobIds == null || jobIds.isEmpty()) {
            return inUse;
        }
        for (Volunteer_Job__c job : [
            SELECT Id
            FROM Volunteer_Job__c
            WHERE
                Id IN :jobIds
                AND Id IN (
                    SELECT Volunteer_Job__c
                    FROM Volunteer_Shift__c
                    WHERE Volunteer_Job__c IN :jobIds
                )
            WITH SYSTEM_MODE
        ]) {
            inUse.add(job.Id);
        }
        Set<Id> unanswered = new Set<Id>(jobIds);
        unanswered.removeAll(inUse);
        if (unanswered.isEmpty()) {
            return inUse;
        }
        for (Volunteer_Job__c job : [
            SELECT Id
            FROM Volunteer_Job__c
            WHERE
                Id IN :unanswered
                AND Id IN (
                    SELECT Volunteer_Job__c
                    FROM Volunteer_Hours__c
                    WHERE Volunteer_Job__c IN :unanswered
                )
            WITH SYSTEM_MODE
        ]) {
            inUse.add(job.Id);
        }
        return inUse;
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

    /** The live entries naming these sign-ups, for R-VU3 when an old entry is undeleted. */
    public static List<Volunteer_Hours__c> selectHoursNamingSignups(Set<Id> signupIds) {
        if (signupIds == null || signupIds.isEmpty()) {
            return new List<Volunteer_Hours__c>();
        }
        return [
            SELECT Id, Volunteer_Signup__c
            FROM Volunteer_Hours__c
            WHERE Volunteer_Signup__c IN :signupIds
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

    /**
     * The requirement rows and volunteer skills that name these contacts or accounts, keyed by
     * the record being deleted, for R-VQ5 and R-VK4. A row naming a contact of one of these
     * accounts is keyed by the account: the platform deletes an account's contacts with it, and
     * a person account's own contact is one of them. Read whoever deletes the person, since a
     * Team Member cannot see requirements but must not leave a background check behind.
     */
    public static Map<Id, Set<Id>> selectRowsNamingPeople(Set<Id> contactIds, Set<Id> accountIds) {
        Map<Id, Set<Id>> rowsByPerson = new Map<Id, Set<Id>>();
        if (contactIds.isEmpty() && accountIds.isEmpty()) {
            return rowsByPerson;
        }
        List<SObject> rows = new List<SObject>();
        rows.addAll(
            [
                SELECT Id, Contact__c, Account__c, Contact__r.AccountId
                FROM Volunteer_Requirement__c
                WHERE
                    Contact__c IN :contactIds
                    OR Account__c IN :accountIds
                    OR Contact__r.AccountId IN :accountIds
                WITH SYSTEM_MODE
            ]
        );
        rows.addAll(
            [
                SELECT Id, Contact__c, Account__c, Contact__r.AccountId
                FROM Volunteer_Skill__c
                WHERE
                    Contact__c IN :contactIds
                    OR Account__c IN :accountIds
                    OR Contact__r.AccountId IN :accountIds
                WITH SYSTEM_MODE
            ]
        );
        for (SObject row : rows) {
            Id person = (Id) row.get('Contact__c');
            if (!contactIds.contains(person)) {
                person = accountIds.contains((Id) row.get('Account__c'))
                    ? (Id) row.get('Account__c')
                    : (Id) row.getSObject('Contact__r').get('AccountId');
            }
            if (!rowsByPerson.containsKey(person)) {
                rowsByPerson.put(person, new Set<Id>());
            }
            rowsByPerson.get(person).add(row.Id);
        }
        return rowsByPerson;
    }
}
