/**
 * The nightly Record Cleanup (L-08, R-NJ8): each pass deletes only rows past the org's retention
 * and keeps newer ones, a finished import goes only once its undo window has closed, and each
 * retention setting falls back to its default and is held between its bounds.
 */
@IsTest(testFor='ApexClass:RecordRetentionBatch')
private class RecordRetentionBatchTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	/** Runs one pass's start and execute in this transaction, as the job would. */
	private static void runPass(Integer pass) {
		RecordRetentionBatch.chain = false;
		RecordRetentionBatch cleanup = new RecordRetentionBatch(pass);
		List<SObject> scope = new List<SObject>();
		Database.QueryLocatorIterator found = cleanup.start(null).iterator();
		while (found.hasNext()) {
			scope.add(found.next());
		}
		if (!scope.isEmpty()) {
			cleanup.execute(null, scope);
		}
		cleanup.finish(null);
	}

	@IsTest
	static void settingChangesPastTheirDaysAreDeleted() {
		System.runAs(TestUsers.admin()) {
			Setting_Change__c old = new Setting_Change__c(
				Setting_Name__c = 'Old',
				Changed_At__c = Datetime.now().addDays(-731)
			);
			Setting_Change__c recent = new Setting_Change__c(
				Setting_Name__c = 'Recent',
				Changed_At__c = Datetime.now().addDays(-10)
			);
			insert as system new List<Setting_Change__c>{ old, recent };

			Test.startTest();
			runPass(RecordRetentionBatch.SETTING_CHANGES);
			Test.stopTest();

			List<Setting_Change__c> left = [SELECT Id FROM Setting_Change__c WITH SYSTEM_MODE];
			Assert.areEqual(1, left.size(), 'Only the change past 730 days is deleted');
			Assert.areEqual(recent.Id, left[0].Id, 'The recent change is kept');
		}
	}

	@IsTest
	static void mergeJournalPastItsDaysIsDeleted() {
		System.runAs(TestUsers.admin()) {
			Merge_Journal__c old = new Merge_Journal__c(Merged_Name__c = 'Old');
			Merge_Journal__c recent = new Merge_Journal__c(Merged_Name__c = 'Recent');
			insert as system new List<Merge_Journal__c>{ old, recent };
			Test.setCreatedDate(old.Id, Datetime.now().addDays(-366));

			Test.startTest();
			runPass(RecordRetentionBatch.MERGE_JOURNAL);
			Test.stopTest();

			List<Merge_Journal__c> left = [SELECT Id FROM Merge_Journal__c WITH SYSTEM_MODE];
			Assert.areEqual(1, left.size(), 'Only the entry past 365 days is deleted');
			Assert.areEqual(recent.Id, left[0].Id, 'The recent entry is kept');
		}
	}

	@IsTest
	static void finishedImportsGoOnlyOnceTheirUndoWindowCloses() {
		System.runAs(TestUsers.admin()) {
			Import_Template__c template = ImportTestDataFactory.template(
				ImportTestDataFactory.donorMapping(),
				ImportTemplateService.RULE_EMAIL
			);
			Import_Batch__c closed = ImportTestDataFactory.batch(template);
			Import_Batch__c undoOpen = ImportTestDataFactory.batch(template);
			Import_Batch__c running = ImportTestDataFactory.batch(template);
			for (Import_Batch__c batch : new List<Import_Batch__c>{ closed, undoOpen, running }) {
				Test.setCreatedDate(batch.Id, Datetime.now().addDays(-400));
				ImportTestDataFactory.rows(
					batch,
					new List<Map<String, String>>{
						ImportTestDataFactory.donorRow('Ana', 'Row', 'row@example.org', null)
					}
				);
			}
			// After the rows, which save each batch's in-memory status again.
			update as system new List<Import_Batch__c>{
				new Import_Batch__c(
					Id = closed.Id,
					Status__c = ImportBatchService.STATUS_COMPLETE,
					Undo_Deadline__c = Datetime.now().addDays(-300)
				),
				new Import_Batch__c(
					Id = undoOpen.Id,
					Status__c = ImportBatchService.STATUS_COMPLETE,
					Undo_Deadline__c = Datetime.now().addDays(5)
				),
				new Import_Batch__c(
					Id = running.Id,
					Status__c = ImportBatchService.STATUS_COMMITTING
				)
			};
			insert as system new Import_Journal__c(Import_Batch__c = closed.Id);

			Test.startTest();
			runPass(RecordRetentionBatch.IMPORT_JOURNAL);
			runPass(RecordRetentionBatch.IMPORT_ROWS);
			runPass(RecordRetentionBatch.IMPORT_BATCHES);
			Test.stopTest();

			Set<Id> left = new Map<Id, Import_Batch__c>(
					[SELECT Id FROM Import_Batch__c WITH SYSTEM_MODE]
				)
				.keySet();
			Assert.isFalse(left.contains(closed.Id), 'A finished import past its undo is deleted');
			Assert.isTrue(left.contains(undoOpen.Id), 'An import that can still be undone is kept');
			Assert.isTrue(left.contains(running.Id), 'An unfinished import is kept');
			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Import_Journal__c WITH SYSTEM_MODE],
				'The deleted import\'s journal goes first'
			);
			Assert.areEqual(
				2,
				[SELECT COUNT() FROM Import_Row__c WITH SYSTEM_MODE],
				'Only the deleted import\'s rows go'
			);
		}
	}

	@IsTest
	static void importsAbandonedInDraftParsingOrPreviewGoAfterTheSameDays() {
		System.runAs(TestUsers.admin()) {
			Import_Template__c template = ImportTestDataFactory.template(
				ImportTestDataFactory.donorMapping(),
				ImportTemplateService.RULE_EMAIL
			);
			List<Import_Batch__c> old = new List<Import_Batch__c>();
			for (
				String status : new List<String>{
					ImportBatchService.STATUS_DRAFT,
					ImportBatchService.STATUS_PARSING,
					ImportBatchService.STATUS_DRY_RUN
				}
			) {
				Import_Batch__c batch = ImportTestDataFactory.batch(template);
				ImportTestDataFactory.rows(
					batch,
					new List<Map<String, String>>{
						ImportTestDataFactory.donorRow('Ana', 'Row', 'row@example.org', null)
					}
				);
				old.add(new Import_Batch__c(Id = batch.Id, Status__c = status));
				Test.setCreatedDate(batch.Id, Datetime.now().addDays(-400));
			}
			Import_Batch__c recent = ImportTestDataFactory.batch(template);
			Import_Batch__c committing = ImportTestDataFactory.batch(template);
			Test.setCreatedDate(committing.Id, Datetime.now().addDays(-400));
			old.add(
				new Import_Batch__c(
					Id = committing.Id,
					Status__c = ImportBatchService.STATUS_COMMITTING
				)
			);
			update as system old;

			Test.startTest();
			runPass(RecordRetentionBatch.IMPORT_JOURNAL);
			runPass(RecordRetentionBatch.IMPORT_ROWS);
			runPass(RecordRetentionBatch.IMPORT_BATCHES);
			Test.stopTest();

			Set<Id> left = new Map<Id, Import_Batch__c>(
					[SELECT Id FROM Import_Batch__c WITH SYSTEM_MODE]
				)
				.keySet();
			Assert.isTrue(left.contains(recent.Id), 'A recent draft is kept');
			Assert.isTrue(left.contains(committing.Id), 'An import that is running is kept');
			Assert.isFalse(left.contains(old[0].Id), 'An old draft is deleted');
			Assert.isFalse(left.contains(old[1].Id), 'An old parsing import is deleted');
			Assert.isFalse(left.contains(old[2].Id), 'An old preview is deleted');
			Assert.areEqual(
				0,
				[
					SELECT COUNT()
					FROM Import_Row__c
					WHERE Import_Batch__c = :old[0].Id
					WITH SYSTEM_MODE
				],
				'Its staged rows go with it'
			);
		}
	}

	@IsTest
	static void errorLogEntriesPastTheirDaysAreDeletedWhateverTheirStatus() {
		System.runAs(TestUsers.admin()) {
			List<Error_Log__c> logs = new List<Error_Log__c>();
			for (
				String status : new List<String>{
					ErrorLogger.STATUS_NEW,
					ErrorLogger.STATUS_RESOLVED,
					ErrorLogger.STATUS_NEW
				}
			) {
				logs.add(
					new Error_Log__c(
						Timestamp__c = System.now(),
						Context__c = 'Retention test',
						Message__c = 'The Garcia household could not be renamed.',
						Severity__c = ErrorLogger.SEVERITY_ERROR,
						Status__c = status
					)
				);
			}
			insert logs;
			Test.setCreatedDate(logs[0].Id, Datetime.now().addDays(-181));
			Test.setCreatedDate(logs[1].Id, Datetime.now().addDays(-181));

			Test.startTest();
			runPass(RecordRetentionBatch.ERROR_LOG);
			Test.stopTest();

			Assert.areEqual(180, RecordRetentionBatch.errorLogDays(), 'The shipped default');
			Assert.areEqual(
				1,
				[
					SELECT COUNT()
					FROM Error_Log__c
					WHERE Context__c = 'Retention test'
					WITH SYSTEM_MODE
				],
				'The two older than 180 days are gone, New or not'
			);
		}
	}

	@IsTest
	static void aSettingOfZeroKeepsEveryErrorLogEntry() {
		System.runAs(TestUsers.admin()) {
			BarnCRM_Settings__c settings = BarnCRM_Settings__c.getOrgDefaults();
			settings.Error_Log_Retention_Days__c = 0;
			TestDataFactory.saveSettings(settings);
			Error_Log__c old = new Error_Log__c(
				Timestamp__c = System.now(),
				Context__c = 'Retention test',
				Message__c = 'The Garcia household could not be renamed.',
				Severity__c = ErrorLogger.SEVERITY_ERROR,
				Status__c = ErrorLogger.STATUS_NEW
			);
			insert old;
			Test.setCreatedDate(old.Id, Datetime.now().addDays(-4000));

			Test.startTest();
			runPass(RecordRetentionBatch.ERROR_LOG);
			Test.stopTest();

			Assert.isNull(RecordRetentionBatch.errorLogDays(), 'Zero keeps everything');
			Assert.areEqual(
				1,
				[
					SELECT COUNT()
					FROM Error_Log__c
					WHERE Context__c = 'Retention test'
					WITH SYSTEM_MODE
				],
				'Every entry is kept'
			);
		}
	}

	@IsTest
	static void fieldUseCountsPastTheirDaysAreDeleted() {
		System.runAs(TestUsers.admin()) {
			Field_Utilization_Snapshot__c old = new Field_Utilization_Snapshot__c(
				Object_Name__c = 'Account',
				Field_Name__c = 'Name',
				Taken_At__c = Datetime.now().addDays(-800)
			);
			Field_Utilization_Snapshot__c recent = new Field_Utilization_Snapshot__c(
				Object_Name__c = 'Account',
				Field_Name__c = 'Name',
				Taken_At__c = Datetime.now().addDays(-1)
			);
			insert as system new List<Field_Utilization_Snapshot__c>{ old, recent };

			Test.startTest();
			runPass(RecordRetentionBatch.FIELD_UTILIZATION);
			Test.stopTest();

			List<Field_Utilization_Snapshot__c> left = [
				SELECT Id
				FROM Field_Utilization_Snapshot__c
				WITH SYSTEM_MODE
			];
			Assert.areEqual(1, left.size(), 'Only the count past 730 days is deleted');
			Assert.areEqual(recent.Id, left[0].Id, 'The recent count is kept');
		}
	}

	@IsTest
	static void fieldHistoryPastItsDaysIsDeleted() {
		System.runAs(TestUsers.admin()) {
			Field_History__c old = new Field_History__c(Record_Id__c = 'old', Changes__c = '[]');
			Field_History__c recent = new Field_History__c(Record_Id__c = 'new', Changes__c = '[]');
			insert as system new List<Field_History__c>{ old, recent };
			Test.setCreatedDate(old.Id, Datetime.now().addDays(-731));

			Test.startTest();
			runPass(RecordRetentionBatch.FIELD_HISTORY);
			Test.stopTest();

			List<Field_History__c> left = [SELECT Id FROM Field_History__c WITH SYSTEM_MODE];
			Assert.areEqual(1, left.size(), 'Only the change past 730 days is deleted (R-FH5)');
			Assert.areEqual(recent.Id, left[0].Id, 'The recent change is kept');
		}
	}

	@IsTest
	static void daysFallBackToDefaultsAndStayInBounds() {
		System.runAs(TestUsers.admin()) {
			Assert.areEqual(365, RecordRetentionBatch.mergeJournalDays(), 'Merge journal default');
			Assert.areEqual(
				730,
				RecordRetentionBatch.settingChangeDays(),
				'Setting change default'
			);

			BarnCRM_Settings__c settings = BarnCRM_Settings__c.getOrgDefaults();
			settings.Merge_Journal_Retention_Days__c = 5;
			settings.Setting_Change_Retention_Days__c = 9000;
			settings.Import_History_Retention_Days__c = 90;
			TestDataFactory.saveSettings(settings);

			Assert.areEqual(30, RecordRetentionBatch.mergeJournalDays(), 'Held at the minimum');
			Assert.areEqual(3650, RecordRetentionBatch.settingChangeDays(), 'Held at ten years');
			Assert.areEqual(
				90,
				RecordRetentionBatch.importHistoryDays(),
				'A value in range is kept'
			);
		}
	}

	@IsTest
	static void theStepStartsTheFirstPassAndChainsTheRest() {
		// runs-as: deploying user (only starts a batch; reads AsyncApexJob, no permission set involved)
		NightlyStep step = RecordRetentionBatch.step();
		Assert.areEqual(RecordRetentionBatch.JOB_NAME, step.key, 'The step carries the job key');

		Test.startTest();
		new RecordRetentionBatch().execute((SchedulableContext) null);
		Test.stopTest();

		Assert.isTrue(
			[
				SELECT COUNT()
				FROM AsyncApexJob
				WHERE ApexClass.Name = 'RecordRetentionBatch' AND JobType = 'BatchApex'
			] >= 1,
			'The step starts the first pass'
		);
	}
}
