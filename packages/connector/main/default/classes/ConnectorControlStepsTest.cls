/**
 * For Each, Wait and Change Data (CN-05; canonical model R-CR1, R-CR12). A For Each works through
 * a list, logging one line, continues after 200 items without repeating one, refuses more than
 * 1,000 and cannot hold a Wait; a Wait makes the run Waiting without using a retry and carries on
 * when woken; Change Data builds data later steps read and writes nothing.
 */
@IsTest(testFor='ApexClass:ConnectorControlSteps, ApexClass:ConnectorStepRunner, ApexClass:ConnectorRecipeDocument')
private class ConnectorControlStepsTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(ConnectorConnections.ADMIN_SET);
	}

	private static User admin() {
		return TestUsers.adminWith(ConnectorConnections.ADMIN_SET);
	}

	private static Connector_Recipe__c active(String name, String steps) {
		return ConnectorRecipeTestData.recipe(
			name,
			ConnectorRecipeTestData.document(steps),
			true,
			ConnectorRecipes.RUN_AS_AUTOMATION
		);
	}

	private static Map<String, Object> state(Connector_Run__c run) {
		return (Map<String, Object>) JSON.deserializeUntyped(run.State_JSON__c);
	}

	private static Map<String, Object> output(Connector_Run__c run, String stepId) {
		return (Map<String, Object>) ((Map<String, Object>) state(run).get('steps')).get(stepId);
	}

	private static List<Object> log(Connector_Run__c run) {
		return (List<Object>) JSON.deserializeUntyped(run.Step_Log_JSON__c);
	}

	/** A list of `count` people as Run Now JSON. */
	private static String people(Integer count) {
		List<Object> items = new List<Object>();
		for (Integer i = 0; i < count; i++) {
			items.add(new Map<String, Object>{ 'last' => 'Person' + i, 'mail' => 'person' + i + '@example.org' });
		}
		return JSON.serialize(new Map<String, Object>{ 'people' => items });
	}

	@IsTest
	static void forEachSavesARecordForEachItemAndLogsOneLine() {
		System.runAs(admin()) {
			Id mapId = ConnectorRecipeTestData.contactMap('Person To Contact');
			Connector_Recipe__c recipe = active(
				'Each Person',
				'[{"id":"each","kind":"forEach","items":"trigger.people","do":[' +
					'{"id":"save","kind":"upsert","map":"' +
					mapId +
					'","input":"loop.item"}]}]'
			);
			Connector_Run__c run = ConnectorRecipeTestData.queuedRun(recipe, people(3), false);

			Test.startTest();
			Connector_Run__c done = ConnectorRecipeTestData.runAll(run.Id);
			Test.stopTest();

			Assert.areEqual(ConnectorRunStore.SUCCEEDED, done.Status__c, done.Error_Message__c);
			Assert.areEqual(3, done.Records_Written__c.intValue());
			Assert.areEqual(3, [SELECT COUNT() FROM Contact WHERE Email LIKE 'person%@example.org' WITH SYSTEM_MODE]);
			Assert.areEqual(3, output(done, 'each').get('count'));
			Assert.isNull(output(done, 'save'), 'A step inside keeps its result for the current item only.');
			Assert.areEqual(1, log(done).size(), 'Steps inside log only failures.');
		}
	}

	@IsTest
	static void forEachContinuesAfter200ItemsWithoutRepeatingOne() {
		System.runAs(admin()) {
			Connector_Recipe__c recipe = active(
				'Many Items',
				'[{"id":"each","kind":"forEach","items":"trigger.people","do":[' +
					'{"id":"check","kind":"if","conditions":[{"path":"loop.item.last","operator":"is not null"}],' +
					'"then":[],"otherwise":[{"id":"odd","kind":"stop","outcome":"Failed","message":"No name"}]}]}]'
			);
			Connector_Run__c run = ConnectorRecipeTestData.queuedRun(recipe, people(250), false);

			Test.startTest();
			Connector_Run__c paused = ConnectorRecipeTestData.runAll(run.Id);
			Connector_Run__c done = ConnectorRecipeTestData.runAll(run.Id);
			Test.stopTest();

			Assert.areEqual(ConnectorRunStore.QUEUED, paused.Status__c, 'Continues in a new transaction.');
			Assert.areEqual(ConnectorRunStore.SUCCEEDED, done.Status__c, done.Error_Message__c);
			Assert.areEqual(250, output(done, 'each').get('count'));
		}
	}

	@IsTest
	static void forEachRefusesMoreThan1000ItemsAndATestRunsTheFirstItemOnly() {
		System.runAs(admin()) {
			Id mapId = ConnectorRecipeTestData.contactMap('Person To Contact');
			String steps =
				'[{"id":"each","kind":"forEach","items":"trigger.people","do":[' +
				'{"id":"save","kind":"upsert","map":"' +
				mapId +
				'","input":"loop.item"}]}]';
			Connector_Recipe__c recipe = active('Too Many', steps);
			Connector_Run__c run = ConnectorRecipeTestData.queuedRun(recipe, people(1001), false);
			Connector_Run__c tested = ConnectorRecipeTestData.queuedRun(
				recipe,
				JSON.serialize(new Map<String, Object>{ 'sample' => JSON.deserializeUntyped(people(3)) }),
				true
			);

			Test.startTest();
			Connector_Run__c refused = ConnectorRecipeTestData.runAll(run.Id);
			Connector_Run__c tried = ConnectorRecipeTestData.runAll(tested.Id);
			Test.stopTest();

			Assert.areEqual(ConnectorRunStore.FAILED, refused.Status__c);
			Assert.areEqual('each', refused.Failed_Step__c);
			Assert.areEqual(
				BarnHelp.text('Connector', 'Connector_Run_ErrorTooManyItems', new List<Object>{ 1001, 1000 }),
				refused.Error_Message__c
			);
			Assert.areEqual(ConnectorRunStore.SUCCEEDED, tried.Status__c, tried.Error_Message__c);
			Assert.areEqual(1, output(tried, 'each').get('count'), 'A test runs the first item only.');
			Assert.isNotNull(output(tried, 'save').get('wouldWrite'), 'And keeps what it would write.');
			Assert.areEqual(0, [SELECT COUNT() FROM Contact WHERE Email LIKE 'person%@example.org' WITH SYSTEM_MODE]);
		}
	}

	@IsTest
	static void waitMakesTheRunWaitWithoutARetryAndCarriesOnWhenWoken() {
		System.runAs(admin()) {
			Connector_Recipe__c recipe = active(
				'Wait An Hour',
				'[{"id":"pause","kind":"wait","amount":1,"unit":"hours"},' +
				'{"id":"end","kind":"stop","outcome":"Succeeded","message":"Done"}]'
			);
			Connector_Run__c run = ConnectorRecipeTestData.queuedRun(recipe, '{}', false);

			Test.startTest();
			Connector_Run__c waiting = ConnectorRecipeTestData.runAll(run.Id);
			Connector_Run__c stored = [
				SELECT Id, Attempt__c, Next_Attempt_At__c, State_JSON__c
				FROM Connector_Run__c
				WHERE Id = :run.Id
				WITH SYSTEM_MODE
			];
			Map<String, Object> saved = (Map<String, Object>) JSON.deserializeUntyped(stored.State_JSON__c);
			((Map<String, Object>) ((Map<String, Object>) saved.get('steps')).get('pause'))
				.put('at', Datetime.now().addMinutes(-1).getTime());
			update as system new Connector_Run__c(
				Id = run.Id,
				Status__c = ConnectorRunStore.QUEUED,
				State_JSON__c = JSON.serialize(saved)
			);
			Connector_Run__c done = ConnectorRecipeTestData.runAll(run.Id);
			Test.stopTest();

			Assert.areEqual(ConnectorRunStore.WAITING, waiting.Status__c);
			Assert.isTrue(stored.Next_Attempt_At__c > Datetime.now().addMinutes(55), 'About an hour on.');
			Assert.isTrue(stored.Next_Attempt_At__c <= Datetime.now().addMinutes(61));
			Assert.isTrue(stored.Attempt__c == null || stored.Attempt__c == 0, 'A wait uses no retry.');
			Assert.areEqual(ConnectorRunStore.SUCCEEDED, done.Status__c, done.Error_Message__c);
		}
	}

	@IsTest
	static void changeDataBuildsDataLaterStepsReadAndATestDoesNotWait() {
		System.runAs(admin()) {
			Id bodyId = ConnectorRecipeTestData.bodyMap('Name Only');
			Connector_Recipe__c recipe = active(
				'Reshape',
				'[{"id":"reshape","kind":"transform","map":"' +
					bodyId +
					'","input":"trigger"},' +
					'{"id":"pause","kind":"wait","amount":2,"unit":"days"},' +
					'{"id":"check","kind":"if","conditions":[{"path":"steps.reshape.name","operator":"equals","value":"Lovelace"}],' +
					'"then":[],"otherwise":[{"id":"bad","kind":"stop","outcome":"Failed","message":"Not built"}]}]'
			);
			Connector_Run__c run = ConnectorRecipeTestData.queuedRun(
				recipe,
				JSON.serialize(new Map<String, Object>{ 'sample' => new Map<String, Object>{ 'last' => 'Lovelace' } }),
				true
			);

			Test.startTest();
			Connector_Run__c done = ConnectorRecipeTestData.runAll(run.Id);
			Test.stopTest();

			Assert.areEqual(ConnectorRunStore.SUCCEEDED, done.Status__c, done.Error_Message__c);
			Assert.areEqual('Lovelace', output(done, 'reshape').get('name'));
			Assert.areEqual(0, done.Records_Written__c.intValue(), 'Change Data writes nothing.');
		}
	}

	@IsTest
	static void savesRefuseAWaitInALoopAWaitOutOfRangeAndABlankLeftByAnImport() {
		System.runAs(admin()) {
			Test.startTest();
			List<String> inLoop = ConnectorRecipeDocument.problems(
				ConnectorRecipeDocument.parse(
					ConnectorRecipeTestData.document(
						'[{"id":"each","kind":"forEach","items":"trigger.people","do":[' +
						'{"id":"pause","kind":"wait","amount":1,"unit":"hours"}]}]'
					)
				)
			);
			List<String> tooShort = ConnectorRecipeDocument.problems(
				ConnectorRecipeDocument.parse(
					ConnectorRecipeTestData.document('[{"id":"pause","kind":"wait","amount":2,"unit":"minutes"}]')
				)
			);
			List<String> tooLong = ConnectorRecipeDocument.problems(
				ConnectorRecipeDocument.parse(
					ConnectorRecipeTestData.document('[{"id":"pause","kind":"wait","amount":31,"unit":"days"}]')
				)
			);
			List<String> blank = ConnectorRecipeDocument.problems(
				ConnectorRecipeDocument.parse(
					ConnectorRecipeTestData.document(
						'[{"id":"pause","kind":"wait","amount":1,"unit":"days","fill":["headers"]}]'
					)
				)
			);
			List<String> loopPath = ConnectorRecipeDocument.problems(
				ConnectorRecipeDocument.parse(
					ConnectorRecipeTestData.document(
						'[{"id":"each","kind":"forEach","items":"elsewhere.list","do":[]}]'
					)
				)
			);
			Test.stopTest();

			List<Object> at = new List<Object>{ 'pause' };
			Assert.isTrue(inLoop.contains(BarnHelp.text('Connector', 'Connector_Recipe_ErrorInLoop', at)), inLoop + '');
			Assert.isTrue(tooShort.contains(BarnHelp.text('Connector', 'Connector_Recipe_ErrorWait', at)));
			Assert.isTrue(tooLong.contains(BarnHelp.text('Connector', 'Connector_Recipe_ErrorWait', at)));
			Assert.areEqual(new List<String>{ BarnHelp.text('Connector', 'Connector_Recipe_ErrorFill', at) }, blank);
			Assert.isTrue(
				loopPath.contains(BarnHelp.text('Connector', 'Connector_Recipe_ErrorItems', new List<Object>{ 'each' }))
			);
		}
	}
}
