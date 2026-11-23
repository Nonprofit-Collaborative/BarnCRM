/**
 * The Archived Records panel and restore (canonical model R-ARC1, R-ARC4, R-ARC7): objects, pages
 * and a row's fields read through the store, and the restore chain: records created again with
 * new Ids, lookups to records gone left out, children re-parented, a row whose record or child
 * could not be created kept archived, the rows removed and the count lowered.
 *
 * The big object is replaced by `ArchiveStoreMemory`, and each link is run in turn by the test,
 * since an Apex test can neither read or write a big object nor chain queueables.
 */
@IsTest(
	testFor='ApexClass:ArchiveViewerService, ApexClass:ArchiveRestoreJob, ApexClass:ArchiveController, ApexClass:DataManagerController'
)
private class ArchiveViewerTest {
	@TestSetup
	// runs-as: deploying user (creates the test users themselves)
	static void createUsers() {
		TestUsers.admin();
		archivist();
	}

	/**
	 * BarnCRM Archive Admin (D-223, ADR-0240 amendment AR-14): someone who is not a BarnCRM Admin
	 * sees archived records only with it, and with BarnCRM Bulk Delete may run rules and restore.
	 */
	@IsTest
	static void archiveAdminOpensTheArchiveAndOthersAreRefused() {
		ArchiveStoreMemory.install();
		User staff = TestUsers.standardUserWith(
			'Archive Staff',
			new List<String>{ 'BarnCRM_Staff', 'BarnCRM_Bulk_Delete' }
		);
		User keeper = TestUsers.standardUserWith(
			'Archive Keeper',
			new List<String>{ 'BarnCRM_Staff', 'BarnCRM_Bulk_Delete', 'BarnCRM_Archive_Admin' }
		);
		User viewer = TestUsers.standardUserWith(
			'Archive Viewer',
			new List<String>{ 'BarnCRM_Staff', 'BarnCRM_Archive_Admin' }
		);
		System.runAs(staff) {
			System.Assert.isFalse(ArchiveViewerService.allowed(), 'Bulk Delete alone does not open the archive');
			System.Assert.isFalse(ArchiveRuleService.allowed(), 'Nor archive rules');
			try {
				ArchiveViewerService.open();
				System.Assert.fail('Refused');
			} catch (ArchiveRules.ArchiveRuleException refused) {
				System.Assert.isTrue(refused.getMessage().contains('Archive Admin'), refused.getMessage());
			}
		}
		System.runAs(keeper) {
			System.Assert.isTrue(ArchiveViewerService.allowed(), 'Archive Admin opens the archive');
			System.Assert.isTrue(ArchiveRuleService.allowed(), 'With Bulk Delete, archive rules too');
			ArchiveViewerService.Viewer opened = ArchiveViewerService.open();
			System.Assert.isTrue(opened.canRestore, 'And restore');
		}
		System.runAs(viewer) {
			System.Assert.isTrue(ArchiveViewerService.allowed(), 'Archive Admin alone views');
			System.Assert.isFalse(ArchiveViewerService.canRestore(), 'Restoring also needs Bulk Delete');
		}
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
			SELECT Status__c, Rows_Created__c, Rows_Deleted__c, Rows_Rejected__c, Run_Log__c, Operation_JSON__c
			FROM Import_Batch__c
			WHERE Id = :jobId
			WITH SYSTEM_MODE
		];
	}

	/** Archives two volunteers who report to a staff person, then deletes the staff person. */
	private static ArchiveStoreMemory archiveVolunteers() {
		Contact staff;
		System.runAs(TestUsers.admin()) {
			DataProtectedFields.targetsOverride = new Map<String, Set<String>>();
			BigObjectArchiveJob.childObjectsForTest = new Set<String>{ 'Contact' };
			staff = TestDataFactory.person(new Contact(LastName = 'Staff Person', Title = 'Staff'));
			insert staff;
			insert new List<Contact>{
				TestDataFactory.person(
					new Contact(LastName = 'Archived One', Title = 'Volunteer', ReportsToId = staff.Id)
				),
				TestDataFactory.person(new Contact(LastName = 'Archived Two', Title = 'Volunteer'))
			};
		}
		ArchiveStoreMemory store = ArchiveStoreMemory.install();
		BigObjectArchiveJob.queuedForTest = new List<Object>();
		System.runAs(archivist()) {
			ArchiveDestinations.forKey(ArchiveRules.BIG_OBJECT)
				.start(new ArchiveRun(null, 'Old Volunteers', VOLUNTEERS, 'Contact', 2));
			drain();
		}
		System.runAs(TestUsers.admin()) {
			delete staff;
		}
		System.Assert.areEqual(2, store.rowsByKey.size(), 'Two rows archived');
		return store;
	}

	@IsTest
	static void listsObjectsPagesAndShowsARowsFields() {
		archiveVolunteers();
		System.runAs(archivist()) {
			ArchiveViewerService.Viewer viewer = ArchiveController.getArchive();
			System.Assert.areEqual(1, viewer.objects.size(), 'One archived object');
			System.Assert.areEqual('Contact', viewer.objects[0].name, 'By API name');
			System.Assert.areEqual(2, viewer.archivedCount, 'The count kept by the archive');
			System.Assert.isTrue(viewer.canRestore, 'An archivist may restore');
			System.Assert.isTrue(ArchiveController.canViewArchive(), 'The grant');
			System.Assert.areEqual('c__panel', DataManagerController.panelStateKey(), 'The page state key');

			ArchiveViewerService.RowPage first = ArchiveController.getArchivedRows('Contact', null, null, null);
			System.Assert.areEqual(2, first.rows.size(), 'Both rows');
			System.Assert.isFalse(first.more, 'Nothing more');
			System.Assert.areEqual('Old Volunteers', first.rows[0].ruleName, 'The rule');

			ArchiveViewerService.RowPage after = ArchiveController.getArchivedRows(
				'Contact',
				Date.today().addDays(-1),
				Date.today(),
				first.rows[0].id
			);
			System.Assert.areEqual(1, after.rows.size(), 'The page after the first row');
			System.Assert.areEqual(
				0,
				ArchiveController.getArchivedRows('Contact', Date.today().addDays(-9), Date.today().addDays(-8), null)
					.rows.size(),
				'Nothing archived in an earlier range'
			);

			ArchiveViewerService.Detail detail = ArchiveController.getArchivedRow('Contact', first.rows[0].id);
			Set<String> names = new Set<String>();
			for (ArchiveViewerService.FieldValue field : detail.fields) {
				names.add(field.name);
			}
			System.Assert.isTrue(names.contains('LastName'), 'Every readable field: ' + names);
		}
	}

	@IsTest
	static void refusesBadInputAndPeopleWithoutTheGrant() {
		ArchiveStoreMemory.install();
		User outsider = TestUsers.standardUser('Archive Outsider');
		System.runAs(outsider) {
			System.Assert.isFalse(ArchiveViewerService.allowed(), 'No grant');
			try {
				ArchiveViewerService.open();
				System.Assert.fail('Refused');
			} catch (ArchiveRules.ArchiveRuleException refused) {
				System.Assert.isTrue(refused.getMessage().contains('BarnCRM Admin'), refused.getMessage());
			}
		}
		System.runAs(TestUsers.admin()) {
			System.Assert.isFalse(ArchiveViewerService.canRestore(), 'Restoring also needs Bulk Delete Records');
			try {
				ArchiveViewerService.restore('Contact', new List<String>{ '1|003' });
				System.Assert.fail('Refused');
			} catch (ArchiveRules.ArchiveRuleException refused) {
				System.Assert.isNotNull(refused.getMessage(), 'Says why');
			}
		}
		System.runAs(archivist()) {
			for (String bad : new List<String>{ null, 'x|003', '123' }) {
				try {
					ArchiveViewerService.keyOf('Contact', bad);
					System.Assert.fail('Not a key: ' + bad);
				} catch (ArchiveRules.ArchiveRuleException refused) {
					System.Assert.isNotNull(refused.getMessage(), 'Says why');
				}
			}
			try {
				ArchiveViewerService.rows('', null, null, null);
				System.Assert.fail('An object first');
			} catch (ArchiveRules.ArchiveRuleException refused) {
				System.Assert.isNotNull(refused.getMessage(), 'Says why');
			}
			try {
				ArchiveViewerService.restore('Contact', new List<String>());
				System.Assert.fail('At least one row');
			} catch (ArchiveRules.ArchiveRuleException refused) {
				System.Assert.isNotNull(refused.getMessage(), 'Says why');
			}
			try {
				ArchiveViewerService.detail('Contact', '1000|003000000000001');
				System.Assert.fail('Gone');
			} catch (ArchiveRules.ArchiveRuleException refused) {
				System.Assert.isNotNull(refused.getMessage(), 'Says why');
			}
			System.Assert.areEqual(
				'Not_An_Object__x',
				ArchiveViewerService.labelOf('Not_An_Object__x'),
				'Name when gone'
			);
		}
	}

	@IsTest
	static void restoresWithNewIdsLeavesOutGoneLookupsAndRemovesTheRows() {
		ArchiveStoreMemory store = archiveVolunteers();
		Id jobId;
		System.runAs(archivist()) {
			List<String> rowIds = new List<String>();
			for (ArchiveViewerService.Row row : ArchiveViewerService.rows('Contact', null, null, null).rows) {
				rowIds.add(row.id);
			}
			jobId = ArchiveController.restoreArchivedRows('Contact', rowIds);
			drain();
		}
		List<Contact> back = [
			SELECT Id, LastName, ReportsToId
			FROM Contact
			WHERE Title = 'Volunteer'
			WITH SYSTEM_MODE
		];
		System.Assert.areEqual(2, back.size(), 'Both volunteers back');
		for (Contact one : back) {
			System.Assert.isNull(one.ReportsToId, 'The lookup to a deleted record is left out');
		}
		System.Assert.areEqual(0, store.rowsByKey.size(), 'Their rows removed');
		System.Assert.areEqual(0, BigObjectArchiveJob.archivedCount(), 'The count lowered');
		Import_Batch__c job = reread(jobId);
		System.Assert.areEqual(ImportBatchService.STATUS_COMPLETE, job.Status__c, 'Complete: ' + job.Run_Log__c);
		System.Assert.areEqual(2, job.Rows_Created__c, 'Two created');
		System.Assert.areEqual(2, job.Rows_Deleted__c, 'Two removed from the archive');
		System.Assert.isTrue(
			job.Run_Log__c.contains(String.valueOf(back[0].Id)),
			'The new Id logged: ' + job.Run_Log__c
		);
		System.Assert.isTrue(job.Run_Log__c.contains('ReportsToId'), 'What was left out logged');
		System.Assert.isTrue(job.Operation_JSON__c.contains('"restore"'), 'A restore');
		System.runAs(archivist()) {
			System.Assert.areEqual(2, ArchiveRuleService.runs().size(), 'The run and the restore both listed');
		}
	}

	@IsTest
	static void aRemoveThatDiesIsCountedByItsFinisherOrTheNightlySweep() {
		ArchiveStoreMemory store = archiveVolunteers();
		System.Assert.areEqual(2, BigObjectArchiveJob.archivedCount(), 'Two counted');
		String stopped = BarnHelp.text('Core', 'Core_ArchiveViewer_LogRemoveStopped');
		List<Id> jobIds = new List<Id>();
		System.runAs(archivist()) {
			List<String> rowIds = new List<String>();
			for (ArchiveViewerService.Row row : ArchiveViewerService.rows('Contact', null, null, null).rows) {
				rowIds.add(row.id);
			}
			// Two restores of one row each; each chain dies right after its Remove deleted the row.
			for (String rowId : rowIds) {
				jobIds.add(ArchiveController.restoreArchivedRows('Contact', new List<String>{ rowId }));
				((Queueable) BigObjectArchiveJob.queuedForTest.remove(0)).execute(null);
				((Queueable) BigObjectArchiveJob.queuedForTest.remove(0)).execute(null);
				BigObjectArchiveJob.queuedForTest.clear();
			}
			System.Assert.areEqual(0, store.rowsByKey.size(), 'Both rows removed');
			System.Assert.areEqual(2, BigObjectArchiveJob.archivedCount(), 'Not counted yet: no Write settled them');

			// The first chain's finisher settles from the keys its Write saved; twice is once.
			new BigObjectArchiveJob.Finisher(jobIds[0], stopped).stopped('Died');
			new BigObjectArchiveJob.Finisher(jobIds[0], stopped).stopped('Again');
			System.Assert.areEqual(1, BigObjectArchiveJob.archivedCount(), 'The finisher counted its row once');

			// The second chain stopped with no finisher: the nightly sweep settles it once it is stale.
			ArchiveCountSettle.sweep();
			System.Assert.areEqual(1, BigObjectArchiveJob.archivedCount(), 'A recent job may still be running');
			ArchiveCountSettle.staleHours = -1;
			new ArchiveRulesStep().execute((SchedulableContext) null);
			System.Assert.areEqual(0, BigObjectArchiveJob.archivedCount(), 'The sweep counted the second');
		}
		Import_Batch__c swept = reread(jobIds[1]);
		System.Assert.areEqual(ImportBatchService.STATUS_FAILED, swept.Status__c, 'Marked failed');
		System.Assert.isTrue(
			swept.Run_Log__c.contains(BarnHelp.text('Core', 'Core_ArchiveRules_LogSwept')),
			'Saying why: ' + swept.Run_Log__c
		);
		System.Assert.isFalse(swept.Operation_JSON__c.contains('"pending"'), 'Nothing left pending');
	}

	@IsTest
	static void aRowAlreadyBeingRestoredIsRefused() {
		archiveVolunteers();
		// The restores get their own limits, as a person's later clicks would.
		Test.startTest();
		System.runAs(archivist()) {
			List<String> rowIds = new List<String>();
			for (ArchiveViewerService.Row row : ArchiveViewerService.rows('Contact', null, null, null).rows) {
				rowIds.add(row.id);
			}
			Import_Batch__c job = ArchiveViewerService.restore('Contact', new List<String>{ rowIds[0] });
			System.Assert.isTrue(job.Operation_JSON__c.contains(rowIds[0]), 'The job keeps its rows');
			try {
				ArchiveViewerService.restore('Contact', rowIds);
				System.Assert.fail('A row in a restore still going is refused');
			} catch (ArchiveRules.ArchiveRuleException expected) {
				System.Assert.areEqual(
					BarnHelp.text('Core', 'Core_ArchiveViewer_ErrorRestoring'),
					expected.getMessage(),
					'In plain words'
				);
			}
			System.Assert.isNotNull(
				ArchiveViewerService.restore('Contact', new List<String>{ rowIds[1] }),
				'Another row may start'
			);
			drain();
			System.Assert.isNotNull(
				ArchiveViewerService.restore('Contact', new List<String>{ rowIds[0] }),
				'Once the restore ends, the row is no longer held'
			);
		}
		Test.stopTest();
	}

	@IsTest
	static void keepsArchivedARowWhoseRecordOrChildCannotBeCreated() {
		ArchiveStoreMemory store = ArchiveStoreMemory.install();
		BigObjectArchiveJob.queuedForTest = new List<Object>();
		Datetime at = Datetime.newInstance((Datetime.now().getTime() / 1000) * 1000);
		// An organization whose saved child cannot be created (no last name), and a person
		// without a last name: neither is created and both rows stay.
		Account org = TestDataFactory.organization(new Account(Name = 'Archived Org'));
		Contact noName = new Contact(FirstName = 'Nameless');
		store.insertRows(
			new List<Archived_Record__b>{
				row(
					'Account',
					at,
					'001000000000001AAA',
					ArchiveRecordJson.toJson(
						org,
						new Map<String, List<SObject>>{ 'Contact' => new List<SObject>{ noName } },
						new Map<String, String>{ 'Contact' => 'AccountId' }
					)
				),
				row('Account', at, '001000000000002AAA', null)
			}
		);
		System.runAs(TestUsers.admin()) {
			BigObjectArchiveJob.addToCount(2);
		}
		Id jobId;
		System.runAs(archivist()) {
			jobId = ArchiveViewerService.restore(
					'Account',
					new List<String>{ at.getTime() + '|001000000000001AAA', at.getTime() + '|001000000000002AAA' }
				)
				.Id;
			drain();
		}
		System.Assert.areEqual(
			0,
			[SELECT COUNT() FROM Account WHERE Name = 'Archived Org' WITH SYSTEM_MODE],
			'Taken back out'
		);
		System.Assert.areEqual(2, store.rowsByKey.size(), 'Both rows stay archived');
		System.Assert.areEqual(2, BigObjectArchiveJob.archivedCount(), 'The count unchanged');
		Import_Batch__c job = reread(jobId);
		System.Assert.areEqual(2, job.Rows_Rejected__c, 'Both named: ' + job.Run_Log__c);
		System.Assert.areEqual(0, job.Rows_Deleted__c, 'Nothing removed');
	}

	@IsTest
	static void restoresChildrenWithTheNewParentAndNotesACopyThatStayed() {
		ArchiveStoreMemory store = ArchiveStoreMemory.install();
		BigObjectArchiveJob.queuedForTest = new List<Object>();
		Datetime at = Datetime.newInstance((Datetime.now().getTime() / 1000) * 1000);
		Account org = TestDataFactory.organization(new Account(Name = 'Archived Parent'));
		Contact child = TestDataFactory.person(new Contact(LastName = 'Archived Child'));
		store.insertRows(
			new List<Archived_Record__b>{
				row(
					'Account',
					at,
					'001000000000003AAA',
					ArchiveRecordJson.toJson(
						org,
						new Map<String, List<SObject>>{ 'Contact' => new List<SObject>{ child } },
						new Map<String, String>{ 'Contact' => 'AccountId' }
					)
				)
			}
		);
		Id jobId;
		System.runAs(archivist()) {
			jobId = ArchiveViewerService.restore('Account', new List<String>{ at.getTime() + '|001000000000003AAA' })
				.Id;
			// Write creates the records and Remove deletes the row; the row is then put back, as
			// a delete that did not take would leave it.
			Map<String, Archived_Record__b> before = store.rowsByKey.clone();
			((Queueable) BigObjectArchiveJob.queuedForTest.remove(0)).execute(null);
			((Queueable) BigObjectArchiveJob.queuedForTest.remove(0)).execute(null);
			System.Assert.areEqual(0, store.rowsByKey.size(), 'Remove deleted the row');
			store.rowsByKey.putAll(before);
			drain();
		}
		Account parent = [SELECT Id FROM Account WHERE Name = 'Archived Parent' WITH SYSTEM_MODE LIMIT 1];
		System.Assert.areEqual(
			1,
			[SELECT COUNT() FROM Contact WHERE LastName = 'Archived Child' WITH SYSTEM_MODE],
			'The child created again'
		);
		Import_Batch__c job = reread(jobId);
		System.Assert.isTrue(job.Run_Log__c.contains(String.valueOf(parent.Id)), 'The new parent Id logged');
		System.Assert.areEqual(1, job.Rows_Created__c, 'Created');
		System.Assert.areEqual(0, job.Rows_Deleted__c, 'The copy stayed, and the log says so: ' + job.Run_Log__c);
		System.Assert.areEqual(1, store.rowsByKey.size(), 'Still archived');
	}

	@IsTest
	static void failedLinkMarksTheJobFailed() {
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
			new BigObjectArchiveJob.Finisher(job.Id, BarnHelp.text('Core', 'Core_ArchiveViewer_LogRemoveStopped'))
				.execute(null);
			System.Assert.areEqual(
				ImportBatchService.STATUS_COMMITTING,
				reread(job.Id).Status__c,
				'No context, no change'
			);
			Set<Id> found = ArchiveRestoreJob.existingOf(new Set<Id>{ UserInfo.getUserId(), job.Id });
			System.Assert.isTrue(found.contains(UserInfo.getUserId()), 'An active user exists');
			// A restore's Write link finishes with the restore's own line.
			new BigObjectArchiveJob.Finisher(job.Id, BarnHelp.text('Core', 'Core_ArchiveViewer_LogStopped'))
				.stopped('Because');
		}
		Import_Batch__c failed = reread(job.Id);
		System.Assert.areEqual(ImportBatchService.STATUS_FAILED, failed.Status__c, 'Failed');
		System.Assert.isTrue(
			failed.Run_Log__c.endsWith(BarnHelp.text('Core', 'Core_ArchiveViewer_LogStopped') + ' Because'),
			'A restore names the restore, with the reason: ' + failed.Run_Log__c
		);
		System.Assert.isFalse(
			failed.Run_Log__c.contains(BarnHelp.text('Core', 'Core_ArchiveRules_LogStopped')),
			'Never "run the rule again"'
		);
	}

	private static Archived_Record__b row(String objectName, Datetime at, String originalId, String body) {
		return new Archived_Record__b(
			Object_Name__c = objectName,
			Archived_At__c = at,
			Original_Id__c = originalId,
			Record_Name__c = originalId,
			Record_JSON__c = body
		);
	}
}
