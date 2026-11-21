/**
 * Flows use BarnCRM Connector (CN-06; canonical model R-CR4, R-MAP1 to R-MAP3): Run a BarnCRM
 * Connector Recipe queues a run that executes as the recipe's identity, and Apply a Saved Map
 * builds and saves a record as the person running the flow.
 */
@IsTest(testFor='ApexClass:ConnectorRunRecipeAction, ApexClass:ConnectorApplyMapAction')
private class ConnectorFlowActionsTest {
	private static final String MAIL = 'flow.person@example.org';

	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(ConnectorConnections.ADMIN_SET);
	}

	private static User admin() {
		return TestUsers.adminWith(ConnectorConnections.ADMIN_SET);
	}

	@IsTest
	static void aFlowQueuesARunOfAnActiveRecipeOnly() {
		System.runAs(admin()) {
			ConnectorRecipeTestData.recipe(
				'From Flow',
				ConnectorRecipeTestData.document('[{"id":"end","kind":"stop","outcome":"Succeeded"}]'),
				true,
				ConnectorRecipes.RUN_AS_AUTOMATION
			);
			ConnectorRecipeTestData.recipe(
				'Still Draft',
				ConnectorRecipeTestData.document('[{"id":"end","kind":"stop","outcome":"Succeeded"}]'),
				false,
				ConnectorRecipes.RUN_AS_AUTOMATION
			);
			List<ConnectorRunRecipeAction.Request> requests = new List<ConnectorRunRecipeAction.Request>();
			for (String name : new List<String>{ 'From Flow', 'Still Draft', 'From Flow' }) {
				ConnectorRunRecipeAction.Request request = new ConnectorRunRecipeAction.Request();
				request.recipeName = name;
				request.recordId = UserInfo.getUserId();
				request.dataJson = '{"amount":5}';
				requests.add(request);
			}
			requests[2].dataJson = 'not json';

			Test.startTest();
			List<ConnectorRunRecipeAction.Result> results = ConnectorRunRecipeAction.run(requests);
			Test.stopTest();

			Assert.isTrue(results[0].queued);
			Connector_Run__c run = [
				SELECT Started_By__c, Ran_As__c, Input_JSON__c
				FROM Connector_Run__c
				WHERE Id = :results[0].runId
				WITH SYSTEM_MODE
			];
			Assert.areEqual('Flow', run.Started_By__c);
			Assert.areEqual(ConnectorRecipes.RUN_AS_AUTOMATION, run.Ran_As__c);
			Map<String, Object> input = (Map<String, Object>) JSON.deserializeUntyped(run.Input_JSON__c);
			Assert.areEqual(String.valueOf(UserInfo.getUserId()), String.valueOf(input.get('recordId')));
			Assert.areEqual(5, ((Map<String, Object>) input.get('data')).get('amount'));
			Assert.isFalse(results[1].queued);
			Assert.areEqual(
				BarnHelp.text('Connector', 'Connector_Flow_NoRecipe', new List<Object>{ 'Still Draft' }),
				results[1].message
			);
			Assert.isFalse(results[2].queued);
			Assert.areEqual(BarnHelp.text('Connector', 'Connector_Run_ErrorInput'), results[2].message);
		}
	}

	@IsTest
	static void aSavedMapCreatesThenFindsAndUpdatesAsThePerson() {
		System.runAs(admin()) {
			ConnectorRecipeTestData.contactMap('Flow Contact');
			ConnectorRecipeTestData.bodyMap('Flow Body');
			List<ConnectorApplyMapAction.Request> requests = new List<ConnectorApplyMapAction.Request>();
			for (String name : new List<String>{ 'Flow Contact', 'Flow Contact', 'Flow Body', 'No Such Map' }) {
				ConnectorApplyMapAction.Request request = new ConnectorApplyMapAction.Request();
				request.mapName = name;
				request.dataJson = '{"last":"Flowers","mail":"' + MAIL + '"}';
				requests.add(request);
			}

			Test.startTest();
			List<ConnectorApplyMapAction.Result> results = ConnectorApplyMapAction.apply(requests);
			Test.stopTest();

			Assert.areEqual('created', results[0].action, 'Message: ' + results[0].message);
			Assert.areEqual('updated', results[1].action, 'The map matches by email.');
			Assert.areEqual(results[0].recordId, results[1].recordId);
			Assert.areEqual(1, [SELECT COUNT() FROM Contact WHERE Email = :MAIL WITH SYSTEM_MODE]);
			Assert.areEqual(BarnHelp.text('Connector', 'Connector_Flow_NotRecordMap'), results[2].message);
			Assert.areEqual(BarnHelp.text('Connector', 'Connector_Run_ErrorMapGone'), results[3].message);
		}
	}

	@IsTest
	static void aSavedMapReadsASourceRecordAndUpdatesTheRecordGiven() {
		System.runAs(admin()) {
			Contact source = TestDataFactory.person(new Contact(LastName = 'Source', Email = 'source@example.org'));
			Contact target = TestDataFactory.person(new Contact(LastName = 'Target'));
			insert as system new List<Contact>{ source, target };
			ConnectorRecipeTestData.saveMap(
				'Copy Name',
				'Contact',
				'{"version":1,"from":{"kind":"record","object":"Contact"},"to":{"kind":"record","object":"Contact"},' +
				'"columns":[{"source":"LastName","target":"LastName"}]}'
			);
			ConnectorApplyMapAction.Request request = new ConnectorApplyMapAction.Request();
			request.mapName = 'Copy Name';
			request.sourceRecordId = source.Id;
			request.targetRecordId = target.Id;

			Test.startTest();
			List<ConnectorApplyMapAction.Result> results = ConnectorApplyMapAction.apply(
				new List<ConnectorApplyMapAction.Request>{ request }
			);
			Test.stopTest();

			Assert.areEqual('updated', results[0].action, 'Message: ' + results[0].message);
			Assert.areEqual(target.Id, results[0].recordId);
			Assert.areEqual('Source', [SELECT LastName FROM Contact WHERE Id = :target.Id WITH SYSTEM_MODE].LastName);
		}
	}
}
