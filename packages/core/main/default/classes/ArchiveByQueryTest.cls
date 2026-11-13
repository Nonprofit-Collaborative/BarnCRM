/**
 * Archive by Query (C-67, canonical model R-BD9): the records saved to Files first, every
 * readable field headed by API name; the delete only of records not changed since the file was
 * started; the Recycle Bin emptied only after the second typed count, and then no undo; and
 * nothing deleted when the file was not saved.
 *
 * A test runs one queued job at Test.stopTest, so the export and the delete it starts from its
 * finish are tested apart: the delete runs on a job made with the same definition.
 */
@IsTest(
	testFor='ApexClass:BulkDeleteService, ApexClass:BulkDeleteBatch, ApexClass:FindExportBatch, ApexClass:BulkDeleteController'
)
private class ArchiveByQueryTest {
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

	/** `volunteers` contacts titled Volunteer and one titled Staff. */
	private static void makePeople(Integer volunteers) {
		DataProtectedFields.targetsOverride = new Map<String, Set<String>>();
		List<Contact> people = new List<Contact>{
			TestDataFactory.person(new Contact(LastName = 'Staff Person', Title = 'Staff'))
		};
		for (Integer index = 0; index < volunteers; index++) {
			people.add(
				TestDataFactory.person(
					new Contact(LastName = 'Archived ' + index, Title = 'Volunteer')
				)
			);
		}
		insert people;
	}

	private static User deleter() {
		return TestUsers.withPermissionSets(
			new List<String>{ TestUsers.CORE_ADMIN, 'BarnCRM_Bulk_Delete' }
		);
	}

	private static Import_Batch__c reread(Id jobId) {
		return [
			SELECT Status__c, Operation_JSON__c, Rows_Deleted__c, Run_Log__c, Job_Id__c
			FROM Import_Batch__c
			WHERE Id = :jobId
			WITH SYSTEM_MODE
		];
	}

	/** A bulk delete job with an archive's definition, as the export's finish leaves it. */
	private static Import_Batch__c archiveJob(Datetime notChangedAfter, Boolean emptyBin) {
		BulkDeleteService.Plan checked = BulkDeleteService.plan(VOLUNTEERS);
		checked.notChangedAfter = notChangedAfter;
		checked.emptyRecycleBin = emptyBin;
		return BulkDeleteService.createJob(checked, 3, 3);
	}

	@IsTest
	static void savesEveryReadableFieldToFilesBeforeDeleting() {
		System.runAs(TestUsers.admin()) {
			makePeople(3);
			Import_Batch__c job;
			Test.startTest();
			System.runAs(deleter()) {
				job = BulkDeleteService.startArchive(VOLUNTEERS, 3, null);
				System.Assert.isNotNull(job.Job_Id__c, 'The export is the job until the delete');
				System.Assert.areEqual(
					4,
					[SELECT COUNT() FROM Contact],
					'Nothing is deleted before the file is saved'
				);
			}
			Test.stopTest();

			job = reread(job.Id);
			// The file is the deleter's: a file is read by those it is shared with, even in system mode.
			ContentVersion file;
			System.runAs(deleter()) {
				file = [
					SELECT Title, VersionData
					FROM ContentVersion
					WHERE Title LIKE 'Contact-%-part-1'
					WITH SYSTEM_MODE
					LIMIT 1
				];
			}
			List<String> lines = file.VersionData.toString().split('\r\n');
			System.Assert.areEqual(4, lines.size(), 'A heading row and the three records');
			List<String> heading = lines[0].substring(1).split(',');
			System.Assert.areEqual('Id', heading[0], 'Id first');
			System.Assert.isTrue(heading.contains('LastName'), 'Headed by API name: ' + lines[0]);
			System.Assert.isTrue(heading.contains('Title'), 'Every readable field, not the query');
			System.Assert.isFalse(
				file.VersionData.toString().contains('Staff Person'),
				'Only the matching records'
			);
			System.Assert.isTrue(
				job.Run_Log__c.contains(file.Title),
				'The run log names the file: ' + job.Run_Log__c
			);
			System.Assert.isTrue(
				job.Operation_JSON__c.contains('"notChangedAfter"'),
				'The delete keeps only records not changed since the file started'
			);
		}
	}

	@IsTest
	static void deletesOnlyRecordsNotChangedSinceTheFileStarted() {
		System.runAs(TestUsers.admin()) {
			makePeople(3);
			Import_Batch__c kept;
			System.runAs(deleter()) {
				kept = archiveJob(Datetime.now().addDays(-1), false);
			}
			Test.startTest();
			System.runAs(deleter()) {
				BulkDeleteService.afterArchiveExport(kept.Id, false, 3, 'Contact-file-part-1');
			}
			Test.stopTest();
			kept = reread(kept.Id);

			System.Assert.areEqual(0, kept.Rows_Deleted__c, kept.Run_Log__c);
			System.Assert.areEqual(
				4,
				[SELECT COUNT() FROM Contact],
				'Every record changed after the file started is left alone'
			);
		}
	}

	@IsTest
	static void emptiesTheRecycleBinOnlyWhenAskedAndThenRefusesUndo() {
		System.runAs(TestUsers.admin()) {
			makePeople(3);
			Import_Batch__c job;
			System.runAs(deleter()) {
				job = archiveJob(Datetime.now().addMinutes(5), true);
			}
			Test.startTest();
			System.runAs(deleter()) {
				BulkDeleteService.afterArchiveExport(job.Id, false, 3, 'Contact-file-part-1');
			}
			Test.stopTest();
			job = reread(job.Id);

			System.Assert.areEqual(3, job.Rows_Deleted__c, job.Run_Log__c);
			// In a test an emptied record still answers ALL ROWS, so emptied is proved by the
			// deleter no longer being able to undelete any of them.
			System.runAs(deleter()) {
				List<Contact> binned = [SELECT Id FROM Contact WHERE IsDeleted = TRUE ALL ROWS];
				System.Assert.areEqual(3, binned.size(), 'The three deleted records');
				for (Database.UndeleteResult result : Database.undelete(binned, false)) {
					System.Assert.isFalse(result.isSuccess(), 'Emptied from the Recycle Bin');
				}
			}
			System.Assert.isTrue(
				job.Run_Log__c.contains(
					String.format(
						BarnHelp.text('Core', 'Core_Archive_LogEmptied'),
						new List<Object>{ '3', '0' }
					)
				),
				job.Run_Log__c
			);
			System.runAs(deleter()) {
				BulkDeleteService.UndoPreview undo = BulkDeleteService.undoPreview(job.Id);
				System.Assert.isFalse(undo.allowed, 'Nothing left to undelete');
				System.Assert.areEqual(
					BarnHelp.text('Core', 'Core_Archive_UndoEmptied'),
					undo.reason
				);
			}
		}
	}

	@IsTest
	static void deletesNothingWhenTheFileWasNotSaved() {
		System.runAs(TestUsers.admin()) {
			makePeople(3);
			Import_Batch__c job;
			System.runAs(deleter()) {
				job = archiveJob(Datetime.now().addMinutes(5), false);
			}
			Test.startTest();
			System.runAs(deleter()) {
				BulkDeleteService.afterArchiveExport(job.Id, true, 2, 'Contact-file-part-1');
			}
			Test.stopTest();
			job = reread(job.Id);

			System.Assert.areEqual(ImportBatchService.STATUS_FAILED, job.Status__c);
			System.Assert.isTrue(
				job.Run_Log__c.contains(BarnHelp.text('Core', 'Core_Archive_LogNoFile')),
				job.Run_Log__c
			);
			System.Assert.areEqual(4, [SELECT COUNT() FROM Contact], 'Nothing deleted');
		}
	}

	@IsTest
	static void refusesAnEmptyRequestWithoutTheSameSecondCount() {
		System.runAs(TestUsers.admin()) {
			makePeople(3);
			Test.startTest();
			System.runAs(deleter()) {
				try {
					BulkDeleteController.startArchive(VOLUNTEERS, 3, 2);
					System.Assert.fail('A different second count must be refused');
				} catch (AuraHandledException refused) {
					System.Assert.areEqual(
						BarnHelp.text('Core', 'Core_Archive_ErrorEmptyConfirm'),
						refused.getMessage()
					);
				}
			}
			System.runAs(TestUsers.withPermissionSets(new List<String>{ TestUsers.CORE_ADMIN })) {
				try {
					BulkDeleteController.startArchive(VOLUNTEERS, 3, null);
					System.Assert.fail('Archive needs Bulk Delete Records');
				} catch (AuraHandledException refused) {
					System.Assert.isNotNull(refused.getMessage());
				}
			}
			Test.stopTest();
			System.Assert.areEqual(0, [SELECT COUNT() FROM Import_Batch__c], 'No job started');
			System.Assert.areEqual(4, [SELECT COUNT() FROM Contact]);
		}
	}
}
