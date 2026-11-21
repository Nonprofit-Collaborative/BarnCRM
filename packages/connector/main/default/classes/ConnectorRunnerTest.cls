/**
 * Recipes run on their own (CN-02; canonical model R-CR1, R-CR4, R-CR5, R-RUN1 to R-RUN4;
 * design Sections 3.4, 3.7 and 4; security review F1, F4 and F7). Each test runs the runner's
 * job body in its own transaction: record steps save through a map, Call an App builds a
 * checked request, a callout never follows a record write in one transaction, and a failed run
 * is logged without its request.
 */
@IsTest(
	testFor='ApexClass:ConnectorRunner, ApexClass:ConnectorStepRunner, ApexClass:ConnectorRunStore, ApexClass:ConnectorMapRuntime, ApexTrigger:ConnectorStartTrigger'
)
private class ConnectorRunnerTest {
	private static final String MAIL = 'ada.lovelace@example.org';

	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(ConnectorConnections.ADMIN_SET);
	}

	private static User admin() {
		return TestUsers.adminWith(ConnectorConnections.ADMIN_SET);
	}

	private static List<Object> log(Connector_Run__c run) {
		return (List<Object>) JSON.deserializeUntyped(run.Step_Log_JSON__c);
	}

	private static Map<String, Object> logOf(Connector_Run__c run, Integer index) {
		return (Map<String, Object>) log(run)[index];
	}

	@IsTest
	static void recordStepsSaveThroughTheMapAndACalloutWaitsForTheNextTransaction() {
		System.runAs(admin()) {
			Id mapId = ConnectorRecipeTestData.contactMap('Contact From Payload');
			String steps =
				'[{"id":"make","kind":"upsert","map":"' +
				mapId +
				'","input":"trigger"},' +
				'{"id":"look","kind":"find","query":{"version":1,"object":"Contact","fields":["LastName","Email"],' +
				'"filter":{"version":1,"conditions":[{"id":1,"field":"Email","operator":"equals","value":"x"}]}},' +
				'"values":[{"condition":1,"path":"trigger.mail"}],"stopIfNone":true},' +
				'{"id":"fix","kind":"update","map":"' +
				mapId +
				'","recordId":"steps.make.id","input":"trigger"},' +
				'{"id":"send","kind":"callApp","connection":"' +
				ConnectorRecipeTestData.CONNECTION +
				'","method":"GET","path":"/ping"}]';
			Connector_Recipe__c recipe = ConnectorRecipeTestData.recipe(
				'Payload To Contact',
				ConnectorRecipeTestData.document(steps),
				true,
				ConnectorRecipes.RUN_AS_AUTOMATION
			);
			Connector_Run__c run = ConnectorRecipeTestData.queuedRun(
				recipe,
				'{"last":"Lovelace","mail":"' + MAIL + '"}',
				false
			);

			Test.startTest();
			Connector_Run__c paused = ConnectorRecipeTestData.runAll(run.Id);
			Test.stopTest();

			Assert.areEqual(ConnectorRunStore.QUEUED, paused.Status__c, 'Stopped before the callout, to continue.');
			Assert.areEqual(2, paused.Records_Written__c.intValue(), 'Create or Update, then Update.');
			Map<String, Object> state = (Map<String, Object>) JSON.deserializeUntyped(paused.State_JSON__c);
			Assert.areEqual(
				new Set<Object>{ 'make', 'look', 'fix' },
				new Set<Object>((List<Object>) state.get('done')),
				'Done steps are never repeated.'
			);
			Contact saved = [SELECT Id, LastName FROM Contact WHERE Email = :MAIL WITH SYSTEM_MODE];
			Map<String, Object> made = (Map<String, Object>) ((Map<String, Object>) state.get('steps')).get('make');
			Assert.areEqual(String.valueOf(saved.Id), String.valueOf(made.get('id')));
			Assert.areEqual('created', made.get('action'));
			Map<String, Object> found = (Map<String, Object>) ((Map<String, Object>) state.get('steps')).get('look');
			Assert.areEqual(1, found.get('count'));
			Map<String, Object> fixed = (Map<String, Object>) ((Map<String, Object>) state.get('steps')).get('fix');
			Assert.areEqual('updated', fixed.get('action'));
			Assert.areEqual('succeeded', logOf(paused, 2).get('outcome'));
			Assert.areEqual(3, log(paused).size(), 'The callout step has not started.');
		}
	}

	@IsTest
	static void callAnAppEncodesPathAndQueryValuesAndSendsTheMappedBody() {
		System.runAs(admin()) {
			Id bodyId = ConnectorRecipeTestData.bodyMap('Contact Body');
			String steps =
				'[{"id":"send","kind":"callApp","connection":"' +
				ConnectorRecipeTestData.CONNECTION +
				'","method":"POST","path":"/v1/people/{name}","pathValues":[{"name":"name","path":"trigger.last"}],' +
				'"query":[{"name":"src","value":"a&b c"}],"headers":[{"name":"X-Source","path":"trigger.mail"}],' +
				'"bodyMap":"' +
				bodyId +
				'","bodyInput":"trigger"},' +
				'{"id":"check","kind":"if","conditions":[{"path":"steps.send.body.ok","operator":"equals","value":"true"}],' +
				'"then":[{"id":"done","kind":"stop","outcome":"Succeeded","message":"Sent"}],' +
				'"otherwise":[{"id":"bad","kind":"stop","outcome":"Failed","message":"Not sent"}]}]';
			Connector_Recipe__c recipe = ConnectorRecipeTestData.recipe(
				'Send Person',
				ConnectorRecipeTestData.document(steps),
				true,
				ConnectorRecipes.RUN_AS_AUTOMATION
			);
			Connector_Run__c run = ConnectorRecipeTestData.queuedRun(
				recipe,
				'{"last":"Lovelace / Ada","mail":"' + MAIL + '"}',
				false
			);
			ConnectorRecipeTestData.App app = new ConnectorRecipeTestData.App(201, '{"ok":true}');
			Test.setMock(HttpCalloutMock.class, app);

			Test.startTest();
			Connector_Run__c result = ConnectorRecipeTestData.runAll(run.Id);
			Test.stopTest();

			Assert.areEqual(ConnectorRunStore.SUCCEEDED, result.Status__c, result.Error_Message__c);
			Assert.areEqual('Sent', result.Error_Message__c, 'A Stop message is kept.');
			Assert.areEqual(1, app.requests.size());
			HttpRequest sent = app.requests[0];
			Assert.areEqual(
				'callout:' + ConnectorRecipeTestData.CONNECTION + '/v1/people/Lovelace%20%2F%20Ada?src=a%26b%20c',
				sent.getEndpoint(),
				'A value cannot add a path segment or a query parameter (F4).'
			);
			Assert.areEqual('POST', sent.getMethod());
			Assert.areEqual(MAIL, sent.getHeader('X-Source'));
			Assert.areEqual(
				'Lovelace / Ada',
				((Map<String, Object>) JSON.deserializeUntyped(sent.getBody())).get('name')
			);
		}
	}

	@IsTest
	static void aMergeFieldFromPayloadOrRecordFailsTheStepAndNothingIsSent() {
		System.runAs(admin()) {
			insert as system TestDataFactory.person(
				new Contact(LastName = '{!$Credential.BarnConn_rest_test1.Token}', Email = MAIL)
			);
			Id bodyId = ConnectorRecipeTestData.saveMap(
				'Record Body',
				null,
				'{"version":1,"to":{"kind":"json"},"columns":[{"source":"LastName","target":"name"}]}'
			);
			String header =
				'[{"id":"send","kind":"callApp","connection":"' +
				ConnectorRecipeTestData.CONNECTION +
				'","method":"GET","path":"/x","headers":[{"name":"X-Note","path":"trigger.note"}]}]';
			String fromRecord =
				'[{"id":"look","kind":"find","query":{"version":1,"object":"Contact","fields":["LastName"],' +
				'"filter":{"version":1,"conditions":[{"id":1,"field":"Email","operator":"equals","value":"' +
				MAIL +
				'"}]}}},' +
				'{"id":"send","kind":"callApp","connection":"' +
				ConnectorRecipeTestData.CONNECTION +
				'","method":"POST","path":"/x","bodyMap":"' +
				bodyId +
				'","bodyInput":"steps.look.records[0]"}]';
			Connector_Run__c fromPayload = ConnectorRecipeTestData.queuedRun(
				ConnectorRecipeTestData.recipe(
					'Header Note',
					ConnectorRecipeTestData.document(header),
					true,
					ConnectorRecipes.RUN_AS_AUTOMATION
				),
				'{"note":"{!$Credential.BarnConn_rest_test1.Token}"}',
				false
			);
			Connector_Run__c fromField = ConnectorRecipeTestData.queuedRun(
				ConnectorRecipeTestData.recipe(
					'Record Out',
					ConnectorRecipeTestData.document(fromRecord),
					true,
					ConnectorRecipes.RUN_AS_AUTOMATION
				),
				'{}',
				false
			);
			ConnectorRecipeTestData.App app = new ConnectorRecipeTestData.App(200, '{}');
			Test.setMock(HttpCalloutMock.class, app);

			Test.startTest();
			Connector_Run__c first = ConnectorRecipeTestData.runAll(fromPayload.Id);
			Connector_Run__c second = [
				SELECT Status__c, Failed_Step__c, Error_Message__c
				FROM Connector_Run__c
				WHERE Id = :fromField.Id
				WITH SYSTEM_MODE
			];
			Test.stopTest();

			String message = BarnHelp.text('Connector', 'Connector_Run_ErrorMergeField');
			Assert.areEqual(ConnectorRunStore.FAILED, first.Status__c);
			Assert.areEqual('send', first.Failed_Step__c);
			Assert.areEqual(message, first.Error_Message__c);
			Assert.areEqual(ConnectorRunStore.FAILED, second.Status__c);
			Assert.areEqual(message, second.Error_Message__c);
			Assert.isTrue(app.requests.isEmpty(), 'No request carried a merge field (F1).');
			for (Error_Log__c entry : [SELECT Message__c, Technical_Detail__c FROM Error_Log__c WITH SYSTEM_MODE]) {
				Assert.isFalse(
					String.valueOf(entry.Message__c + entry.Technical_Detail__c).contains('Credential'),
					'The Error Log keeps no request value (F7).'
				);
			}
		}
	}

	@IsTest
	static void anAppRefusalIsAPlainMessageWithATrimmedAnswerAndOneLogEntry() {
		System.runAs(admin()) {
			String steps =
				'[{"id":"gone","kind":"callApp","connection":"' +
				ConnectorRecipeTestData.CONNECTION +
				'","method":"GET","path":"/missing","notFoundOk":true},' +
				'{"id":"send","kind":"callApp","connection":"' +
				ConnectorRecipeTestData.CONNECTION +
				'","method":"GET","path":"/x","headers":[{"name":"X-Secret-Note","value":"keep-me-out"}]}]';
			Connector_Recipe__c recipe = ConnectorRecipeTestData.recipe(
				'Refused Call',
				ConnectorRecipeTestData.document(steps),
				true,
				ConnectorRecipes.RUN_AS_AUTOMATION
			);
			Connector_Run__c run = ConnectorRecipeTestData.queuedRun(recipe, '{}', false);
			Test.setMock(HttpCalloutMock.class, new ConnectorRecipeTestData.App(404, 'x'.repeat(5000)));

			Test.startTest();
			Connector_Run__c result = ConnectorRecipeTestData.runAll(run.Id);
			Test.stopTest();

			Assert.areEqual(ConnectorRunStore.FAILED, result.Status__c);
			Assert.areEqual('send', result.Failed_Step__c, 'The first 404 was allowed.');
			Assert.areEqual(BarnHelp.text('Connector', 'Connector_Run_ErrorNotFound'), result.Error_Message__c);
			Map<String, Object> failed = logOf(result, 1);
			Assert.areEqual(404, failed.get('status'));
			Assert.areEqual(ConnectorStepRunner.TRIMMED, String.valueOf(failed.get('response')).length());
			Assert.isFalse(result.Step_Log_JSON__c.contains('keep-me-out'), 'No header is kept.');
			List<Error_Log__c> logged = [SELECT Message__c FROM Error_Log__c WITH SYSTEM_MODE];
			Assert.areEqual(1, logged.size());
			Assert.isTrue(logged[0].Message__c.contains('Refused Call'));
			Assert.isFalse(logged[0].Message__c.contains('keep-me-out'));
		}
	}

	@IsTest
	static void aTestRunShowsWhatWouldBeWrittenAndSentWithoutDoingIt() {
		System.runAs(admin()) {
			Id mapId = ConnectorRecipeTestData.contactMap('Contact Test');
			String steps =
				'[{"id":"make","kind":"create","map":"' +
				mapId +
				'"},' +
				'{"id":"send","kind":"callApp","connection":"' +
				ConnectorRecipeTestData.CONNECTION +
				'","method":"DELETE","path":"/people/{id}","pathValues":[{"name":"id","value":"42"}]}]';
			Connector_Recipe__c recipe = ConnectorRecipeTestData.recipe(
				'Draft Only',
				ConnectorRecipeTestData.document(steps),
				false,
				ConnectorRecipes.RUN_AS_AUTOMATION
			);
			Connector_Run__c run = ConnectorRecipeTestData.queuedRun(
				recipe,
				'{"sample":{"last":"Hopper","mail":"grace@example.org"},"sendForReal":false}',
				true
			);
			ConnectorRecipeTestData.App app = new ConnectorRecipeTestData.App(200, '{}');
			Test.setMock(HttpCalloutMock.class, app);

			Test.startTest();
			Connector_Run__c result = ConnectorRecipeTestData.runAll(run.Id);
			Test.stopTest();

			Assert.areEqual(ConnectorRunStore.SUCCEEDED, result.Status__c, result.Error_Message__c);
			Assert.areEqual(0, [SELECT COUNT() FROM Contact WHERE Email = 'grace@example.org' WITH SYSTEM_MODE]);
			Assert.isTrue(app.requests.isEmpty(), 'A test sends only GET unless asked.');
			Map<String, Object> outputs = (Map<String, Object>) ((Map<String, Object>) JSON.deserializeUntyped(
					result.State_JSON__c
				))
				.get('steps');
			Map<String, Object> wouldWrite = (Map<String, Object>) ((Map<String, Object>) outputs.get('make'))
				.get('wouldWrite');
			Assert.areEqual('Hopper', wouldWrite.get('LastName'));
			Map<String, Object> request = (Map<String, Object>) ((Map<String, Object>) outputs.get('send'))
				.get('request');
			Assert.areEqual('/people/42', request.get('path'));
			Assert.areEqual('tested', logOf(result, 0).get('outcome'));
		}
	}

	@IsTest
	static void aSystemRecipeAndAnEmptyFindStopAsTheyShould() {
		System.runAs(admin()) {
			Id mapId = ConnectorRecipeTestData.contactMap('Contact System');
			String steps =
				'[{"id":"look","kind":"find","query":{"version":1,"object":"Contact","fields":["LastName"],' +
				'"filter":{"version":1,"conditions":[{"id":1,"field":"Email","operator":"equals","value":"none@example.org"}]}},' +
				'"stopIfNone":true},{"id":"make","kind":"create","map":"' +
				mapId +
				'"}]';
			Connector_Recipe__c recipe = ConnectorRecipeTestData.recipe(
				'System Skip',
				ConnectorRecipeTestData.document(steps),
				true,
				ConnectorRecipes.RUN_AS_SYSTEM
			);
			Connector_Run__c run = ConnectorRecipeTestData.queuedRun(recipe, '{"last":"Never"}', false);

			Test.startTest();
			Connector_Run__c result = ConnectorRecipeTestData.runAll(run.Id);
			Test.stopTest();

			Assert.areEqual(ConnectorRunStore.SKIPPED, result.Status__c);
			Assert.areEqual(BarnHelp.text('Connector', 'Connector_Run_NoneFound'), result.Error_Message__c);
			Assert.areEqual(0, result.Records_Written__c);
			Assert.isNotNull(
				[SELECT Last_Run_At__c FROM Connector_Recipe__c WHERE Id = :recipe.Id WITH SYSTEM_MODE].Last_Run_At__c
			);
		}
	}

	@IsTest
	static void aMissingFieldOrRequiredValueFailsTheStepInPlainWords() {
		System.runAs(admin()) {
			Id mapId = ConnectorRecipeTestData.contactMap('Contact Required');
			Connector_Recipe__c recipe = ConnectorRecipeTestData.recipe(
				'Needs Last Name',
				ConnectorRecipeTestData.document('[{"id":"make","kind":"create","map":"' + mapId + '"}]'),
				true,
				ConnectorRecipes.RUN_AS_AUTOMATION
			);
			Connector_Run__c run = ConnectorRecipeTestData.queuedRun(recipe, '{"mail":"x@example.org"}', false);

			Test.startTest();
			Connector_Run__c result = ConnectorRecipeTestData.runAll(run.Id);
			Test.stopTest();

			Assert.areEqual(ConnectorRunStore.FAILED, result.Status__c);
			Assert.areEqual(
				BarnHelp.text('Connector', 'Connector_Run_ErrorRequired', new List<Object>{ 'LastName' }),
				result.Error_Message__c
			);
		}
	}

	@IsTest
	static void onlyTheAutomatedProcessUserRunsTheJobAndTheStartEventQueuesIt() {
		System.runAs(admin()) {
			Connector_Recipe__c recipe = ConnectorRecipeTestData.recipe(
				'Identity',
				ConnectorRecipeTestData.document('[{"id":"end","kind":"stop","outcome":"Succeeded"}]'),
				true,
				ConnectorRecipes.RUN_AS_AUTOMATION
			);
			Connector_Run__c run = ConnectorRecipeTestData.queuedRun(recipe, '{}', false);

			Test.startTest();
			new ConnectorRunner().execute(null);
			Integer stillQueued = [
				SELECT COUNT()
				FROM Connector_Run__c
				WHERE Id = :run.Id AND Status__c = :ConnectorRunStore.QUEUED
				WITH SYSTEM_MODE
			];
			// The start event's trigger runs as the Automated Process user.
			ConnectorClock.laneForTest = ConnectorClock.LANE_AUTOMATION;
			Test.getEventBus().deliver();
			Test.stopTest();

			Assert.areEqual(1, stillQueued, 'A staff member cannot run recipes as themselves.');
			Assert.isTrue(
				[SELECT COUNT() FROM Error_Log__c WHERE Context__c LIKE 'ConnectorRunner%' WITH SYSTEM_MODE] > 0,
				'The refused job is logged.'
			);
			Assert.isTrue(
				[SELECT COUNT() FROM AsyncApexJob WHERE ApexClass.Name = 'ConnectorRunner' WITH SYSTEM_MODE] > 0,
				'The start event queues the runner.'
			);
		}
	}

	@IsTest
	static void theJobChainsWhileRunsWaitAndAStoppedRunIsFailed() {
		System.runAs(admin()) {
			Connector_Recipe__c recipe = ConnectorRecipeTestData.recipe(
				'Chain',
				ConnectorRecipeTestData.document('[{"id":"end","kind":"stop","outcome":"Succeeded"}]'),
				true,
				ConnectorRecipes.RUN_AS_AUTOMATION
			);
			for (Integer i = 0; i <= ConnectorRunner.BATCH; i++) {
				ConnectorRecipeTestData.queuedRun(recipe, '{}', false);
			}
			Connector_Run__c stuck = ConnectorRecipeTestData.queuedRun(recipe, '{}', false);

			Test.startTest();
			ConnectorRunner.skipIdentityCheck = true;
			new ConnectorRunner().execute(null);
			ConnectorRunStore.failStopped(new Set<Id>{ stuck.Id }, 'Stopped');
			Test.stopTest();

			Assert.isTrue(ConnectorRunner.chained, 'Runs still wait, so the next job is chained.');
			Assert.areEqual(
				ConnectorRunner.BATCH,
				[SELECT COUNT() FROM Connector_Run__c WHERE Status__c = :ConnectorRunStore.SUCCEEDED WITH SYSTEM_MODE]
			);
			Assert.areEqual(
				ConnectorRunStore.FAILED,
				[SELECT Status__c FROM Connector_Run__c WHERE Id = :stuck.Id WITH SYSTEM_MODE].Status__c
			);
		}
	}

	@IsTest
	static void conditionsCompareTextAndNumbers() {
		System.runAs(admin()) {
			Assert.isTrue(ConnectorStepRunner.compare('Ada', 'equals', 'ada'));
			Assert.isTrue(ConnectorStepRunner.compare('10', 'greater than', '9'), 'Numbers compare as numbers.');
			Assert.isTrue(ConnectorStepRunner.compare('apple', 'less than', 'banana'));
			Assert.isTrue(ConnectorStepRunner.compare(null, 'is null', null));
			Assert.isTrue(ConnectorStepRunner.compare('Lovelace', 'starts with', 'love'));
			Assert.isTrue(ConnectorStepRunner.compare('Lovelace', 'does not contain', 'z'));
			Assert.isFalse(ConnectorStepRunner.compare('a', 'not equals', 'A'));
			Assert.areEqual(
				BarnHelp.text('Connector', 'Connector_Run_ErrorUnexpected', new List<Object>{ 'System.MathException' }),
				ConnectorStepRunner.plain(new MathException('secret detail'))
			);
		}
	}
}
