/**
 * Rewrites the name and greetings of every household the org has not taken over by hand.
 * Started from the settings page after a naming pattern changes. R-H14.
 */
public with sharing class HouseholdNamingBatch implements Database.Batchable<SObject>, Database.Stateful {
    public Integer householdsRead = 0;
    public Integer householdsChanged = 0;

    /**
     * Households left untouched because they already carry a native Nonprofit Cloud
     * household group, mutual exclusion (product-plan Section 11.2 item 9): BarnCRM
     * never rewrites the name or greetings of an Account somebody else's household model
     * owns.
     */
    public Integer householdsSkippedNative = 0;

    public Database.QueryLocator start(Database.BatchableContext context) {
        return HouseholdSelector.getHouseholdsForRecomputeLocator();
    }

    public void execute(Database.BatchableContext context, List<SObject> scope) {
        Set<Id> householdIds = new Map<Id, SObject>(scope).keySet();
        householdsRead += householdIds.size();
        // One predicate query for the whole scope, never one per household.
        Set<Id> nativeHouseholds = HouseholdSelector.nativeHouseholdAccountsAmong(householdIds);
        Set<Id> eligible = new Set<Id>(householdIds);
        eligible.removeAll(nativeHouseholds);
        householdsSkippedNative += nativeHouseholds.size();
        householdsChanged += HouseholdNamingService.applyNaming(eligible);
    }

    public void finish(Database.BatchableContext context) {
        // Counts stay on the job (read, rewritten, and left alone because the household is a
        // native Nonprofit Cloud one) so that the settings page can report what happened;
        // there is nothing further to do once the batch is done.
        return;
    }
}
