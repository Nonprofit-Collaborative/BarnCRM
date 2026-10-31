/**
 * The reads service delivery makes for the person using it, in user mode (P-02).
 */
public with sharing class ServiceDeliverySelector {
    /** The program's active services, by name. */
    public static List<Service__c> selectActiveServices(Id programId) {
        return [
            SELECT Id, Name, Unit_Of_Measure__c
            FROM Service__c
            WHERE Program__c = :programId AND Active__c = TRUE
            WITH USER_MODE
            ORDER BY Name
        ];
    }

    /** The deliveries of this service on this day, oldest first, at most `howMany`. */
    public static List<Service_Delivery__c> selectDeliveriesOn(
        Id serviceId,
        Date deliveryDate,
        Integer howMany
    ) {
        return [
            SELECT
                Id,
                Contact__c,
                Contact__r.Name,
                Account__c,
                Account__r.Name,
                Enrollment__c,
                Attendance__c,
                Quantity__c
            FROM Service_Delivery__c
            WHERE Service__c = :serviceId AND Delivery_Date__c = :deliveryDate
            WITH USER_MODE
            ORDER BY CreatedDate, Name
            LIMIT :howMany
        ];
    }

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
