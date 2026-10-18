/**
 * The hours reads `VolunteerHoursService` makes, in user mode: a coordinator approves,
 * rejects or reopens only the entries they can see.
 */
public with sharing class VolunteerHoursSelector {
    /** The entries with these Ids, with what a status change reads. */
    public static List<Volunteer_Hours__c> selectForStatusChange(Set<Id> hoursIds) {
        if (hoursIds == null || hoursIds.isEmpty()) {
            return new List<Volunteer_Hours__c>();
        }
        return [
            SELECT Id, Status__c, Rejection_Reason__c
            FROM Volunteer_Hours__c
            WHERE Id IN :hoursIds
            WITH USER_MODE
        ];
    }
}
