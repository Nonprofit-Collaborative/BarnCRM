/**
 * Service delivery logic (P-02, canonical model 29ZB): the attendance values, and linking a
 * delivery to the person's enrollment in the service's program (R-SD3).
 */
@NamespaceAccessible
public with sharing class ServiceDeliveryService {
    @NamespaceAccessible
    public static final String PRESENT = 'Present';
    @NamespaceAccessible
    public static final String EXCUSED_ABSENCE = 'Excused Absence';
    @NamespaceAccessible
    public static final String UNEXCUSED_ABSENCE = 'Unexcused Absence';

    /** The attendance values, in picklist order. */
    public static final List<String> ATTENDANCE = new List<String>{
        PRESENT,
        EXCUSED_ABSENCE,
        UNEXCUSED_ABSENCE
    };

    /** Whether this attendance is an absence, which delivers nothing (R-SD2). */
    public static Boolean isAbsence(String attendance) {
        return attendance == EXCUSED_ABSENCE || attendance == UNEXCUSED_ABSENCE;
    }

    /**
     * Fills each delivery's empty enrollment with the person's enrollment in its service's
     * program: an open one first, else the one that started last (R-SD3). A person with no
     * enrollment there is left unlinked.
     */
    public static void linkEnrollments(List<Service_Delivery__c> deliveries) {
        Set<Id> serviceIds = new Set<Id>();
        Set<Id> contactIds = new Set<Id>();
        Set<Id> accountIds = new Set<Id>();
        for (Service_Delivery__c delivery : deliveries) {
            serviceIds.add(delivery.Service__c);
            if (delivery.Contact__c != null) {
                contactIds.add(delivery.Contact__c);
            }
            if (delivery.Account__c != null) {
                accountIds.add(delivery.Account__c);
            }
        }
        Map<Id, Id> programByService = ServiceDeliverySelector.selectProgramIdsOf(serviceIds);
        Map<String, Enrollment__c> best = new Map<String, Enrollment__c>();
        for (
            Enrollment__c enrollment : ServiceDeliverySelector.selectEnrollmentsFor(
                new Set<Id>(programByService.values()),
                contactIds,
                accountIds
            )
        ) {
            String key = enrollment.Program__c + ':' + personOf(enrollment);
            Enrollment__c current = best.get(key);
            // Ordered newest start first, so the first seen wins unless a later one is open.
            if (
                current == null ||
                (!EnrollmentService.isOpen(current.Stage__c) &&
                EnrollmentService.isOpen(enrollment.Stage__c))
            ) {
                best.put(key, enrollment);
            }
        }
        for (Service_Delivery__c delivery : deliveries) {
            Id programId = programByService.get(delivery.Service__c);
            Id person = delivery.Contact__c != null ? delivery.Contact__c : delivery.Account__c;
            Enrollment__c found = best.get(programId + ':' + person);
            if (found != null) {
                delivery.Enrollment__c = found.Id;
            }
        }
    }

    private static Id personOf(Enrollment__c enrollment) {
        return enrollment.Contact__c != null ? enrollment.Contact__c : enrollment.Account__c;
    }
}
