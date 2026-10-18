/**
 * The reads a volunteer letter makes, in the user's own access (R-VL3): a letter counts only the
 * hours, and names only the people, the person generating it can see.
 */
public with sharing class VolunteerLetterSelector {
    /** The active templates, one per type (R-VL1), for the record action to offer. */
    public static List<Volunteer_Letter_Template__c> activeTemplates() {
        return [
            SELECT Id, Name, Type__c
            FROM Volunteer_Letter_Template__c
            WHERE Active__c = TRUE
            WITH USER_MODE
            ORDER BY Type__c, Name
        ];
    }

    public static Volunteer_Letter_Template__c template(Id templateId) {
        List<Volunteer_Letter_Template__c> found = [
            SELECT Id, Name, Type__c, Body__c
            FROM Volunteer_Letter_Template__c
            WHERE Id = :templateId
            WITH USER_MODE
            LIMIT 1
        ];
        return found.isEmpty() ? null : found[0];
    }

    public static List<Contact> contacts(Set<Id> contactIds) {
        return [
            SELECT Id, Name, FirstName, Preferred_Name__c
            FROM Contact
            WHERE Id IN :contactIds
            WITH USER_MODE
        ];
    }

    /**
     * The person accounts among these, or none where person accounts are off. The person fields
     * are named as text, since they exist only where person accounts are on (ADR-0013).
     */
    public static List<Account> personAccounts(Set<Id> accountIds) {
        if (accountIds.isEmpty() || !OrgShapeDetector.hasPersonAccounts()) {
            return new List<Account>();
        }
        return Database.queryWithBinds(
            'SELECT Id, Name, FirstName, Preferred_Name__c FROM Account ' +
            'WHERE Id IN :accountIds AND RecordTypeId IN :personTypes',
            new Map<String, Object>{
                'accountIds' => accountIds,
                'personTypes' => OrgShapeDetector.personAccountRecordTypeIds()
            },
            AccessLevel.USER_MODE
        );
    }

    /** Approved hours in the period, summed per person and job. */
    public static List<AggregateResult> approvedHoursByJob(
        Set<Id> personIds,
        Date fromDate,
        Date toDate
    ) {
        return [
            SELECT Contact__c, Account__c, Volunteer_Job__r.Name jobName, SUM(Hours__c) total
            FROM Volunteer_Hours__c
            WHERE
                Status__c = :VolunteerHoursService.STATUS_APPROVED
                AND Date_Worked__c >= :fromDate
                AND Date_Worked__c <= :toDate
                AND (Contact__c IN :personIds
                OR Account__c IN :personIds)
            WITH USER_MODE
            GROUP BY Contact__c, Account__c, Volunteer_Job__r.Name
            ORDER BY Volunteer_Job__r.Name
        ];
    }
}
