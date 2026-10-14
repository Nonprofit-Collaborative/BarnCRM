/**
 * Puts the survivors of a Salesforce merge right once the merge is saved (PEOPLE-15).
 *
 * The platform's merge moves the other record's children onto the survivor without saving
 * them, so no trigger on a child runs, and it refuses a trigger's write to the records in the
 * merge. So the account and contact handlers name the survivors here, from `after delete`,
 * and this job, run just after the save as RollupService.runForSurvivors runs the totals,
 * does what the children's own triggers would have done:
 *
 * - a person who was in both merged households is left with one membership in the survivor,
 *   which keeps Is Primary if either row had it (junction mode);
 * - a household that took in another household's members is recounted, renamed and given
 *   its primary again (never tidied away: it is the record the merge kept);
 * - a survivor that arrived with two default addresses keeps one (R-AD2);
 * - a person loses the relationships they now have with themselves and second copies of one
 *   they now hold twice, and their primary affiliation is chosen again.
 *
 * Each part is settled on its own, and a failure is logged without stopping the others.
 *
 * A merge that cannot queue the job itself (inside a Queueable, or with no queueable job left)
 * publishes `Merge_Settlement_Ready__e` naming its survivors instead. The event is delivered
 * after the merge commits, and its subscriber queues this job in a fresh transaction (ADR-NEXT),
 * as `Rollup_Queue_Ready__e` starts the Rollup Queue (ADR-0100, ADR-0117).
 */
public with sharing class MergeSettlement implements Queueable {
    /** Identifiers one event carries per list: 200 of 18 characters and a comma fit the field. */
    @TestVisible
    private static final Integer IDS_PER_EVENT = 200;

    private static final String SEPARATOR = ',';

    /** The platform delivers a batch again after `RetryableException` nine times at most. */
    private static final Integer LAST_RETRY = 8;

    private final Set<Id> householdIds;
    private final Set<Id> ownerIds;
    private final Set<Id> personIds;

    /** The survivors the last call queued a job for, so a test can see what was asked. */
    @TestVisible
    private static Set<Id> lastQueued;

    /** The events the last call published, so a test can see what was asked. */
    @TestVisible
    private static List<Merge_Settlement_Ready__e> lastPublished;

    /** Test seam: true or false stands in for `System.isQueueable()`; null reads the platform. */
    @TestVisible
    private static Boolean queueableForTest;

    /** Test seam: a message here stands in for the platform refusing the publish. */
    @TestVisible
    private static String publishFailureForTest;

    /** Test seam: stands in for the jobs the subscriber's transaction may still queue. */
    @TestVisible
    private static Integer jobsLeftForTest;

    /** Test seam: stands in for the times the platform has delivered this batch again. */
    @TestVisible
    private static Integer retriesForTest;

    /** Every survivor the subscriber queued a job for, across its calls, for a test. */
    @TestVisible
    private static Set<Id> queuedByEvents;

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
     * A merge inside a Queueable does not queue the job: that would take the one job the
     * running Queueable may chain, which its own work may need (RollupQueue keeps it free in
     * the same way). Nor does one in a transaction that can queue no more. Either way it
     * publishes `Merge_Settlement_Ready__e` naming the survivors, delivered after commit, and
     * the subscriber queues the job (ADR-NEXT). Only a publish the platform refuses leaves the
     * survivors unsettled; they are then named in the Error Log as a warning, so an
     * administrator can check them.
     */
    public static void afterMerge(Set<Id> householdIds, Set<Id> ownerIds, Set<Id> personIds) {
        householdIds = householdIds == null ? new Set<Id>() : householdIds;
        ownerIds = ownerIds == null ? new Set<Id>() : ownerIds;
        personIds = personIds == null ? new Set<Id>() : personIds;
        Set<Id> survivors = new Set<Id>();
        survivors.addAll(householdIds);
        survivors.addAll(ownerIds);
        survivors.addAll(personIds);
        if (survivors.isEmpty()) {
            return;
        }
        if (inQueueable() || Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) {
            publish(householdIds, ownerIds, personIds, survivors);
            return;
        }
        lastQueued = survivors;
        System.enqueueJob(new MergeSettlement(householdIds, ownerIds, personIds));
    }

    /**
     * The subscriber of `Merge_Settlement_Ready__e`: queues one job per event, in the merge's
     * place. Its delivery batch is 50 events (`PlatformEventSubscriberConfig`), within the jobs
     * one transaction may queue, so normally every event is queued. Should the jobs run out
     * anyway, it sets a resume checkpoint after each event it queued and stops: the platform
     * sends the events after the checkpoint again in a new call. When not even the first
     * could be queued there is no checkpoint, so it asks for the whole batch again with
     * `EventBus.RetryableException` (nothing was queued, so nothing is undone); on the last
     * retry the platform allows it names the survivors in the Error Log instead. No event is
     * dropped silently.
     *
     * @param events the events delivered, oldest first
     */
    public static void settlePublished(List<Merge_Settlement_Ready__e> events) {
        Set<Id> queued = new Set<Id>();
        Integer room = jobsLeftForTest != null
            ? jobsLeftForTest
            : Limits.getLimitQueueableJobs() - Limits.getQueueableJobs();
        Integer queuedJobs = 0;
        for (Merge_Settlement_Ready__e event : events) {
            if (queuedJobs >= room) {
                if (queuedJobs == 0) {
                    Integer retries = retriesForTest != null
                        ? retriesForTest
                        : EventBus.TriggerContext.currentContext().retries;
                    if (retries < LAST_RETRY) {
                        throw new EventBus.RetryableException(
                            'No queueable job left to tidy up after a merge; delivering again.'
                        );
                    }
                    // The platform retries no further: name the survivors for an administrator.
                    logNotSettled(survivorsIn(events), 'No queueable job left');
                }
                break;
            }
            queuedJobs++;
            Set<Id> householdIds = idsIn(event.Household_Ids__c);
            Set<Id> ownerIds = idsIn(event.Owner_Ids__c);
            Set<Id> personIds = idsIn(event.Person_Ids__c);
            queued.addAll(householdIds);
            queued.addAll(ownerIds);
            queued.addAll(personIds);
            System.enqueueJob(new MergeSettlement(householdIds, ownerIds, personIds));
            EventBus.TriggerContext.currentContext().setResumeCheckpoint(event.ReplayId);
        }
        lastQueued = queued;
        if (queuedByEvents == null) {
            queuedByEvents = new Set<Id>();
        }
        queuedByEvents.addAll(queued);
    }

    /**
     * Publishes the survivors in events of up to 200 identifiers per list, delivered after
     * commit. Logs them as a warning only when the platform refuses the publish.
     */
    private static void publish(
        Set<Id> householdIds,
        Set<Id> ownerIds,
        Set<Id> personIds,
        Set<Id> survivors
    ) {
        List<Id> households = new List<Id>(householdIds);
        List<Id> owners = new List<Id>(ownerIds);
        List<Id> people = new List<Id>(personIds);
        Integer longest = Math.max(households.size(), Math.max(owners.size(), people.size()));
        List<Merge_Settlement_Ready__e> events = new List<Merge_Settlement_Ready__e>();
        for (Integer start = 0; start < longest; start += IDS_PER_EVENT) {
            events.add(
                new Merge_Settlement_Ready__e(
                    Household_Ids__c = slice(households, start),
                    Owner_Ids__c = slice(owners, start),
                    Person_Ids__c = slice(people, start)
                )
            );
        }
        lastPublished = events;
        String failure = publishFailureForTest;
        if (failure == null) {
            try {
                for (Database.SaveResult result : EventBus.publish(events)) {
                    if (!result.isSuccess()) {
                        failure = result.getErrors()[0].getMessage();
                        break;
                    }
                }
            } catch (Exception thrown) {
                failure = thrown.getMessage();
            }
        }
        if (failure != null) {
            logNotSettled(survivors, failure);
        }
    }

    private static void logNotSettled(Set<Id> survivors, String failure) {
        List<String> named = new List<String>();
        for (Id survivorId : survivors) {
            named.add(String.valueOf(survivorId));
        }
        ErrorLogger.logMessage(
            String.format(
                Label.Core_Households_MergeSettleNotQueued,
                new List<String>{ String.join(named, ', '), failure }
            ),
            Label.Core_Households_ErrorContextMergeSettle,
            ErrorLogger.SEVERITY_WARNING
        );
    }

    /** The identifiers from start, up to one event's worth, joined; null when none are left. */
    private static String slice(List<Id> ids, Integer start) {
        if (start >= ids.size()) {
            return null;
        }
        List<String> part = new List<String>();
        Integer stop = Math.min(ids.size(), start + IDS_PER_EVENT);
        for (Integer i = start; i < stop; i++) {
            part.add(String.valueOf(ids[i]));
        }
        return String.join(part, SEPARATOR);
    }

    private static Set<Id> survivorsIn(List<Merge_Settlement_Ready__e> events) {
        Set<Id> survivors = new Set<Id>();
        for (Merge_Settlement_Ready__e event : events) {
            survivors.addAll(idsIn(event.Household_Ids__c));
            survivors.addAll(idsIn(event.Owner_Ids__c));
            survivors.addAll(idsIn(event.Person_Ids__c));
        }
        return survivors;
    }

    private static Set<Id> idsIn(String joined) {
        Set<Id> ids = new Set<Id>();
        if (String.isBlank(joined)) {
            return ids;
        }
        for (String part : joined.split(SEPARATOR)) {
            if (String.isNotBlank(part)) {
                ids.add(Id.valueOf(part.trim()));
            }
        }
        return ids;
    }

    private static Boolean inQueueable() {
        return queueableForTest == null ? System.isQueueable() : queueableForTest;
    }

    public void execute(QueueableContext context) {
        try {
            HouseholdService.collapseDuplicateMemberships(householdIds);
        } catch (Exception failed) {
            ErrorLogger.log(failed, Label.Core_Households_ErrorContextMergeSettle);
        }
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
