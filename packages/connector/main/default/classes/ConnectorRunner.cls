/**
 * The one runner chain of BarnCRM Connector (canonical model R-CR4, R-RUN4; design Sections 3.2,
 * 3.7 and 4). `Connector_Start__e`'s trigger calls `start`, so the job runs as the Automated
 * Process user, never as the person who pressed Run Now (D-215); asynchronous Apex keeps that
 * identity in every job it chains. Each job takes the oldest queued runs, runs them until the
 * transaction nears its limits or a callout would follow a record write, saves them all at the
 * end (a callout cannot follow uncommitted DML) and chains the next job while runs wait.
 *
 * A Transaction Finalizer marks the run that was going when the job died (a limit the code
 * cannot catch) as failed and starts the chain again, so one run cannot stall the rest.
 */
public with sharing class ConnectorRunner implements Queueable, Database.AllowsCallouts {
	@TestVisible
	private static final Integer BATCH = 20;
	private static final Set<String> RUNNING = new Set<String>{ 'Queued', 'Preparing', 'Processing', 'Holding' };
	/** Tests run one job; the chain is checked through `chained`. */
	@TestVisible
	private static Boolean chained = false;
	/** Tests run as their own user; the identity check stands everywhere else. */
	@TestVisible
	private static Boolean skipIdentityCheck = false;

	/** Starts the chain unless a job of it is already queued or running. */
	public static void start() {
		if (Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) {
			return;
		}
		Integer going = [
			SELECT COUNT()
			FROM AsyncApexJob
			WHERE JobType = 'Queueable' AND ApexClass.Name = 'ConnectorRunner' AND Status IN :RUNNING
			WITH SYSTEM_MODE
		];
		if (going == 0) {
			try {
				AsyncStarter.queue(new ConnectorRunner(), 'ConnectorRunner.start');
			} catch (Exception busy) {
				// The runs stay Queued; the next start event (any queue or retry) starts them.
				ErrorLogger.log(busy, 'ConnectorRunner.start');
			}
		}
	}

	public void execute(QueueableContext context) {
		if (!skipIdentityCheck && UserInfo.getUserType() != 'AutomatedProcess') {
			// Only the start event's trigger may run recipes (R-CR4): never as a staff member.
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
		process(ConnectorRunStore.queued(BATCH), guard);
		if (ConnectorRunStore.anyQueued()) {
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
		for (Connector_Run__c run : runs) {
			if (budget.low()) {
				break;
			}
			guard.current = run.Id;
			Connector_Run__c result = runOne(run, budget);
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
		ConnectorRunStore.save(touched, lastRuns);
		// After every callout of the transaction: an Error Log write is DML.
		ErrorLogger.logMessages(failures, failedRuns, 'ConnectorRunner', ErrorLogger.SEVERITY_ERROR);
	}

	private static Connector_Run__c runOne(Connector_Run__c run, ConnectorStepRunner.Budget budget) {
		ConnectorStepRunner steps = new ConnectorStepRunner(run, budget);
		try {
			return run.Ran_As__c == ConnectorRecipes.RUN_AS_SYSTEM
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

	/** Fails the run a dead job was on, then starts the chain again for the rest. */
	public with sharing class Guard implements Finalizer {
		public Id current;

		public void execute(FinalizerContext context) {
			if (context.getResult() != ParentJobResult.UNHANDLED_EXCEPTION) {
				return;
			}
			if (current != null) {
				ConnectorRunStore.failStopped(
					new Set<Id>{ current },
					BarnHelp.text(
						'Connector',
						'Connector_Run_ErrorStopped',
						new List<Object>{ context.getException().getTypeName() }
					)
				);
			}
			if (ConnectorRunStore.anyQueued()) {
				chain();
			}
		}
	}
}
