/**
 * Import Files (C-70, canonical model R-FI1 to R-FI5): the record check, a load in groups with
 * its journal and counts, the refusals, the undo that keeps a changed document, and the
 * permission. These tests have not been executed: no org in this environment.
 */
@IsTest(testFor='ApexClass:FilesImportService, ApexClass:FilesImportController')
private class FilesImportServiceTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	private static FilesImportService.IncomingFile file(Integer row, Id recordId, String text) {
		FilesImportService.IncomingFile incoming = new FilesImportService.IncomingFile();
		incoming.row = row;
		incoming.recordId = recordId;
		incoming.fileName = 'letters/letter-' + row + '.txt';
		incoming.data = text == null ? null : EncodingUtil.base64Encode(Blob.valueOf(text));
		return incoming;
	}

	private static Import_Batch__c job(Id jobId) {
		return [
			SELECT
				Status__c,
				Operation__c,
				Row_Count__c,
				Rows_Created__c,
				Rows_Rejected__c,
				Rows_Deleted__c,
				Undo_Deadline__c,
				Run_Log__c
			FROM Import_Batch__c
			WHERE Id = :jobId
		];
	}

	@IsTest
	static void theCheckListsIdsThatAreNotIdsOrNameNoRecord() {
		System.runAs(TestUsers.admin()) {
			Contact person = TestDataFactory.person(new Contact(LastName = 'Smith'));
			insert person;
			Contact other = TestDataFactory.person(new Contact(LastName = 'Jones'));
			insert other;
			delete other;
			List<String> unseen = FilesImportController.check(
				new List<String>{ person.Id, other.Id, 'not an id', '' }
			);
			Assert.isFalse(unseen.contains(String.valueOf(person.Id)), 'A record the person sees.');
			Assert.isTrue(unseen.contains(String.valueOf(other.Id)), 'Deleted.');
			Assert.isTrue(unseen.contains('not an id'));
		}
	}

	@IsTest
	static void aLoadSavesEachFileLinkedToItsRecordAndJournalsIt() {
		System.runAs(TestUsers.admin()) {
			Contact person = TestDataFactory.person(new Contact(LastName = 'Smith'));
			insert person;
			Id jobId = FilesImportController.start('letters.zip', 3);
			Import_Batch__c started = job(jobId);
			Assert.areEqual(FilesImportService.OPERATION_FILES, started.Operation__c);
			Assert.areEqual(ImportBatchService.STATUS_COMMITTING, started.Status__c);
			Assert.isNotNull(started.Undo_Deadline__c);

			FilesImportService.IncomingFile titled = file(1, person.Id, 'Dear friend');
			titled.title = 'Pledge letter';
			FilesImportService.GroupResult result = FilesImportController.addFiles(
				jobId,
				new List<FilesImportService.IncomingFile>{
					titled,
					file(2, person.Id, 'Thank you'),
					file(3, person.Id, null)
				}
			);
			Assert.areEqual(2, result.saved);
			Assert.areEqual(1, result.refusals.size(), 'The empty file.');
			Assert.areEqual(3, result.refusals[0].row);

			List<ContentDocumentLink> links = [
				SELECT ContentDocument.Title
				FROM ContentDocumentLink
				WHERE LinkedEntityId = :person.Id
				ORDER BY ContentDocument.Title
			];
			Assert.areEqual(2, links.size());
			Assert.areEqual(
				'letter-2',
				links[0].ContentDocument.Title,
				'File name less extension.'
			);
			Assert.areEqual('Pledge letter', links[1].ContentDocument.Title);

			FilesImportService.JobView finished = FilesImportController.finish(jobId);
			Assert.areEqual(ImportBatchService.STATUS_COMPLETE, finished.status);
			Assert.areEqual(2, finished.saved);
			Assert.areEqual(1, finished.refused);
			Assert.isTrue(finished.canUndo);
			Assert.areEqual(
				2,
				ImportJournalService.actionCount(
					jobId,
					ImportJournalService.PHASE_COMMIT,
					ImportJournalService.ACTION_CREATED
				)
			);
			Assert.areEqual(1, FilesImportController.getJobs().size());
		}
	}

	@IsTest
	static void undoDeletesTheDocumentsAndKeepsOneChangedSince() {
		System.runAs(TestUsers.admin()) {
			Contact person = TestDataFactory.person(new Contact(LastName = 'Smith'));
			insert person;
			Id jobId = FilesImportController.start('letters.zip', 2);
			FilesImportController.addFiles(
				jobId,
				new List<FilesImportService.IncomingFile>{
					file(1, person.Id, 'One'),
					file(2, person.Id, 'Two')
				}
			);
			FilesImportController.finish(jobId);
			ContentVersion first = [
				SELECT ContentDocumentId
				FROM ContentVersion
				WHERE Title = 'letter-1'
				LIMIT 1
			];
			insert new ContentVersion(
				ContentDocumentId = first.ContentDocumentId,
				Title = 'letter-1',
				PathOnClient = 'letter-1.txt',
				VersionData = Blob.valueOf('One, revised')
			);

			try {
				FilesImportController.undo(jobId, 5);
				Assert.fail('A count other than the files saved is refused.');
			} catch (AuraHandledException refused) {
				Assert.isTrue(refused.getMessage().contains('5'));
			}

			FilesImportService.JobView undone = FilesImportController.undo(jobId, 2);
			Assert.areEqual(ImportBatchService.STATUS_UNDONE, undone.status);
			Assert.areEqual(1, undone.deleted);
			Assert.isFalse(undone.canUndo);
			Assert.areEqual(1, [SELECT COUNT() FROM ContentDocument], 'The changed one is kept.');

			try {
				FilesImportController.undo(jobId, 2);
				Assert.fail('Once only.');
			} catch (AuraHandledException refused) {
				Assert.areEqual(
					BarnHelp.text('Core', 'Core_Import_UndoErrorAlreadyUndone'),
					refused.getMessage()
				);
			}
		}
	}

	@IsTest
	static void aGroupMustBeSmallAndTheJobStillLoading() {
		System.runAs(TestUsers.admin()) {
			Contact person = TestDataFactory.person(new Contact(LastName = 'Smith'));
			insert person;
			Id jobId = FilesImportController.start('letters.zip', 25);
			List<FilesImportService.IncomingFile> tooMany = new List<FilesImportService.IncomingFile>();
			for (Integer row = 1; row <= 21; row++) {
				tooMany.add(file(row, person.Id, 'x'));
			}
			try {
				FilesImportController.addFiles(jobId, tooMany);
				Assert.fail('Twenty at most.');
			} catch (AuraHandledException refused) {
				Assert.isTrue(refused.getMessage().contains('20'));
			}
			FilesImportController.finish(jobId);
			try {
				FilesImportController.addFiles(
					jobId,
					new List<FilesImportService.IncomingFile>{ file(1, person.Id, 'x') }
				);
				Assert.fail('Finished.');
			} catch (AuraHandledException refused) {
				Assert.areEqual(
					BarnHelp.text('Core', 'Core_FilesImport_ErrorJobGone'),
					refused.getMessage()
				);
			}
			try {
				FilesImportController.start('big.zip', FilesImportService.MAX_FILES + 1);
				Assert.fail('Too many files.');
			} catch (AuraHandledException refused) {
				Assert.isTrue(refused.getMessage().length() > 0);
			}
		}
	}

	@IsTest
	static void someoneWithoutManageSettingsIsRefused() {
		User staff = TestUsers.standardUserWith(
			'FilesStaff',
			new List<String>{ 'BarnCRM_Find_And_Export' }
		);
		System.runAs(staff) {
			Assert.isNull(FilesImportController.getJobs());
			try {
				FilesImportController.start('letters.zip', 1);
				Assert.fail('Refused.');
			} catch (AuraHandledException refused) {
				Assert.areEqual(
					BarnHelp.text('Core', 'Core_FilesImport_ErrorNoPermission'),
					refused.getMessage()
				);
			}
		}
	}
}
