/**
 * The big object archive run (canonical model R-ARC3, R-ARC5): Copy then Settle, the originals
 * deleted only once their copies are read back, records changed since the start kept, the cap,
 * the job's counts, a failed link, and the count settled from the rows read back (D-223).
 *
 * The big object is replaced by `ArchiveStoreMemory`, and each link is run in turn by the test,
 * since an Apex test can neither write a big object nor chain queueables.
 */
@IsTest(
	testFor='ApexClass:BigObjectArchiveJob, ApexClass:ArchiveToBigObject, ApexClass:ArchiveRecordJson, ApexClass:ArchiveCountSettle'
)
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

	/**
	 * Runs a three volunteer archive one record per Copy. After the first Copy, either the cursor
	 * is lost (`cursorGone`) or the second volunteer is deleted.
	 */
	private static Import_Batch__c archiveOneByOne(ArchiveStoreMemory store, Boolean cursorGone) {
		BigObjectArchiveJob.queuedForTest = new List<Object>();
		BigObjectArchiveJob.chunkSize = 1;
		Import_Batch__c job;
		System.runAs(archivist()) {
			job = ArchiveDestinations.forKey(ArchiveRules.BIG_OBJECT)
				.start(new ArchiveRun(null, 'Old Volunteers', VOLUNTEERS, 'Contact', 3));
			((Queueable) BigObjectArchiveJob.queuedForTest.remove(0)).execute(null);
			System.Assert.areEqual(1, store.rowsByKey.size(), 'The first Copy took one record');
			if (cursorGone) {
				BigObjectArchiveJob.cursorGoneForTest = true;
			} else {
				// Deleted after the cursor opened: a gap the run steps over.
				List<Contact> rest = [
					SELECT Id
					FROM Contact
					WHERE Title = 'Volunteer'
					WITH SYSTEM_MODE
					ORDER BY Id
				];
				Database.delete(rest[1], AccessLevel.SYSTEM_MODE);
			}
			// One record per Copy runs many links: they share the test's own limits with the
			// outer ones, as a real chain gives each link its own.
			Test.startTest();
			while (!BigObjectArchiveJob.queuedForTest.isEmpty() && Limits.getQueries() < 60) {
				((Queueable) BigObjectArchiveJob.queuedForTest.remove(0)).execute(null);
			}
			Test.stopTest();
			drain();
		}
		return reread(job.Id);
	}

	@IsTest
	static void theCursorStepsOverRecordsDeletedSinceItOpened() {
		System.runAs(TestUsers.admin()) {
			makePeople(3);
		}
		ArchiveStoreMemory store = ArchiveStoreMemory.install();
		Import_Batch__c job = archiveOneByOne(store, false);
		System.Assert.areEqual(ImportBatchService.STATUS_COMPLETE, job.Status__c, 'Complete: ' + job.Run_Log__c);
		System.Assert.areEqual(2, job.Rows_Deleted__c, 'The two still there archived');
		System.Assert.areEqual(2, store.rowsByKey.size(), 'Two rows archived');
		System.Assert.areEqual(1, [SELECT COUNT() FROM Contact WITH SYSTEM_MODE], 'Only the staff person left');
	}

	@IsTest
	static void aCursorThePlatformLetGoIsOpenedAgainWhereTheRunWas() {
		System.runAs(TestUsers.admin()) {
			makePeople(3);
		}
		ArchiveStoreMemory store = ArchiveStoreMemory.install();
		Import_Batch__c job = archiveOneByOne(store, true);
		System.Assert.isFalse(BigObjectArchiveJob.cursorGoneForTest, 'The lost cursor was met');
		System.Assert.areEqual(ImportBatchService.STATUS_COMPLETE, job.Status__c, 'Complete: ' + job.Run_Log__c);
		System.Assert.areEqual(3, job.Rows_Deleted__c, 'Each record archived once');
		System.Assert.areEqual(3, store.rowsByKey.size(), 'Three rows, none twice');
		System.Assert.areEqual(1, [SELECT COUNT() FROM Contact WITH SYSTEM_MODE], 'Only the staff person left');
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
			System.Assert.areEqual(
				BarnHelp.text(
					'Core',
					'Core_ArchiveRules_BigObjectFull',
					new List<Object>{ BigObjectArchiveJob.CAP.format() }
				),
				new ArchiveToBigObject().unavailableReason(),
				'At the cap it is refused in plain words, not as a run log line'
			);
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
			BigObjectArchiveJob.Finisher finisher = new BigObjectArchiveJob.Finisher(
				job.Id,
				BarnHelp.text('Core', 'Core_ArchiveRules_LogStopped')
			);
			finisher.execute(null);
			System.Assert.areEqual(
				ImportBatchService.STATUS_COMMITTING,
				reread(job.Id).Status__c,
				'No context, no change'
			);
			finisher.stopped('Because');
		}
		job = reread(job.Id);
		System.Assert.areEqual(ImportBatchService.STATUS_FAILED, job.Status__c, 'Failed');
		System.Assert.isTrue(
			job.Run_Log__c.endsWith(BarnHelp.text('Core', 'Core_ArchiveRules_LogStopped') + ' Because'),
			'An archive run says to run the rule again, with the reason: ' + job.Run_Log__c
		);
	}

	@IsTest
	static void aCopyThatDiesWithCopiesItCannotRemoveIsCountedAsItLeftThem() {
		System.runAs(TestUsers.admin()) {
			makePeople(2);
		}
		ArchiveStoreMemory store = ArchiveStoreMemory.install();
		BigObjectArchiveJob.queuedForTest = new List<Object>();
		Import_Batch__c job;
		System.runAs(archivist()) {
			job = ArchiveDestinations.forKey(ArchiveRules.BIG_OBJECT)
				.start(new ArchiveRun(null, 'Old Volunteers', VOLUNTEERS, 'Contact', 2));
			((Queueable) BigObjectArchiveJob.queuedForTest.remove(0)).execute(null);
			System.Assert.areEqual(2, store.rowsByKey.size(), 'The Copy saved both');
			System.Assert.areEqual(0, BigObjectArchiveJob.archivedCount(), 'Counted only once settled');
			// The link dies and its finisher cannot take the copies back.
			store.deletesRefused = 1;
			BigObjectArchiveJob.lastFinisher.stopped('Died');
			System.Assert.areEqual(
				2,
				BigObjectArchiveJob.archivedCount(),
				'Counted as they are, from the rows read back'
			);
			ArchiveCountSettle.settle(job.Id);
			System.Assert.areEqual(2, BigObjectArchiveJob.archivedCount(), 'Settling again changes nothing');
		}
		System.Assert.areEqual(ImportBatchService.STATUS_FAILED, reread(job.Id).Status__c, 'Failed');
	}

	@IsTest
	static void aSettleThatCannotQueueTheNextLinkTakesItsCopiesBack() {
		System.runAs(TestUsers.admin()) {
			makePeople(2);
		}
		ArchiveStoreMemory store = ArchiveStoreMemory.install();
		BigObjectArchiveJob.queuedForTest = new List<Object>();
		Import_Batch__c job;
		System.runAs(archivist()) {
			job = ArchiveDestinations.forKey(ArchiveRules.BIG_OBJECT)
				.start(new ArchiveRun(null, 'Old Volunteers', VOLUNTEERS, 'Contact', 2));
			((Queueable) BigObjectArchiveJob.queuedForTest.remove(0)).execute(null);
			System.Assert.areEqual(2, store.rowsByKey.size(), 'The Copy saved both');
			Queueable settle = (Queueable) BigObjectArchiveJob.queuedForTest.remove(0);
			BigObjectArchiveJob.queuedForTest = null;
			AsyncStarter.busyForTest = true;
			try {
				settle.execute(null);
				System.Assert.fail('The next link could not be queued');
			} catch (AsyncStarter.BusyException expected) {
				// The platform rolls the Settle back and runs its finisher, as below.
				BigObjectArchiveJob.lastFinisher.stopped(expected.getMessage());
			}
		}
		System.Assert.areEqual(0, store.rowsByKey.size(), 'The Settle copies deleted, never left archived and live');
		System.Assert.areEqual(ImportBatchService.STATUS_FAILED, reread(job.Id).Status__c, 'Failed');
	}

	@IsTest
	static void copiesASettleKeptAreDeletedWithOneRetryAndCountedWhenTheyStay() {
		System.runAs(TestUsers.admin()) {
			makePeople(1);
		}
		ArchiveStoreMemory store = ArchiveStoreMemory.install();
		BigObjectArchiveJob.queuedForTest = new List<Object>();
		Datetime at = Datetime.newInstance((Datetime.now().getTime() / 1000) * 1000).addDays(-1);
		store.insertRows(
			new List<Archived_Record__b>{
				new Archived_Record__b(Object_Name__c = 'Contact', Archived_At__c = at, Original_Id__c = 'kept1'),
				new Archived_Record__b(Object_Name__c = 'Contact', Archived_At__c = at, Original_Id__c = 'kept2')
			}
		);
		String left = BarnHelp.text('Core', 'Core_ArchiveRules_NoteCopiesLeft', new List<Object>{ '1' });
		Import_Batch__c job;
		System.runAs(archivist()) {
			// One refusal: the retry deletes the copy there; the one already gone is counted.
			job = ArchiveDestinations.forKey(ArchiveRules.BIG_OBJECT)
				.start(new ArchiveRun(null, 'Old Volunteers', VOLUNTEERS, 'Contact', 1));
			BigObjectArchiveJob first = (BigObjectArchiveJob) BigObjectArchiveJob.queuedForTest[0];
			first.orphans.add(new ArchiveStore.Key('Contact', at, 'kept1'));
			first.orphans.add(new ArchiveStore.Key('Contact', at, 'gone'));
			store.deletesRefused = 1;
			drain();
		}
		Import_Batch__c finished = reread(job.Id);
		System.Assert.areEqual(
			ImportBatchService.STATUS_COMPLETE,
			finished.Status__c,
			'Complete: ' + finished.Run_Log__c
		);
		System.Assert.isTrue(finished.Run_Log__c.contains(left), 'One copy counted as left: ' + finished.Run_Log__c);
		System.Assert.areEqual(1, finished.Rows_Deleted__c, 'The run went on');

		System.runAs(TestUsers.admin()) {
			makePeople(1);
		}
		// The second run gets its own limits, as a later run would.
		Test.startTest();
		System.runAs(archivist()) {
			// Refused twice: the copy stays, the log counts it, and the chain still ends.
			job = ArchiveDestinations.forKey(ArchiveRules.BIG_OBJECT)
				.start(new ArchiveRun(null, 'Old Volunteers', VOLUNTEERS, 'Contact', 1));
			((BigObjectArchiveJob) BigObjectArchiveJob.queuedForTest[0])
				.orphans.add(new ArchiveStore.Key('Contact', at, 'kept2'));
			store.deletesRefused = 2;
			drain();
		}
		Test.stopTest();
		finished = reread(job.Id);
		System.Assert.isTrue(finished.Run_Log__c.contains(left), 'Counted: ' + finished.Run_Log__c);
		Integer stayed = 0;
		for (Archived_Record__b row : store.rowsByKey.values()) {
			stayed += row.Original_Id__c.startsWith('kept') ? 1 : 0;
		}
		System.Assert.areEqual(1, stayed, 'Only the copy refused twice stays');
	}

	@IsTest
	static void aRecordGivenAChildAfterItsCopyIsKeptLiveWhole() {
		DataProtectedFields.targetsOverride = new Map<String, Set<String>>();
		Account org;
		System.runAs(TestUsers.admin()) {
			org = TestDataFactory.organization(new Account(Name = 'Kids Org Late'));
			insert org;
			insert TestDataFactory.person(new Contact(LastName = 'First Kid', AccountId = org.Id));
		}
		String orgsQuery = VOLUNTEERS.replace('"Contact"', '"Account"')
			.replace('"LastName"', '"Name"')
			.replace('"Title"', '"Name"')
			.replace('"Volunteer"', '"Kids Org Late"');
		ArchiveStoreMemory store = ArchiveStoreMemory.install();
		BigObjectArchiveJob.queuedForTest = new List<Object>();
		Import_Batch__c job;
		// An organization has many kinds of cascade-delete children, each a query per link.
		Test.startTest();
		System.runAs(archivist()) {
			job = ArchiveDestinations.forKey(ArchiveRules.BIG_OBJECT)
				.start(new ArchiveRun(null, 'Old Orgs', orgsQuery, 'Account', 1));
			BigObjectArchiveJob link = (BigObjectArchiveJob) BigObjectArchiveJob.queuedForTest.remove(0);
			link.execute(null);
			System.Assert.areEqual(1, store.rowsByKey.size(), 'The Copy saved the organization with its child');
			System.Assert.isFalse(link.copiedChildIds.isEmpty(), 'And knows the children it saved');
			// As if the child were added after the Copy: the Settle finds a child its copy does not
			// hold (a real insert could touch the organization, which the changed check catches first).
			link.copiedChildIds.clear();
			drain();
		}
		Test.stopTest();
		System.Assert.areEqual(
			1,
			[SELECT COUNT() FROM Account WHERE Id = :org.Id WITH SYSTEM_MODE],
			'The organization stays live'
		);
		System.Assert.areEqual(
			1,
			[SELECT COUNT() FROM Contact WHERE AccountId = :org.Id WITH SYSTEM_MODE],
			'Its child too'
		);
		System.Assert.isTrue(store.rowsByKey.isEmpty(), 'Its copy was removed, so it is not both live and archived');
		job = reread(job.Id);
		System.Assert.areEqual(ImportBatchService.STATUS_COMPLETE, job.Status__c, 'Complete: ' + job.Run_Log__c);
		System.Assert.areEqual(0, job.Rows_Deleted__c, 'Nothing deleted');
		System.Assert.isTrue(
			job.Run_Log__c.contains(
				BarnHelp.text('Core', 'Core_ArchiveRules_NoteChildAdded', new List<Object>{ 'Kids Org Late' })
			),
			'The log says why and that the next run takes it whole: ' + job.Run_Log__c
		);
	}

	@IsTest
	static void aChunkWhoseChildrenAreTooManyIsHalvedAndALoneParentLeftOut() {
		DataProtectedFields.targetsOverride = new Map<String, Set<String>>();
		Map<String, Integer> childrenByName = new Map<String, Integer>{
			'Kids Org A' => 2,
			'Kids Org B' => 2,
			'Kids Org C' => 6
		};
		System.runAs(TestUsers.admin()) {
			Map<String, Account> orgs = new Map<String, Account>();
			for (String name : childrenByName.keySet()) {
				orgs.put(name, TestDataFactory.organization(new Account(Name = name)));
			}
			insert orgs.values();
			List<Contact> kids = new List<Contact>();
			for (String name : childrenByName.keySet()) {
				for (Integer i = 0; i < childrenByName.get(name); i++) {
					kids.add(
						TestDataFactory.person(new Contact(LastName = name + ' ' + i, AccountId = orgs.get(name).Id))
					);
				}
			}
			insert kids;
		}
		String orgsQuery = VOLUNTEERS.replace('"Contact"', '"Account"')
			.replace('"LastName"', '"Name"')
			.replace('"Title"', '"Name"')
			.replace('"equals"', '"contains"')
			.replace('"Volunteer"', '"Kids Org"');
		ArchiveStoreMemory.install();
		BigObjectArchiveJob.queuedForTest = new List<Object>();
		// Each organization with two children fits alone; the one with six never does.
		BigObjectArchiveJob.childRows = 5;
		// An organization has many kinds of cascade-delete children, each a query per Copy, so
		// the test reads the rows of single Copies rather than running the whole chain.
		Test.startTest();
		System.runAs(archivist()) {
			ArchiveDestinations.forKey(ArchiveRules.BIG_OBJECT)
				.start(new ArchiveRun(null, 'Old Orgs', orgsQuery, 'Account', 3));
			BigObjectArchiveJob first = (BigObjectArchiveJob) BigObjectArchiveJob.queuedForTest[0];
			List<Account> page = [
				SELECT Id, Name
				FROM Account
				WHERE Name LIKE 'Kids Org%'
				WITH SYSTEM_MODE
				ORDER BY Id
			];
			List<Archived_Record__b> rows = first.rowsFor(page);
			System.Assert.areEqual(1, rows.size(), 'Halved to the first organization: ' + first.notes);
			System.Assert.areEqual(String.valueOf(page[0].Id), rows[0].Original_Id__c, 'The first one');
			System.Assert.areEqual(2, first.leftOver.size(), 'The two not reached wait for the next Copy');

			Account tooMany = page[2].Name == 'Kids Org C'
				? page[2]
				: [
						SELECT Id, Name
						FROM Account
						WHERE Name = 'Kids Org C'
						WITH SYSTEM_MODE
				  ];
			rows = first.rowsFor(new List<SObject>{ tooMany });
			System.Assert.isTrue(rows.isEmpty(), 'The organization with too many children is left out');
			System.Assert.isTrue(String.join(first.notes, ' ').contains('Kids Org C'), 'By name: ' + first.notes);
		}
		Test.stopTest();
	}
}
