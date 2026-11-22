/**
 * The big object archive run (canonical model R-ARC3, R-ARC5): Copy then Settle, the originals
 * deleted only once their copies are read back, records changed since the start kept, the cap,
 * the job's counts and a failed link.
 *
 * The big object is replaced by `ArchiveStoreMemory`, and each link is run in turn by the test,
 * since an Apex test can neither write a big object nor chain queueables.
 */
@IsTest(testFor='ApexClass:BigObjectArchiveJob, ApexClass:ArchiveToBigObject, ApexClass:ArchiveRecordJson')
private class ArchiveJobTest {
	@TestSetup
	// runs-as: deploying user (creates the test users themselves)
	static void createUsers() {
		TestUsers.admin();
		archivist();
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

	private static User archivist() {
		return TestUsers.withPermissionSets(new List<String>{ TestUsers.CORE_ADMIN, 'BarnCRM_Bulk_Delete' });
	}

	private static void makePeople(Integer howMany) {
		DataProtectedFields.targetsOverride = new Map<String, Set<String>>();
		List<Contact> people = new List<Contact>{
			TestDataFactory.person(new Contact(LastName = 'Staff Person', Title = 'Staff'))
		};
		for (Integer index = 0; index < howMany; index++) {
			people.add(TestDataFactory.person(new Contact(LastName = 'Archived ' + index, Title = 'Volunteer')));
		}
		insert people;
	}

	/** Runs every queued link until the chain ends; returns how many ran. */
	private static Integer drain() {
		Integer ran = 0;
		while (!BigObjectArchiveJob.queuedForTest.isEmpty()) {
			Queueable next = (Queueable) BigObjectArchiveJob.queuedForTest.remove(0);
			next.execute(null);
			ran++;
			System.Assert.isTrue(ran < 50, 'The chain ends');
		}
		return ran;
	}

	private static Import_Batch__c reread(Id jobId) {
		return [
			SELECT Status__c, Rows_Deleted__c, Rows_Rejected__c, Run_Log__c, Operation__c
			FROM Import_Batch__c
			WHERE Id = :jobId
			WITH SYSTEM_MODE
		];
	}

	@IsTest
	static void copiesThenDeletesTheOriginals() {
		System.runAs(TestUsers.admin()) {
			makePeople(3);
		}
		ArchiveStoreMemory store = ArchiveStoreMemory.install();
		BigObjectArchiveJob.queuedForTest = new List<Object>();
		Import_Batch__c job;
		System.runAs(archivist()) {
			job = ArchiveDestinations.forKey(ArchiveRules.BIG_OBJECT)
				.start(new ArchiveRun(null, 'Old Volunteers', VOLUNTEERS, 'Contact', 3));
			System.Assert.areEqual(4, [SELECT COUNT() FROM Contact WITH SYSTEM_MODE], 'Nothing deleted at start');
			drain();
		}
		System.Assert.areEqual(1, [SELECT COUNT() FROM Contact WITH SYSTEM_MODE], 'The three volunteers went');
		System.Assert.areEqual(3, store.rowsByKey.size(), 'Three rows archived');
		Archived_Record__b row = store.rowsByKey.values()[0];
		System.Assert.areEqual('Contact', row.Object_Name__c, 'Keyed by object');
		System.Assert.isTrue(row.Record_JSON__c.contains('"LastName"'), 'Every readable field: ' + row.Record_JSON__c);
		System.Assert.isTrue(ArchiveRecordJson.names(row.Person_Ids__c, row.Original_Id__c), 'A contact names itself');
		System.Assert.areEqual('Old Volunteers', row.Rule_Name__c, 'The rule that archived it');
		job = reread(job.Id);
		System.Assert.areEqual(ImportBatchService.STATUS_COMPLETE, job.Status__c, 'Complete: ' + job.Run_Log__c);
		System.Assert.areEqual(3, job.Rows_Deleted__c, 'Counts the originals deleted');
		System.Assert.areEqual(BigObjectArchiveJob.OPERATION_ARCHIVE, job.Operation__c, 'An Archive job');
		System.Assert.areEqual(3, BigObjectArchiveJob.archivedCount(), 'The count kept');
	}

	@IsTest
	static void keepsRecordsChangedSinceTheStartAndRowsNotSaved() {
		System.runAs(TestUsers.admin()) {
			makePeople(2);
		}
		ArchiveStoreMemory store = ArchiveStoreMemory.install();
		BigObjectArchiveJob.queuedForTest = new List<Object>();
		Import_Batch__c job;
		System.runAs(archivist()) {
			job = ArchiveDestinations.forKey(ArchiveRules.BIG_OBJECT)
				.start(new ArchiveRun(null, 'Old Volunteers', VOLUNTEERS, 'Contact', 2));
			// The run started before the records last changed.
			BigObjectArchiveJob first = (BigObjectArchiveJob) BigObjectArchiveJob.queuedForTest.remove(0);
			BigObjectArchiveJob.queuedForTest.add(
				new BigObjectArchiveJob(
					job.Id,
					new ArchiveRun(null, 'Old Volunteers', VOLUNTEERS, 'Contact', 2),
					Datetime.now().addDays(-1)
				)
			);
			System.Assert.isNotNull(first, 'The start queued the first Copy');
			drain();
		}
		System.Assert.areEqual(3, [SELECT COUNT() FROM Contact WITH SYSTEM_MODE], 'Nothing deleted');
		System.Assert.areEqual(0, store.rowsByKey.size(), 'Nothing archived');
		job = reread(job.Id);
		System.Assert.areEqual(2, job.Rows_Rejected__c, 'Both named as left out: ' + job.Run_Log__c);
		System.Assert.areEqual(0, BigObjectArchiveJob.archivedCount(), 'Nothing counted');

		// A copy that is not there when read back is never deleted.
		List<Contact> archived = [SELECT Id FROM Contact WHERE Title = 'Volunteer' WITH SYSTEM_MODE];
		for (Contact volunteer : archived) {
			store.lostOnInsert.add(String.valueOf(volunteer.Id));
		}
		System.runAs(archivist()) {
			job = ArchiveDestinations.forKey(ArchiveRules.BIG_OBJECT)
				.start(new ArchiveRun(null, 'Old Volunteers', VOLUNTEERS, 'Contact', 2));
			drain();
		}
		System.Assert.areEqual(3, [SELECT COUNT() FROM Contact WITH SYSTEM_MODE], 'Still nothing deleted');
		System.Assert.areEqual(2, reread(job.Id).Rows_Rejected__c, 'Both named as not saved');
	}

	@IsTest
	static void stopsAtTheCap() {
		System.runAs(TestUsers.admin()) {
			makePeople(2);
			BigObjectArchiveJob.addToCount(BigObjectArchiveJob.CAP - 1);
		}
		ArchiveStoreMemory.install();
		BigObjectArchiveJob.queuedForTest = new List<Object>();
		Import_Batch__c job;
		System.runAs(archivist()) {
			job = ArchiveDestinations.forKey(ArchiveRules.BIG_OBJECT)
				.start(new ArchiveRun(null, 'Old Volunteers', VOLUNTEERS, 'Contact', 2));
			drain();
			System.Assert.isNull(
				new ArchiveToBigObject().unavailableReason(),
				'Below the cap the destination is usable'
			);
		}
		job = reread(job.Id);
		System.Assert.areEqual(ImportBatchService.STATUS_FAILED, job.Status__c, 'Stopped');
		System.Assert.areEqual(3, [SELECT COUNT() FROM Contact WITH SYSTEM_MODE], 'Nothing deleted');
		System.runAs(TestUsers.admin()) {
			BigObjectArchiveJob.addToCount(1);
		}
		System.runAs(archivist()) {
			System.Assert.isNotNull(new ArchiveToBigObject().unavailableReason(), 'At the cap it is refused');
		}
	}

	@IsTest
	static void failureMarksTheJobFailed() {
		Import_Batch__c job;
		System.runAs(archivist()) {
			job = new Import_Batch__c(
				Operation__c = BigObjectArchiveJob.OPERATION_ARCHIVE,
				Status__c = ImportBatchService.STATUS_COMMITTING,
				Run_Log__c = 'Started',
				Started_At__c = Datetime.now(),
				Committed_By__c = UserInfo.getUserId()
			);
			insert as system job;
			new BigObjectArchiveJob.Finisher(job.Id).execute(null);
			System.Assert.areEqual(
				ImportBatchService.STATUS_COMMITTING,
				reread(job.Id).Status__c,
				'No context, no change'
			);
			BigObjectArchiveJob.fail(job.Id, 'Because');
		}
		job = reread(job.Id);
		System.Assert.areEqual(ImportBatchService.STATUS_FAILED, job.Status__c, 'Failed');
		System.Assert.isTrue(job.Run_Log__c.endsWith('Because'), 'With the reason');
	}
}
