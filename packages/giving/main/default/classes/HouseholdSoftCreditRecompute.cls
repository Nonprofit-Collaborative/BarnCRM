/**
 * The asynchronous half of R-SC3: it brings the automatic household soft credits on a
 * household's gifts back into line after its membership changed.
 *
 * Queueable rather than inline, because a household's giving history has no bound and moving one
 * person between households must not fail on the size of it. One household per job, chained, so
 * that a change touching several households cannot blow a single job's limits and so that a
 * failure names the household it happened on.
 *
 * A job that cannot be queued at all (an org already at its chaining limit, a trigger context
 * that forbids it) is reported to the Error Log rather than swallowed: recognition that quietly
 * stopped being maintained is the failure mode this rule exists to prevent.
 */
public with sharing class HouseholdSoftCreditRecompute implements Queueable {
    private static final String CONTEXT = 'Household soft credit recompute';

    /**
     * How many households one save may queue a recompute for. One save that moves one person
     * touches two households; a data load that moves five thousand people is what this bounds,
     * because a job chained per household would run for as long as the load did.
     */
    public static final Integer HOUSEHOLDS_PER_TRANSACTION_CAP = 50;

    private final List<Id> pending;

    private HouseholdSoftCreditRecompute(List<Id> pending) {
        this.pending = pending;
    }

    /**
     * Queues the recompute for these households. Does nothing when the org has turned automatic
     * household credits off and there is therefore nothing to keep in line, and nothing in a
     * context that cannot queue work, which is what a test doing its own DML inside
     * `Test.startTest` looks like.
     */
    public static void enqueue(Set<Id> householdIds) {
        if (householdIds == null || householdIds.isEmpty()) {
            return;
        }
        // A household with no gifts has no credits to put right, and its next gift credits its
        // members when it is saved. Leaving those out keeps the job's slot free: loading people
        // into new households (the sample data load is a chain of jobs) queued a recompute that
        // had nothing to do and took the one job the load needed for its next step.
        List<Id> pending = new List<Id>(GiftLookupSelector.selectHouseholdsWithGifts(householdIds));
        if (pending.isEmpty()) {
            return;
        }
        if (pending.size() > HOUSEHOLDS_PER_TRANSACTION_CAP) {
            // A bulk load of people is the case this bounds. Recrediting every household it
            // touches would chain a job per household for as long as the load ran, so past this
            // point the work is left to the next save of each gift and the fact is recorded.
            ErrorLogger.logMessage(
                String.format(
                    Label.Giving_SoftCredits_RecomputeDeferred,
                    new List<String>{
                        String.valueOf(pending.size() - HOUSEHOLDS_PER_TRANSACTION_CAP)
                    }
                ),
                CONTEXT,
                'Warning'
            );
            List<Id> capped = new List<Id>();
            for (Integer index = 0; index < HOUSEHOLDS_PER_TRANSACTION_CAP; index++) {
                capped.add(pending[index]);
            }
            pending = capped;
        }
        if (System.isFuture() || Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) {
            // No async slot to take. The credits are corrected the next time each gift is saved.
            ErrorLogger.logMessage(
                String.format(
                    Label.Giving_SoftCredits_RecomputeDeferred,
                    new List<String>{ String.valueOf(pending.size()) }
                ),
                CONTEXT,
                'Warning'
            );
            return;
        }
        System.enqueueJob(new HouseholdSoftCreditRecompute(pending));
    }

    public void execute(QueueableContext jobContext) {
        if (pending == null || pending.isEmpty()) {
            return;
        }
        // The recompute failure below is already caught and logged, but the chained
        // System.enqueueJob call after it is not: if that call itself throws (the org's
        // queueable limit moving under it, for example), the failure would otherwise reach
        // no one but the platform's own failure email. The finalizer is the net under that
        // one path.
        System.attachFinalizer(new RecomputeFinalizer(CONTEXT));
        Id householdId = pending[0];
        List<Id> remaining = new List<Id>(pending);
        remaining.remove(0);
        try {
            SoftCreditService.recomputeForHouseholds(new Set<Id>{ householdId });
        } catch (Exception failure) {
            ErrorLogger.log(failure, CONTEXT, householdId);
        }
        if (
            !remaining.isEmpty() &&
            !Test.isRunningTest() &&
            Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()
        ) {
            System.enqueueJob(new HouseholdSoftCreditRecompute(remaining));
        } else if (remaining.isEmpty()) {
            // The chain has ended. The rollup engine queued the soft credit totals without
            // taking this job's one chained job, so they are calculated now.
            RollupService.startQueuedRecalculation();
        }
    }

    /**
     * Catches whatever escapes execute() uncaught, which today can only be the chained
     * System.enqueueJob call, and logs it through ErrorLogger. Does nothing else and never
     * throws, matching the pattern every other Error Log writer in this package follows.
     */
    private with sharing class RecomputeFinalizer implements System.Finalizer {
        private final String context;

        private RecomputeFinalizer(String context) {
            this.context = context;
        }

        public void execute(System.FinalizerContext ctx) {
            if (ctx.getResult() == ParentJobResult.UNHANDLED_EXCEPTION) {
                ErrorLogger.log(ctx.getException(), context);
            }
        }
    }
}
