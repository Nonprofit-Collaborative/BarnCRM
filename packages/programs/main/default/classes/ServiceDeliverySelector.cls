/**
 * The reads service delivery makes for the person using it, in user mode (P-02).
 */
public with sharing class ServiceDeliverySelector {
    /** The program of each of these services the user can see. */
    public static Map<Id, Id> selectProgramIdsOf(Set<Id> serviceIds) {
        Map<Id, Id> programs = new Map<Id, Id>();
        for (Service__c service : [
            SELECT Id, Program__c
            FROM Service__c
            WHERE Id IN :serviceIds
            WITH USER_MODE
        ]) {
            programs.put(service.Id, service.Program__c);
        }
        return programs;
    }

    /** These people's enrollments in these programs, newest start first. */
    public static List<Enrollment__c> selectEnrollmentsFor(
        Set<Id> programIds,
        Set<Id> contactIds,
        Set<Id> accountIds
    ) {
        return [
            SELECT Id, Program__c, Contact__c, Account__c, Stage__c
            FROM Enrollment__c
            WHERE
                Program__c IN :programIds
                AND (Contact__c IN :contactIds
                OR Account__c IN :accountIds)
            WITH USER_MODE
            ORDER BY Start_Date__c DESC NULLS LAST, Name DESC
            LIMIT 10000
        ];
    }
}
