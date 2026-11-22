/**
 * The off-platform destination seam (canonical model R-SQ17): the choice offered only while a
 * module provides a destination, a run's parts sent one per execute, what was sent and what waits
 * kept on the job, the Files copy removed only when asked, waiting parts sent again by the nightly
 * step, and an archive deleting only after every part was sent. The destination is a stand-in;
 * the Connector's own tests cover its callout. These tests have not been executed: no org in this
 * environment.
 */
@IsTest(testFor='ApexClass:OffPlatformSendBatch, ApexClass:BackupSetService, ApexClass:BulkDeleteService')
private class OffPlatformSendBatchTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	/** Stands in for a module's destination: answers with `failure`, keeps what it was sent. */
	private class FakeDestination implements OffPlatformDestination {
		String failure;
		List<String> names = new List<String>();
		public String key() {
			return OffPlatformSendBatch.OFF_PLATFORM;
		}
		public String notReady() {
			return null;
		}
		public String send(String fileName, Blob body) {
			names.add(fileName);
			return failure;
		}
	}

	private static FakeDestination install(String failure) {
		FakeDestination fake = new FakeDestination();
		fake.failure = failure;
		ModuleExtensions.stubForTest(OffPlatformDestination.class, 'Connector', fake, true);
		return fake;
	}

	private static void noneInstalled() {
		ModuleExtensions.stubForTest(OffPlatformDestination.class, 'Connector', null, true);
	}

	/** A complete Backup run with one part in Files, sent off platform. */
	private static Import_Batch__c backupRun(Id documentId) {
		Import_Batch__c job = new Import_Batch__c(
			Operation__c = 'Backup',
			Status__c = ImportBatchService.STATUS_COMPLETE,
			Started_At__c = Datetime.now(),
			File_Id__c = documentId,
			File_Name__c = 'Contact-run-part-1',
			Run_Log__c = 'Saved.',
			Operation_JSON__c = JSON.serialize(
				new Map<String, Object>{
					'version' => 1,
					'destination' => 'offPlatform',
					'documents' => new List<Id>{ documentId },
					'offPlatform' => new Map<String, Object>{
						'state' => 'sending',
						'sent' => new List<Object>(),
						'waiting' => new List<Id>{ documentId }
					}
				}
			)
		);
		insert job;
		return job;
	}

	private static Id part() {
		ContentVersion version = new ContentVersion(
			Title = 'Contact-run-part-1',
			PathOnClient = 'run.csv',
			VersionData = Blob.valueOf('Id\r\n003000000000001\r\n')
		);
		insert version;
		return [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :version.Id].ContentDocumentId;
	}

	private static Map<String, Object> stateOf(Id jobId) {
		Map<String, Object> definition = (Map<String, Object>) JSON.deserializeUntyped(
			[SELECT Operation_JSON__c FROM Import_Batch__c WHERE Id = :jobId].Operation_JSON__c
		);
		return (Map<String, Object>) definition.get('offPlatform');
	}

	@IsTest
	static void withoutADestinationTheChoiceIsRefusedAndANoteSaysWhy() {
		System.runAs(TestUsers.admin()) {
			noneInstalled();
			OffPlatformSendBatch.Status status = OffPlatformSendBatch.status();
			Assert.isFalse(status.available, 'Nothing installed');
			Assert.areEqual(BarnHelp.text('Core', 'Core_OffPlatform_NotInstalled'), status.note);
			Saved_Query__c query = new Saved_Query__c(
				Name = 'Volunteers',
				Object_Name__c = 'Contact',
				Query_JSON__c = BackupSetService.marked('{"version":1,"object":"Contact","fields":["LastName"]}')
			);
			insert query;
			try {
				BackupSetController.setSchedule(query.Id, 'daily', null, null, 'offPlatform');
				Assert.fail('Refused');
			} catch (AuraHandledException refused) {
				Assert.areEqual(BarnHelp.text('Core', 'Core_OffPlatform_NotInstalled'), refused.getMessage());
			}
			try {
				BulkDeleteService.startArchive('{}', 1, null, 'offPlatform');
				Assert.fail('Refused');
			} catch (BulkDeleteService.BulkDeleteException refused) {
				Assert.areEqual(BarnHelp.text('Core', 'Core_OffPlatform_NotInstalled'), refused.getMessage());
			}

			install(null);
			BackupSetService.Panel page = BackupSetController.setSchedule(query.Id, 'daily', null, null, 'offPlatform');
			Assert.isTrue(page.destination.available, 'Offered once installed');
			Assert.areEqual('offPlatform', page.sets[0].destination, 'Saved on the set');
		}
	}

	@IsTest
	static void staffWhoBackUpSeeWhetherTheDestinationIsOffered() {
		User staff = TestUsers.standardUserWith('OffPlatformStaff', new List<String>{ 'BarnCRM_Find_And_Export' });
		System.runAs(staff) {
			noneInstalled();
			Assert.isFalse(OffPlatformSendBatch.status().available, 'Nothing installed');
			install(null);
			Assert.isTrue(OffPlatformSendBatch.status().available, 'Offered once installed');
		}
	}

	@IsTest
	static void everyPartSentIsKeptOnTheRunAndTheFilesCopyStaysByDefault() {
		System.runAs(TestUsers.admin()) {
			FakeDestination fake = install(null);
			Id documentId = part();
			Import_Batch__c job = backupRun(documentId);
			Test.startTest();
			OffPlatformSendBatch.start(job.Id, new List<Id>{ documentId }, false);
			Test.stopTest();

			Assert.areEqual(new List<String>{ 'Contact-run-part-1.csv' }, fake.names, 'The part, named as in Files');
			Assert.areEqual('sent', stateOf(job.Id).get('state'));
			Import_Batch__c after = [SELECT File_Id__c, Run_Log__c FROM Import_Batch__c WHERE Id = :job.Id];
			Assert.areEqual(documentId, after.File_Id__c, 'Files copy kept');
			Assert.isTrue(after.Run_Log__c.contains(BarnHelp.text('Core', 'Core_OffPlatform_LogSent', new List<Object>{ 1 })));
		}
	}

	@IsTest
	static void withRemoveFilesCopyOnTheSentPartsLeaveFiles() {
		System.runAs(TestUsers.admin()) {
			BarnCRM_Settings__c settings = TestDataFactory.defaultSettings();
			settings.Backup_Remove_Sent_Files__c = true;
			TestDataFactory.saveSettings(settings);
			install(null);
			Id documentId = part();
			Import_Batch__c job = backupRun(documentId);
			BackupSetService.afterSent(job.Id, new List<Id>{ documentId }, new List<Id>(), new List<String>());
			Assert.areEqual(0, [SELECT COUNT() FROM ContentDocument WHERE Id = :documentId], 'Removed from Files');
			Assert.isNull([SELECT File_Id__c FROM Import_Batch__c WHERE Id = :job.Id].File_Id__c);
		}
	}

	@IsTest
	static void aRefusedPartWaitsOnTheRunAndTheNightlyStepSendsItAgain() {
		System.runAs(TestUsers.admin()) {
			install('The storage answered 403.');
			Id documentId = part();
			Import_Batch__c job = backupRun(documentId);
			Test.startTest();
			OffPlatformSendBatch.start(job.Id, new List<Id>{ documentId }, false);
			Test.stopTest();

			Map<String, Object> state = stateOf(job.Id);
			Assert.areEqual('waiting', state.get('state'));
			Assert.areEqual(1, ((List<Object>) state.get('waiting')).size(), 'The part waits');
			Import_Batch__c after = [SELECT Run_Log__c, File_Id__c FROM Import_Batch__c WHERE Id = :job.Id];
			Assert.isTrue(after.Run_Log__c.contains('403'), 'The failure is on the run: ' + after.Run_Log__c);
			Assert.areEqual(documentId, after.File_Id__c, 'Files copy kept while a part waits');
			Assert.areEqual(1, BackupSetSchedule.resendWaiting(), 'Sent again by the nightly step');
		}
	}

	@IsTest
	static void anArchiveDeletesNothingWhenAPartWasNotSent() {
		System.runAs(TestUsers.admin()) {
			Import_Batch__c job = new Import_Batch__c(
				Operation__c = 'Delete',
				Status__c = ImportBatchService.STATUS_COMMITTING,
				Run_Log__c = 'Started.',
				Chunk_Size__c = 200
			);
			insert job;
			BulkDeleteService.afterArchiveSent(
				job.Id,
				new List<Id>(),
				new List<Id>{ part() },
				new List<String>{ 'part-1: The storage answered 500.' }
			);
			Import_Batch__c after = [SELECT Status__c, Run_Log__c, Job_Id__c FROM Import_Batch__c WHERE Id = :job.Id];
			Assert.areEqual(ImportBatchService.STATUS_FAILED, after.Status__c);
			Assert.isNull(after.Job_Id__c, 'No delete started');
			Assert.isTrue(after.Run_Log__c.contains('500'), after.Run_Log__c);
		}
	}
}
