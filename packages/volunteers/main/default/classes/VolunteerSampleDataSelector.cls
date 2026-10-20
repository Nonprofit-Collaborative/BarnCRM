/**
 * All SOQL for the Volunteers sample data set (C-10, canonical model Part G "Sample data"). No
 * other class in this feature issues a query directly (plan Section 9.3).
 *
 * The sample people are Core's: contacts flagged `Sample_Data__c`, in either membership mode,
 * because Core cannot create person accounts. The module's own records are found through the
 * two flagged kinds, jobs and skills: shifts, schedules, sign-ups and hours hang off a sample
 * job, and an hours entry counts as sample only when its person is a sample person too, so an
 * entry somebody recorded for a real person is never taken. Everything reads in the user's own
 * access, as Giving's does.
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

    public List<Id> shiftIds(Integer cap) {
        return idsOf(
            [
                SELECT Id
                FROM Volunteer_Shift__c
                WHERE Volunteer_Job__r.Sample_Data__c = TRUE
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

    public List<Id> jobIds(Integer cap) {
        return idsOf(
            [SELECT Id FROM Volunteer_Job__c WHERE Sample_Data__c = TRUE WITH USER_MODE LIMIT :cap]
        );
    }

    /** Volunteer skills naming a sample skill or held by a sample person. */
    public List<Id> volunteerSkillIds(Integer cap) {
        return idsOf(
            [
                SELECT Id
                FROM Volunteer_Skill__c
                WHERE Skill__r.Sample_Data__c = TRUE OR Contact__r.Sample_Data__c = TRUE
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
        return idsOf(
            [SELECT Id FROM Skill__c WHERE Sample_Data__c = TRUE WITH USER_MODE LIMIT :cap]
        );
    }

    /** How many of each kind the removal deletes, in removal order. */
    public List<Integer> removalCounts() {
        return new List<Integer>{
            countSampleHours(),
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
                WHERE Skill__r.Sample_Data__c = TRUE OR Contact__r.Sample_Data__c = TRUE
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
