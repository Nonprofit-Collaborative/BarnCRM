/**
 * The recipe clock (CN-03; canonical model R-CR1, R-CR4, R-CR6 to R-CR8, R-RUN2, R-CS1; design
 * Sections 3.2, 3.7, 3.9 and 3.10; security review F4, F7 and F12). Dana, the Connector admin,
 * publishes Schedule and Record Change recipes; each lane's heartbeat starts their runs as the
 * lane's identity, retries what may pass, pauses a recipe that keeps failing, and Health Check
 * says when a lane stopped or the integration user cannot run its recipes. A test cannot run as
 * the Automated Process user, so `laneForTest` stands in for the lane's identity.
 */
@IsTest(
	testFor='ApexClass:ConnectorClock, ApexClass:ConnectorTriggers, ApexClass:ConnectorIntegrationUser, ApexClass:ConnectorClockChecks, ApexClass:ConnectorNightlyJobProvider, ApexTrigger:ConnectorStartUserTrigger'
)
private class ConnectorClockTest {
	private static final String INTEGRATOR = 'Integrator';
	private static final String DEPARTED = 'Departed';
	private static final String STOP_STEPS = '[{"id":"end","kind":"stop","outcome":"Succeeded"}]';

	@TestSetup
	static void createTestUsers() {
		// runs-as: deploying user (creates the test users and deactivates one; no BarnCRM logic runs)
		TestUsers.adminWith(ConnectorConnections.ADMIN_SET);
		TestUsers.standardUser(INTEGRATOR);
		TestUsers.fromSetup(INTEGRATOR);
		User departed = TestUsers.standardUser(DEPARTED);
		departed.IsActive = false;
		update as system departed;
	}

	private static User admin() {
		return TestUsers.adminWith(ConnectorConnections.ADMIN_SET);
	}

	/** The user setup deactivated (TestUsers.fromSetup finds active users only). */
	private static Id departed() {
		return [SELECT Id FROM User WHERE LastName = :DEPARTED AND IsActive = FALSE WITH SYSTEM_MODE LIMIT 1].Id;
	}

	/** An Active recipe started by the clock, its trigger as given. */
	private static Connector_Recipe__c clockRecipe(String name, String triggerJson, String kind, String runAs) {
		String document = '{"version":1,"trigger":' + triggerJson + ',"steps":' + STOP_STEPS + '}';
		Connector_Recipe__c recipe = ConnectorRecipeTestData.recipe(name, document, true, runAs);
		recipe.Trigger_Kind__c = kind;
		update as system recipe;
		return recipe;
	}

	private static String recordTrigger(String mode) {
		return '{"kind":"record","on":"changed","mode":"' +
			mode +
			'","query":{"version":1,"object":"Contact","fields":["LastName"]}}';
	}

	private static Connector_Recipe__c reread(Id recipeId) {
		return [
			SELECT Id, Status__c, Next_Run_At__c, Watermark__c, Consecutive_Failures__c
			FROM Connector_Recipe__c
			WHERE Id = :recipeId
			WITH SYSTEM_MODE
		];
	}

	private static List<Connector_Run__c> runsOf(Id recipeId) {
		return [
			SELECT Id, Status__c, Started_By__c, Input_JSON__c, Attempt__c, Next_Attempt_At__c
			FROM Connector_Run__c
			WHERE Recipe__c = :recipeId
			WITH SYSTEM_MODE
			ORDER BY CreatedDate, Id
		];
	}

	private static Integer logged(String context) {
		return [SELECT COUNT() FROM Error_Log__c WHERE Context__c LIKE :context WITH SYSTEM_MODE];
	}

	private static void chooseUser(Id userId) {
		OrgSettingsSystemWriter.save(
			Connector_Settings__c.SObjectType,
			new Map<Schema.SObjectField, Object>{
				Connector_Settings__c.Integration_User_Id__c => String.valueOf(userId)
			}
		);
	}

	/** A finding's fields by key; `Finding`'s fields are `@AuraEnabled` only, so read through JSON. */
	private static Map<String, Object> findingOf(List<HealthCheckService.Finding> found, String key) {
		for (Object each : (List<Object>) JSON.deserializeUntyped(JSON.serialize(found))) {
			Map<String, Object> fields = (Map<String, Object>) each;
			if (fields.get('key') == key) {
				return fields;
			}
		}
		return null;
	}

	@IsTest
	static void schedulesComeDueInTheOrgTimeZoneAndBadTriggersAreRefusedInWords() {
		System.runAs(admin()) {
			String zone = [SELECT TimeZoneSidKey FROM Organization WITH SYSTEM_MODE LIMIT 1].TimeZoneSidKey;
			Datetime now = Datetime.now();

			Test.startTest();
			Datetime quarter = ConnectorTriggers.nextAt(new Map<String, Object>{ 'every' => '15m' }, now);
			Datetime hourly = ConnectorTriggers.nextAt(new Map<String, Object>{ 'every' => 'hour' }, now);
			Datetime daily = ConnectorTriggers.nextAt(
				new Map<String, Object>{ 'every' => 'day', 'at' => '09:30' },
				now
			);
			Datetime weekly = ConnectorTriggers.nextAt(
				new Map<String, Object>{ 'every' => 'week', 'at' => '18:00', 'day' => 'MON' },
				now
			);
			String badSchedule = ConnectorTriggers.problem(
				new Map<String, Object>{ 'kind' => 'schedule', 'every' => 'day', 'at' => '25:00' }
			);
			String badRecord = ConnectorTriggers.problem(
				new Map<String, Object>{ 'kind' => 'record', 'on' => 'deleted', 'query' => new Map<String, Object>() }
			);
			String goodRecord = ConnectorTriggers.problem(
				(Map<String, Object>) JSON.deserializeUntyped(recordTrigger('batch'))
			);
			Test.stopTest();

			Assert.areEqual(now.addMinutes(15), quarter);
			Assert.areEqual(now.addHours(1), hourly);
			Assert.areEqual('09:30', daily.format('HH:mm', zone), 'A daily time is the org\'s wall clock time.');
			Assert.isTrue(daily > now && daily <= now.addDays(1));
			Assert.areEqual('Mon 18:00', weekly.format('EEE HH:mm', zone));
			Assert.isTrue(weekly > now && weekly <= now.addDays(7));
			Assert.areEqual(BarnHelp.text('Connector', 'Connector_Recipe_ErrorSchedule'), badSchedule);
			Assert.areEqual(BarnHelp.text('Connector', 'Connector_Recipe_ErrorRecordTrigger'), badRecord);
			Assert.isNull(goodRecord);
		}
	}

	@IsTest
	static void aScheduleBeatStartsOneRunAndMovesTheRecipeOn() {
		System.runAs(admin()) {
			Connector_Recipe__c recipe = clockRecipe(
				'Hourly',
				'{"kind":"schedule","every":"hour"}',
				ConnectorRecipes.SCHEDULE,
				ConnectorRecipes.RUN_AS_AUTOMATION
			);
			ConnectorClock.laneForTest = ConnectorClock.LANE_AUTOMATION;

			Test.startTest();
			new ConnectorClock().execute(null);
			Test.stopTest();

			List<Connector_Run__c> runs = runsOf(recipe.Id);
			Assert.areEqual(1, runs.size(), 'A due schedule starts one run.');
			Assert.areEqual('Schedule', runs[0].Started_By__c);
			Assert.isTrue(runs[0].Input_JSON__c.contains('scheduledAt'));
			Assert.isTrue(
				reread(recipe.Id).Next_Run_At__c > Datetime.now().addMinutes(55),
				'The next run is an hour on.'
			);
			Assert.isTrue(ConnectorClock.published.contains(ConnectorClock.LANE_AUTOMATION), 'The runner is started.');
			Assert.isTrue(ConnectorClock.chained, 'The lane still has work, so the next beat is queued.');
		}
	}

	@IsTest
	static void aRecordChangePollMakesRunsFromTheWatermarkAndSkipsTheIdentitiesChanges() {
		System.runAs(admin()) {
			Connector_Recipe__c recipe = clockRecipe(
				'Contacts Changed',
				recordTrigger('each'),
				ConnectorRecipes.RECORD_CHANGE,
				ConnectorRecipes.RUN_AS_AUTOMATION
			);
			recipe.Watermark__c = ConnectorTriggers.watermark(Datetime.now().addMinutes(-10), null);
			update as system recipe;
			insert as system new List<Contact>{ new Contact(LastName = 'Lovelace'), new Contact(LastName = 'Hopper') };
			Map<String, Object> each = (Map<String, Object>) JSON.deserializeUntyped(recordTrigger('each'));
			Map<String, Object> batch = (Map<String, Object>) JSON.deserializeUntyped(recordTrigger('batch'));
			Connector_Recipe__c copy = recipe.clone(true);
			Connector_Recipe__c guarded = recipe.clone(true);

			Test.startTest();
			List<Connector_Run__c> batchRuns = new ConnectorTriggers(copy, batch, new Set<Id>()).poll();
			List<Connector_Run__c> skipped = new ConnectorTriggers(guarded, each, new Set<Id>{ UserInfo.getUserId() })
				.poll();
			ConnectorClock.laneForTest = ConnectorClock.LANE_AUTOMATION;
			new ConnectorClock().execute(null);
			Test.stopTest();

			List<Connector_Run__c> runs = runsOf(recipe.Id);
			Assert.areEqual(2, runs.size(), 'Each changed record starts its own run.');
			Assert.areEqual('RecordChange', runs[0].Started_By__c);
			Assert.isTrue(runs[0].Input_JSON__c.contains('Lovelace'), 'The record is the run\'s input.');
			Assert.areEqual(1, batchRuns.size(), 'A batch trigger starts one run for the records.');
			Assert.isTrue(batchRuns[0].Input_JSON__c.contains('recordIds'));
			Assert.isTrue(skipped.isEmpty(), 'Records last changed by a recipe identity are skipped.');
			Connector_Recipe__c after = reread(recipe.Id);
			Assert.isTrue(after.Watermark__c.contains('|003'), 'The Watermark moves to the last record read.');
			Assert.isTrue(after.Next_Run_At__c > Datetime.now(), 'The next poll waits 15 minutes.');

			List<Connector_Run__c> again = new ConnectorTriggers(after, each, new Set<Id>()).poll();
			Assert.isTrue(again.isEmpty(), 'A record is not run twice.');
		}
	}

	@IsTest
	static void aFailureThatMayPassWaitsForItsNextTryAndIsQueuedAgain() {
		System.runAs(admin()) {
			Connector_Recipe__c recipe = clockRecipe(
				'Retried',
				'{"kind":"schedule","every":"day","at":"03:00"}',
				ConnectorRecipes.SCHEDULE,
				ConnectorRecipes.RUN_AS_AUTOMATION
			);
			ConnectorStepRunner.StepFailureException passing = new ConnectorStepRunner.StepFailureException('503');
			passing.passing = true;
			Connector_Run__c run = new Connector_Run__c(
				Status__c = ConnectorRunStore.FAILED,
				Attempt__c = 0,
				Is_Test__c = false,
				Recipe__r = new Connector_Recipe__c(Retry_Attempts__c = 2)
			);

			Test.startTest();
			Datetime now = Datetime.now();
			Connector_Run__c waiting = ConnectorRunner.waitIfPassing(run.clone(), passing);
			passing.retryAfter = 999999;
			Connector_Run__c capped = ConnectorRunner.waitIfPassing(run.clone(), passing);
			Connector_Run__c spent = run.clone();
			spent.Attempt__c = 2;
			spent = ConnectorRunner.waitIfPassing(spent, passing);
			Connector_Run__c lasting = ConnectorRunner.waitIfPassing(run.clone(), null);

			Connector_Run__c due = new Connector_Run__c(
				Recipe__c = recipe.Id,
				Status__c = ConnectorRunStore.WAITING,
				Started_By__c = 'Schedule',
				Ran_As__c = ConnectorRecipes.RUN_AS_AUTOMATION,
				Recipe_Version__c = 1,
				Attempt__c = 0,
				Failed_Step__c = 'send',
				Next_Attempt_At__c = now.addMinutes(-1)
			);
			insert as system due;
			ConnectorRunStore.releaseWaiting(ConnectorClock.runAsOf(ConnectorClock.LANE_AUTOMATION));
			Test.stopTest();

			Assert.areEqual(ConnectorRunStore.WAITING, waiting.Status__c);
			Assert.isTrue(waiting.Next_Attempt_At__c >= now.addMinutes(15), 'The first retry is 15 minutes on.');
			Assert.isTrue(capped.Next_Attempt_At__c <= now.addDays(1).addMinutes(1), 'Retry-After is capped at a day.');
			Assert.areEqual(ConnectorRunStore.FAILED, spent.Status__c, 'Retry Attempts used up: the run fails.');
			Assert.areEqual(ConnectorRunStore.FAILED, lasting.Status__c, 'A lasting failure does not wait.');
			Connector_Run__c released = runsOf(recipe.Id)[0];
			Assert.areEqual(ConnectorRunStore.QUEUED, released.Status__c, 'A due Waiting run is queued again.');
			Assert.areEqual(1, released.Attempt__c);
			Assert.isNull(released.Next_Attempt_At__c);
		}
	}

	@IsTest
	static void aRecipeThatKeepsFailingPausesItselfAndSaysSo() {
		System.runAs(admin()) {
			Connector_Recipe__c recipe = ConnectorRecipeTestData.recipe(
				'Always Fails',
				ConnectorRecipeTestData.document('[{"id":"end","kind":"stop","outcome":"Failed"}]'),
				true,
				ConnectorRecipes.RUN_AS_AUTOMATION
			);
			recipe.Pause_After_Failures__c = 2;
			update as system recipe;
			Connector_Run__c first = ConnectorRecipeTestData.queuedRun(recipe, '{}', false);
			ConnectorRecipeTestData.queuedRun(recipe, '{}', false);

			Test.startTest();
			ConnectorRecipeTestData.runAll(first.Id);
			Test.stopTest();

			Connector_Recipe__c after = reread(recipe.Id);
			Assert.areEqual(ConnectorRunStore.PAUSED_BY_FAILURES, after.Status__c);
			Assert.areEqual(2, after.Consecutive_Failures__c);
			Assert.areEqual(
				3,
				[
					SELECT COUNT()
					FROM Error_Log__c
					WHERE Message__c LIKE '%Always Fails%' AND Context__c = 'ConnectorRunner' AND Severity__c = 'Error'
					WITH SYSTEM_MODE
				],
				'Each failed run is logged, and the pause once more.'
			);
		}
	}

	@IsTest
	static void pauseAllRecipesStopsTheClockButNotTestRuns() {
		System.runAs(admin()) {
			Connector_Recipe__c recipe = clockRecipe(
				'Paused Schedule',
				'{"kind":"schedule","every":"15m"}',
				ConnectorRecipes.SCHEDULE,
				ConnectorRecipes.RUN_AS_AUTOMATION
			);
			ConnectorRecipeTestData.queuedRun(recipe, '{}', true);
			ConnectorClock.laneForTest = ConnectorClock.LANE_AUTOMATION;

			Test.startTest();
			ConnectorClock.Status paused = ConnectorClock.setPaused(true);
			ConnectorClock.published.clear();
			ConnectorClock.beat(ConnectorClock.LANE_AUTOMATION);
			Boolean testRunStarted = ConnectorClock.published.contains(ConnectorClock.LANE_AUTOMATION);
			ConnectorClock.Status resumed = ConnectorClock.setPaused(false);
			Test.stopTest();

			Assert.isTrue(paused.paused);
			Assert.isFalse(resumed.paused);
			Assert.areEqual(1, runsOf(recipe.Id).size(), 'Paused, no schedule run starts.');
			Assert.isTrue(testRunStarted, 'A Test run from the editor still starts.');
			Assert.areEqual(2, resumed.lanes.size());
			Assert.isTrue(
				ConnectorClock.published.contains(ConnectorClock.LANE_AUTOMATION),
				'Unpausing starts the lane.'
			);
		}
	}

	@IsTest
	static void aStartEventRunsOnlyAsItsLanesIdentity() {
		System.runAs(admin()) {
			Test.startTest();
			ConnectorClock.onStart(ConnectorClock.LANE_USER);
			new ConnectorClock().execute(null);
			Test.stopTest();

			Assert.isNull(ConnectorClock.runningLane(), 'A staff member is no recipe identity.');
			Assert.areEqual(1, logged('ConnectorClock.onStart'), 'The wrong lane is logged.');
			Assert.areEqual(1, logged('ConnectorClock.execute'), 'A beat as a staff member does nothing.');
		}
	}

	@IsTest
	static void theHeartbeatPicksUpAQueuedRunNoRunnerStarted() {
		System.runAs(admin()) {
			Connector_Recipe__c recipe = ConnectorRecipeTestData.recipe(
				'Stranded',
				ConnectorRecipeTestData.document(STOP_STEPS),
				true,
				ConnectorRecipes.RUN_AS_AUTOMATION
			);
			insert as system ConnectorTriggers.newRun(recipe, 'Manual', '{}');
			ConnectorClock.laneForTest = ConnectorClock.LANE_AUTOMATION;

			Test.startTest();
			ConnectorClock.beat(ConnectorClock.LANE_AUTOMATION);
			Test.getEventBus().deliver();
			Test.stopTest();

			Assert.isTrue(ConnectorClock.published.contains(ConnectorClock.LANE_AUTOMATION));
			Assert.isTrue(
				[SELECT COUNT() FROM AsyncApexJob WHERE ApexClass.Name = 'ConnectorRunner' WITH SYSTEM_MODE] > 0,
				'The start event the beat published starts the runner.'
			);
			Assert.isTrue(
				[SELECT COUNT() FROM AsyncApexJob WHERE ApexClass.Name = 'ConnectorClock' WITH SYSTEM_MODE] > 0,
				'And the lane\'s heartbeat.'
			);
		}
	}

	@IsTest
	static void theNightlyStepDeletesExpiredRunsAndStartsLanesWithWork() {
		System.runAs(admin()) {
			Connector_Recipe__c brief = ConnectorRecipeTestData.recipe(
				'Kept A Week',
				ConnectorRecipeTestData.document(STOP_STEPS),
				true,
				ConnectorRecipes.RUN_AS_AUTOMATION
			);
			brief.Keep_Runs_Days__c = 7;
			update as system brief;
			Connector_Recipe__c month = ConnectorRecipeTestData.recipe(
				'Kept A Month',
				ConnectorRecipeTestData.document(STOP_STEPS),
				true,
				ConnectorRecipes.RUN_AS_AUTOMATION
			);
			List<Connector_Run__c> runs = new List<Connector_Run__c>();
			for (Connector_Recipe__c recipe : new List<Connector_Recipe__c>{ brief, brief, month }) {
				Connector_Run__c run = ConnectorTriggers.newRun(recipe, 'Manual', '{}');
				run.Status__c = ConnectorRunStore.SUCCEEDED;
				runs.add(run);
			}
			insert as system runs;
			Test.setCreatedDate(runs[0].Id, Datetime.now().addDays(-10));
			Test.setCreatedDate(runs[2].Id, Datetime.now().addDays(-10));
			clockRecipe(
				'Nightly Schedule',
				'{"kind":"schedule","every":"hour"}',
				ConnectorRecipes.SCHEDULE,
				ConnectorRecipes.RUN_AS_AUTOMATION
			);

			Test.startTest();
			List<NightlyStep> steps = new ConnectorNightlyJobProvider().nightlySteps();
			new ConnectorNightlyJobProvider.Cleanup().execute(null);
			Test.stopTest();

			Assert.areEqual(1, steps.size());
			Assert.areEqual(1, runsOf(brief.Id).size(), 'Only the run past its recipe\'s Keep Runs Days goes.');
			Assert.areEqual(1, runsOf(month.Id).size(), 'Thirty days by default.');
			Assert.isTrue(ConnectorClock.published.contains(ConnectorClock.LANE_AUTOMATION), 'A stopped lane starts.');
		}
	}

	@IsTest
	static void danaChoosesTheIntegrationUserAndTheSubscriberIsWritten() {
		User integrator = TestUsers.fromSetup(INTEGRATOR);
		System.runAs(admin()) {
			ConnectorRecipeTestData.App app = new ConnectorRecipeTestData.App(200, '{"records":[]}');
			Test.setMock(HttpCalloutMock.class, app);
			String refused;
			try {
				ConnectorIntegrationUser.choose(departed());
			} catch (ConnectorConnections.ConnectorException expected) {
				refused = expected.getMessage();
			}

			Test.startTest();
			ConnectorIntegrationUser.View chosen = ConnectorRecipesController.chooseIntegrationUser(integrator.Id);
			Test.stopTest();

			Assert.areEqual(BarnHelp.text('Connector', 'Connector_IntegrationUser_ErrorChoice'), refused);
			Assert.areEqual(String.valueOf(integrator.Id), chosen.id);
			Assert.areEqual(integrator.Id, ConnectorIntegrationUser.chosenId(), 'Saved org-wide.');
			Assert.isTrue(ConnectorIntegrationUser.ready());
			Assert.isTrue(ConnectorIntegrationUser.identityIds().contains(integrator.Id), 'The loop guard skips it.');
			Assert.areEqual(2, app.requests.size(), 'The subscriber is looked up, then created.');
			Assert.areEqual('GET', app.requests[0].getMethod());
			Assert.areEqual('POST', app.requests[1].getMethod());
			Assert.isTrue(app.requests[1].getBody().contains(integrator.Id));
			Assert.isTrue(app.requests[1].getEndpoint().startsWith('callout:Barn_Org_Connection/'));
			Assert.isTrue(
				ConnectorRecipesController.getIntegrationUser().hasConnections,
				'It gets BarnCRM Connections.'
			);
		}
	}

	@IsTest
	static void aRefusedSubscriberWriteIsLoggedAndAccessStaysAsItWas() {
		User integrator = TestUsers.fromSetup(INTEGRATOR);
		System.runAs(admin()) {
			Test.setMock(HttpCalloutMock.class, new ConnectorRecipeTestData.App(403, '[{"message":"no"}]'));

			Test.startTest();
			AsyncStarter.queue(new ConnectorIntegrationUser.SubscriberJob(integrator.Id, null), 'ConnectorClockTest');
			Test.stopTest();

			Assert.areEqual(1, logged('ConnectorIntegrationUser'));
			Assert.isFalse(ConnectorConnections.holds(integrator.Id, ConnectorConnections.ACCESS_SET, null));
		}
	}

	@IsTest
	static void healthCheckSaysWhenALaneStoppedOrTheIntegrationUserCannotRun() {
		System.runAs(admin()) {
			clockRecipe(
				'Unattended',
				'{"kind":"schedule","every":"hour"}',
				ConnectorRecipes.SCHEDULE,
				ConnectorRecipes.RUN_AS_AUTOMATION
			);
			ConnectorRecipeTestData.recipe(
				'As The Integrator',
				ConnectorRecipeTestData.document(STOP_STEPS),
				true,
				ConnectorRecipes.RUN_AS_USER
			);
			Connector_Recipe__c failing = ConnectorRecipeTestData.recipe(
				'Gave Up',
				ConnectorRecipeTestData.document(STOP_STEPS),
				true,
				ConnectorRecipes.RUN_AS_AUTOMATION
			);
			failing.Status__c = ConnectorRunStore.PAUSED_BY_FAILURES;
			update as system failing;

			Test.startTest();
			List<HealthCheckService.Finding> none = ConnectorClockChecks.findings();
			chooseUser(departed());
			ConnectorClock.setPaused(true);
			List<HealthCheckService.Finding> inactive = ConnectorClockChecks.findings();
			Test.stopTest();

			Map<String, Object> stopped = findingOf(none, 'connector_clock_stopped_automation');
			Assert.isNotNull(stopped, 'A lane with work and no heartbeat is named.');
			Assert.isTrue(
				String.valueOf(stopped.get('fixTarget')).endsWith('Super_Connector'),
				'Its fix opens Super Connector.'
			);
			Assert.areEqual(
				BarnHelp.text('Connector', 'Connector_Health_UserNotChosen_Title'),
				findingOf(none, 'connector_integration_user_inactive').get('title')
			);
			Map<String, Object> gone = findingOf(inactive, 'connector_integration_user_inactive');
			Assert.areEqual(BarnHelp.text('Connector', 'Connector_Health_UserInactive_Title'), gone.get('title'));
			Assert.areEqual(HealthCheckService.SEVERITY_ERROR, gone.get('severity'));
			Assert.isTrue(
				String.valueOf(gone.get('detail')).contains('As The Integrator'),
				'The recipes it stops are named.'
			);
			Assert.isNotNull(findingOf(none, 'connector_paused_by_failures'));
			Assert.isNull(findingOf(none, 'connector_recipes_paused'));
			Assert.isNotNull(findingOf(inactive, 'connector_recipes_paused'));
		}
	}

	@IsTest
	static void danaSetsARecipesRetriesPausesResumesAndRetriesItsFailedRuns() {
		System.runAs(admin()) {
			Connector_Recipe__c recipe = clockRecipe(
				'Settings',
				'{"kind":"schedule","every":"day","at":"06:00"}',
				ConnectorRecipes.SCHEDULE,
				ConnectorRecipes.RUN_AS_AUTOMATION
			);
			List<Connector_Run__c> failed = new List<Connector_Run__c>();
			for (Boolean isTest : new List<Boolean>{ false, false, true }) {
				Connector_Run__c run = ConnectorTriggers.newRun(recipe, isTest ? 'Test' : 'Schedule', '{}');
				run.Status__c = ConnectorRunStore.FAILED;
				run.Is_Test__c = isTest;
				failed.add(run);
			}
			insert as system failed;
			String outOfRange;
			String noUser;

			Test.startTest();
			try {
				ConnectorRecipesController.saveRecipeSettings(recipe.Id, 9, 10, 30, true);
			} catch (Exception expected) {
				outOfRange = expected.getMessage();
			}
			try {
				ConnectorRecipesController.setRunAs(recipe.Id, ConnectorRecipes.RUN_AS_USER, false);
			} catch (Exception expected) {
				noUser = expected.getMessage();
			}
			ConnectorRecipes.Recipe saved = ConnectorRecipesController.saveRecipeSettings(recipe.Id, 1, 5, 14, false);
			ConnectorRecipes.Recipe paused = ConnectorRecipesController.pauseRecipe(recipe.Id);
			ConnectorRecipes.Recipe resumed = ConnectorRecipesController.resumeRecipe(recipe.Id);
			Integer retried = ConnectorRecipesController.retryAllFailed(recipe.Id);
			ConnectorClock.Status clock = ConnectorRecipesController.restartClock();
			Test.stopTest();

			Assert.areEqual(BarnHelp.text('Connector', 'Connector_Settings_ErrorRange'), outOfRange);
			Assert.areEqual(BarnHelp.text('Connector', 'Connector_RunAs_ErrorNoUser'), noUser);
			Assert.areEqual(1, saved.retryAttempts);
			Assert.areEqual(5, saved.pauseAfterFailures);
			Assert.areEqual(14, saved.keepRunsDays);
			Assert.isFalse(saved.ignoreOwnChanges);
			Assert.areEqual(ConnectorRunStore.PAUSED, paused.status);
			Assert.areEqual(ConnectorRunStore.ACTIVE, resumed.status);
			Assert.isNotNull(resumed.nextRunAt, 'A resumed schedule takes its next time.');
			Assert.areEqual(2, retried, 'Test runs are not retried with the rest.');
			Assert.isFalse(clock.paused);
			Assert.isTrue(ConnectorClock.published.contains(ConnectorClock.LANE_AUTOMATION));
		}
	}
}
