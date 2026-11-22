/**
 * Erasing a person and the archive (canonical model R-ARC6): the extension queues the scan only
 * when the archive holds rows; the scan does nothing without an Erasure record (a preview), and
 * otherwise deletes every row that is the person or names them, across objects and pages, then
 * lowers the count in a last link.
 *
 * The big object is replaced by `ArchiveStoreMemory`; each link is run in turn by the test.
 */
@IsTest(testFor='ApexClass:ArchiveErasureExtension, ApexClass:ArchiveErasureJob, ApexClass:PersonErasureExtensions')
private class ArchiveErasureTest {
	private static final String PERSON = String.valueOf(Id.valueOf('003000000000001'));
	private static final String OTHER = String.valueOf(Id.valueOf('003000000000002'));

	@TestSetup
	// runs-as: deploying user (creates the test user itself)
	static void createUsers() {
		TestUsers.admin();
	}

	private static void drain() {
		Integer ran = 0;
		while (!BigObjectArchiveJob.queuedForTest.isEmpty()) {
			((Queueable) BigObjectArchiveJob.queuedForTest.remove(0)).execute(null);
			ran++;
			System.Assert.isTrue(ran < 50, 'The chain ends');
		}
	}

	/** Rows of two objects: some name the person, the rest do not; more than a page of one. */
	private static ArchiveStoreMemory fill() {
		ArchiveStoreMemory store = ArchiveStoreMemory.install();
		Datetime at = Datetime.newInstance((Datetime.now().getTime() / 1000) * 1000);
		List<Archived_Record__b> rows = new List<Archived_Record__b>{
			row('Contact', at, PERSON, PERSON),
			row('Contact', at, OTHER, OTHER),
			row('Thing__c', at.addSeconds(-5), 'a01000000000001AAA', OTHER + ',' + PERSON)
		};
		for (Integer i = 0; i < ArchiveErasureJob.PAGE + 50; i++) {
			rows.add(row('Thing__c', at.addSeconds(-i), 'a02' + String.valueOf(i).leftPad(12, '0') + 'AAA', OTHER));
		}
		rows.add(row('Thing__c', at.addSeconds(-400), 'a03000000000001AAA', PERSON));
		store.insertRows(rows);
		BigObjectArchiveJob.addToCount(rows.size());
		return store;
	}

	private static Archived_Record__b row(String objectName, Datetime at, String originalId, String people) {
		return new Archived_Record__b(
			Object_Name__c = objectName,
			Archived_At__c = at,
			Original_Id__c = originalId,
			Person_Ids__c = people
		);
	}

	@IsTest
	static void deletesTheRowsNamingTheErasedPerson() {
		System.runAs(TestUsers.admin()) {
			ArchiveStoreMemory store = fill();
			Integer before = store.rowsByKey.size();
			insert as system new Erasure__c(Erased_Record_Id__c = PERSON, Details__c = 'Test');
			BigObjectArchiveJob.queuedForTest = new List<Object>();
			List<PersonErasure.Change> changes = new ArchiveErasureExtension().erase(Id.valueOf(PERSON));
			System.Assert.areEqual(1, changes.size(), 'Reported as counted');
			System.Assert.areEqual(PersonErasure.DELETED, changes[0].action, 'Deleted');
			System.Assert.isTrue(
				new ArchiveErasureExtension().fieldsToKeep(Contact.SObjectType).isEmpty(),
				'Keeps nothing'
			);
			System.Assert.areEqual(1, BigObjectArchiveJob.queuedForTest.size(), 'The scan queued');
			drain();
			System.Assert.areEqual(
				0,
				[SELECT COUNT() FROM Error_Log__c WITH SYSTEM_MODE],
				'No failure: ' + [SELECT Message__c, Technical_Detail__c FROM Error_Log__c WITH SYSTEM_MODE LIMIT 2]
			);
			System.Assert.areEqual(before - 3, store.rowsByKey.size(), 'The three rows naming the person went');
			for (Archived_Record__b left : store.rowsByKey.values()) {
				System.Assert.isFalse(ArchiveRecordJson.names(left.Person_Ids__c, PERSON), 'None names them');
			}
			System.Assert.areEqual(before - 3, BigObjectArchiveJob.archivedCount(), 'The count lowered');
		}
	}

	@IsTest
	static void doesNothingWithoutAnErasureRecord() {
		System.runAs(TestUsers.admin()) {
			ArchiveStoreMemory store = fill();
			Integer before = store.rowsByKey.size();
			BigObjectArchiveJob.queuedForTest = new List<Object>();
			new ArchiveErasureExtension().erase(Id.valueOf(PERSON));
			drain();
			System.Assert.areEqual(before, store.rowsByKey.size(), 'A preview deletes nothing');
			System.Assert.areEqual(before, BigObjectArchiveJob.archivedCount(), 'The count unchanged');
		}
	}

	@IsTest
	static void aLinkThatDiesLogsAnError() {
		System.runAs(TestUsers.admin()) {
			// The erasure chain's finalizer: no job, so an Error naming no record.
			BigObjectArchiveJob.Finisher finisher = new BigObjectArchiveJob.Finisher(
				null,
				BarnHelp.text('Core', 'Core_ArchiveErasure_Stopped')
			);
			finisher.execute(null);
			System.Assert.areEqual(0, [SELECT COUNT() FROM Error_Log__c WITH SYSTEM_MODE], 'No context, no log');
			finisher.stopped('Because');
			Error_Log__c logged = [SELECT Severity__c, Message__c FROM Error_Log__c WITH SYSTEM_MODE LIMIT 1];
			System.Assert.areEqual(ErrorLogger.SEVERITY_ERROR, logged.Severity__c, 'An Error');
			System.Assert.isTrue(logged.Message__c.contains('Because'), 'With the reason: ' + logged.Message__c);
		}
	}

	@IsTest
	static void queuesNothingWhenTheArchiveIsEmpty() {
		System.runAs(TestUsers.admin()) {
			ArchiveStoreMemory.install();
			BigObjectArchiveJob.queuedForTest = new List<Object>();
			System.Assert.isTrue(new ArchiveErasureExtension().erase(Id.valueOf(PERSON)).isEmpty(), 'Nothing to say');
			System.Assert.isTrue(BigObjectArchiveJob.queuedForTest.isEmpty(), 'Nothing queued');
			System.Assert.isTrue(
				PersonErasureExtensions.EXTENSION_CLASSES.contains('ArchiveErasureExtension'),
				'Registered as an extension'
			);
		}
	}
}
