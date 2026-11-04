/**
 * R-GP3 for Grant_Payment__c, run by the Core trigger dispatcher through the registry row
 * `Grant_Payment_Received`, switchable from the Automation page (ADR-0017): it fills in an empty
 * Received Date when a payment becomes Received, and keeps a restricted grant's Received ledger
 * entry in step with each received payment. It does work for the user rather than enforcing a
 * rule, so an import of past payments and entries can turn it off.
 */
@NamespaceAccessible
public with sharing class GrantPaymentReceivedHandler extends TriggerHandler {
    @NamespaceAccessible
    public GrantPaymentReceivedHandler() {
        return;
    }

    public override String getName() {
        return 'GrantPaymentReceivedHandler';
    }

    public override void beforeInsert() {
        GrantPaymentService.fillReceivedDates((List<Grant_Payment__c>) newRecords(), null);
    }

    public override void beforeUpdate() {
        GrantPaymentService.fillReceivedDates(
            (List<Grant_Payment__c>) newRecords(),
            (Map<Id, Grant_Payment__c>) oldRecordsById()
        );
    }

    public override void afterInsert() {
        GrantPaymentService.syncLedger((List<Grant_Payment__c>) newRecords(), false);
    }

    public override void afterUpdate() {
        GrantPaymentService.syncLedger((List<Grant_Payment__c>) newRecords(), false);
    }

    public override void beforeDelete() {
        GrantPaymentService.syncLedger((List<Grant_Payment__c>) oldRecords(), true);
    }
}
