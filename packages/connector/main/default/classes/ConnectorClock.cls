/**
 * The recipe clock of BarnCRM Connector (canonical model R-CR4, R-CR6, R-CR7; design Sections
 * 3.2, 3.7 and 3.10, D-215). No Scheduled Apex and no person: Scheduled Apex runs as whoever
 * scheduled it and stops once that person is deactivated. Instead each lane has a heartbeat, a
 * Queueable its start event's trigger starts, so it runs as that lane's identity (the Automated
 * Process user for BarnCRM Automation and System recipes, the integration user for Integration
 * User recipes), and queues itself again 5 minutes later while the lane has work. Asynchronous
 * Apex keeps the identity of whoever queued it, so every beat and every run keeps the lane's.
 *
 * A beat may queue only one job, itself, so when runs wait it publishes its lane's start event,
 * whose trigger starts the runner. A Transaction Finalizer queues a beat that failed again; any
 * start event and the nightly step start a missing heartbeat.
 */
public with sharing class ConnectorClock implements Queueable {
	public static final String LANE_AUTOMATION = 'Automation';
	public static final String LANE_USER = 'IntegrationUser';
	public static final String SETTINGS = 'Connector_Settings__c';
	public static final Integer BEAT_MINUTES = 5;
	public static final Integer POLL_MINUTES = 15;
	public static final Set<String> GOING = new Set<String>{ 'Queued', 'Preparing', 'Processing', 'Holding' };

	/** Tests act as a lane's identity, since a test cannot run as the Automated Process user. */
	@TestVisible
	private static String laneForTest;
	/** Tests run one beat; the next is checked through `chained`. */
	@TestVisible
	private static Boolean chained = false;
	/** The lanes whose start events this transaction published, for tests. */
	@TestVisible
	private static Set<String> published = new Set<String>();

	/** The Recipe Clock card: Pause All Recipes, BarnCRM's automation pause and each lane. */
	public class Status {
		@AuraEnabled
		public Boolean paused;
		@AuraEnabled
		public Boolean automationPaused;
		@AuraEnabled
		public List<Lane> lanes = new List<Lane>();
	}

	/** One lane: whether it has work for a heartbeat and whether one is waiting or running. */
	public class Lane {
		@AuraEnabled
		public String lane;
		@AuraEnabled
		public Boolean needed;
		@AuraEnabled
		public Boolean beating;
	}

	public static Status status() {
		Status result = new Status();
		result.paused = SettingsService.flag(SETTINGS, 'Recipes_Paused__c');
		result.automationPaused = AutomationControl.isPaused() || AutomationControl.isOffForRunningUser();
		Map<String, Id> users = new Map<String, Id>{
			LANE_AUTOMATION => ConnectorIdentity.automatedProcessId(),
			LANE_USER => ConnectorIntegrationUser.chosenId()
		};
		for (String name : users.keySet()) {
			Lane each = new Lane();
			each.lane = name;
			each.needed = ConnectorRunStore.clockNeeded(runAsOf(name));
			each.beating = users.get(name) != null && beating(users.get(name), null);
			result.lanes.add(each);
		}
		return result;
	}

	/** Pause All Recipes on or off, org-wide and audited (R-CR7, R-CS1); off starts both lanes. */
	public static Status setPaused(Boolean paused) {
		ConnectorConnections.requireManager();
		SettingsService.saveValues(SETTINGS, new Map<String, Object>{ 'Recipes_Paused__c' => paused == true });
		if (paused != true) {
			publish(lanesNeeded());
		}
		Status result = status();
		result.paused = paused == true;
		return result;
	}

	/** Restart: each lane with work gets its start event, which starts a missing heartbeat. */
	public static Status restart() {
		ConnectorConnections.requireManager();
		publish(lanesNeeded());
		return status();
	}

	/** The lanes with recipe work for a heartbeat. */
	public static Set<String> lanesNeeded() {
		Set<String> found = new Set<String>();
		for (String lane : new List<String>{ LANE_AUTOMATION, LANE_USER }) {
			if (ConnectorRunStore.clockNeeded(runAsOf(lane))) {
				found.add(lane);
			}
		}
		return found;
	}

	/** The Run As values a lane runs. */
	public static Set<String> runAsOf(String lane) {
		return lane == LANE_USER
			? new Set<String>{ ConnectorRecipes.RUN_AS_USER }
			: new Set<String>{ ConnectorRecipes.RUN_AS_AUTOMATION, ConnectorRecipes.RUN_AS_SYSTEM };
	}

	public static String laneOf(String runAs) {
		return runAs == ConnectorRecipes.RUN_AS_USER ? LANE_USER : LANE_AUTOMATION;
	}

	/** The lane the running user works, or null when it is no recipe identity (R-CR4). */
	public static String runningLane() {
		if (laneForTest != null) {
			return laneForTest;
		}
		if (UserInfo.getUserType() == 'AutomatedProcess') {
			return LANE_AUTOMATION;
		}
		Id chosen = ConnectorIntegrationUser.chosenId();
		return chosen != null && chosen == UserInfo.getUserId() ? LANE_USER : null;
	}

	/** Pause All Recipes, or BarnCRM Automation Control's timed pause or Pause All (R-CR7). */
	public static Boolean paused() {
		return SettingsService.flag(SETTINGS, 'Recipes_Paused__c') ||
			AutomationControl.isPaused() ||
			AutomationControl.isOffForRunningUser();
	}

	/** Publishes each named lane's start event, after commit. */
	public static void publish(Set<String> lanes) {
		List<SObject> events = new List<SObject>();
		if (lanes.contains(LANE_AUTOMATION)) {
			events.add(new Connector_Start__e());
		}
		if (lanes.contains(LANE_USER)) {
			events.add(new Connector_Start_User__e());
		}
		if (!events.isEmpty()) {
			EventBus.publish(events);
			published.addAll(lanes);
		}
	}

	/**
	 * A start event's trigger: starts the lane's runner and heartbeat when the trigger runs as
	 * that lane's identity; otherwise does nothing and says so once in the Error Log.
	 */
	public static void onStart(String lane) {
		if (runningLane() != lane) {
			ErrorLogger.logMessage(
				BarnHelp.text('Connector', 'Connector_Log_WrongLane', new List<Object>{ lane }),
				'ConnectorClock.onStart',
				ErrorLogger.SEVERITY_WARNING
			);
			return;
		}
		ConnectorRunner.start(lane);
		ensure(lane);
	}

	/** Starts the lane's heartbeat when it has work and none is waiting or running. */
	public static void ensure(String lane) {
		if (!ConnectorRunStore.clockNeeded(runAsOf(lane)) || beating(UserInfo.getUserId(), null)) {
			return;
		}
		try {
			AsyncStarter.queue(new ConnectorClock(), 'ConnectorClock.ensure');
		} catch (Exception busy) {
			// The next start event or the nightly step starts it.
			ErrorLogger.log(busy, 'ConnectorClock.ensure');
		}
	}

	/** Whether a heartbeat queued by the user, other than `except`, waits or runs. */
	public static Boolean beating(Id userId, Id except) {
		return [
				SELECT COUNT()
				FROM AsyncApexJob
				WHERE
					JobType = 'Queueable'
					AND ApexClass.Name = 'ConnectorClock'
					AND Status IN :GOING
					AND CreatedById = :userId
					AND Id != :except
				WITH SYSTEM_MODE
			] > 0;
	}

	public void execute(QueueableContext context) {
		String lane = runningLane();
		if (lane == null) {
			ErrorLogger.logMessage(
				BarnHelp.text('Connector', 'Connector_Log_WrongIdentity'),
				'ConnectorClock.execute',
				ErrorLogger.SEVERITY_WARNING
			);
			return;
		}
		if (!Test.isRunningTest()) {
			System.attachFinalizer(new Restart());
		}
		beat(lane);
		Id me = context == null ? null : context.getJobId();
		if (ConnectorRunStore.clockNeeded(runAsOf(lane)) && !beating(UserInfo.getUserId(), me)) {
			next();
		}
	}

	/**
	 * One beat (R-CR6): Waiting runs that are due are queued again, each due recipe runs or
	 * polls, and the runner is started when runs wait. Paused, it only starts Test runs.
	 */
	@TestVisible
	private static void beat(String lane) {
		Set<String> runAs = runAsOf(lane);
		Boolean paused = paused();
		if (!paused) {
			ConnectorRunStore.releaseWaiting(runAs);
			Datetime now = Datetime.now();
			List<Connector_Run__c> runs = new List<Connector_Run__c>();
			List<Connector_Recipe__c> moved = new List<Connector_Recipe__c>();
			List<String> problems = new List<String>();
			Set<Id> identities = ConnectorIntegrationUser.identityIds();
			for (Connector_Recipe__c recipe : ConnectorRunStore.due(runAs, now)) {
				if (low()) {
					break;
				}
				// Only what the beat moved is written back: the runner, an App Poll and an admin
				// change the rest of the recipe meanwhile, and a stale copy would undo it.
				Connector_Recipe__c slim = new Connector_Recipe__c(Id = recipe.Id);
				String mark = recipe.Watermark__c;
				try {
					runs.addAll(dueRuns(recipe, identities, now));
					if (recipe.Watermark__c != mark) {
						slim.Watermark__c = recipe.Watermark__c;
					}
				} catch (Exception refused) {
					problems.add(failedPoll(recipe, refused, now));
					slim.Consecutive_Failures__c = recipe.Consecutive_Failures__c;
					if (recipe.Status__c == ConnectorRunStore.PAUSED_BY_FAILURES) {
						slim.Status__c = recipe.Status__c;
					}
				}
				slim.Next_Run_At__c = recipe.Next_Run_At__c;
				moved.add(slim);
			}
			ConnectorRunStore.clockSave(runs, moved);
			ErrorLogger.logMessages(problems, 'ConnectorClock', ErrorLogger.SEVERITY_ERROR);
		}
		if (ConnectorRunStore.anyQueued(runAs, paused)) {
			publish(new Set<String>{ lane });
		}
	}

	/** A due recipe's runs: one for a schedule, the changed records' for a Record Change. */
	private static List<Connector_Run__c> dueRuns(Connector_Recipe__c recipe, Set<Id> identities, Datetime now) {
		Map<String, Object> starter = ConnectorRecipeDocument.mapOf(
			ConnectorRecipeDocument.parse(recipe.Definition_JSON__c).get('trigger')
		);
		if (recipe.Trigger_Kind__c == ConnectorRecipes.SCHEDULE) {
			Datetime due = recipe.Next_Run_At__c == null ? now : recipe.Next_Run_At__c;
			recipe.Next_Run_At__c = ConnectorTriggers.nextAt(starter, now);
			return new List<Connector_Run__c>{
				ConnectorTriggers.newRun(
					recipe,
					'Schedule',
					JSON.serialize(new Map<String, Object>{ 'scheduledAt' => due })
				)
			};
		}
		recipe.Next_Run_At__c = now.addMinutes(POLL_MINUTES);
		if (recipe.Trigger_Kind__c == ConnectorAppPoll.APP_POLL) {
			// A beat cannot call out: the runner makes the poll (R-CR16).
			return ConnectorAppPoll.pollRun(recipe);
		}
		ConnectorTriggers poller = new ConnectorTriggers(recipe, starter, identities);
		return recipe.Run_As__c == ConnectorRecipes.RUN_AS_SYSTEM
			? ConnectorRunStore.pollInSystemMode(poller)
			: poller.poll();
	}

	/**
	 * A recipe that could not run or poll (its object or a field gone, no access) tries again in
	 * 15 minutes, counts as a failure and pauses itself at its limit (R-CR7).
	 */
	private static String failedPoll(Connector_Recipe__c recipe, Exception refused, Datetime now) {
		recipe.Next_Run_At__c = now.addMinutes(POLL_MINUTES);
		recipe.Consecutive_Failures__c =
			(recipe.Consecutive_Failures__c == null ? 0 : recipe.Consecutive_Failures__c) + 1;
		if (recipe.Consecutive_Failures__c >= ConnectorRecipes.pauseAfter(recipe)) {
			recipe.Status__c = ConnectorRunStore.PAUSED_BY_FAILURES;
		}
		return BarnHelp.text(
			'Connector',
			'Connector_Log_PollFailed',
			new List<Object>{ recipe.Name, refused.getMessage() }
		);
	}

	/** A beat stops early near the limits; what is left stays due for the next one. */
	private static Boolean low() {
		return Limits.getQueries() >= 150 || Limits.getDmlStatements() >= 120 || Limits.getCpuTime() >= 40000;
	}

	private static void next() {
		if (Test.isRunningTest()) {
			chained = true;
			return;
		}
		AsyncStarter.queue(new ConnectorClock(), BEAT_MINUTES, 'ConnectorClock');
	}

	/** Queues a beat that died again, so one failure cannot stop the clock. */
	public with sharing class Restart implements Finalizer {
		public void execute(FinalizerContext context) {
			if (context.getResult() != ParentJobResult.UNHANDLED_EXCEPTION) {
				return;
			}
			ErrorLogger.logMessage(
				BarnHelp.text(
					'Connector',
					'Connector_Log_BeatFailed',
					new List<Object>{ context.getException().getTypeName() }
				),
				'ConnectorClock',
				ErrorLogger.SEVERITY_WARNING
			);
			next();
		}
	}
}
