/**
 * Puts the survivors of a Salesforce merge right once the merge is saved (PEOPLE-15).
 *
 * The platform's merge moves the other record's children onto the survivor without saving
 * them, so no trigger on a child runs, and it refuses a trigger's write to the records in the
 * merge. So the account and contact handlers name the survivors here, from `after delete`,
 * and this job, run just after the save as RollupService.runForSurvivors runs the totals,
 * does what the children's own triggers would have done:
 *
 * - a household that took in another household's members is recounted, renamed and given
 *   its primary again (never tidied away: it is the record the merge kept);
 * - a survivor that arrived with two default addresses keeps one (R-AD2);
 * - a person loses the relationships they now have with themselves and second copies of one
 *   they now hold twice, and their primary affiliation is chosen again.
 *
 * Each part is settled on its own, and a failure is logged without stopping the others.
 */
public with sharing class MergeSettlement implements Queueable {
    private final Set<Id> householdIds;
    private final Set<Id> ownerIds;
    private final Set<Id> personIds;

    /** The survivors the last call queued a job for, so a test can see what was asked. */
    @TestVisible
    private static Set<Id> lastQueued;

    @TestVisible
    private MergeSettlement(Set<Id> householdIds, Set<Id> ownerIds, Set<Id> personIds) {
        this.householdIds = householdIds;
        this.ownerIds = ownerIds;
        this.personIds = personIds;
    }

    /**
     * Queues the settlement of these survivors.
     *
     * @param householdIds households a merge folded another household into
     * @param ownerIds every survivor, as the owner of addresses
     * @param personIds the survivors that are people, contacts or person accounts
     *
     * A merge inside a Queueable is not given a job: that would take the one job the
     * running Queueable may chain, which its own work may need (RollupQueue keeps it free in
     * the same way). Nor is one queued when the transaction can queue no more. Either way
     * the survivors are named in the Error Log as a warning, so an administrator can check
     * them.
     */
    public static void afterMerge(Set<Id> householdIds, Set<Id> ownerIds, Set<Id> personIds) {
        Set<Id> survivors = new Set<Id>();
        survivors.addAll(householdIds);
        survivors.addAll(ownerIds);
        survivors.addAll(personIds);
        if (survivors.isEmpty()) {
            return;
        }
        if (System.isQueueable() || Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) {
            List<String> named = new List<String>();
            for (Id survivorId : survivors) {
                named.add(String.valueOf(survivorId));
            }
            ErrorLogger.logMessage(
                String.format(
                    Label.Core_Households_MergeSettleNotQueued,
                    new List<String>{ String.join(named, ', ') }
                ),
                Label.Core_Households_ErrorContextMergeSettle,
                ErrorLogger.SEVERITY_WARNING
            );
            return;
        }
        lastQueued = survivors;
        System.enqueueJob(new MergeSettlement(householdIds, ownerIds, personIds));
    }

    public void execute(QueueableContext context) {
        try {
            HouseholdService.afterMembershipChange(householdIds, false);
        } catch (Exception failed) {
            ErrorLogger.log(failed, Label.Core_Households_ErrorContextMergeSettle);
        }
        try {
            AddressService.keepOneDefault(ownerIds);
        } catch (Exception failed) {
            ErrorLogger.log(failed, Label.Core_Households_ErrorContextMergeSettle);
        }
        try {
            RelationshipService.removeSelfAndDuplicates(personIds);
        } catch (Exception failed) {
            ErrorLogger.log(failed, Label.Core_Households_ErrorContextMergeSettle);
        }
        try {
            AffiliationService.refreshPrimariesFor(personIds);
        } catch (Exception failed) {
            ErrorLogger.log(failed, Label.Core_Households_ErrorContextMergeSettle);
        }
    }
}
