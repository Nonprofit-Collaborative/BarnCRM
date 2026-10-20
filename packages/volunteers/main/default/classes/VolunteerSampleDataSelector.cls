/**
 * All SOQL for the Volunteers sample data set (C-10, canonical model Part G "Sample data"). No
 * other class in this feature issues a query directly (plan Section 9.3).
 *
 * The sample people are Core's: contacts flagged `Sample_Data__c`, in either membership mode,
 * because Core cannot create person accounts. The module's own records are found through the
 * two flagged kinds, jobs and skills: shifts, schedules, sign-ups and hours hang off a sample
 * job, and an hours entry, sign-up or volunteer skill counts as sample only when its person is a
 * sample person too, so a row somebody recorded for a real person is never taken. A sample shift
 * that also holds a real person's sign-up or hours is not taken either, nor its job, nor a sample
 * skill a real person or job holds; the "what real records keep" reads find them so the removal
 * can leave them out and name them. Everything reads in the user's own access, as Giving's does.
 */
public with sharing class VolunteerSampleDataSelector {
    /** Up to `cap` sample people, in the order of the key Core's generator gave them. */
    public List<Contact> samplePeople(Integer cap) {
        return [
            SELECT Id
            FROM Contact
            WHERE Sample_Data__c = TRUE
            WITH USER_MODE
            ORDER BY Sample_Data_Key__c NULLS LAST, Id
            LIMIT :cap
        ];
    }

    public List<Volunteer_Job__c> sampleJobs() {
        return [
            SELECT Id, Name
            FROM Volunteer_Job__c
            WHERE Sample_Data__c = TRUE
            WITH USER_MODE
            ORDER BY Name
        ];
    }

    /** The one-off sample shifts, oldest first; shifts a schedule created are left out. */
    public List<Volunteer_Shift__c> sampleOneOffShifts() {
        return [
            SELECT Id, Volunteer_Job__c, Start_Time__c, End_Time__c
            FROM Volunteer_Shift__c
            WHERE Volunteer_Job__r.Sample_Data__c = TRUE AND Shift_Schedule__c = NULL
            WITH USER_MODE
            ORDER BY Start_Time__c, Id
        ];
    }

    /** Sample hours entries, newest worked first, up to `cap`. */
    public List<Volunteer_Hours__c> sampleHours(Integer cap) {
        return [
            SELECT Id, Status__c
            FROM Volunteer_Hours__c
            WHERE Volunteer_Job__r.Sample_Data__c = TRUE AND Contact__r.Sample_Data__c = TRUE
            WITH USER_MODE
            ORDER BY Date_Worked__c DESC, Id
            LIMIT :cap
        ];
    }

    public Integer countSampleHours() {
        return [
            SELECT COUNT()
            FROM Volunteer_Hours__c
            WHERE Volunteer_Job__r.Sample_Data__c = TRUE AND Contact__r.Sample_Data__c = TRUE
            WITH USER_MODE
        ];
    }

    // ---------------------------------------------------------------- removal, in its order

    /** Sample people's sign-ups on the sample jobs' shifts. */
    public List<Id> signupIds(Integer cap) {
        return idsOf(
            [
                SELECT Id
                FROM Volunteer_Signup__c
                WHERE
                    Volunteer_Shift__r.Volunteer_Job__r.Sample_Data__c = TRUE
                    AND Contact__r.Sample_Data__c = TRUE
                WITH USER_MODE
                LIMIT :cap
            ]
        );
    }

    /**
     * The sample jobs' shifts that no real person is signed up for or has hours on. A shift with
     * either is kept, with its sign-ups and hours, so its job is kept too (R-VJ1).
     */
    public List<Id> shiftIds(Integer cap) {
        return idsOf(
            [
                SELECT Id
                FROM Volunteer_Shift__c
                WHERE
                    Volunteer_Job__r.Sample_Data__c = TRUE
                    AND Id NOT IN (
                        SELECT Volunteer_Shift__c
                        FROM Volunteer_Signup__c
                        WHERE Contact__c = NULL OR Contact__r.Sample_Data__c = FALSE
                    )
                    AND Id NOT IN (
                        SELECT Volunteer_Shift__c
                        FROM Volunteer_Hours__c
                        WHERE
                            Volunteer_Shift__c != NULL
                            AND (Contact__c = NULL
                            OR Contact__r.Sample_Data__c = FALSE)
                    )
                WITH USER_MODE
                LIMIT :cap
            ]
        );
    }

    public List<Id> scheduleIds(Integer cap) {
        return idsOf(
            [
                SELECT Id
                FROM Shift_Schedule__c
                WHERE Job__r.Sample_Data__c = TRUE
                WITH USER_MODE
                LIMIT :cap
            ]
        );
    }

    /** The sample jobs, less those real records keep. */
    public List<Id> jobIds(Integer cap, Set<Id> kept) {
        return idsOf(
            [
                SELECT Id
                FROM Volunteer_Job__c
                WHERE Sample_Data__c = TRUE AND Id NOT IN :kept
                WITH USER_MODE
                LIMIT :cap
            ]
        );
    }

    /**
     * Volunteer skills held by a sample person. A real person's row on a sample skill is kept, so
     * the skill is kept too (its Restrict lookup).
     */
    public List<Id> volunteerSkillIds(Integer cap) {
        return idsOf(
            [
                SELECT Id
                FROM Volunteer_Skill__c
                WHERE Contact__r.Sample_Data__c = TRUE
                WITH USER_MODE
                LIMIT :cap
            ]
        );
    }

    public List<Id> requirementIds(Integer cap) {
        return idsOf(
            [
                SELECT Id
                FROM Volunteer_Requirement__c
                WHERE Contact__r.Sample_Data__c = TRUE
                WITH USER_MODE
                LIMIT :cap
            ]
        );
    }

    public List<Id> skillIds(Integer cap) {
        return skillIds(cap, new Set<Id>());
    }

    /** The sample skills, less those real records keep. */
    public List<Id> skillIds(Integer cap, Set<Id> kept) {
        return idsOf(
            [
                SELECT Id
                FROM Skill__c
                WHERE Sample_Data__c = TRUE AND Id NOT IN :kept
                WITH USER_MODE
                LIMIT :cap
            ]
        );
    }

    // ------------------------------------------------------- what real records keep from removal

    /** Real people's sign-ups on the sample jobs' shifts: each keeps its shift and so its job. */
    public List<Volunteer_Signup__c> realSignupsOnSampleShifts(Integer cap) {
        return [
            SELECT
                Volunteer_Shift__c,
                Volunteer_Shift__r.Name,
                Volunteer_Shift__r.Volunteer_Job__c,
                Volunteer_Shift__r.Volunteer_Job__r.Name,
                Contact__r.Name,
                Account__r.Name
            FROM Volunteer_Signup__c
            WHERE
                Volunteer_Shift__r.Volunteer_Job__r.Sample_Data__c = TRUE
                AND (Contact__c = NULL
                OR Contact__r.Sample_Data__c = FALSE)
            WITH USER_MODE
            ORDER BY Volunteer_Shift__r.Start_Time__c, Id
            LIMIT :cap
        ];
    }

    /**
     * Real people's hours on a sample job or a sample job's shift: each keeps its shift, when it
     * names one, and its job (R-VJ1).
     */
    public List<Volunteer_Hours__c> realHoursOnSampleJobs(Integer cap) {
        return [
            SELECT
                Volunteer_Job__c,
                Volunteer_Job__r.Name,
                Volunteer_Job__r.Sample_Data__c,
                Volunteer_Shift__c,
                Volunteer_Shift__r.Name,
                Volunteer_Shift__r.Volunteer_Job__c,
                Volunteer_Shift__r.Volunteer_Job__r.Name,
                Volunteer_Shift__r.Volunteer_Job__r.Sample_Data__c,
                Contact__r.Name,
                Account__r.Name
            FROM Volunteer_Hours__c
            WHERE
                (Volunteer_Job__r.Sample_Data__c = TRUE
                OR Volunteer_Shift__r.Volunteer_Job__r.Sample_Data__c = TRUE)
                AND (Contact__c = NULL
                OR Contact__r.Sample_Data__c = FALSE)
            WITH USER_MODE
            ORDER BY Date_Worked__c, Id
            LIMIT :cap
        ];
    }

    /** Real people's volunteer skills on sample skills: each keeps its skill (Restrict lookup). */
    public List<Volunteer_Skill__c> realVolunteerSkillsOnSampleSkills(Integer cap) {
        return [
            SELECT Skill__c, Skill__r.Name, Contact__r.Name, Account__r.Name
            FROM Volunteer_Skill__c
            WHERE
                Skill__r.Sample_Data__c = TRUE
                AND (Contact__c = NULL
                OR Contact__r.Sample_Data__c = FALSE)
            WITH USER_MODE
            ORDER BY Skill__r.Name, Id
            LIMIT :cap
        ];
    }

    /** Real jobs' job skills on sample skills: each keeps its skill too (Restrict lookup). */
    public List<Job_Skill__c> realJobSkillsOnSampleSkills(Integer cap) {
        return [
            SELECT Skill__c, Skill__r.Name, Job__r.Name
            FROM Job_Skill__c
            WHERE Skill__r.Sample_Data__c = TRUE AND Job__r.Sample_Data__c = FALSE
            WITH USER_MODE
            ORDER BY Skill__r.Name, Id
            LIMIT :cap
        ];
    }

    /**
     * How many of each kind the removal deletes, in removal order. Shifts are counted before
     * their sample sign-ups go, so a kept shift is counted too: at worst one stage too many,
     * which deletes nothing.
     */
    public List<Integer> removalCounts() {
        return new List<Integer>{
            countSampleHours(),
            [
                SELECT COUNT()
                FROM Volunteer_Signup__c
                WHERE
                    Volunteer_Shift__r.Volunteer_Job__r.Sample_Data__c = TRUE
                    AND Contact__r.Sample_Data__c = TRUE
                WITH USER_MODE
            ],
            [
                SELECT COUNT()
                FROM Volunteer_Shift__c
                WHERE Volunteer_Job__r.Sample_Data__c = TRUE
                WITH USER_MODE
            ],
            [
                SELECT COUNT()
                FROM Shift_Schedule__c
                WHERE Job__r.Sample_Data__c = TRUE
                WITH USER_MODE
            ],
            [SELECT COUNT() FROM Volunteer_Job__c WHERE Sample_Data__c = TRUE WITH USER_MODE],
            [
                SELECT COUNT()
                FROM Volunteer_Skill__c
                WHERE Contact__r.Sample_Data__c = TRUE
                WITH USER_MODE
            ],
            [
                SELECT COUNT()
                FROM Volunteer_Requirement__c
                WHERE Contact__r.Sample_Data__c = TRUE
                WITH USER_MODE
            ],
            [SELECT COUNT() FROM Skill__c WHERE Sample_Data__c = TRUE WITH USER_MODE]
        };
    }

    private static List<Id> idsOf(List<SObject> records) {
        return new List<Id>(new Map<Id, SObject>(records).keySet());
    }
}
