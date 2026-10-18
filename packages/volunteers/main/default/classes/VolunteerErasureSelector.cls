/**
 * The reads erasing a person needs (R-ER5, R-ER8): every Volunteers record that names the
 * person, in system mode, so a record the person erasing cannot see is still found and the
 * erasure then refuses rather than leaving it behind. Each read is capped, as Giving's are.
 *
 * `without sharing` (ADR-0021): hours and requirements are Private, and a read limited by the
 * eraser's sharing would leave another user's entry, notes included, behind while reporting the
 * person erased. It returns only Ids, notes, statuses and shift start times, and every change is
 * then made as the user (`VolunteersErasureExtension`), which is what refuses a user who may not.
 */
public without sharing class VolunteerErasureSelector {
    private static final Integer CAP = 10000;

    public static List<Volunteer_Hours__c> hoursOf(Set<Id> contacts, Set<Id> accounts) {
        return [
            SELECT Id, Notes__c
            FROM Volunteer_Hours__c
            WHERE Contact__c IN :contacts OR Account__c IN :accounts
            WITH SYSTEM_MODE
            LIMIT :CAP
        ];
    }

    public static List<Volunteer_Signup__c> signupsOf(Set<Id> contacts, Set<Id> accounts) {
        return [
            SELECT Id, Status__c, Notes__c, Volunteer_Shift__r.Start_Time__c
            FROM Volunteer_Signup__c
            WHERE Contact__c IN :contacts OR Account__c IN :accounts
            WITH SYSTEM_MODE
            LIMIT :CAP
        ];
    }

    public static List<Volunteer_Skill__c> skillsOf(Set<Id> contacts, Set<Id> accounts) {
        return [
            SELECT Id
            FROM Volunteer_Skill__c
            WHERE Contact__c IN :contacts OR Account__c IN :accounts
            WITH SYSTEM_MODE
            LIMIT :CAP
        ];
    }

    public static List<Volunteer_Requirement__c> requirementsOf(
        Set<Id> contacts,
        Set<Id> accounts
    ) {
        return [
            SELECT Id
            FROM Volunteer_Requirement__c
            WHERE Contact__c IN :contacts OR Account__c IN :accounts
            WITH SYSTEM_MODE
            LIMIT :CAP
        ];
    }
}
