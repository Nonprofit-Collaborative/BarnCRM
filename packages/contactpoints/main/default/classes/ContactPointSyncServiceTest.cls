/**
 * Ana's email, phones and addresses reach Salesforce Contact Points and stay in step: changed,
 * removed, put back when edited elsewhere, deleted with her, made again when she is restored, and
 * right after a merge; 251 people at once; Contact Points BarnCRM did not make left alone; and an
 * org without the objects copies nothing and fails nothing (R-CPL1 to R-CPL4).
 *
 * Where the test org itself lacks the Contact Point or Individual objects, each test proves the
 * module skips them and stops there.
 */
@IsTest(testFor='ApexClass:ContactPointSyncService')
private class ContactPointSyncServiceTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	/** Whether this org can hold all three kinds. */
	private static Boolean ready() {
		Boolean all = ContactPointSyncService.activeKinds().size() == 3;
		if (!all) {
			Contact someone = person('Absent', 'absent@example.invalid', '5550109999');
			Database.insert(someone, AccessLevel.SYSTEM_MODE);
			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Contact_Point_Link__c WITH SYSTEM_MODE],
				'An org without the objects copies nothing and the save goes ahead'
			);
		}
		return all;
	}

	private static Contact person(String lastName, String email, String homePhone) {
		return (Contact) TestDataFactory.pastDuplicateRules(
			new Contact(
				FirstName = 'Ana',
				LastName = lastName,
				Personal_Email__c = email,
				HomePhone = homePhone
			)
		);
	}

	private static Id individualOf(Id personId) {
		return (Id) Database.query(
				'SELECT IndividualId FROM Contact WHERE Id = :personId',
				AccessLevel.SYSTEM_MODE
			)[0]
			.get('IndividualId');
	}

	private static List<SObject> copies(String objectName, Id parent, String fields) {
		return Database.query(
			'SELECT Id, ' +
				fields +
				' FROM ' +
				objectName +
				' WHERE ParentId = :parent ORDER BY Id',
			AccessLevel.SYSTEM_MODE
		);
	}

	private static List<Contact_Point_Link__c> linksOf(Id personId) {
		return [
			SELECT Id, Kind__c, Source__c, Contact_Point_Id__c
			FROM Contact_Point_Link__c
			WHERE Contact__c = :personId
			WITH SYSTEM_MODE
			ORDER BY Kind__c, Source__c
		];
	}

	@IsTest
	static void aPersonsCopiesFollowEverySave() {
		System.runAs(TestUsers.admin()) {
			if (!ready()) {
				return;
			}
			Contact ana = person('Rivera', 'ana@home.example', '(555) 010-0001');
			ana.MobilePhone = '555 010 0002';

			Test.startTest();
			insert ana;
			Id parent = individualOf(ana.Id);
			List<SObject> emails = copies('ContactPointEmail', parent, 'EmailAddress');
			Integer phonesAtFirst = copies('ContactPointPhone', parent, 'TelephoneNumber').size();

			ana.Personal_Email__c = 'ana@new.example';
			ana.MobilePhone = null;
			update ana;
			Test.stopTest();

			Assert.isNotNull(parent, 'Ana was given an Individual');
			Assert.areEqual(1, emails.size(), 'One email copy');
			Assert.areEqual(2, phonesAtFirst, 'Home and mobile');
			List<SObject> emailsNow = copies('ContactPointEmail', parent, 'EmailAddress');
			Assert.areEqual(emails[0].Id, emailsNow[0].Id, 'The same copy, updated in place');
			Assert.areEqual('ana@new.example', emailsNow[0].get('EmailAddress'));
			Assert.areEqual(
				1,
				copies('ContactPointPhone', parent, 'TelephoneNumber').size(),
				'The cleared mobile copy is removed'
			);
			Assert.areEqual(2, linksOf(ana.Id).size(), 'One link per copy');
		}
	}

	@IsTest
	static void anEditMadeElsewhereIsPutBack() {
		System.runAs(TestUsers.admin()) {
			if (!ready()) {
				return;
			}
			Contact ana = person('Rivera', 'ana@home.example', null);
			insert ana;
			Id parent = individualOf(ana.Id);
			SObject copy = copies('ContactPointEmail', parent, 'EmailAddress')[0];
			copy.put('EmailAddress', 'someone@else.example');
			Database.update(copy, AccessLevel.SYSTEM_MODE);

			Test.startTest();
			ContactPointSyncService.Result result = ContactPointSyncService.syncPeople(
				new Set<Id>{ ana.Id },
				null
			);
			Test.stopTest();

			Assert.areEqual(1, result.updated, 'BarnCRM is the source: one copy put back');
			Assert.areEqual(
				'ana@home.example',
				copies('ContactPointEmail', parent, 'EmailAddress')[0].get('EmailAddress')
			);
		}
	}

	@IsTest
	static void aSecondChangeInOneTransactionIsCopiedAndClearingIsCheap() {
		System.runAs(TestUsers.admin()) {
			if (!ready()) {
				return;
			}
			Contact ana = person('Rivera', 'ana@home.example', '5550100001');
			insert ana;
			Id parent = individualOf(ana.Id);

			Test.startTest();
			ana.Personal_Email__c = 'ana@one.example';
			update ana;
			ana.Personal_Email__c = 'ana@two.example';
			update ana;
			List<SObject> afterTwo = copies('ContactPointEmail', parent, 'EmailAddress');
			// Cleared without the sync, then synced alone, to count only what the sync reads.
			AutomationControl.bypass('Contact_Point_Sync_Person');
			ana.Personal_Email__c = null;
			ana.Email = null;
			ana.HomePhone = null;
			update ana;
			AutomationControl.clearBypass('Contact_Point_Sync_Person');
			Integer before = Limits.getQueries();
			ContactPointSyncService.Result cleared = ContactPointSyncService.syncPeople(
				new Set<Id>{ ana.Id },
				new Set<String>{ ContactPointPlan.EMAIL, ContactPointPlan.PHONE }
			);
			Integer spent = Limits.getQueries() - before;
			Test.stopTest();

			Assert.areEqual(1, afterTwo.size());
			Assert.areEqual(
				'ana@two.example',
				afterTwo[0].get('EmailAddress'),
				'The second change of the transaction reaches the copy'
			);
			Assert.isTrue(cleared.deleted >= 2, 'The email and phone copies are removed');
			// The person and their links, nothing more: a cleared value reads no Contact Point
			// (6 before the Batch C review: the copies and the adoptable rows of each kind).
			Assert.isTrue(spent <= 2, 'Queries for clearing a person: ' + spent);
		}
	}

	@IsTest
	static void deletedWithThePersonAndMadeAgainOnRestore() {
		System.runAs(TestUsers.admin()) {
			if (!ready()) {
				return;
			}
			Contact ana = person('Rivera', 'ana@home.example', '5550100001');
			insert ana;
			Id parent = individualOf(ana.Id);

			Test.startTest();
			Database.delete(ana, AccessLevel.SYSTEM_MODE);
			Integer whileDeleted = copies('ContactPointEmail', parent, 'EmailAddress').size();
			Database.undelete(ana, AccessLevel.SYSTEM_MODE);
			Test.stopTest();

			Assert.areEqual(0, whileDeleted, 'Deleted with her');
			Assert.areEqual(
				1,
				copies('ContactPointEmail', parent, 'EmailAddress').size(),
				'Made again when she is restored'
			);
			for (Contact_Point_Link__c link : linksOf(ana.Id)) {
				Assert.isNotNull(link.Contact_Point_Id__c, 'Each restored link names its new copy');
			}
		}
	}

	@IsTest
	static void aMergeLeavesTheSurvivorsCopiesRight() {
		System.runAs(TestUsers.admin()) {
			if (!ready()) {
				return;
			}
			Contact keep = person('Rivera', 'ana@home.example', null);
			Contact merged = person('Rivera', 'ana.r@old.example', null);
			insert new List<Contact>{ keep, merged };
			Id mergedCopy = Id.valueOf(linksOf(merged.Id)[0].Contact_Point_Id__c);

			Test.startTest();
			Database.merge(keep, merged.Id, AccessLevel.SYSTEM_MODE);
			ContactPointSyncService.syncPeople(new Set<Id>{ keep.Id }, null);
			Test.stopTest();

			Assert.areEqual(
				0,
				Database.query(
						'SELECT Id FROM ContactPointEmail WHERE Id = :mergedCopy', // detection-only: runs only after ready() found the object
						AccessLevel.SYSTEM_MODE
					)
					.size(),
				'The merged-away person\'s copy is deleted'
			);
			List<Contact_Point_Link__c> links = linksOf(keep.Id);
			Assert.areEqual(1, links.size(), 'One link per source on the survivor');
			Assert.areEqual(
				'ana@home.example',
				copies('ContactPointEmail', individualOf(keep.Id), 'EmailAddress')[0]
					.get('EmailAddress')
			);
		}
	}

	@IsTest
	static void ownAndHouseholdAddressesCurrentOnly() {
		System.runAs(TestUsers.admin()) {
			if (!ready()) {
				return;
			}
			Account household = new Account(
				Name = 'Rivera Household',
				RecordTypeId = HouseholdService.householdRecordTypeId()
			);
			Database.insert(household, AccessLevel.SYSTEM_MODE);
			Contact ana = person('Rivera', null, null);
			ana.AccountId = household.Id;
			insert ana;
			Address__c home = new Address__c(
				Account__c = household.Id,
				Street__c = '1 Main St',
				City__c = 'Springfield',
				Postal_Code__c = '01101',
				Is_Default__c = true,
				Status__c = 'Current'
			);
			Address__c work = new Address__c(
				Contact__c = ana.Id,
				Street__c = '5 Office Park',
				City__c = 'Springfield',
				Status__c = 'Current'
			);
			Address__c old = new Address__c(
				Contact__c = ana.Id,
				Street__c = '9 Old Rd',
				Status__c = 'Former'
			);

			Test.startTest();
			Database.insert(new List<Address__c>{ home, work, old }, AccessLevel.SYSTEM_MODE);
			Id parent = individualOf(ana.Id);
			Integer atFirst = copies('ContactPointAddress', parent, 'Street').size();
			work.Status__c = 'Former';
			Database.update(work, AccessLevel.SYSTEM_MODE);
			Test.stopTest();

			Assert.areEqual(2, atFirst, 'The household and her own current address');
			List<SObject> now = copies('ContactPointAddress', parent, 'Street');
			Assert.areEqual(1, now.size(), 'A former address is removed');
			Assert.areEqual('1 Main St', now[0].get('Street'));
		}
	}

	@IsTest
	static void adoptsAMatchingContactPointAndLeavesOthersAlone() {
		System.runAs(TestUsers.admin()) {
			if (!ready()) {
				return;
			}
			AutomationControl.bypass('Contact_Point_Sync_Person');
			Contact ana = person('Rivera', 'ana@home.example', null);
			insert ana;
			SObject individual = Schema.getGlobalDescribe().get('Individual').newSObject();
			individual.put('LastName', 'Rivera');
			Database.insert(individual, AccessLevel.SYSTEM_MODE);
			SObject linked = Contact.SObjectType.newSObject(ana.Id);
			linked.put('IndividualId', individual.Id);
			Database.update(linked, AccessLevel.SYSTEM_MODE);
			AutomationControl.clearBypass('Contact_Point_Sync_Person');
			Assert.areEqual(0, linksOf(ana.Id).size(), 'Switched off: nothing copied');
			Schema.SObjectType emailType = Schema.getGlobalDescribe().get('ContactPointEmail');
			SObject same = emailType.newSObject();
			same.put('ParentId', individual.Id);
			same.put('EmailAddress', 'ANA@home.example');
			SObject other = emailType.newSObject();
			other.put('ParentId', individual.Id);
			other.put('EmailAddress', 'consent@form.example');
			Database.insert(new List<SObject>{ same, other }, AccessLevel.SYSTEM_MODE);

			Test.startTest();
			ContactPointSyncService.Result result = ContactPointSyncService.syncPeople(
				new Set<Id>{ ana.Id },
				null
			);
			Test.stopTest();

			Assert.areEqual(0, result.created, 'The matching one is adopted, not doubled');
			Assert.areEqual(String.valueOf(same.Id), linksOf(ana.Id)[0].Contact_Point_Id__c);
			Assert.areEqual(
				2,
				copies('ContactPointEmail', individual.Id, 'EmailAddress').size(),
				'The unlinked one is left alone'
			);
		}
	}

	@IsTest
	static void twoHundredFiftyOnePeopleInOneSave() {
		System.runAs(TestUsers.admin()) {
			if (!ready()) {
				return;
			}
			List<Contact> people = new List<Contact>();
			for (Integer i = 0; i < 251; i++) {
				people.add(person('Bulk' + i, 'bulk' + i + '@example.invalid', '555010' + i));
			}

			Test.startTest();
			insert people;
			Test.stopTest();

			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Error_Log__c WITH SYSTEM_MODE],
				'Nothing failed: emails and phones are saved grouped by object'
			);
			Assert.areEqual(
				502,
				[SELECT COUNT() FROM Contact_Point_Link__c WITH SYSTEM_MODE],
				'An email and a phone for each of the 251, across both trigger chunks'
			);
			Assert.areEqual(
				251,
				Database.countQuery(
					'SELECT COUNT() FROM Contact WHERE IndividualId != null AND LastName LIKE \'Bulk%\'',
					AccessLevel.SYSTEM_MODE
				),
				'Each has an Individual'
			);
		}
	}

	@IsTest
	static void aMissingObjectOrATurnedOffKindIsSkipped() {
		System.runAs(TestUsers.admin()) {
			ContactPointSyncService.missingForTest.add('Individual');
			Assert.isTrue(
				ContactPointSyncService.activeKinds().isEmpty(),
				'Without the Individual object nothing can be copied'
			);
			ContactPointSyncService.missingForTest.clear();
			ContactPointSyncService.missingForTest.add(ContactPointPlan.ADDRESS);
			SettingsService.saveValues(
				ContactPointSyncService.SETTINGS_OBJECT,
				new Map<String, Object>{ 'Sync_Phones__c' => false }
			);

			Test.startTest();
			Set<String> kinds = ContactPointSyncService.activeKinds();
			Contact ana = person('Rivera', 'ana@home.example', '5550100001');
			insert ana;
			Test.stopTest();

			Assert.isFalse(kinds.contains(ContactPointPlan.ADDRESS), 'A missing object is skipped');
			Assert.isFalse(kinds.contains(ContactPointPlan.PHONE), 'A kind turned off is skipped');
			for (Contact_Point_Link__c link : linksOf(ana.Id)) {
				Assert.areEqual(ContactPointPlan.EMAIL, link.Kind__c, 'Only emails are copied');
			}
		}
	}
}
