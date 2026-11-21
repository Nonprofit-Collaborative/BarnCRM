/**
 * Dana, the Connector admin, builds, tests, publishes and runs recipes on Super Connector, and
 * Sam, who holds only BarnCRM Connector Viewer, sees them and their runs (CN-02; canonical model
 * R-CR1 to R-CR5, R-RUN4, R-CN8). Publishing is Dana's alone, System needs her confirmation and
 * records who chose it, and a BarnCRM Automation recipe is refused when its identity could not
 * write what its maps write.
 */
@IsTest(testFor='ApexClass:ConnectorRecipesController, ApexClass:ConnectorRecipes, ApexClass:ConnectorIdentity')
private class ConnectorRecipesControllerTest {
	private static final String VIEWER_SET = 'Connector_Viewer';

	@TestSetup
	static void createTestUsers() {
		TestUsers.adminWith(ConnectorConnections.ADMIN_SET);
		TestUsers.adminWith(VIEWER_SET);
	}

	private static User admin() {
		return TestUsers.adminWith(ConnectorConnections.ADMIN_SET);
	}

	private static String message(Exception refused) {
		return refused.getMessage();
	}

	private static String callDocument() {
		return ConnectorRecipeTestData.document(
			'[{"id":"look","kind":"find","query":{"version":1,"object":"Contact","fields":["LastName"]}},' +
				'{"id":"send","kind":"callApp","connection":"' +
				ConnectorRecipeTestData.CONNECTION +
				'","method":"GET","path":"/ping"}]'
		);
	}

	@IsTest
	static void danaSavesPublishesAndRunsARecipe() {
		System.runAs(admin()) {
			ConnectorRecipeTestData.readyConnection();

			Test.startTest();
			ConnectorRecipes.Recipe saved = ConnectorRecipesController.saveDraft(
				null,
				'Ping The App',
				'Checks the app answers',
				callDocument(),
				null
			);
			ConnectorRecipes.Recipe published = ConnectorRecipesController.publish(saved.id);
			ConnectorRecipes.Run run = ConnectorRecipesController.runNow(published.id, '{"note":"hello"}');
			ConnectorRecipes.RecipesPage page = ConnectorRecipesController.getRecipes();
			List<ConnectorRecipes.Run> runs = ConnectorRecipesController.getRuns(published.id);
			Test.stopTest();

			Assert.areEqual(ConnectorRecipes.DRAFT, saved.status);
			Assert.areEqual(ConnectorRecipes.RUN_AS_AUTOMATION, saved.runAs, 'BarnCRM Automation is the default.');
			Assert.isTrue(saved.unpublished);
			Assert.areEqual(ConnectorRunStore.ACTIVE, published.status);
			Assert.areEqual(1, published.version);
			Assert.isFalse(published.unpublished);
			Assert.areEqual(ConnectorRunStore.QUEUED, run.status);
			Assert.areEqual('Manual', run.startedBy);
			Assert.areEqual(1, runs.size());
			Assert.isTrue(page.canManage);
			Assert.areEqual(1, page.recipes.size());
			Assert.areEqual(ConnectorRecipeTestData.CONNECTION, page.connections[0].value);
		}
	}

	@IsTest
	static void publishRefusesAnAppThatIsNotReadyAndADraftCannotRun() {
		System.runAs(admin()) {
			ConnectorRecipeTestData.noConnections();
			ConnectorRecipes.Recipe saved = ConnectorRecipesController.saveDraft(
				null,
				'Not Ready',
				null,
				callDocument(),
				null
			);

			Test.startTest();
			String notReady;
			try {
				ConnectorRecipesController.publish(saved.id);
			} catch (AuraHandledException refused) {
				notReady = message(refused);
			}
			String draftRun;
			try {
				ConnectorRecipesController.runNow(saved.id, null);
			} catch (AuraHandledException refused) {
				draftRun = message(refused);
			}
			String inUse;
			ConnectorConnections.credentialPermissionOverride = true;
			ConnectorRecipeTestData.readyConnection();
			try {
				ConnectorConnectionsController.deleteConnection(ConnectorRecipeTestData.CONNECTION);
			} catch (AuraHandledException refused) {
				inUse = message(refused);
			}
			Test.stopTest();

			Assert.areEqual(
				BarnHelp.text(
					'Connector',
					'Connector_Publish_Connection',
					new List<Object>{ ConnectorRecipeTestData.CONNECTION }
				),
				notReady
			);
			Assert.areEqual(BarnHelp.text('Connector', 'Connector_Run_ErrorNotActive'), draftRun);
			Assert.areEqual(
				BarnHelp.text('Connector', 'Connector_Error_InUse'),
				inUse,
				'A connection a recipe names cannot be deleted (R-CN8).'
			);
		}
	}

	@IsTest
	static void automationIsCheckedAgainstItsIdentityAndSystemNeedsAConfirmation() {
		System.runAs(admin()) {
			ConnectorRecipeTestData.noConnections();
			Id mapId = ConnectorRecipeTestData.contactMap('Contact For Publish');
			ConnectorIdentity.automatedProcessOverride = '005000000000000';
			ConnectorRecipes.Recipe saved = ConnectorRecipesController.saveDraft(
				null,
				'Make Contacts',
				null,
				ConnectorRecipeTestData.document('[{"id":"make","kind":"upsert","map":"' + mapId + '"}]'),
				UserInfo.getUserId()
			);

			Test.startTest();
			String noAccess;
			try {
				ConnectorRecipesController.publish(saved.id);
			} catch (AuraHandledException refused) {
				noAccess = message(refused);
			}
			String unconfirmed;
			try {
				ConnectorRecipesController.setRunAs(saved.id, ConnectorRecipes.RUN_AS_SYSTEM, false);
			} catch (AuraHandledException refused) {
				unconfirmed = message(refused);
			}
			String integrationUser;
			try {
				ConnectorRecipesController.setRunAs(saved.id, ConnectorRecipes.RUN_AS_USER, true);
			} catch (AuraHandledException refused) {
				integrationUser = message(refused);
			}
			ConnectorRecipes.Recipe chosen = ConnectorRecipesController.setRunAs(
				saved.id,
				ConnectorRecipes.RUN_AS_SYSTEM,
				true
			);
			ConnectorRecipes.Recipe published = ConnectorRecipesController.publish(saved.id);
			List<HealthCheckService.Finding> findings = ConnectorHealthCheckExtension.recipeFindings();
			Test.stopTest();

			Assert.areEqual(
				BarnHelp.text('Connector', 'Connector_Publish_ObjectAccess', new List<Object>{ 'Contact' }),
				noAccess,
				'Map targets are checked against the identity at Publish.'
			);
			Assert.areEqual(BarnHelp.text('Connector', 'Connector_RunAs_ErrorConfirm'), unconfirmed);
			Assert.areEqual(
				BarnHelp.text('Connector', 'Connector_RunAs_ErrorNoUser'),
				integrationUser,
				'The Integration User needs an active integration user chosen on Recipe Clock first.'
			);
			Assert.areEqual(ConnectorRecipes.RUN_AS_SYSTEM, chosen.runAs);
			Assert.areEqual(UserInfo.getName(), chosen.runAsChosenBy, 'Who chose System is recorded.');
			Assert.isNotNull(chosen.runAsChosenAt);
			Assert.areEqual(ConnectorRunStore.ACTIVE, published.status);
			Assert.areEqual(1, findings.size(), 'Health Check lists System recipes.');
			Assert.areEqual('connector_system_recipes', findings[0].getKey());
			Assert.isTrue(findings[0].getDetail().contains('Make Contacts'));
		}
	}

	@IsTest
	static void savesAreCheckedAndAMergeFieldIsRefused() {
		System.runAs(admin()) {
			ConnectorRecipesController.saveDraft(null, 'Taken', null, callDocument(), null);
			List<String> refusals = new List<String>();

			Test.startTest();
			for (
				List<String> attempt : new List<List<String>>{
					new List<String>{ 'Taken', null, callDocument(), null },
					new List<String>{ 'Merge', '{!$Api.Session_ID}', callDocument(), null },
					new List<String>{ 'Owner', null, callDocument(), 'not-an-id' },
					new List<String>{ 'Empty', null, ConnectorRecipeTestData.document('[]'), null }
				}
			) {
				try {
					ConnectorRecipesController.saveDraft(null, attempt[0], attempt[1], attempt[2], attempt[3]);
					refusals.add(null);
				} catch (AuraHandledException refused) {
					refusals.add(message(refused));
				}
			}
			Test.stopTest();

			Assert.areEqual(
				new List<String>{
					BarnHelp.text('Connector', 'Connector_Recipe_ErrorNameTaken'),
					BarnHelp.text('Connector', 'Connector_Recipe_ErrorMergeField'),
					BarnHelp.text('Connector', 'Connector_Recipe_ErrorOwner'),
					BarnHelp.text('Connector', 'Connector_Recipe_ErrorNoSteps')
				},
				refusals
			);
		}
	}

	@IsTest
	static void aTestRunsTheDraftAndAFailedRunIsRetried() {
		System.runAs(admin()) {
			Connector_Recipe__c recipe = ConnectorRecipeTestData.recipe(
				'Retry Me',
				ConnectorRecipeTestData.document('[{"id":"end","kind":"stop","outcome":"Failed","message":"No"}]'),
				true,
				ConnectorRecipes.RUN_AS_AUTOMATION
			);
			Connector_Run__c failed = ConnectorRecipeTestData.queuedRun(recipe, '{}', false);
			ConnectorRecipeTestData.runAll(failed.Id);

			Test.startTest();
			ConnectorRecipes.Run tested = ConnectorRecipesController.testRecipe(recipe.Id, '{"a":1}', null, false);
			String badId;
			try {
				ConnectorRecipesController.testRecipe(recipe.Id, null, 'nope', false);
			} catch (AuraHandledException refused) {
				badId = message(refused);
			}
			ConnectorRecipes.Run opened = ConnectorRecipesController.getRun(failed.Id);
			ConnectorRecipes.Run retried = ConnectorRecipesController.retryRun(failed.Id);
			String twice;
			try {
				ConnectorRecipesController.retryRun(failed.Id);
			} catch (AuraHandledException refused) {
				twice = message(refused);
			}
			Test.stopTest();

			Assert.isTrue(tested.isTest);
			Assert.areEqual('Test', tested.startedBy);
			Assert.areEqual(BarnHelp.text('Connector', 'Connector_Test_ErrorRecordId'), badId);
			Assert.areEqual(ConnectorRunStore.FAILED, opened.status);
			Assert.areEqual('No', opened.errorMessage);
			Assert.isNotNull(opened.stepLogJson);
			Assert.areEqual(ConnectorRunStore.QUEUED, retried.status);
			Assert.areEqual(1, retried.attempt);
			Assert.areEqual(BarnHelp.text('Connector', 'Connector_Run_ErrorNotFailed'), twice);
		}
	}

	@IsTest
	static void recipeAccessAssignsThePickedSetsAndTheConnectionsSet() {
		User sam = TestUsers.adminWith(VIEWER_SET);
		System.runAs(admin()) {
			ConnectorIdentity.automatedProcessOverride = sam.Id;
			ConnectorIdentity.Access before = ConnectorRecipesController.getRecipeAccess();
			String coreAdmin;
			for (ConnectorIdentity.Choice choice : before.choices) {
				if (choice.name == 'BarnCRM_Admin') {
					coreAdmin = choice.id;
				}
			}

			Test.startTest();
			String unknown;
			try {
				ConnectorRecipesController.saveRecipeAccess(new List<String>{ UserInfo.getUserId() });
			} catch (AuraHandledException refused) {
				unknown = message(refused);
			}
			ConnectorIdentity.Access after = ConnectorRecipesController.saveRecipeAccess(new List<String>{ coreAdmin });
			Test.stopTest();

			Assert.isTrue(before.ready);
			Assert.isNotNull(coreAdmin, 'BarnCRM Admin is offered.');
			for (ConnectorIdentity.Choice choice : before.choices) {
				Assert.areNotEqual(ConnectorConnections.ADMIN_SET, choice.name, 'Connector Admin is never offered.');
			}
			Assert.areEqual(BarnHelp.text('Connector', 'Connector_Access_Unknown'), unknown);
			Assert.isTrue(after.saved);
			Assert.areEqual(
				1,
				[
					SELECT COUNT()
					FROM PermissionSetAssignment
					WHERE AssigneeId = :sam.Id AND PermissionSet.Name = :ConnectorConnections.ACCESS_SET
					WITH SYSTEM_MODE
				],
				'Recipes may use the connections (F12).'
			);
		}
	}

	@IsTest
	static void samSeesRecipesButCannotChangeThem() {
		System.runAs(TestUsers.standardUserWith('Sam', new List<String>{ VIEWER_SET })) {
			Test.startTest();
			ConnectorRecipes.RecipesPage page = ConnectorRecipesController.getRecipes();
			List<ConnectorRecipes.Run> runs = ConnectorRecipes.runs(null, null);
			String refused;
			try {
				ConnectorRecipesController.saveDraft(null, 'Mine', null, callDocument(), null);
			} catch (AuraHandledException e) {
				refused = message(e);
			}
			Test.stopTest();

			Assert.isFalse(page.canManage);
			Assert.isTrue(runs.isEmpty(), 'Sam may read Run History.');
			Assert.isTrue(page.connections.isEmpty(), 'Only an admin sees connections and maps.');
			Assert.areEqual(BarnHelp.text('Connector', 'Connector_Error_NoManage'), refused);
		}
	}
}
