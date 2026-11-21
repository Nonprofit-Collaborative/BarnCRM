/**
 * The runner chains of BarnCRM Connector, one per lane (canonical model R-CR4, R-CR7, R-RUN4;
 * design Sections 3.2, 3.7 and 4). A lane's start event trigger calls `start`, so the job runs as
 * that lane's identity (the Automated Process user, or the integration user), never as the person
 * who pressed Run Now (D-215); asynchronous Apex keeps that identity in every job it chains. Each
 * job runs the runs taken for it (Running, `ConnectorRunStore.claim`) until the transaction nears
 * its limits or a callout would follow a record write, saves them all at the end (a callout
 * cannot follow uncommitted DML), then takes the lane's next oldest Queued runs and chains the
 * next job for them. The start event's trigger takes the first job's runs.
 *
 * A run that fails for a reason that may pass waits and is retried at 15 minutes, 1 hour, 4 hours
 * and 12 hours, up to its recipe's Retry Attempts (R-CR7). A recipe that fails Pause After
 * Failures times in a row pauses itself.
 *
 * A Transaction Finalizer fails every run the job had begun when it died (a limit the code cannot
 * catch): their writes were undone but their callouts were sent, so they are not run again
 * unasked; Retry continues each from its saved state. The runs it had not begun stay Running for
 * the next job, which the Finalizer chains.
 */
public with sharing class ConnectorRunner implements Queueable, Database.AllowsCallouts {
	@TestVisible
	private static final Integer BATCH = 20;
	/** Minutes before each retry (R-CR7). */
	public static final List<Integer> BACKOFF_MINUTES = new List<Integer>{ 15, 60, 240, 720 };
	private static final Integer LONGEST_WAIT_SECONDS = 86400;
	/** Tests run one job; the chain is checked through `chained`. */
	@TestVisible
	private static Boolean chained = false;
	/** Tests run as their own user; the identity check stands everywhere else. */
	@TestVisible
	private static Boolean skipIdentityCheck = false;

	/**
	 * Starts the lane's chain, as its identity, unless a job of it is already queued or running:
	 * takes the first job's runs, then queues it.
	 */
	public static void start(String lane) {
		if (Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) {
			return;
		}
		Id me = UserInfo.getUserId();
		Integer going = [
			SELECT COUNT()
			FROM AsyncApexJob
			WHERE
				JobType = 'Queueable'
				AND ApexClass.Name = 'ConnectorRunner'
				AND Status IN :ConnectorClock.GOING
				AND CreatedById = :me
			WITH SYSTEM_MODE
		];
		if (going == 0 && ConnectorRunStore.claim(BATCH, ConnectorClock.runAsOf(lane), ConnectorClock.paused())) {
			try {
				AsyncStarter.queue(new ConnectorRunner(), 'ConnectorRunner.start');
			} catch (Exception busy) {
				// The runs stay Queued; the lane's heartbeat publishes its start event again.
				ErrorLogger.log(busy, 'ConnectorRunner.start');
			}
		}
	}

	public void execute(QueueableContext context) {
		String lane = ConnectorClock.runningLane();
		if (lane == null && skipIdentityCheck) {
			lane = ConnectorClock.LANE_AUTOMATION;
		}
		if (lane == null) {
			// Only a lane's start event may run recipes (R-CR4): never as a staff member.
			ErrorLogger.logMessage(
				BarnHelp.text('Connector', 'Connector_Log_WrongIdentity'),
				'ConnectorRunner.execute',
				ErrorLogger.SEVERITY_WARNING
			);
			return;
		}
		Guard guard = new Guard();
		if (!Test.isRunningTest()) {
			System.attachFinalizer(guard);
		}
		Set<String> runAs = ConnectorClock.runAsOf(lane);
		// Paused (R-CR7): only Test runs from the editor still run.
		Boolean testsOnly = ConnectorClock.paused();
		guard.runAs = runAs;
		guard.testsOnly = testsOnly;
		process(ConnectorRunStore.running(BATCH, runAs, testsOnly), guard);
		// After every callout: the next job's runs are taken, then it is chained.
		if (ConnectorRunStore.claim(BATCH, runAs, testsOnly)) {
			chain();
		}
	}

	/** Runs each run in turn and saves them all once the transaction is done with callouts. */
	@TestVisible
	private static void process(List<Connector_Run__c> runs, Guard guard) {
		ConnectorStepRunner.Budget budget = new ConnectorStepRunner.Budget();
		List<Connector_Run__c> touched = new List<Connector_Run__c>();
		Map<Id, Datetime> lastRuns = new Map<Id, Datetime>();
		List<String> failures = new List<String>();
		List<Id> failedRuns = new List<Id>();
		ConnectorAppPoll polls = new ConnectorAppPoll();
		ConnectorRunStore.loadRecipes(runs);
		for (Connector_Run__c run : runs) {
			if (budget.low()) {
				break;
			}
			guard.current = run.Id;
			guard.begun.add(run.Id);
			Connector_Run__c result;
			if (ConnectorAppPoll.isPoll(run)) {
				// An App Poll's poll run (R-CR16): spent once its items are found.
				result = polls.poll(run, budget);
				if (result == null) {
					continue;
				}
				result = waitIfPassing(result, polls.passingFailure);
			} else {
				result = runOne(run, budget);
			}
			touched.add(result);
			if (result.Status__c != ConnectorRunStore.QUEUED && result.Is_Test__c != true) {
				lastRuns.put(result.Recipe__c, Datetime.now());
			}
			if (result.Status__c == ConnectorRunStore.FAILED && result.Is_Test__c != true) {
				failures.add(failureText(result));
				failedRuns.add(result.Id);
			}
			if (result.Status__c == ConnectorRunStore.QUEUED) {
				break;
			}
		}
		guard.current = null;
		List<String> paused = ConnectorRunStore.save(touched, lastRuns);
		polls.save();
		// After every callout of the transaction: an Error Log write is DML.
		ErrorLogger.logMessages(failures, failedRuns, 'ConnectorRunner', ErrorLogger.SEVERITY_ERROR);
		ErrorLogger.logMessages(paused, 'ConnectorRunner', ErrorLogger.SEVERITY_ERROR);
	}

	private static Connector_Run__c runOne(Connector_Run__c run, ConnectorStepRunner.Budget budget) {
		ConnectorStepRunner steps = new ConnectorStepRunner(run, budget);
		Connector_Run__c result;
		try {
			result = run.Ran_As__c == ConnectorRecipes.RUN_AS_SYSTEM
				? ConnectorRunStore.runInSystemMode(steps)
				: steps.execute();
		} catch (Exception unexpected) {
			run.Status__c = ConnectorRunStore.FAILED;
			run.Error_Message__c = BarnHelp.text(
				'Connector',
				'Connector_Run_ErrorUnexpected',
				new List<Object>{ unexpected.getTypeName() }
			);
			run.Finished_At__c = Datetime.now();
			return run;
		}
		return waitIfPassing(result, steps.passingFailure);
	}

	/**
	 * A failure that may pass waits for its next try (R-CR7): at the backoff for this attempt, or
	 * later when the app's `Retry-After` says so, at most a day; Test runs never wait.
	 */
	@TestVisible
	private static Connector_Run__c waitIfPassing(
		Connector_Run__c run,
		ConnectorStepRunner.StepFailureException passing
	) {
		Integer made = run.Attempt__c == null ? 0 : run.Attempt__c.intValue();
		if (
			passing == null ||
			run.Status__c != ConnectorRunStore.FAILED ||
			run.Is_Test__c == true ||
			made >= ConnectorRecipes.retryAttempts(run.Recipe__r)
		) {
			return run;
		}
		Integer seconds = BACKOFF_MINUTES[Math.min(made, BACKOFF_MINUTES.size() - 1)] * 60;
		if (passing.retryAfter != null && passing.retryAfter > seconds) {
			seconds = Math.min(passing.retryAfter, LONGEST_WAIT_SECONDS);
		}
		run.Status__c = ConnectorRunStore.WAITING;
		run.Next_Attempt_At__c = Datetime.now().addSeconds(seconds);
		run.Finished_At__c = null;
		return run;
	}

	/**
	 * One Error Log entry per failed run (R-RUN4): the recipe, the step and the plain message,
	 * never a request, header or response (F7).
	 */
	private static String failureText(Connector_Run__c run) {
		return BarnHelp.text(
			'Connector',
			'Connector_Log_RunFailed',
			new List<Object>{
				run.Recipe__r.Name,
				run.Name,
				String.isBlank(run.Failed_Step__c) ? '-' : run.Failed_Step__c,
				run.Error_Message__c
			}
		);
	}

	private static void chain() {
		if (Test.isRunningTest()) {
			chained = true;
			return;
		}
		System.enqueueJob(new ConnectorRunner());
	}

	/** Fails the runs a dead job had begun, then starts the chain again for the rest. */
	public with sharing class Guard implements Finalizer {
		public Id current;
		/** Every run the job began, the one it was on included. */
		public Set<Id> begun = new Set<Id>();
		public Set<String> runAs;
		public Boolean testsOnly = false;

		public void execute(FinalizerContext context) {
			if (context.getResult() != ParentJobResult.UNHANDLED_EXCEPTION) {
				return;
			}
			if (!begun.isEmpty()) {
				ConnectorRunStore.failStopped(
					begun,
					BarnHelp.text(
						'Connector',
						'Connector_Run_ErrorStopped',
						new List<Object>{ context.getException().getTypeName() }
					)
				);
			}
			if (ConnectorRunStore.claim(BATCH, runAs, testsOnly)) {
				chain();
			}
		}
	}
}
