/**
 * Watching apps for new items (CN-13; canonical model R-CR1, R-CR6, R-CR20; design Section 3.2;
 * security review F1, F4, F7). Dana, the Connector admin, publishes a recipe whose When is An App
 * Has New Items: the clock queues one poll run at a time, the runner asks the app through the
 * connection, the first look only notes the newest stamp, later looks start a run per new item
 * (or one for all), oldest first, and a failed look is kept, retried and logged without its
 * request. A test cannot run as the Automated Process user, so `laneForTest` stands in for it.
 */
@IsTest(
	testFor='ApexClass:ConnectorAppPoll, ApexClass:ConnectorRunner, ApexClass:ConnectorClock, ApexClass:ConnectorRunStore, ApexClass:ConnectorRecipeDocument, ApexClass:ConnectorTriggers'
)
private class ConnectorAppPollTest {
	private static final String SECRET = 'not-a-key-but-never-echoed';
	private static final String STOP_STEPS = '[{"id":"end","kind":"stop","outcome":"Succeeded"}]';
	private static Integer made = 0;

	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(ConnectorConnections.ADMIN_SET);
	}

	private static User admin() {
		return TestUsers.adminWith(ConnectorConnections.ADMIN_SET);
	}

	/** An App Poll trigger on the test connection, with its changes. */
	private static Map<String, Object> starter(Map<String, Object> changes) {
		Map<String, Object> polled = new Map<String, Object>{
			'kind' => 'appPoll',
			'connection' => ConnectorRecipeTestData.CONNECTION,
			'path' => '/lists/{listId}/members',
			'pathValues' => new List<Object>{ new Map<String, Object>{ 'name' => 'listId', 'value' => 'L 1' } },
			'query' => new List<Object>{
				new Map<String, Object>{ 'name' => 'status', 'value' => 'unsubscribed' },
				new Map<String, Object>{ 'name' => 'since_last_changed', 'path' => ConnectorAppPoll.WATERMARK_PATH }
			},
			'items' => 'members',
			'id' => 'id',
			'stamp' => 'last_changed',
			'mode' => 'each'
		};
		polled.putAll(changes);
		return polled;
	}

	/** An Active App Poll recipe with the trigger and Watermark given. */
	private static Connector_Recipe__c pollRecipe(Map<String, Object> polled, String watermark) {
		String document = '{"version":1,"trigger":' + JSON.serialize(polled) + ',"steps":' + STOP_STEPS + '}';
		made++;
		Connector_Recipe__c recipe = ConnectorRecipeTestData.recipe(
			'Unsubscribes ' + made,
			document,
			true,
			ConnectorRecipes.RUN_AS_AUTOMATION
		);
		recipe.Trigger_Kind__c = ConnectorAppPoll.APP_POLL;
		recipe.Watermark__c = watermark;
		update as system recipe;
		return recipe;
	}

	/** Queues the recipe's poll run as the clock does, and runs the runner's job body once. */
	private static void pollOnce(Connector_Recipe__c recipe) {
		insert as system ConnectorAppPoll.pollRun(recipe);
		ConnectorRunner.process(ConnectorRunStore.queued(50), new ConnectorRunner.Guard());
	}

	private static List<Connector_Run__c> runsOf(Id recipeId) {
		return [
			SELECT
				Id,
				Status__c,
				Started_By__c,
				Input_JSON__c,
				Event_Key__c,
				Failed_Step__c,
				Error_Message__c,
				Step_Log_JSON__c,
				Next_Attempt_At__c
			FROM Connector_Run__c
			WHERE Recipe__c = :recipeId
			WITH SYSTEM_MODE
			ORDER BY CreatedDate, Id
		];
	}

	private static String watermarkOf(Id recipeId) {
		return [SELECT Watermark__c FROM Connector_Recipe__c WHERE Id = :recipeId WITH SYSTEM_MODE].Watermark__c;
	}

	private static String member(String id, String changed, String email) {
		return '{"id":' +
			(id == null ? 'null' : '"' + id + '"') +
			',"last_changed":"' +
			changed +
			'","email_address":"' +
			email +
			'"}';
	}

	@IsTest
	static void anAppPollIsCheckedLikeCallAnAppAndOnlyReadsTheWatermark() {
		System.runAs(admin()) {
			Test.startTest();
			String good = ConnectorAppPoll.problem(starter(new Map<String, Object>()));
			Map<String, Object> document = new Map<String, Object>{
				'version' => 1,
				'trigger' => starter(new Map<String, Object>{ 'items' => '', 'mode' => 'batch', 'limit' => 50 }),
				'steps' => JSON.deserializeUntyped(STOP_STEPS)
			};
			List<String> saved = ConnectorRecipeDocument.problems(document);
			Set<String> named = ConnectorRecipeDocument.connections(document);
			List<Map<String, Object>> bad = new List<Map<String, Object>>{
				new Map<String, Object>{ 'connection' => 'Barn_Stripe' },
				new Map<String, Object>{ 'path' => '//other.example.org/x' },
				new Map<String, Object>{ 'path' => '/a@b' },
				new Map<String, Object>{ 'pathValues' => new List<Object>() },
				new Map<String, Object>{
					'query' => new List<Object>{ new Map<String, Object>{ 'name' => 'q', 'path' => 'trigger.email' } }
				},
				new Map<String, Object>{
					'headers' => new List<Object>{
						new Map<String, Object>{ 'name' => 'Authorization', 'value' => 'x' }
					}
				},
				new Map<String, Object>{ 'id' => '' },
				new Map<String, Object>{ 'stamp' => 'last changed' },
				new Map<String, Object>{ 'mode' => 'some' },
				new Map<String, Object>{ 'limit' => 500 }
			};
			Integer refused = 0;
			for (Map<String, Object> change : bad) {
				if (ConnectorTriggers.problem(starter(change)) != null) {
					refused++;
				}
			}
			Test.stopTest();

			Assert.isNull(good, 'A complete App Poll trigger is accepted.');
			Assert.isTrue(saved.isEmpty(), 'The recipe saves: ' + saved);
			Assert.isTrue(named.contains(ConnectorRecipeTestData.CONNECTION), 'Publish checks the poll\'s connection.');
			Assert.areEqual(bad.size(), refused, 'Each broken trigger is refused in words.');
			Assert.areEqual(
				ConnectorAppPoll.APP_POLL,
				ConnectorRecipes.kindOf(document),
				'Listed as App Poll for the clock.'
			);
		}
	}

	@IsTest
	static void theClockQueuesOnePollRunAtATime() {
		System.runAs(admin()) {
			Connector_Recipe__c recipe = pollRecipe(starter(new Map<String, Object>()), null);
			ConnectorClock.laneForTest = ConnectorClock.LANE_AUTOMATION;

			Test.startTest();
			new ConnectorClock().execute(null);
			recipe.Next_Run_At__c = Datetime.now().addMinutes(-1);
			update as system recipe;
			ConnectorClock.beat(ConnectorClock.LANE_AUTOMATION);
			Test.stopTest();

			List<Connector_Run__c> runs = runsOf(recipe.Id);
			Assert.areEqual(1, runs.size(), 'A second look waits while the first is queued.');
			Assert.areEqual(ConnectorAppPoll.APP_POLL, runs[0].Started_By__c);
			Assert.isNull(runs[0].Input_JSON__c, 'A poll run carries no data.');
			Assert.isTrue(runs[0].Event_Key__c.startsWith(recipe.Id + ConnectorAppPoll.POLL_KEY));
			Assert.isTrue(ConnectorClock.published.contains(ConnectorClock.LANE_AUTOMATION), 'The runner is started.');
		}
	}

	@IsTest
	static void theFirstLookOnlyNotesTheNewestStamp() {
		System.runAs(admin()) {
			Connector_Recipe__c recipe = pollRecipe(starter(new Map<String, Object>()), null);
			ConnectorRecipeTestData.App app = new ConnectorRecipeTestData.App(
				200,
				'{"members":[' +
					member('a', '2026-11-20T10:00:00Z', 'ann@example.org') +
					',' +
					member('b', '2026-11-20T09:00:00Z', 'bo@example.org') +
					']}'
			);
			Test.setMock(HttpCalloutMock.class, app);

			Test.startTest();
			pollOnce(recipe);
			Test.stopTest();

			Assert.isTrue(runsOf(recipe.Id).isEmpty(), 'Items already in the app are not run; the poll run is spent.');
			Assert.areEqual('2026-11-20T10:00:00Z', watermarkOf(recipe.Id));
			Assert.areEqual(1, app.requests.size());
			Assert.areEqual('GET', app.requests[0].getMethod());
			Assert.areEqual(
				'callout:' + ConnectorRecipeTestData.CONNECTION + '/lists/L%201/members?status=unsubscribed',
				app.requests[0].getEndpoint(),
				'Only the connection\'s own address; no "since" before the first Watermark (F4).'
			);
		}
	}

	@IsTest
	static void laterLooksRunEachNewItemOldestFirstAndKeepAStampTogether() {
		System.runAs(admin()) {
			Connector_Recipe__c recipe = pollRecipe(
				starter(new Map<String, Object>{ 'limit' => 2 }),
				'2026-11-20T09:00:00Z'
			);
			ConnectorRecipeTestData.App app = new ConnectorRecipeTestData.App(
				200,
				'{"members":[' +
					member('c', '2026-11-20T11:00:00Z', 'cy@example.org') +
					',' +
					member('b', '2026-11-20T09:00:00Z', 'bo@example.org') +
					',' +
					member('a', '2026-11-20T10:00:00Z', 'ann@example.org') +
					',' +
					member(null, '2026-11-20T10:30:00Z', 'nobody@example.org') +
					',' +
					member('d', '2026-11-20T11:00:00Z', 'di@example.org') +
					',' +
					member('e', '2026-11-20T12:00:00Z', 'ed@example.org') +
					']}'
			);
			Test.setMock(HttpCalloutMock.class, app);

			Test.startTest();
			pollOnce(recipe);
			Test.stopTest();

			List<Connector_Run__c> runs = runsOf(recipe.Id);
			List<String> ids = new List<String>();
			for (Connector_Run__c run : runs) {
				Assert.areEqual(ConnectorRunStore.QUEUED, run.Status__c);
				Assert.areEqual(ConnectorAppPoll.APP_POLL, run.Started_By__c);
				Map<String, Object> input = (Map<String, Object>) JSON.deserializeUntyped(run.Input_JSON__c);
				ids.add((String) input.get('itemId'));
				Assert.isNotNull(((Map<String, Object>) input.get('item')).get('email_address'));
			}
			Assert.areEqual(
				new List<String>{ 'a', 'c', 'd' },
				ids,
				'Oldest first, at most 2, plus the item sharing the last stamp; no id, no run.'
			);
			Assert.areEqual('2026-11-20T11:00:00Z', watermarkOf(recipe.Id), 'e waits for the next look.');
			Assert.isTrue(
				app.requests[0].getEndpoint().endsWith('since_last_changed=2026-11-20T09%3A00%3A00Z'),
				'The Watermark goes in encoded: ' + app.requests[0].getEndpoint()
			);
		}
	}

	@IsTest
	static void aBatchLookStartsOneRunAndComparesNumbersAsNumbers() {
		System.runAs(admin()) {
			Connector_Recipe__c recipe = pollRecipe(
				starter(new Map<String, Object>{ 'mode' => 'batch', 'items' => '', 'stamp' => 'seq' }),
				'9'
			);
			Test.setMock(
				HttpCalloutMock.class,
				new ConnectorRecipeTestData.App(200, '[{"id":1,"seq":9},{"id":2,"seq":10},{"id":3,"seq":11}]')
			);

			Test.startTest();
			pollOnce(recipe);
			Test.stopTest();

			List<Connector_Run__c> runs = runsOf(recipe.Id);
			Assert.areEqual(1, runs.size(), 'One run for all the new items.');
			Map<String, Object> input = (Map<String, Object>) JSON.deserializeUntyped(runs[0].Input_JSON__c);
			Assert.areEqual(new List<Object>{ '2', '3' }, input.get('itemIds'), '10 is after 9 as a number.');
			Assert.areEqual(2, ((List<Object>) input.get('items')).size());
			Assert.areEqual('11', watermarkOf(recipe.Id));
			Assert.isTrue(ConnectorAppPoll.compareStamps('2026-11-20T10:00:00Z', '2026-11-20T09:59:59Z') > 0);
			Assert.areEqual(0, ConnectorAppPoll.compareStamps('7', '7.0'));
		}
	}

	@IsTest
	static void aLookThatMayPassWaitsAndTheWatermarkStays() {
		System.runAs(admin()) {
			Connector_Recipe__c recipe = pollRecipe(starter(new Map<String, Object>()), '2026-11-20T09:00:00Z');
			Test.setMock(HttpCalloutMock.class, new ConnectorRecipeTestData.App(503, 'down ' + SECRET));

			Test.startTest();
			pollOnce(recipe);
			Test.stopTest();

			List<Connector_Run__c> runs = runsOf(recipe.Id);
			Assert.areEqual(1, runs.size(), 'The failed look is kept.');
			Assert.areEqual(ConnectorRunStore.WAITING, runs[0].Status__c, 'A 503 is retried later (R-CR7).');
			Assert.isNotNull(runs[0].Next_Attempt_At__c);
			Assert.areEqual('trigger', runs[0].Failed_Step__c);
			Assert.areEqual('2026-11-20T09:00:00Z', watermarkOf(recipe.Id), 'Nothing is missed.');
		}
	}

	@IsTest
	static void aRefusedLookFailsInPlainWordsAndLogsNoRequest() {
		System.runAs(admin()) {
			Connector_Recipe__c recipe = pollRecipe(starter(new Map<String, Object>()), '2026-11-20T09:00:00Z');
			Test.setMock(HttpCalloutMock.class, new ConnectorRecipeTestData.App(401, SECRET.repeat(200)));

			Test.startTest();
			pollOnce(recipe);
			Test.stopTest();

			Connector_Run__c run = runsOf(recipe.Id)[0];
			Assert.areEqual(ConnectorRunStore.FAILED, run.Status__c);
			Assert.isFalse(run.Error_Message__c.contains(SECRET), 'The message is plain words (F7).');
			Map<String, Object> logged = (Map<String, Object>) ((List<Object>) JSON.deserializeUntyped(
				run.Step_Log_JSON__c
			))[0];
			Assert.areEqual(401, logged.get('status'));
			Assert.isTrue(((String) logged.get('response')).length() <= ConnectorStepRunner.TRIMMED, 'Trimmed.');
			for (Error_Log__c entry : [SELECT Message__c FROM Error_Log__c WITH SYSTEM_MODE]) {
				Assert.isFalse(entry.Message__c.contains(SECRET), 'The Error Log keeps no response or request.');
			}
			Assert.areEqual(
				1,
				[SELECT COUNT() FROM Error_Log__c WHERE Context__c LIKE 'ConnectorRunner%' WITH SYSTEM_MODE],
				'One entry for the failed look.'
			);
		}
	}

	@IsTest
	static void anAnswerWithoutTheListOrAPayloadMergeFieldFails() {
		System.runAs(admin()) {
			Connector_Recipe__c recipe = pollRecipe(starter(new Map<String, Object>()), '{!x}');
			Connector_Recipe__c other = pollRecipe(
				starter(new Map<String, Object>{ 'query' => new List<Object>() }),
				'2026-11-20T09:00:00Z'
			);
			Test.setMock(HttpCalloutMock.class, new ConnectorRecipeTestData.App(200, '{"data":[]}'));

			Test.startTest();
			insert as system ConnectorAppPoll.pollRun(recipe);
			pollOnce(other);
			Test.stopTest();

			Connector_Run__c guarded = runsOf(recipe.Id)[0];
			Assert.areEqual(ConnectorRunStore.FAILED, guarded.Status__c);
			Assert.areEqual(
				BarnHelp.text('Connector', 'Connector_Run_ErrorMergeField'),
				guarded.Error_Message__c,
				'A Watermark holding a merge field is never sent (F1).'
			);
			Connector_Run__c noList = runsOf(other.Id)[0];
			Assert.areEqual(ConnectorRunStore.FAILED, noList.Status__c);
			Assert.areEqual(
				BarnHelp.text('Connector', 'Connector_Poll_ErrorItems', new List<Object>{ 'members' }),
				noList.Error_Message__c
			);
		}
	}

	@IsTest
	static void aLookWaitsWhenARecordWasWrittenEarlierInTheJob() {
		System.runAs(admin()) {
			Connector_Recipe__c recipe = pollRecipe(starter(new Map<String, Object>()), null);
			insert as system ConnectorAppPoll.pollRun(recipe);
			Connector_Run__c run = ConnectorRunStore.queued(50)[0];
			ConnectorStepRunner.Budget budget = new ConnectorStepRunner.Budget();
			budget.wrote = true;

			Test.startTest();
			Connector_Run__c left = new ConnectorAppPoll().poll(run, budget);
			Test.stopTest();

			Assert.areEqual(run, left, 'Left Queued for the next transaction: no callout after a write.');
			Assert.areEqual(ConnectorRunStore.QUEUED, left.Status__c);
			Assert.isTrue(ConnectorAppPoll.isPoll(left));
		}
	}

	@IsTest
	static void danaPublishesAnAppPollAndTheClockStartsFromNoWatermark() {
		System.runAs(admin()) {
			ConnectorRecipeTestData.readyConnection();
			String document =
				'{"version":1,"trigger":' +
				JSON.serialize(starter(new Map<String, Object>())) +
				',"steps":' +
				STOP_STEPS +
				'}';

			Test.startTest();
			ConnectorRecipes.Recipe saved = ConnectorRecipesController.saveDraft(null, 'Watch', null, document, null);
			ConnectorRecipesController.publish(saved.id);
			Test.stopTest();

			Connector_Recipe__c row = [
				SELECT Trigger_Kind__c, Next_Run_At__c, Watermark__c, Status__c
				FROM Connector_Recipe__c
				WHERE Id = :saved.id
				WITH SYSTEM_MODE
			];
			Assert.areEqual(ConnectorAppPoll.APP_POLL, row.Trigger_Kind__c);
			Assert.areEqual(ConnectorRunStore.ACTIVE, row.Status__c);
			Assert.isNotNull(row.Next_Run_At__c, 'Due at once.');
			Assert.isNull(row.Watermark__c, 'The first look sets it.');
			Assert.isTrue(ConnectorClock.published.contains(ConnectorClock.LANE_AUTOMATION), 'The clock starts.');
		}
	}
}
