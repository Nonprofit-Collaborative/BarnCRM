/**
 * Starts the stewardship plans a gift calls for, after the gift is saved.
 *
 * After insert rather than before, and last in the gift automations at order 60, because a plan is
 * started against a gift whose allocations, commitment link and soft credits have already settled,
 * and because a plan holds a lookup to the gift, which needs the gift to have an id.
 *
 * Registered in `Automation_Registry__mdt` with Always Runs false, so an administrator can switch
 * it off before a bulk import (R-SP1). Nothing is started retroactively when it is switched back
 * on: a welcome sequence for a gift from three weeks ago is not a welcome, and the registry row
 * says so where the administrator reads it.
 */
@NamespaceAccessible
public with sharing class StewardshipTriggerHandler extends TriggerHandler {
    private static final String CONTEXT = 'Stewardship plans';

    @NamespaceAccessible
    public StewardshipTriggerHandler() {
        return;
    }

    public override void afterInsert() {
        start();
    }

    private void start() {
        List<SObject> records = newRecords();
        if (records == null || records.isEmpty()) {
            return;
        }
        try {
            StewardshipService.startForGifts((List<Gift__c>) records);
        } catch (Exception failure) {
            // A plan that could not start must not stop somebody recording a gift (R-SP9).
            ErrorLogger.log(failure, CONTEXT);
        }
    }
}
