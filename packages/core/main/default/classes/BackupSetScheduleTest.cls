/**
 * Scheduled Backup Sets (canonical model R-SQ16): saving a schedule, which days a schedule falls
 * on, the nightly step starting only the sets due, Find keeping the schedule, and a scheduled set
 * keeping the files of its newest runs only. These tests have not been executed: no org in this
 * environment.
 */
@IsTest(testFor='ApexClass:BackupSetSchedule, ApexClass:BackupSetService, ApexClass:BackupSetController')
private class BackupSetScheduleTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	private static final String VOLUNTEERS = JSON.serialize(
		new Map<String, Object>{
			'version' => 1,
			'object' => 'Contact',
			'fields' => new List<Object>{ 'LastName' },
			'filter' => new Map<String, Object>{
				'version' => 1,
				'conditions' => new List<Object>{
					new Map<String, Object>{
						'id' => 1,
						'field' => 'Title',
						'operator' => 'equals',
						'value' => 'Volunteer'
					}
				}
			}
		}
	);

	private static Saved_Query__c backupSet(String name) {
		Saved_Query__c query = new Saved_Query__c(
			Name = name,
			Object_Name__c = 'Contact',
			Query_JSON__c = BackupSetService.marked(VOLUNTEERS)
		);
		insert query;
		return query;
	}

	private static void people() {
		DataProtectedFields.targetsOverride = new Map<String, Set<String>>();
		List<Contact> people = new List<Contact>();
		for (Integer index = 0; index < 5; index++) {
			people.add(TestDataFactory.person(new Contact(LastName = 'Person ' + index, Title = 'Volunteer')));
		}
		insert people;
	}

	@IsTest
	static void aScheduleIsSavedShownAndKeptWhenFindSavesTheQueryAgain() {
		System.runAs(TestUsers.admin()) {
			Saved_Query__c query = backupSet('Volunteers');
			BackupSetService.Panel page = BackupSetController.setSchedule(query.Id, 'weekly', 3, null, 'files');
			Assert.areEqual('weekly', page.sets[0].frequency, 'Shown as saved');
			Assert.areEqual(3, page.sets[0].weekday, 'On Wednesday');
			Assert.areEqual(BackupSetService.DEFAULT_RUNS_KEPT, page.runsKept, 'The default when the setting is empty');

			FindController.saveQuery(query.Id, 'Volunteers', VOLUNTEERS, false);
			String saved = [SELECT Query_JSON__c FROM Saved_Query__c WHERE Id = :query.Id].Query_JSON__c;
			Assert.areEqual(3, BackupSetService.scheduleOf(saved).get('weekday'), 'Find keeps the schedule');

			page = BackupSetController.setSchedule(query.Id, 'off', null, null, 'files');
			Assert.areEqual('off', page.sets[0].frequency, 'Taken off');
			Assert.isTrue(page.sets[0].id == query.Id, 'Still a Backup Set');
		}
	}

	@IsTest
	static void aScheduleWithoutItsDayOrOnAQueryThatIsNotASetIsRefused() {
		System.runAs(TestUsers.admin()) {
			Saved_Query__c query = backupSet('Volunteers');
			for (
				List<Object> wrong : new List<List<Object>>{
					new List<Object>{ 'weekly', null, null },
					new List<Object>{ 'monthly', null, 29 },
					new List<Object>{ 'hourly', null, null }
				}
			) {
				try {
					BackupSetController.setSchedule(
						query.Id,
						(String) wrong[0],
						(Integer) wrong[1],
						(Integer) wrong[2],
						null
					);
					Assert.fail('Refused: ' + wrong);
				} catch (AuraHandledException refused) {
					Assert.areEqual(BarnHelp.text('Core', 'Core_BackupSets_ErrorSchedule'), refused.getMessage());
				}
			}
			BackupSetService.setBackup(query.Id, false);
			try {
				BackupSetController.setSchedule(query.Id, 'daily', null, null, null);
				Assert.fail('Not a set');
			} catch (AuraHandledException refused) {
				Assert.areEqual(BarnHelp.text('Core', 'Core_BackupSets_ErrorNotSet'), refused.getMessage());
			}
		}
	}

	@IsTest
	static void aScheduleFallsOnItsDayOnly() {
		System.runAs(TestUsers.admin()) {
			Date monday = Date.newInstance(2026, 11, 23);
			Assert.areEqual(1, ArchiveRules.weekdayOf(monday), '23 November 2026 is a Monday');
			Assert.areEqual(7, ArchiveRules.weekdayOf(monday.addDays(6)), 'and the 29th a Sunday');
			Assert.isTrue(BackupSetService.isDue(new Map<String, Object>{ 'frequency' => 'daily' }, monday));
			Assert.isTrue(
				BackupSetService.isDue(new Map<String, Object>{ 'frequency' => 'weekly', 'weekday' => 1 }, monday)
			);
			Assert.isFalse(
				BackupSetService.isDue(new Map<String, Object>{ 'frequency' => 'weekly', 'weekday' => 2 }, monday)
			);
			Assert.isTrue(
				BackupSetService.isDue(new Map<String, Object>{ 'frequency' => 'monthly', 'day' => 23 }, monday)
			);
			Assert.isFalse(BackupSetService.isDue(new Map<String, Object>(), monday), 'No schedule never runs');
		}
	}

	@IsTest
	static void theNightlyStepStartsOnlyTheSetsDueToday() {
		System.runAs(TestUsers.admin()) {
			people();
			Saved_Query__c daily = backupSet('Daily');
			Saved_Query__c notToday = backupSet('Not Today');
			backupSet('On Demand');
			BackupSetService.setSchedule(daily.Id, 'daily', null, null, null);
			Integer tomorrow = ArchiveRules.weekdayOf(Date.today().addDays(1));
			BackupSetService.setSchedule(notToday.Id, 'weekly', tomorrow, null, null);

			NightlyStep step = BackupSetSchedule.step();
			Assert.areEqual(BackupSetSchedule.STEP_KEY, step.key);
			Assert.isTrue(step.switchDefault, 'Shipped on: nothing runs without a schedule');

			Test.startTest();
			step.run();
			Test.stopTest();

			List<Import_Batch__c> jobs = [
				SELECT Status__c, Operation_JSON__c, Run_Log__c, File_Id__c
				FROM Import_Batch__c
				WHERE Operation__c = 'Backup'
			];
			Assert.areEqual(1, jobs.size(), 'Only the daily set ran');
			Assert.isTrue(jobs[0].Operation_JSON__c.contains(daily.Id), jobs[0].Operation_JSON__c);
			Assert.areEqual(ImportBatchService.STATUS_COMPLETE, jobs[0].Status__c, jobs[0].Run_Log__c);
			Assert.isTrue(jobs[0].Operation_JSON__c.contains('documents'), 'Its parts are kept on the job');
		}
	}

	@IsTest
	static void someoneWhoMayNotUseBackupSetsStartsNothingAndItIsLogged() {
		User staff = TestUsers.standardUserWith('BackupScheduleStaff', new List<String>{ 'BarnCRM_Find_And_Export' });
		System.runAs(staff) {
			Assert.areEqual(0, BackupSetSchedule.startDue(Date.today()), 'Nothing started');
		}
		System.runAs(TestUsers.admin()) {
			Assert.areEqual(0, [SELECT COUNT() FROM Import_Batch__c WHERE Operation__c = 'Backup']);
		}
	}

	@IsTest
	static void aScheduledSetKeepsTheFilesOfItsNewestRunsOnly() {
		System.runAs(TestUsers.admin()) {
			BarnCRM_Settings__c settings = TestDataFactory.defaultSettings();
			settings.Backup_Runs_Kept__c = 1;
			TestDataFactory.saveSettings(settings);
			Saved_Query__c query = backupSet('Volunteers');
			BackupSetService.setSchedule(query.Id, 'daily', null, null, null);
			List<Id> documents = new List<Id>();
			List<Import_Batch__c> jobs = new List<Import_Batch__c>();
			for (Integer index = 0; index < 2; index++) {
				ContentVersion version = new ContentVersion(
					Title = 'Contact-run-' + index + '-part-1',
					PathOnClient = 'run.csv',
					VersionData = Blob.valueOf('Id\r\n')
				);
				insert version;
				Id documentId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :version.Id].ContentDocumentId;
				documents.add(documentId);
				jobs.add(
					new Import_Batch__c(
						Operation__c = 'Backup',
						Status__c = ImportBatchService.STATUS_COMPLETE,
						Started_At__c = Datetime.now().addDays(index - 2),
						File_Id__c = documentId,
						File_Name__c = version.Title,
						Run_Log__c = 'Saved.',
						Operation_JSON__c = JSON.serialize(
							new Map<String, Object>{
								'version' => 1,
								'savedQueryId' => query.Id,
								'documents' => new List<Id>{ documentId }
							}
						)
					)
				);
			}
			insert jobs;

			BackupSetSchedule.keepNewest(query.Id);

			Assert.areEqual(1, [SELECT COUNT() FROM ContentDocument WHERE Id IN :documents], 'The older file is gone');
			Assert.areEqual(1, [SELECT COUNT() FROM ContentDocument WHERE Id = :documents[1]], 'The newest stays');
			Import_Batch__c older = [SELECT File_Id__c, Run_Log__c FROM Import_Batch__c WHERE Id = :jobs[0].Id];
			Assert.isNull(older.File_Id__c, 'No file to open');
			Assert.isTrue(
				older.Run_Log__c.contains(BarnHelp.text('Core', 'Core_BackupSets_LogRemoved', new List<Object>{ 1 }))
			);

			BackupSetService.setSchedule(query.Id, 'off', null, null, null);
			BackupSetSchedule.keepNewest(query.Id);
			Assert.areEqual(
				1,
				[SELECT COUNT() FROM ContentDocument WHERE Id = :documents[1]],
				'On demand keeps every file'
			);
		}
	}
}
