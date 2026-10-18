/**
 * The shift reads the Volunteers rules make, in user mode: each is about a shift the user is
 * saving hours or a sign-up against, so it reads what that user may see.
 */
public with sharing class VolunteerShiftSelector {
    /** The shifts with these Ids: their name, job and times. A shift the user cannot see is absent. */
    public static Map<Id, Volunteer_Shift__c> selectByIds(Set<Id> shiftIds) {
        if (shiftIds == null || shiftIds.isEmpty()) {
            return new Map<Id, Volunteer_Shift__c>();
        }
        return new Map<Id, Volunteer_Shift__c>(
            [
                SELECT Id, Name, Volunteer_Job__c, Start_Time__c, End_Time__c
                FROM Volunteer_Shift__c
                WHERE Id IN :shiftIds
                WITH USER_MODE
            ]
        );
    }
}
