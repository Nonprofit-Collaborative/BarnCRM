/**
 * The Archived Record store's own reads and guards, and the row JSON (canonical model R-ARC2,
 * R-ARC4, R-ARC6): what a row holds, the people it names, and what a restore builds from it.
 * Nothing here writes the big object, which an Apex test cannot do.
 */
@IsTest(testFor='ApexClass:ArchiveStore, ApexClass:ArchiveRecordJson')
private class ArchiveStoreTest {
	private static final Id ACCOUNT_ID = Id.valueOf('001000000000001');
	private static final Id MANAGER_ID = Id.valueOf('003000000000002');
	private static final Id PERSON_ID = Id.valueOf('003000000000003');
	private static final Id CHILD_ID = Id.valueOf('003000000000004');

	@TestSetup
	// runs-as: deploying user (creates the test user itself)
	static void createUsers() {
		TestUsers.admin();
	}

	private static String sampleJson() {
		Contact person = new Contact(
			Id = PERSON_ID,
			LastName = 'Arcstore',
			AccountId = ACCOUNT_ID,
			ReportsToId = MANAGER_ID
		);
		Contact report = new Contact(
			Id = CHILD_ID,
			LastName = 'Report',
			ReportsToId = PERSON_ID,
			AccountId = ACCOUNT_ID
		);
		return ArchiveRecordJson.toJson(
			person,
			new Map<String, List<SObject>>{ 'Contact' => new List<SObject>{ report }, 'Task' => new List<SObject>() },
			new Map<String, String>{ 'Contact' => 'ReportsToId' }
		);
	}

	@IsTest
	static void rowJsonRoundTripsTheRecordAndItsChildren() {
		System.runAs(TestUsers.admin()) {
			String body = sampleJson();
			SObject record = ArchiveRecordJson.recordOf(body);
			System.Assert.areEqual('Arcstore', record.get('LastName'), 'The record as it was read');
			Map<String, String> fieldByObject = new Map<String, String>();
			Map<String, List<SObject>> children = ArchiveRecordJson.childrenOf(body, fieldByObject);
			System.Assert.areEqual(new Set<String>{ 'Contact' }, children.keySet(), 'Empty kinds are not written');
			System.Assert.areEqual('ReportsToId', fieldByObject.get('Contact'), 'The lookup to the parent');
			System.Assert.areEqual('Report', children.get('Contact')[0].get('LastName'), 'The child as it was read');

			Set<Id> lookups = ArchiveRecordJson.lookupsOf(body);
			System.Assert.isTrue(lookups.contains(ACCOUNT_ID), 'The account lookup');
			System.Assert.isTrue(lookups.contains(MANAGER_ID), 'The manager lookup');
			System.Assert.isFalse(lookups.contains(CHILD_ID), 'A row\'s own Id is not a lookup');
		}
	}

	@IsTest
	static void restoreKeepsWritableFieldsAndLiveLookupsOnly() {
		System.runAs(TestUsers.admin()) {
			ArchiveRecordJson.Restored made = ArchiveRecordJson.restore(sampleJson(), new Set<Id>{ ACCOUNT_ID });
			System.Assert.isNull(made.record.Id, 'A new record');
			System.Assert.areEqual('Arcstore', made.record.get('LastName'), 'Writable fields are kept');
			System.Assert.areEqual(ACCOUNT_ID, made.record.get('AccountId'), 'A lookup whose target exists is kept');
			System.Assert.isNull(made.record.get('ReportsToId'), 'A lookup whose target is gone is dropped');
			System.Assert.isTrue(made.dropped.contains('ReportsToId'), 'And reported');

			SObject child = made.childrenByObject.get('Contact')[0];
			System.Assert.isNull(child.get('ReportsToId'), 'The parent lookup is left for the caller');
			System.Assert.isFalse(made.dropped.contains('Contact.ReportsToId'), 'And is not reported as dropped');
			System.Assert.areEqual(
				'ReportsToId',
				made.parentFieldByObject.get('Contact'),
				'The field the caller fills'
			);
		}
	}

	@IsTest
	static void peopleAreTheContactsAndAccountsARowNames() {
		// runs-as: deploying user (pure logic: Ids and strings, no records or permissions)
		Contact person = new Contact(Id = PERSON_ID, AccountId = ACCOUNT_ID);
		Contact report = new Contact(Id = CHILD_ID, ReportsToId = MANAGER_ID);
		String people = ArchiveRecordJson.peopleOf(person, new List<SObject>{ report });
		for (Id one : new List<Id>{ PERSON_ID, ACCOUNT_ID, CHILD_ID, MANAGER_ID }) {
			System.Assert.isTrue(ArchiveRecordJson.names(people, one), 'Named: ' + one);
		}
		System.Assert.isFalse(ArchiveRecordJson.names(people, Id.valueOf('003000000000009')), 'Not named');
		System.Assert.isFalse(ArchiveRecordJson.names(null, PERSON_ID), 'No people');
		System.Assert.isNull(ArchiveRecordJson.peopleOf(new Contact(), new List<SObject>()), 'Nobody named');
	}

	@IsTest
	static void childKindsLeaveOutSystemChildren() {
		System.runAs(TestUsers.admin()) {
			List<ArchiveRecordJson.ChildKind> kinds = ArchiveRecordJson.childKinds(
				Contact.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
			);
			for (ArchiveRecordJson.ChildKind kind : kinds) {
				System.Assert.isFalse(
					BulkDeleteService.isSystemChild(kind.objectName),
					'No system child: ' + kind.objectName
				);
				System.Assert.isNotNull(kind.fieldName, 'Each kind names its lookup');
				System.Assert.areNotEqual(
					'ActionableListMember',
					kind.objectName,
					'A child the platform will not read by its parent is left out'
				);
			}
		}
	}

	@IsTest
	static void childrenThatCannotBeReadByTheirRecordAreNamedInTheLog() {
		System.runAs(TestUsers.admin()) {
			Schema.DescribeSObjectResult contacts = Contact.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED);
			List<String> notKept = ArchiveRecordJson.notKept(contacts);
			String line = ArchiveRecordJson.notKeptLine(contacts);
			System.Assert.isTrue(notKept.size() <= 1, 'Only Actionable List Members are named today');
			if (!notKept.isEmpty()) {
				System.Assert.isTrue(line.startsWith('\n'), 'The line starts on a new line');
				System.Assert.isTrue(line.contains(notKept[0]), 'The line names them');
			} else {
				System.Assert.areEqual('', line, 'Nothing to name in an org without them');
			}
			System.Assert.areEqual(
				'',
				ArchiveRecordJson.notKeptLine(Saved_Query__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)),
				'An object without such children has no line'
			);
		}
	}

	@IsTest
	static void storeReadsByIndexAndGuardsItsWrites() {
		System.runAs(TestUsers.admin()) {
			ArchiveStore store = ArchiveStore.get();
			Datetime now = Datetime.now();
			ArchiveStore.Key key = new ArchiveStore.Key('Contact', now, String.valueOf(PERSON_ID));
			Archived_Record__b row = key.row();
			System.Assert.areEqual('Contact', row.Object_Name__c, 'The key builds the index fields');
			System.Assert.areEqual(String.valueOf(PERSON_ID), row.Original_Id__c, 'The original Id');

			System.Assert.areEqual(0, store.insertRows(new List<Archived_Record__b>()).size(), 'Nothing to write');
			System.Assert.areEqual(0, store.deleteRows(new List<ArchiveStore.Key>()), 'Nothing to delete');
			System.Assert.isTrue(store.present('Contact', now, new Set<String>()).isEmpty(), 'Nothing asked');

			Set<String> ids = new Set<String>{ String.valueOf(PERSON_ID) };
			System.Assert.isTrue(store.present('Contact', now, ids).isEmpty(), 'No copy at this time');
			System.Assert.isTrue(store.rows('Contact', now, ids).isEmpty(), 'No row at this time');
			System.Assert.isNotNull(store.page('Contact', now.addDays(-1), now, null, null, 5), 'A first page');
			System.Assert.isNotNull(store.page('Contact', now.addDays(-1), now, now, 'zzz', 5), 'A later page');
			System.Assert.isNotNull(store.scan('Contact', null, null, 5), 'A first scan');
			System.Assert.isNotNull(store.scan('Contact', now, 'zzz', 5), 'A later scan');
			System.Assert.isNull(store.nextObject('zzzzzz'), 'No object name sorts after this');
			store.nextObject(null);
		}
	}

	@IsTest
	static void aPersonWithoutCreateAccessWritesNothing() {
		User staff = TestUsers.standardUserWith('Arcstaff', new List<String>{ 'BarnCRM_Staff' });
		System.runAs(staff) {
			List<Boolean> saved = ArchiveStore.get()
				.insertRows(new List<Archived_Record__b>{ new ArchiveStore.Key('Contact', Datetime.now(), 'x').row() });
			System.Assert.areEqual(new List<Boolean>{ false }, saved, 'Refused before the platform is asked');
		}
	}
}
