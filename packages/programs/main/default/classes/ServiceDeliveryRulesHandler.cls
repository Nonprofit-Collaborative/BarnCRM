/**
 * R-SD2 and R-SD3 for Service_Delivery__c (canonical model 29Z), run by the Core trigger
 * dispatcher through the registry row `Service_Delivery_Rules`, which always runs: totals count
 * the Quantity and roster figures count by enrollment, so neither may be switched off
 * (ADR-0024). Before a save, an absence's Quantity is set to 0, and a delivery with no enrollment
 * is linked to the person's enrollment in the service's program: the open one, or else the one
 * that started last.
 */
@NamespaceAccessible
public with sharing class ServiceDeliveryRulesHandler extends TriggerHandler {
    @NamespaceAccessible
    public ServiceDeliveryRulesHandler() {
        return;
    }

    public override String getName() {
        return 'ServiceDeliveryRulesHandler';
    }

    public override void beforeInsert() {
        apply((List<Service_Delivery__c>) Trigger.new);
    }

    public override void beforeUpdate() {
        apply((List<Service_Delivery__c>) Trigger.new);
    }

    @TestVisible
    private static void apply(List<Service_Delivery__c> deliveries) {
        List<Service_Delivery__c> unlinked = new List<Service_Delivery__c>();
        for (Service_Delivery__c delivery : deliveries) {
            if (ServiceDeliveryService.isAbsence(delivery.Attendance__c)) {
                delivery.Quantity__c = 0;
            }
            if (
                delivery.Enrollment__c == null &&
                delivery.Service__c != null &&
                (delivery.Contact__c != null ||
                delivery.Account__c != null)
            ) {
                unlinked.add(delivery);
            }
        }
        if (!unlinked.isEmpty()) {
            ServiceDeliveryService.linkEnrollments(unlinked);
        }
    }
}
