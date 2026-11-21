/**
 * Load Rows with an Import Template (CN-09, C-38; canonical model R-CR9, R-IB18): the rows go to
 * Super Importer's own staging, the run waits while a pass runs, a dry run inside every limit is
 * committed, a dry run outside one commits nothing and names the data job, and a Test run only
 * says what it would load. Waiting on a pass never uses up a retry.
 */
@IsTest(testFor='ApexClass:ConnectorImportStep, ApexClass:ConnectorStepRunner, ApexClass:ConnectorRunStore')
private class ConnectorImportStepTest {
	private static final String ROWS =
		'{"rows":[{"First Name":"Ada","Last Name":"Lovelace","Email":"ada@example.org"},' +
		'{"First Name":"Grace","Last Name":"Hopper","Email":"grace@example.org"}]}';

	@TestSetup
	static void setUp() {
		System.runAs(TestUsers.admin()) {
			TestDataFactory.defaultSettings();
		}
		TestUsers.adminWith(ConnectorConnections.ADMIN_SET);
	}

	private static User admin() {
		return TestUsers.adminWith(ConnectorConnections.ADMIN_SET);
	}

	private static Import_Template__c template() {
		return ImportTestDataFactory.template(ImportTestDataFactory.donorMapping(), ImportTemplateService.RULE_EMAIL);
	}

	private static Connector_Recipe__c recipe(Id templateId, String limits) {
		String steps =
			'[{"id":"load","kind":"importRows","template":"' +
			templateId +
			'","rows":"trigger.rows"' +
			(limits == null ? '' : ',"limits":' + limits) +
			'}]';
		return ConnectorRecipeTestData.recipe(
			'Nightly Donors',
			ConnectorRecipeTestData.document(steps),
			true,
			ConnectorRecipes.RUN_AS_AUTOMATION
		);
	}

	/** A queued run of the recipe already part way: waiting on this data job's pass. */
	private static Connector_Run__c partWay(Connector_Recipe__c recipe, Id batchId, String phase) {
		Connector_Run__c run = ConnectorRecipeTestData.queuedRun(recipe, ROWS, false);
		Map<String, Object> progress = new Map<String, Object>{
			'batchId' => batchId,
			'phase' => phase,
			'since' => Datetime.now().getTime()
		};
		update as system new Connector_Run__c(
			Id = run.Id,
			State_JSON__c = JSON.serialize(
				new Map<String, Object>{
					'done' => new List<String>(),
					'steps' => new Map<String, Object>{ 'load' => progress }
				}
			)
		);
		return run;
	}

	/** A data job as a finished pass left it. */
	private static Import_Batch__c finished(Id templateId, String status, Integer created, Integer rejected) {
		Import_Batch__c batch = ImportBatchService.create(templateId, null, 'rows', null, null, null, false);
		update as system new Import_Batch__c(
			Id = batch.Id,
			Status__c = status,
			Row_Count__c = created + rejected,
			Rows_Created__c = created,
			Rows_Updated__c = 0,
			Rows_Matched__c = 0,
			Rows_Rejected__c = rejected
		);
		return [SELECT Id, Name, Status__c, Committed_By__c FROM Import_Batch__c WHERE Id = :batch.Id WITH SYSTEM_MODE];
	}

	private static Map<String, Object> stateOf(Connector_Run__c run) {
		Map<String, Object> state = (Map<String, Object>) JSON.deserializeUntyped(run.State_JSON__c);
		return (Map<String, Object>) state.get('steps');
	}

	private static void wake(Id runId) {
		update as system new Connector_Run__c(
			Id = runId,
			Status__c = ConnectorRunStore.QUEUED,
			Next_Attempt_At__c = null
		);
	}

	@IsTest
	static void theRowsAreStagedAndDryRunThenCommittedInsideTheLimits() {
		System.runAs(admin()) {
			Import_Template__c template = template();
			Connector_Run__c run = ConnectorRecipeTestData.queuedRun(recipe(template.Id, null), ROWS, false);

			Test.startTest();
			Connector_Run__c staged = ConnectorRecipeTestData.runAll(run.Id);
			Test.stopTest();

			Assert.areEqual(ConnectorRunStore.WAITING, staged.Status__c, 'The run waits for the dry run.');
			Assert.isNull(staged.Finished_At__c, 'A waiting run has not finished.');
			Map<String, Object> progress = (Map<String, Object>) stateOf(staged).get('load');
			Assert.areEqual('dryRun', progress.get('phase'));
			Import_Batch__c batch = [
				SELECT Id, Status__c, Row_Count__c, Rows_Rejected__c, File_Name__c
				FROM Import_Batch__c
				WITH SYSTEM_MODE
			];
			Assert.areEqual(String.valueOf(batch.Id), progress.get('batchId'));
			Assert.areEqual(ImportBatchService.STATUS_DRY_RUN_COMPLETE, batch.Status__c, 'Super Importer ran it.');
			Assert.areEqual(2, batch.Row_Count__c.intValue(), 'Both rows were staged.');
			Assert.areEqual(0, batch.Rows_Rejected__c.intValue());
			Assert.isTrue(batch.File_Name__c.contains('Nightly Donors'), 'The data job names the recipe.');
			Assert.areEqual(0, [SELECT COUNT() FROM Contact WHERE Email = 'ada@example.org' WITH SYSTEM_MODE]);

			wake(run.Id);
			Connector_Run__c committing = ConnectorRecipeTestData.runAll(run.Id);

			Assert.areEqual(ConnectorRunStore.WAITING, committing.Status__c, 'The run waits for the commit.');
			Assert.areEqual('commit', ((Map<String, Object>) stateOf(committing).get('load')).get('phase'));
			Assert.areEqual(
				ImportBatchService.STATUS_COMMITTING,
				[SELECT Status__c FROM Import_Batch__c WHERE Id = :batch.Id WITH SYSTEM_MODE].Status__c,
				'Inside every limit, the commit started.'
			);
		}
	}

	@IsTest
	static void aFinishedCommitEndsTheStepWithItsCounts() {
		System.runAs(admin()) {
			Import_Template__c template = template();
			Import_Batch__c batch = finished(template.Id, ImportBatchService.STATUS_COMPLETE, 2, 0);
			Connector_Run__c run = partWay(recipe(template.Id, null), batch.Id, 'commit');

			Test.startTest();
			Connector_Run__c done = ConnectorRecipeTestData.runAll(run.Id);
			Test.stopTest();

			Assert.areEqual(ConnectorRunStore.SUCCEEDED, done.Status__c, 'Message: ' + done.Error_Message__c);
			Assert.areEqual(2, done.Records_Written__c.intValue());
			Map<String, Object> result = (Map<String, Object>) stateOf(done).get('load');
			Assert.areEqual(batch.Name, result.get('batch'));
			Assert.areEqual(2, result.get('created'));
			Map<String, Object> logged = (Map<String, Object>) ((List<Object>) JSON.deserializeUntyped(
				done.Step_Log_JSON__c
			))[0];
			Assert.isTrue(String.valueOf(logged.get('message')).contains(batch.Name), 'The log names the data job.');
		}
	}

	@IsTest
	static void aDryRunOutsideALimitCommitsNothingAndNamesTheJob() {
		System.runAs(admin()) {
			Import_Template__c template = template();
			Import_Batch__c batch = finished(template.Id, ImportBatchService.STATUS_DRY_RUN_COMPLETE, 2, 3);
			Connector_Run__c run = partWay(recipe(template.Id, '{"rejected":2}'), batch.Id, 'dryRun');

			Test.startTest();
			Connector_Run__c failed = ConnectorRecipeTestData.runAll(run.Id);
			Test.stopTest();

			Assert.areEqual(ConnectorRunStore.FAILED, failed.Status__c);
			Assert.areEqual('load', failed.Failed_Step__c);
			Assert.isTrue(failed.Error_Message__c.contains(batch.Name), failed.Error_Message__c);
			Assert.isTrue(failed.Error_Message__c.contains('3'), 'It says how many rows would be rejected.');
			Assert.isFalse(stateOf(failed).containsKey('load'), 'A retry starts the step again from nothing.');
			Import_Batch__c kept = [
				SELECT Status__c, Committed_By__c
				FROM Import_Batch__c
				WHERE Id = :batch.Id
				WITH SYSTEM_MODE
			];
			Assert.areEqual(ImportBatchService.STATUS_DRY_RUN_COMPLETE, kept.Status__c, 'Left for a person.');
			Assert.isNull(kept.Committed_By__c, 'Nothing was committed.');
		}
	}

	@IsTest
	static void aDryRunThatEndedBadlyOrTooManyRowsLoadNothing() {
		System.runAs(admin()) {
			Import_Template__c template = template();
			// A dry run the platform stopped: its status says Dry run, but no job runs it.
			Import_Batch__c stopped = finished(template.Id, ImportBatchService.STATUS_DRY_RUN, 0, 0);
			Connector_Run__c run = partWay(recipe(template.Id, null), stopped.Id, 'dryRun');
			Connector_Recipe__c small = ConnectorRecipeTestData.recipe(
				'Small Loads',
				ConnectorRecipeTestData.document(
					'[{"id":"load","kind":"importRows","template":"' +
						template.Id +
						'","rows":"trigger.rows","limits":{"rows":1}}]'
				),
				true,
				ConnectorRecipes.RUN_AS_AUTOMATION
			);
			Connector_Run__c tooMany = ConnectorRecipeTestData.queuedRun(small, ROWS, false);

			Test.startTest();
			Connector_Run__c failed = ConnectorRecipeTestData.runAll(run.Id);
			Connector_Run__c refused = ConnectorRecipeTestData.runAll(tooMany.Id);
			Test.stopTest();

			Assert.areEqual(ConnectorRunStore.FAILED, failed.Status__c);
			Assert.isTrue(failed.Error_Message__c.contains(stopped.Name), failed.Error_Message__c);
			Assert.areEqual(ConnectorRunStore.FAILED, refused.Status__c);
			Assert.isTrue(refused.Error_Message__c.startsWith('2 '), refused.Error_Message__c);
			Assert.areEqual(1, [SELECT COUNT() FROM Import_Batch__c WITH SYSTEM_MODE], 'No data job was started.');
		}
	}

	@IsTest
	static void aTestRunSaysWhatItWouldLoadAndStagesNothing() {
		System.runAs(admin()) {
			Import_Template__c template = template();
			Connector_Run__c run = ConnectorRecipeTestData.queuedRun(
				recipe(template.Id, null),
				'{"sample":' + ROWS + '}',
				true
			);

			Test.startTest();
			Connector_Run__c tested = ConnectorRecipeTestData.runAll(run.Id);
			Test.stopTest();

			Assert.areEqual(ConnectorRunStore.SUCCEEDED, tested.Status__c, 'Message: ' + tested.Error_Message__c);
			Map<String, Object> would = (Map<String, Object>) ((Map<String, Object>) stateOf(tested).get('load'))
				.get('wouldWrite');
			Assert.areEqual(template.Name, would.get('template'));
			Assert.areEqual(2, would.get('rows'));
			Assert.areEqual(0, [SELECT COUNT() FROM Import_Batch__c WITH SYSTEM_MODE]);
		}
	}

	@IsTest
	static void anIdentityWithoutTheImportPermissionLoadsNothing() {
		User connectorOnly = TestUsers.withPermissionSets(new List<String>{ ConnectorConnections.ADMIN_SET });
		Import_Template__c template;
		System.runAs(admin()) {
			template = template();
		}
		System.runAs(connectorOnly) {
			Connector_Run__c run = ConnectorRecipeTestData.queuedRun(recipe(template.Id, null), ROWS, false);

			Test.startTest();
			Connector_Run__c refused = ConnectorRecipeTestData.runAll(run.Id);
			Test.stopTest();

			Assert.areEqual(ConnectorRunStore.FAILED, refused.Status__c);
			Assert.areEqual(BarnHelp.text('Connector', 'Connector_Import_ErrorPermission'), refused.Error_Message__c);
		}
	}

	@IsTest
	static void waitingOnAPassUsesNoRetry() {
		System.runAs(admin()) {
			Connector_Recipe__c recipe = recipe(template().Id, null);
			Connector_Run__c run = new Connector_Run__c(
				Recipe__c = recipe.Id,
				Status__c = ConnectorRunStore.WAITING,
				Started_By__c = 'Schedule',
				Ran_As__c = ConnectorRecipes.RUN_AS_AUTOMATION,
				Recipe_Version__c = 1,
				Attempt__c = 0,
				Next_Attempt_At__c = Datetime.now().addMinutes(-1)
			);
			insert as system run;

			Test.startTest();
			ConnectorRunStore.releaseWaiting(ConnectorClock.runAsOf(ConnectorClock.LANE_AUTOMATION));
			Test.stopTest();

			Connector_Run__c released = [
				SELECT Status__c, Attempt__c
				FROM Connector_Run__c
				WHERE Id = :run.Id
				WITH SYSTEM_MODE
			];
			Assert.areEqual(ConnectorRunStore.QUEUED, released.Status__c);
			Assert.areEqual(0, released.Attempt__c.intValue(), 'A run waiting on a data job used no retry.');
		}
	}

	@IsTest
	static void rowsAreReadFromRecordsListsAndCsv() {
		System.runAs(admin()) {
			Test.startTest();
			List<Map<String, Object>> fromCsv = ConnectorImportStep.rowsOf(
				'Name,Email\r\n"Lovelace, Ada",ada@example.org\n"Say ""hi""",grace@example.org\n'
			);
			List<Map<String, Object>> fromLists = ConnectorImportStep.rowsOf(
				JSON.deserializeUntyped('[["Name","Age"],["Ada",36],["Grace"]]')
			);
			List<Map<String, Object>> fromRecords = ConnectorImportStep.rowsOf(
				JSON.deserializeUntyped('[{"Name":"Ada","Tags":["a","b"]}]')
			);
			List<String> refusals = new List<String>();
			for (Object bad : new List<Object>{ 42, '"open,quote', JSON.deserializeUntyped('[{"a":1},2]') }) {
				try {
					ConnectorImportStep.rowsOf(bad);
				} catch (ConnectorStepRunner.StepFailureException refused) {
					refusals.add(refused.getMessage());
				}
			}
			Test.stopTest();

			Assert.areEqual(2, fromCsv.size());
			Assert.areEqual('Lovelace, Ada', fromCsv[0].get('Name'));
			Assert.areEqual('Say "hi"', fromCsv[1].get('Name'));
			Assert.areEqual('grace@example.org', fromCsv[1].get('Email'));
			Assert.areEqual('36', fromLists[0].get('Age'), 'Values are text, as in a file.');
			Assert.isNull(fromLists[1].get('Age'), 'A short line leaves the rest blank.');
			Assert.areEqual('["a","b"]', fromRecords[0].get('Tags'), 'A nested value is kept as its JSON.');
			Assert.areEqual(3, refusals.size(), 'Each unreadable source is refused in words.');
		}
	}

	@IsTest
	static void aSaveRefusesAStepWithoutTemplateRowsOrSensibleLimits() {
		System.runAs(admin()) {
			Test.startTest();
			List<String> noTemplate = ConnectorRecipeDocument.problems(
				ConnectorRecipeDocument.parse(
					ConnectorRecipeTestData.document('[{"id":"load","kind":"importRows","rows":"trigger.rows"}]')
				)
			);
			List<String> badRows = ConnectorRecipeDocument.problems(
				ConnectorRecipeDocument.parse(
					ConnectorRecipeTestData.document(
						'[{"id":"load","kind":"importRows","template":"' + UserInfo.getUserId() + '","rows":"rows"}]'
					)
				)
			);
			List<String> badLimits = ConnectorRecipeDocument.problems(
				ConnectorRecipeDocument.parse(
					ConnectorRecipeTestData.document(
						'[{"id":"load","kind":"importRows","template":"' +
							UserInfo.getUserId() +
							'","rows":"trigger.rows","limits":{"rows":0,"rejected":5000}}]'
					)
				)
			);
			Test.stopTest();

			Assert.areEqual(
				new List<String>{
					BarnHelp.text('Connector', 'Connector_Recipe_ErrorTemplate', new List<Object>{ 'load' })
				},
				noTemplate
			);
			Assert.areEqual(
				new List<String>{
					BarnHelp.text('Connector', 'Connector_Recipe_ErrorPath', new List<Object>{ 'load' })
				},
				badRows
			);
			Assert.areEqual(
				new List<String>{
					BarnHelp.text('Connector', 'Connector_Recipe_ErrorLimits', new List<Object>{ 'load' })
				},
				badLimits
			);
		}
	}
}
