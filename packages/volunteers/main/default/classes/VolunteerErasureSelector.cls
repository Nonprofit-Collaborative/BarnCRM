/**
 * The reads erasing a person needs (R-ER5, R-ER8): every Volunteers record that names the
 * person, in system mode, so a record the person erasing cannot see is still found and the
 * erasure then refuses rather than leaving it behind. Each read is capped, as Giving's are.
 *
 * `without sharing` (ADR-0021): hours and requirements are Private, and a read limited by the
 * eraser's sharing would leave another user's entry, notes included, behind while reporting the
 * person erased. It returns only Ids, notes, rejection reasons, statuses, shift start times, and
 * what identifies a generated letter file, and every change but a letter's delete is then made as
 * the user (`VolunteersErasureExtension`), which is what refuses a user who may not.
 */
public without sharing class VolunteerErasureSelector {
    private static final Integer CAP = 10000;

    public static List<Volunteer_Hours__c> hoursOf(Set<Id> contacts, Set<Id> accounts) {
        return [
            SELECT Id, Notes__c, Rejection_Reason__c
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

    /**
     * The person's files that may be letters BarnCRM generated (R-VL4): saved under the letter
     * file name and first published on the person. The caller also matches each title against a
     * letter template, so no other file is ever taken.
     */
    public static List<ContentDocumentLink> letterFilesOf(Id personId) {
        List<ContentDocumentLink> found = new List<ContentDocumentLink>();
        for (ContentDocumentLink link : [
            SELECT
                ContentDocumentId,
                ContentDocument.Title,
                ContentDocument.FileType,
                ContentDocument.LatestPublishedVersion.PathOnClient,
                ContentDocument.LatestPublishedVersion.FirstPublishLocationId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :personId
            WITH SYSTEM_MODE
            LIMIT :CAP
        ]) {
            ContentVersion latest = link.ContentDocument?.LatestPublishedVersion;
            if (
                latest != null &&
                latest.PathOnClient == VolunteerLetterService.FILE_NAME &&
                latest.FirstPublishLocationId == personId
            ) {
                found.add(link);
            }
        }
        return found;
    }

    /** The names of every letter template, which start the titles of the letters made from it. */
    public static Set<String> letterTemplateNames() {
        Set<String> names = new Set<String>();
        for (Volunteer_Letter_Template__c template : [
            SELECT Name
            FROM Volunteer_Letter_Template__c
            WITH SYSTEM_MODE
            LIMIT :CAP
        ]) {
            names.add(template.Name);
        }
        return names;
    }
}
