/**
 * Erasing a person makes their address copies once, from the final state, instead of once for
 * the deleted addresses and again for the ended memberships (ADR-0193 erasure start seam): the
 * Contact Points left are exactly those the two syncs left, for fewer queries, and a refused or
 * failed erasure leaves syncing on.
 */
@IsTest(testFor='ApexClass:ContactPointErasureExtension')
private class ContactPointErasureExtensionTest {
	private static final String ERASE_SET = 'BarnCRM_Erase_People';

	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	private static User eraser() {
		return TestUsers.withPermissionSets(new List<String>{ TestUsers.CORE_ADMIN, ERASE_SET });
	}

	private static Boolean ready() {
		return ContactPointSyncService.activeKinds().size() == 3;
	}

	/** Ana and Sam in one household, each with an email; Ana also has an address of her own. */
	private static List<Contact> household(String lastName) {
		Account home = new Account(
			Name = lastName + ' Household',
			RecordTypeId = HouseholdService.householdRecordTypeId()
		);
		Database.insert(home, AccessLevel.SYSTEM_MODE);
		Database.insert(
			new Address__c(
				Account__c = home.Id,
				Street__c = '1 ' + lastName + ' St',
				City__c = 'Springfield',
				Is_Default__c = true,
				Status__c = 'Current'
			),
			AccessLevel.SYSTEM_MODE
		);
		List<Contact> people = new List<Contact>{
			(Contact) TestDataFactory.pastDuplicateRules(
				new Contact(
					FirstName = 'Ana',
					LastName = lastName,
					Personal_Email__c = 'ana@' + lastName.toLowerCase() + '.example',
					HomePhone = '5550100001'
				)
			),
			(Contact) TestDataFactory.pastDuplicateRules(
				new Contact(
					FirstName = 'Sam',
					LastName = lastName,
					Personal_Email__c = 'sam@' + lastName.toLowerCase() + '.example'
				)
			)
		};
		insert people;
		insert new List<SObject>{
			new Household_Member__c(
				Household__c = home.Id,
				Contact__c = people[0].Id,
				Start_Date__c = Date.today().addDays(-30)
			),
			new Household_Member__c(
				Household__c = home.Id,
				Contact__c = people[1].Id,
				Start_Date__c = Date.today().addDays(-30)
			),
			new Address__c(
				Contact__c = people[0].Id,
				Street__c = '9 Own Way',
				City__c = 'Springfield',
				Status__c = 'Current'
			)
		};
		return people;
	}

	/** Everything Contact Point Sync keeps for these people, as text to compare. */
	private static String state(List<Contact> people, String lastName) {
		List<String> lines = new List<String>();
		for (Contact person : people) {
			Id contactId = person.Id;
			Id parent = (Id) Database.query(
					'SELECT IndividualId FROM Contact WHERE Id = :contactId',
					AccessLevel.SYSTEM_MODE
				)[0]
				.get('IndividualId');
			List<String> kinds = new List<String>();
			for (Contact_Point_Link__c link : [
				SELECT Kind__c, Contact_Point_Id__c
				FROM Contact_Point_Link__c
				WHERE Contact__c = :contactId
				WITH SYSTEM_MODE
				ORDER BY Kind__c
			]) {
				kinds.add(link.Kind__c + (link.Contact_Point_Id__c == null ? '-' : '+'));
			}
			List<String> streets = new List<String>();
			for (
				SObject row : Database.query(
					'SELECT Street FROM ContactPointAddress WHERE ParentId = :parent ORDER BY Street', // detection-only: runs only after ready() found the object
					AccessLevel.SYSTEM_MODE
				)
			) {
				streets.add(((String) row.get('Street')).replace(lastName, 'X'));
			}
			Integer emails = Database.countQuery(
				'SELECT COUNT() FROM ContactPointEmail WHERE ParentId = :parent', // detection-only: runs only after ready() found the object
				AccessLevel.SYSTEM_MODE
			);
			lines.add(String.join(kinds, ',') + ' | ' + String.join(streets, ',') + ' | ' + emails);
		}
		return String.join(lines, ' / ');
	}

	private static String nameOf(Id contactId) {
		return [SELECT Name FROM Contact WHERE Id = :contactId WITH SYSTEM_MODE].Name;
	}

	@IsTest
	static void anErasureCopiesAddressesOnceAndEndsWhereItAlwaysDid() {
		if (!ready()) {
			return;
		}
		User admin = eraser();
		List<Contact> held;
		List<Contact> before;
		System.runAs(admin) {
			HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
			held = household('Alder');
			before = household('Birch');
			List<Contact> warm = household('Cedar');

			Test.startTest();
			// Every cache of the transaction warmed by a preview, so neither erasure is charged for it.
			PersonErasure.preview(warm[0].Id);
			Integer start = Limits.getQueries();
			PersonErasure.erase(held[0].Id, nameOf(held[0].Id), null);
			Integer withHold = Limits.getQueries() - start;
			ContactPointSyncService.holdingForTest = false;
			start = Limits.getQueries();
			PersonErasure.erase(before[0].Id, nameOf(before[0].Id), null);
			Integer withoutHold = Limits.getQueries() - start;
			ContactPointSyncService.holdingForTest = true;
			Test.stopTest();

			Assert.areEqual(
				state(before, 'Birch'),
				state(held, 'Alder'),
				'The Contact Points left are the same with the hold as without it'
			);
			Assert.isTrue(
				withHold < withoutHold,
				'One address sync instead of two: ' + withHold + ' against ' + withoutHold
			);
		}
	}

	@IsTest
	static void aRefusedOrFailedErasureLeavesSyncingOn() {
		if (!ready()) {
			return;
		}
		System.runAs(eraser()) {
			HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
			List<Contact> people = household('Dogwood');
			Id ana = people[0].Id;
			ContactPointErasureExtension extension = new ContactPointErasureExtension();

			Test.startTest();
			try {
				PersonErasure.erase(ana, 'Not Her Name', null);
				Assert.fail('A wrong name is refused');
			} catch (PersonErasure.ErasureException refused) {
				Assert.isNotNull(refused.getMessage());
			}
			insert new Address__c(
				Contact__c = ana,
				Street__c = '2 After Refusal Rd',
				City__c = 'Springfield',
				Status__c = 'Current'
			);
			// A run that failed after the start: Core ends it without the module's erase.
			extension.beforeErase(ana);
			extension.afterErase(ana);
			insert new Address__c(
				Contact__c = ana,
				Street__c = '3 After Failure Rd',
				City__c = 'Springfield',
				Status__c = 'Current'
			);
			Test.stopTest();

			String now = state(new List<Contact>{ people[0] }, 'Dogwood');
			Assert.isTrue(now.contains('2 After Refusal Rd'), 'Copied after a refusal: ' + now);
			Assert.isTrue(now.contains('3 After Failure Rd'), 'Copied after a failure: ' + now);
		}
	}
}
