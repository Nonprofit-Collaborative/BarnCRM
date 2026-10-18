/**
 * The job reads the Volunteers rules make, in user mode: each is about a job the user is saving
 * a shift against.
 */
public with sharing class VolunteerJobSelector {
    /** The names of these jobs. A job the user cannot see is absent. */
    public static Map<Id, String> selectNamesByIds(Set<Id> jobIds) {
        Map<Id, String> names = new Map<Id, String>();
        if (jobIds == null || jobIds.isEmpty()) {
            return names;
        }
        for (Volunteer_Job__c job : [
            SELECT Id, Name
            FROM Volunteer_Job__c
            WHERE Id IN :jobIds
            WITH USER_MODE
        ]) {
            names.put(job.Id, job.Name);
        }
        return names;
    }
}
