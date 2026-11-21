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
	private static final String STOP_STEPS = '[{"id":"end","kind":"stop","outcome":"Succeeded"}]';

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

	/** A well-formed Id no recipe or run holds. */
	private static Id gone() {
		return Id.valueOf(
			Connector_Recipe__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getKeyPrefix() + '000000000001'
		);
	}

	/** What the controller says when the running user calls the named action, or null when it answers. */
	private static String refusal(String action) {
		try {
			switch on action {
				when 'rollBack' {
					ConnectorRecipesController.rollBack(gone());
				}
				when 'discardDraft' {
					ConnectorRecipesController.discardDraft(gone());
				}
				when 'exportRecipe' {
					ConnectorRecipesController.exportRecipe(gone());
				}
				when 'importFile' {
					ConnectorRecipesController.importFile('{}');
				}
				when 'deleteRecipe' {
					ConnectorRecipesController.deleteRecipe(gone());
				}
				when 'pauseRecipe' {
					ConnectorRecipesController.pauseRecipe(gone());
				}
				when 'resumeRecipe' {
					ConnectorRecipesController.resumeRecipe(gone());
				}
				when 'retryAllFailed' {
					ConnectorRecipesController.retryAllFailed(gone());
				}
				when 'getRecipeAccess' {
					ConnectorRecipesController.getRecipeAccess();
				}
				when 'saveRecipeAccess' {
					ConnectorRecipesController.saveRecipeAccess(new List<String>());
				}
				when 'getClock' {
					ConnectorRecipesController.getClock();
				}
				when 'setRecipesPaused' {
					ConnectorRecipesController.setRecipesPaused(true);
				}
				when 'restartClock' {
					ConnectorRecipesController.restartClock();
				}
				when 'getIntegrationUser' {
					ConnectorRecipesController.getIntegrationUser();
				}
				when 'chooseIntegrationUser' {
					ConnectorRecipesController.chooseIntegrationUser(null);
				}
				when 'getRuns' {
					ConnectorRecipesController.getRuns(gone());
				}
				when 'getRun' {
					ConnectorRecipesController.getRun(gone());
				}
				when 'getRecipes' {
					ConnectorRecipesController.getRecipes();
				}
				when else {
					Assert.fail('Unknown action ' + action);
				}
			}
		} catch (AuraHandledException refused) {
			return message(refused);
		}
		return null;
	}

	@IsTest
	static void samIsRefusedEveryChangeAndEveryAdminCardInWords() {
		List<String> changes = new List<String>{
			'rollBack',
			'discardDraft',
			'exportRecipe',
			'importFile',
			'deleteRecipe',
			'pauseRecipe',
			'resumeRecipe',
			'retryAllFailed',
			'getRecipeAccess',
			'saveRecipeAccess',
			'getClock',
			'setRecipesPaused',
			'restartClock',
			'getIntegrationUser',
			'chooseIntegrationUser'
		};
		System.runAs(TestUsers.standardUserWith('Sam', new List<String>{ VIEWER_SET })) {
			Test.startTest();
			Map<String, String> refused = new Map<String, String>();
			for (String action : changes) {
				refused.put(action, refusal(action));
			}
			String runsOfGone = refusal('getRuns');
			Test.stopTest();

			for (String action : changes) {
				Assert.areEqual(
					BarnHelp.text('Connector', 'Connector_Error_NoManage'),
					refused.get(action),
					action + ' needs Manage BarnCRM Connector.'
				);
			}
			Assert.isNull(runsOfGone, 'A viewer reads Run History, here of a recipe with none.');
		}
	}

	@IsTest
	static void aUserWithNoConnectorAccessIsToldSoWhereverRecipesAreRead() {
		System.runAs(TestUsers.standardUser('Nobody')) {
			Test.startTest();
			String recipes = refusal('getRecipes');
			String runs = refusal('getRuns');
			String run = refusal('getRun');
			Test.stopTest();

			String expected = BarnHelp.text('Connector', 'Connector_Error_NoView');
			Assert.areEqual(expected, recipes);
			Assert.areEqual(expected, runs);
			Assert.areEqual(expected, run);
		}
	}

	@IsTest
	static void danaIsToldInWordsWhyAnActionCannotBeDoneToARecipe() {
		System.runAs(admin()) {
			ConnectorRecipeTestData.noConnections();
			ConnectorIdentity.automatedProcessOverride = '005000000000000';
			ConnectorRecipes.Recipe saved = ConnectorRecipesController.saveDraft(
				null,
				'Plain Stop',
				'Does nothing',
				ConnectorRecipeTestData.document(STOP_STEPS),
				null
			);

			Test.startTest();
			String goneText = BarnHelp.text('Connector', 'Connector_Recipe_ErrorGone');
			Assert.areEqual(goneText, refusal('exportRecipe'));
			Assert.areEqual(goneText, refusal('deleteRecipe'));
			Assert.areEqual(goneText, refusal('pauseRecipe'));
			String noPrevious;
			try {
				ConnectorRecipesController.rollBack(saved.id);
			} catch (AuraHandledException refused) {
				noPrevious = message(refused);
			}
			String notPublished;
			try {
				ConnectorRecipesController.discardDraft(saved.id);
			} catch (AuraHandledException refused) {
				notPublished = message(refused);
			}
			String notActive;
			try {
				ConnectorRecipesController.pauseRecipe(saved.id);
			} catch (AuraHandledException refused) {
				notActive = message(refused);
			}
			String notPaused;
			try {
				ConnectorRecipesController.resumeRecipe(saved.id);
			} catch (AuraHandledException refused) {
				notPaused = message(refused);
			}
			String unreadable = refusal('importFile');
			Integer retried = ConnectorRecipesController.retryAllFailed(saved.id);
			Test.stopTest();

			Assert.areEqual(BarnHelp.text('Connector', 'Connector_Recipe_ErrorNoPrevious'), noPrevious);
			Assert.areEqual(BarnHelp.text('Connector', 'Connector_Recipe_ErrorNotPublished'), notPublished);
			Assert.areEqual(BarnHelp.text('Connector', 'Connector_Run_ErrorNotActive'), notActive);
			Assert.areEqual(BarnHelp.text('Connector', 'Connector_Recipe_ErrorNotPaused'), notPaused);
			Assert.isNotNull(unreadable, 'A file with no recipe in it is refused in words.');
			Assert.areEqual(0, retried, 'A recipe that never ran has no failed runs.');
		}
	}

	@IsTest
	static void danaPausesResumesDiscardsExportsAndDeletesARecipe() {
		System.runAs(admin()) {
			ConnectorRecipeTestData.noConnections();
			ConnectorIdentity.automatedProcessOverride = '005000000000000';
			ConnectorRecipes.Recipe saved = ConnectorRecipesController.saveDraft(
				null,
				'Plain Stop',
				'Does nothing',
				ConnectorRecipeTestData.document(STOP_STEPS),
				null
			);

			Test.startTest();
			ConnectorRecipes.Recipe published = ConnectorRecipesController.publish(saved.id);
			ConnectorRecipes.Recipe paused = ConnectorRecipesController.pauseRecipe(saved.id);
			ConnectorRecipes.Recipe resumed = ConnectorRecipesController.resumeRecipe(saved.id);
			ConnectorRecipes.Recipe discarded = ConnectorRecipesController.discardDraft(saved.id);
			String exported = ConnectorRecipesController.exportRecipe(saved.id);
			ConnectorRecipesController.deleteRecipe(saved.id);
			Test.stopTest();

			Assert.areEqual(ConnectorRunStore.ACTIVE, published.status);
			Assert.areEqual(ConnectorRunStore.PAUSED, paused.status);
			Assert.areEqual(ConnectorRunStore.ACTIVE, resumed.status);
			Assert.isFalse(discarded.unpublished, 'The draft is the published definition again.');
			Assert.isTrue(exported.contains('Plain Stop'), 'The file carries the recipe.');
			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Connector_Recipe__c WHERE Id = :saved.id WITH SYSTEM_MODE],
				'Delete removes it.'
			);
		}
	}

	@IsTest
	static void danaPausesAndRestartsTheClockAndSeesWhoRunsIntegrationUserRecipes() {
		System.runAs(admin()) {
			Test.startTest();
			ConnectorClock.Status running = ConnectorRecipesController.getClock();
			ConnectorClock.Status paused = ConnectorRecipesController.setRecipesPaused(true);
			ConnectorClock.Status resumed = ConnectorRecipesController.setRecipesPaused(false);
			ConnectorClock.Status restarted = ConnectorRecipesController.restartClock();
			ConnectorIntegrationUser.View user = ConnectorRecipesController.getIntegrationUser();
			Test.stopTest();

			Assert.isFalse(running.paused);
			Assert.isTrue(paused.paused, 'Pause All Recipes is on.');
			Assert.isFalse(resumed.paused);
			Assert.isNotNull(restarted.lanes);
			Assert.isNull(user.id, 'No integration user is chosen yet.');
		}
	}

	// ---------------------------------------------------------------------------------------
	// Recipe Access on the Automated Process user, and what a recipe identity may map
	// ---------------------------------------------------------------------------------------

	private static ConnectorIdentity.Choice choiceNamed(ConnectorIdentity.Access access, String name) {
		for (ConnectorIdentity.Choice choice : access.choices) {
			if (choice.name == name) {
				return choice;
			}
		}
		return null;
	}

	@IsTest
	static void beforeAFirstSaveBarnCrmAdminAndTheModuleAdminSetsAreTicked() {
		User identity = TestUsers.standardUser('Autopilot');
		System.runAs(admin()) {
			ConnectorIdentity.automatedProcessOverride = identity.Id;

			Test.startTest();
			ConnectorIdentity.Access access = ConnectorIdentity.access();
			Test.stopTest();

			Assert.isTrue(access.ready);
			Assert.isFalse(access.saved, 'The user holds none of the sets on offer.');
			Assert.isFalse(ConnectorIdentity.accessSaved());
			ConnectorIdentity.Choice core = choiceNamed(access, 'BarnCRM_Admin');
			Assert.isNotNull(core, 'BarnCRM Admin is offered.');
			Assert.isTrue(core.picked, 'And ticked to start.');
			Assert.isNull(choiceNamed(access, 'Connector_Viewer'), 'Connector sets are never offered.');
			for (ConnectorIdentity.Choice choice : access.choices) {
				Assert.areEqual(
					choice.name == 'BarnCRM_Admin' ||
					(choice.name.endsWith('_Admin') &&
					choice.name != 'BarnCRM_App_Admin_Console' &&
					choice.name != 'BarnCRM_App_Admin_Standard' &&
					choice.name != 'BarnCRM_Metadata_Admin' &&
					choice.name != ConnectorConnections.ADMIN_SET),
					choice.picked,
					'Only admin sets are ticked to start: ' + choice.name
				);
			}
		}
	}

	@IsTest
	static void savingAssignsOnlyTheNewPicksAndDroppingARecipeAccessSetRemovesIt() {
		User identity = TestUsers.standardUser('Autopilot');
		System.runAs(admin()) {
			ConnectorIdentity.automatedProcessOverride = identity.Id;
			String coreAdmin = choiceNamed(ConnectorIdentity.access(), 'BarnCRM_Admin').id;

			Test.startTest();
			ConnectorIdentity.Access saved = ConnectorIdentity.save(new List<String>{ coreAdmin });
			Boolean heldAfterSave =
				[
					SELECT COUNT()
					FROM PermissionSetAssignment
					WHERE AssigneeId = :identity.Id AND PermissionSetId = :coreAdmin
					WITH SYSTEM_MODE
				] == 1;
			Boolean savedAgain = ConnectorIdentity.save(new List<String>{ coreAdmin }).saved;
			ConnectorIdentity.Access dropped = ConnectorIdentity.save(null);
			Test.stopTest();

			Assert.isTrue(saved.saved);
			Assert.isTrue(choiceNamed(saved, 'BarnCRM_Admin').picked);
			Assert.isTrue(heldAfterSave, 'The picked set is assigned.');
			Assert.isTrue(savedAgain, 'Saving the same picks again changes nothing.');
			Assert.isFalse(dropped.saved, 'Nothing picked leaves no offered set.');
			Assert.areEqual(
				0,
				[
					SELECT COUNT()
					FROM PermissionSetAssignment
					WHERE AssigneeId = :identity.Id AND PermissionSetId = :coreAdmin
					WITH SYSTEM_MODE
				],
				'The set no longer picked is removed.'
			);
		}
	}

	@IsTest
	static void aRecipeIdentityMayMapOnlyWhatItsSetsGrantObjectAndFieldByField() {
		User identity = TestUsers.minimumAccessUserWith('Mapper', new List<String>());
		User bare = TestUsers.minimumAccessUserWith('Bare', new List<String>());
		PermissionSet granting = new PermissionSet(Name = 'Connector_Map_Check', Label = 'Connector Map Check');
		insert as system granting;
		insert as system new ObjectPermissions(
			ParentId = granting.Id,
			SobjectType = 'Contact',
			PermissionsRead = true,
			PermissionsEdit = true
		);
		insert as system new PermissionSetAssignment(AssigneeId = identity.Id, PermissionSetId = granting.Id);
		System.runAs(admin()) {
			Test.startTest();
			List<String> noSets = ConnectorIdentity.mapProblems(
				bare.Id,
				'create',
				'Contact',
				new List<String>{ 'Title' }
			);
			List<String> cannotCreate = ConnectorIdentity.mapProblems(
				identity.Id,
				'create',
				'Contact',
				new List<String>{ 'Title' }
			);
			List<String> noFieldEdit = ConnectorIdentity.mapProblems(
				identity.Id,
				'update',
				'Contact',
				new List<String>{ 'Title', 'No_Such_Field__c' }
			);
			insert as system new FieldPermissions(
				ParentId = granting.Id,
				SobjectType = 'Contact',
				Field = 'Contact.Title',
				PermissionsRead = true,
				PermissionsEdit = true
			);
			List<String> allowed = ConnectorIdentity.mapProblems(
				identity.Id,
				'update',
				'Contact',
				new List<String>{ 'Title', 'No_Such_Field__c' }
			);
			Test.stopTest();

			String objectAccess = BarnHelp.text(
				'Connector',
				'Connector_Publish_ObjectAccess',
				new List<Object>{ 'Contact' }
			);
			Assert.areEqual(new List<String>{ objectAccess }, noSets, 'No set, no object access.');
			Assert.areEqual(new List<String>{ objectAccess }, cannotCreate, 'Edit is not Create.');
			Assert.areEqual(
				new List<String>{
					BarnHelp.text('Connector', 'Connector_Publish_FieldAccess', new List<Object>{ 'Contact.Title' })
				},
				noFieldEdit,
				'Title needs its own field permission; a field that is not there is not blamed on the sets.'
			);
			Assert.isTrue(allowed.isEmpty(), 'Object Edit and the field permission are enough to update.');
		}
	}
}
