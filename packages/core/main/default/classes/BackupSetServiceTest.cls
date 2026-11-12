/**
 * Backup Sets (C-66, canonical model R-SQ15): marking a saved query, a run writing R-BD9's file
 * and completing its Backup job, the run list, and the refusals. These tests have not been
 * executed: no org in this environment.
 */
@IsTest(testFor='ApexClass:BackupSetService, ApexClass:BackupSetController')
private class BackupSetServiceTest {
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

	private static Saved_Query__c savedQuery() {
		DataProtectedFields.targetsOverride = new Map<String, Set<String>>();
		List<Contact> people = new List<Contact>();
		for (Integer index = 0; index < 30; index++) {
			people.add(new Contact(LastName = 'Person ' + index, Title = 'Volunteer'));
		}
		insert people;
		Saved_Query__c query = new Saved_Query__c(
			Name = 'Volunteers',
			Object_Name__c = 'Contact',
			Query_JSON__c = VOLUNTEERS
		);
		insert query;
		return query;
	}

	@IsTest
	static void aMarkedQueryIsListedAndItsRunSavesEveryRecordAndCompletesTheJob() {
		System.runAs(TestUsers.admin()) {
			Saved_Query__c query = savedQuery();
			BackupSetService.Panel page = BackupSetController.getPage();
			Assert.areEqual(0, page.sets.size(), 'Not a Backup Set yet.');
			Assert.areEqual(1, page.candidates.size(), 'Offered to add.');

			page = BackupSetController.setBackup(query.Id, true);
			Assert.areEqual(1, page.sets.size());
			Assert.areEqual(0, page.candidates.size());

			Test.startTest();
			page = BackupSetController.runNow(query.Id);
			Assert.areEqual(1, page.runs.size());
			Assert.isTrue(page.runs[0].running, 'Running until the export finishes.');
			Test.stopTest();

			Import_Batch__c job = [
				SELECT Status__c, Operation__c, Row_Count__c, File_Id__c, File_Name__c, Run_Log__c
				FROM Import_Batch__c
				WHERE Operation__c = 'Backup'
			];
			Assert.areEqual(ImportBatchService.STATUS_COMPLETE, job.Status__c, job.Run_Log__c);
			Assert.areEqual(30, job.Row_Count__c);
			Assert.isNotNull(job.File_Id__c);
			ContentVersion part = [
				SELECT VersionData
				FROM ContentVersion
				WHERE ContentDocumentId = :job.File_Id__c AND IsLatest = TRUE
			];
			String body = part.VersionData.toString();
			Assert.isTrue(body.contains('Id,'), 'API name headings, Id first: ' + body.left(80));
			Assert.isTrue(body.contains('Title'), 'Every readable field, not only the columns.');
			Assert.areEqual(
				30,
				[SELECT COUNT() FROM Contact WHERE Title = 'Volunteer'],
				'Nothing deleted.'
			);
			Assert.areEqual(
				0,
				ImportBatchSelector.selectRecent(10).size(),
				'A Backup job is not an import.'
			);
		}
	}

	@IsTest
	static void savingAgainInFindKeepsTheMarkAndRemovingItKeepsTheQuery() {
		System.runAs(TestUsers.admin()) {
			Saved_Query__c query = savedQuery();
			BackupSetService.setBackup(query.Id, true);
			FindController.saveQuery(query.Id, 'Volunteers', VOLUNTEERS, false);
			Assert.isTrue(
				BackupSetService.isBackupSet(
					[SELECT Query_JSON__c FROM Saved_Query__c WHERE Id = :query.Id].Query_JSON__c
				),
				'Find does not drop the mark.'
			);
			BackupSetService.setBackup(query.Id, false);
			Assert.isFalse(
				BackupSetService.isBackupSet(
					[SELECT Query_JSON__c FROM Saved_Query__c WHERE Id = :query.Id].Query_JSON__c
				)
			);
		}
	}

	@IsTest
	static void aQueryThatIsNotABackupSetIsNotRunAndAFailedExportFailsTheJob() {
		System.runAs(TestUsers.admin()) {
			Saved_Query__c query = savedQuery();
			try {
				BackupSetController.runNow(query.Id);
				Assert.fail('Refused.');
			} catch (AuraHandledException refused) {
				Assert.areEqual(
					BarnHelp.text('Core', 'Core_BackupSets_ErrorNotSet'),
					refused.getMessage()
				);
			}
			Import_Batch__c job = new Import_Batch__c(
				Operation__c = 'Backup',
				Status__c = ImportBatchService.STATUS_COMMITTING,
				Run_Log__c = 'Started.'
			);
			insert job;
			BackupSetService.afterExport(job.Id, true, 0, 1, null, 'Contact-x-part-1', false);
			job = [
				SELECT Status__c, File_Id__c, Run_Log__c
				FROM Import_Batch__c
				WHERE Id = :job.Id
			];
			Assert.areEqual(ImportBatchService.STATUS_FAILED, job.Status__c);
			Assert.isNull(job.File_Id__c);
			Assert.isTrue(
				job.Run_Log__c.contains(BarnHelp.text('Core', 'Core_BackupSets_LogFailed'))
			);
		}
	}

	@IsTest
	static void someoneWithoutManageSettingsIsRefused() {
		User staff = TestUsers.standardUserWith(
			'BackupStaff',
			new List<String>{ 'BarnCRM_Find_And_Export' }
		);
		System.runAs(staff) {
			Assert.isFalse(BackupSetService.allowed());
			try {
				BackupSetController.getPage();
				Assert.fail('Refused.');
			} catch (AuraHandledException refused) {
				Assert.areEqual(
					BarnHelp.text('Core', 'Core_BackupSets_ErrorNoPermission'),
					refused.getMessage()
				);
			}
		}
	}

	@IsTest
	static void theRunListIsForSomeoneWhoMayUseBackupSetsAndNullForAnyoneElse() {
		User staff = TestUsers.standardUserWith(
			'BackupRunsStaff',
			new List<String>{ 'BarnCRM_Find_And_Export' }
		);
		System.runAs(TestUsers.admin()) {
			Saved_Query__c query = savedQuery();
			BackupSetController.setBackup(query.Id, true);
			Test.startTest();
			BackupSetController.runNow(query.Id);
			Test.stopTest();

			List<BackupSetService.RunView> runs = BackupSetController.getRuns();
			Assert.isNotNull(runs, 'An admin sees the runs');
			Assert.areEqual(1, runs.size(), 'The one run');
			Assert.isFalse(runs[0].running, 'It finished');
		}
		System.runAs(staff) {
			Assert.isNull(BackupSetController.getRuns(), 'No list for someone who may not use it');
		}
	}

	@IsTest
	static void aQueryThatIsNotThereIsRefusedWithAMessage() {
		System.runAs(TestUsers.admin()) {
			Id missing =
				Saved_Query__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
					.getKeyPrefix() + '000000000001';
			try {
				BackupSetController.setBackup(missing, true);
				Assert.fail('Nothing to mark');
			} catch (AuraHandledException refused) {
				Assert.isTrue(String.isNotBlank(refused.getMessage()), 'Told why');
			}
			try {
				BackupSetController.runNow(missing);
				Assert.fail('Nothing to run');
			} catch (AuraHandledException refused) {
				Assert.isTrue(String.isNotBlank(refused.getMessage()), 'Told why');
			}
		}
	}

	@IsTest
	static void someoneWithoutManageSettingsCannotMarkOrRunAQuery() {
		User staff = TestUsers.standardUserWith(
			'BackupNoManage',
			new List<String>{ 'BarnCRM_Find_And_Export' }
		);
		System.runAs(staff) {
			try {
				BackupSetController.setBackup(null, true);
				Assert.fail('Refused');
			} catch (AuraHandledException refused) {
				Assert.areEqual(
					BarnHelp.text('Core', 'Core_BackupSets_ErrorNoPermission'),
					refused.getMessage()
				);
			}
			try {
				BackupSetController.runNow(null);
				Assert.fail('Refused');
			} catch (AuraHandledException refused) {
				Assert.areEqual(
					BarnHelp.text('Core', 'Core_BackupSets_ErrorNoPermission'),
					refused.getMessage()
				);
			}
		}
	}
}
