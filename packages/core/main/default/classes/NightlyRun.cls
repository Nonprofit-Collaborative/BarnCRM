/**
 * The nightly run (ADR-0166 nightly-job-dispatcher, canonical model R-NJ1 to R-NJ6): scheduled
 * once, every day at midnight, it takes every step `NightlyJobs.steps()` lists, one at a time.
 *
 * Each link of the run is one short transaction, chained as a delayed queueable:
 * - PLAN records how the last step ended, then finds the next step. One whose time of day has
 *   not come is waited for; one that is off is recorded Skipped; the first that is due is
 *   marked Running.
 * - RUN starts that step's work and nothing else, so the step's own writes (some touch setup
 *   objects) never share a transaction with the run's bookkeeping.
 * - WAIT checks every two minutes whether a batch, queueable or future job the run's user
 *   started since the step began is still unfinished, and gives up after six hours (R-NJ3).
 *
 * A wait over ten minutes, a queue already full (a step that enqueued its own job) and a chain
 * the platform will not extend (the Developer Edition depth) all resume through the one-time
 * job "BarnCRM Nightly Jobs Continue". A run still going when the next night starts is
 * superseded: each link first checks that it still belongs to the newest run (R-NJ6).
 *
 * The state lives in the instance, which the platform serializes between links.
 */
public with sharing class NightlyRun implements Schedulable {
    @TestVisible
    private static final String PLAN = 'plan';
    @TestVisible
    private static final String RUN = 'run';
    @TestVisible
    private static final String WAIT = 'wait';

    /** Minutes between checks on a running step. */
    @TestVisible
    private static final Integer POLL_MINUTES = 2;

    /** Checks before the run gives up waiting: six hours. */
    @TestVisible
    private static final Integer MAX_POLLS = 180;

    /** The longest delay a queueable takes; a longer wait uses the one-time job. */
    private static final Integer MAX_QUEUE_DELAY = 10;

    private static final String CONTEXT = 'NightlyRun';
    private static final List<String> UNFINISHED = new List<String>{
        'Holding',
        'Queued',
        'Preparing',
        'Processing'
    };
    private static final List<String> ASYNC_TYPES = new List<String>{
        'BatchApex',
        'Queueable',
        'Future'
    };

    /** False in a test that drives the links itself: the next link is only recorded. */
    @TestVisible
    private static Boolean chain = true;

    /** In a test, how many unfinished jobs the wait sees, instead of asking the platform. */
    @TestVisible
    private static Integer busyOverride;

    /** The delay, in minutes, of the last link a test asked for; -1 for a one-time job. */
    @TestVisible
    private static Integer lastDelay;

    @TestVisible
    private Datetime runStarted;
    @TestVisible
    private List<String> planned;
    @TestVisible
    private Integer cursor = 0;
    @TestVisible
    private String phase = PLAN;
    @TestVisible
    private Datetime stepStarted;
    @TestVisible
    private Integer polls = 0;
    @TestVisible
    private String failure;

    /** The nightly trigger fires with no run started; a continuation carries its run. */
    public void execute(SchedulableContext context) {
        if (runStarted == null) {
            begin();
        } else {
            advance();
        }
    }

    /**
     * One link of the run as a queueable. A class may not be both Schedulable and Queueable when
     * enqueued, so the link carries the run.
     */
    @TestVisible
    private with sharing class Link implements Queueable {
        private final NightlyRun run;
        Link(NightlyRun run) {
            this.run = run;
        }
        public void execute(QueueableContext context) {
            run.advance();
        }
    }

    // -------------------------------------------------------------------------------------
    // The run
    // -------------------------------------------------------------------------------------

    /** Starts tonight's run: adopts any old schedule, then takes over from a run still going. */
    @TestVisible
    private void begin() {
        NightlyJobs.adoptOldSchedules();
        Datetime now = Datetime.now();
        runStarted = Datetime.newInstance(now.getTime() - Math.mod(now.getTime(), 1000));
        List<Nightly_Job__c> changed = new List<Nightly_Job__c>();
        Datetime unfinishedStep;
        for (Nightly_Job__c row : NightlyJobs.rows().values()) {
            if (row.Last_Outcome__c == NightlyJobs.RUNNING && row.Name != NightlyJobs.JOB_NAME) {
                // R-NJ6: the step last night's run was still on; wait for what it started.
                unfinishedStep = row.Last_Started__c;
                row.Last_Outcome__c = NightlyJobs.GAVE_UP;
                row.Last_Finished__c = now;
                row.Last_Message__c = BarnHelp.text('Core', 'Core_NightlyJobs_Superseded')
                    .left(255);
                changed.add(row);
            }
        }
        Nightly_Job__c run = NightlyJobs.rowFor(NightlyJobs.JOB_NAME);
        run.Last_Started__c = runStarted;
        run.Last_Finished__c = null;
        run.Last_Outcome__c = NightlyJobs.RUNNING;
        run.Last_Message__c = null;
        changed.add(run);
        NightlyJobs.save(changed);

        planned = new List<String>();
        for (NightlyStep step : NightlyJobs.steps()) {
            planned.add(step.key);
        }
        cursor = 0;
        polls = 0;
        if (unfinishedStep != null) {
            cursor = -1;
            phase = WAIT;
            stepStarted = unfinishedStep;
            next(POLL_MINUTES);
        } else {
            phase = PLAN;
            next(0);
        }
    }

    /** One link: run, wait or plan, unless a newer run has taken over. */
    @TestVisible
    private void advance() {
        if (superseded()) {
            return;
        }
        if (phase == RUN) {
            runStep();
            return;
        }
        if (phase == WAIT) {
            if (unfinishedJobs() > 0 && polls < MAX_POLLS) {
                polls++;
                next(POLL_MINUTES);
                return;
            }
            finishStep();
        }
        planNext();
    }

    /** True when a newer run has started since this one: this one stops quietly. */
    private Boolean superseded() {
        Nightly_Job__c run = NightlyJobs.rows()
            .get(ScheduledJobSelector.nameKey(NightlyJobs.JOB_NAME));
        return run == null ||
            run.Last_Started__c == null ||
            runStarted == null ||
            run.Last_Started__c.getTime() != runStarted.getTime();
    }

    /** Starts the step's work, and nothing else in this transaction. */
    private void runStep() {
        Boolean inPlan = cursor >= 0 && cursor < planned.size();
        NightlyStep step = inPlan ? NightlyJobs.step(planned[cursor]) : null;
        failure = null;
        try {
            if (step != null) {
                step.run();
            }
        } catch (Exception thrown) {
            ErrorLogger.log(thrown, CONTEXT + ' ' + planned[cursor]);
            failure = thrown.getMessage();
        }
        phase = WAIT;
        polls = 0;
        next(1);
    }

    /** Records how the step the run waited for ended. */
    private void finishStep() {
        if (cursor >= 0 && cursor < planned.size()) {
            String outcome;
            String message;
            if (failure != null) {
                outcome = NightlyJobs.FAILED;
                message = failure;
            } else if (unfinishedJobs() > 0) {
                outcome = NightlyJobs.GAVE_UP;
                message = BarnHelp.text(
                    'Core',
                    'Core_NightlyJobs_GaveUp',
                    new List<Object>{ MAX_POLLS * POLL_MINUTES / 60 }
                );
            } else {
                outcome = failedJobs() > 0 ? NightlyJobs.DONE_WITH_ERRORS : NightlyJobs.DONE;
            }
            Nightly_Job__c row = NightlyJobs.rowFor(planned[cursor]);
            row.Last_Finished__c = Datetime.now();
            row.Last_Outcome__c = outcome;
            row.Last_Message__c = message == null ? null : message.left(255);
            NightlyJobs.save(new List<Nightly_Job__c>{ row });
        }
        failure = null;
        cursor++;
        phase = PLAN;
    }

    /**
     * Finds the next step that is due and marks it Running, recording the steps that are off as
     * Skipped on the way; waits for a step whose time has not come; ends the run after the last.
     */
    private void planNext() {
        List<Nightly_Job__c> changed = new List<Nightly_Job__c>();
        while (cursor < planned.size()) {
            NightlyStep step = NightlyJobs.step(planned[cursor]);
            if (step == null) {
                cursor++;
                continue;
            }
            Datetime due = dueAt(step.minute);
            Datetime now = Datetime.now();
            if (due > now) {
                NightlyJobs.save(changed);
                nextAt(due);
                return;
            }
            Nightly_Job__c row = NightlyJobs.rowFor(step.key);
            row.Last_Started__c = now;
            row.Last_Message__c = null;
            if (!NightlyJobs.isOn(step)) {
                row.Last_Finished__c = now;
                row.Last_Outcome__c = NightlyJobs.SKIPPED;
                changed.add(row);
                cursor++;
                continue;
            }
            row.Last_Finished__c = null;
            row.Last_Outcome__c = NightlyJobs.RUNNING;
            changed.add(row);
            NightlyJobs.save(changed);
            stepStarted = now;
            phase = RUN;
            next(0);
            return;
        }
        Nightly_Job__c run = NightlyJobs.rowFor(NightlyJobs.JOB_NAME);
        run.Last_Finished__c = Datetime.now();
        run.Last_Outcome__c = NightlyJobs.DONE;
        changed.add(run);
        NightlyJobs.save(changed);
    }

    /** The step's time of day on the night this run started, in the run's time zone. */
    private Datetime dueAt(Integer minute) {
        return Datetime.newInstance(
            runStarted.date(),
            Time.newInstance(minute / 60, Math.mod(minute, 60), 0, 0)
        );
    }

    // -------------------------------------------------------------------------------------
    // What the step started
    // -------------------------------------------------------------------------------------

    private Integer unfinishedJobs() {
        if (busyOverride != null) {
            return busyOverride;
        }
        return [
            SELECT COUNT()
            FROM AsyncApexJob
            WHERE
                CreatedById = :UserInfo.getUserId()
                AND CreatedDate >= :stepStarted
                AND JobType IN :ASYNC_TYPES
                AND Status IN :UNFINISHED
                AND ApexClass.Name != :CONTEXT
            WITH SYSTEM_MODE
        ];
    }

    private Integer failedJobs() {
        if (busyOverride != null) {
            return 0;
        }
        return [
            SELECT COUNT()
            FROM AsyncApexJob
            WHERE
                CreatedById = :UserInfo.getUserId()
                AND CreatedDate >= :stepStarted
                AND JobType IN :ASYNC_TYPES
                AND (Status = 'Failed'
                OR NumberOfErrors > 0)
                AND ApexClass.Name != :CONTEXT
            WITH SYSTEM_MODE
        ];
    }

    // -------------------------------------------------------------------------------------
    // The next link
    // -------------------------------------------------------------------------------------

    /** Chains the next link after `minutes`, as a queueable when it can. */
    private void next(Integer minutes) {
        Boolean queueFull = Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs();
        if (minutes > MAX_QUEUE_DELAY || queueFull) {
            resumeAt(Datetime.now().addMinutes(Math.max(minutes, 1)));
            return;
        }
        if (!chain) {
            lastDelay = minutes;
            return;
        }
        try {
            System.enqueueJob(new Link(this), minutes);
        } catch (AsyncException refused) {
            // The platform will not chain deeper (Developer Edition): resume from a trigger.
            resumeAt(Datetime.now().addMinutes(Math.max(minutes, 1)));
        }
    }

    /** Waits until `due`: as a queueable when it is close, otherwise through the one-time job. */
    private void nextAt(Datetime due) {
        // Rounded up, so the next link never arrives before the step is due.
        Long minutes = (due.getTime() - Datetime.now().getTime() + 59999) / 60000;
        if (minutes <= MAX_QUEUE_DELAY) {
            next(Math.max(minutes.intValue(), 0));
        } else {
            resumeAt(due);
        }
    }

    /** Resumes the run at `due` (a minute from now at the soonest) through the one-time job. */
    private void resumeAt(Datetime due) {
        if (!chain) {
            lastDelay = -1;
            return;
        }
        Datetime at = due > Datetime.now().addMinutes(1) ? due : Datetime.now().addMinutes(1);
        ScheduledJobSelector.stopNamed(NightlyJobs.CONTINUE_JOB_NAME);
        ScheduledJobSelector.schedule(
            NightlyJobs.CONTINUE_JOB_NAME,
            at.format('s m H d M \'?\' yyyy'),
            this
        );
    }
}
