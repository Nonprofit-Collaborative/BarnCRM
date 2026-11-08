/**
 * A person who moves household takes the new household's addresses at once, in the same save and
 * not at their next one, 201 at a time too, and the Automation page's switch stops it; people
 * stored as person accounts are copied like contacts, where the org has them, and an org without
 * them copies nothing and fails nothing (D-186; ADR-0176 decisions 14 and 15).
 */
@IsTest(testFor='ApexClass:ContactPointMembershipHandler')
private class ContactPointMoveTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	private static Boolean ready() {
		return ContactPointSyncService.activeKinds().size() == 3;
	}

	private static Account household(String name, String street) {
		Account household = new Account(
			Name = name,
			RecordTypeId = HouseholdService.householdRecordTypeId()
		);
		Database.insert(household, AccessLevel.SYSTEM_MODE);
		Database.insert(
			new Address__c(
				Account__c = household.Id,
				Street__c = street,
				City__c = 'Springfield',
				Is_Default__c = true,
				Status__c = 'Current'
			),
			AccessLevel.SYSTEM_MODE
		);
		return household;
	}

	private static Contact person(String lastName) {
		return (Contact) TestDataFactory.pastDuplicateRules(
			new Contact(FirstName = 'Ana', LastName = lastName)
		);
	}

	private static List<String> streets(Id parent) {
		List<String> result = new List<String>();
		for (
			SObject row : Database.query(
				'SELECT Street FROM ContactPointAddress WHERE ParentId = :parent ORDER BY Street', // detection-only: runs only after ready() found the object
				AccessLevel.SYSTEM_MODE
			)
		) {
			result.add((String) row.get('Street'));
		}
		return result;
	}

	private static Id individualOf(Id contactId) {
		return (Id) Database.query(
				'SELECT IndividualId FROM Contact WHERE Id = :contactId',
				AccessLevel.SYSTEM_MODE
			)[0]
			.get('IndividualId');
	}

	@IsTest
	static void movingMembershipCopiesTheNewHouseholdsAddressAtOnce() {
		System.runAs(TestUsers.admin()) {
			if (!ready()) {
				return;
			}
			HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
			Account north = household('North Household', '1 North St');
			Account south = household('South Household', '2 South St');
			Contact ana = person('Rivera');
			ana.Personal_Email__c = 'ana@home.example';
			insert ana;
			Household_Member__c membership = new Household_Member__c(
				Household__c = north.Id,
				Contact__c = ana.Id,
				Start_Date__c = Date.today()
			);

			Test.startTest();
			insert membership;
			Id parent = individualOf(ana.Id);
			List<String> joined = streets(parent);
			membership.Household__c = south.Id;
			update membership;
			List<String> moved = streets(parent);
			delete membership;
			List<String> left = streets(parent);
			Test.stopTest();

			Assert.areEqual(new List<String>{ '1 North St' }, joined, 'Joining copies at once');
			Assert.areEqual(new List<String>{ '2 South St' }, moved, 'Moving swaps them at once');
			Assert.isTrue(left.isEmpty(), 'Leaving takes the household addresses away');
		}
	}

	@IsTest
	static void aContactMovedToAnotherAccountAlsoSyncsAtOnce() {
		System.runAs(TestUsers.admin()) {
			if (!ready()) {
				return;
			}
			HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
			Account north = household('North Household', '1 North St');
			Account south = household('South Household', '2 South St');
			Contact ana = person('Rivera');
			ana.AccountId = north.Id;
			insert ana;

			Test.startTest();
			Id parent = individualOf(ana.Id);
			List<String> before = streets(parent);
			ana.AccountId = south.Id;
			update ana;
			List<String> after = streets(parent);
			Test.stopTest();

			Assert.areEqual(new List<String>{ '1 North St' }, before);
			Assert.areEqual(new List<String>{ '2 South St' }, after, 'No second save needed');
		}
	}

	@IsTest
	static void twoHundredOneMembershipsAtOnce() {
		System.runAs(TestUsers.admin()) {
			if (!ready()) {
				return;
			}
			HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
			Account north = household('North Household', '1 North St');
			List<Contact> people = new List<Contact>();
			for (Integer i = 0; i < 201; i++) {
				people.add(person('Bulk' + i));
			}
			insert people;
			List<Household_Member__c> rows = new List<Household_Member__c>();
			for (Contact each : people) {
				rows.add(
					new Household_Member__c(
						Household__c = north.Id,
						Contact__c = each.Id,
						Start_Date__c = Date.today()
					)
				);
			}

			Test.startTest();
			insert rows;
			Test.stopTest();

			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Error_Log__c WITH SYSTEM_MODE],
				'Nothing failed'
			);
			Assert.areEqual(
				201,
				[
					SELECT COUNT()
					FROM Contact_Point_Link__c
					WHERE Kind__c = 'Address'
					WITH SYSTEM_MODE
				],
				'Each of the 201 has the household address'
			);
		}
	}

	@IsTest
	static void theAutomationSwitchStopsTheMoveSync() {
		System.runAs(TestUsers.admin()) {
			if (!ready()) {
				return;
			}
			HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
			Account north = household('North Household', '1 North St');
			Contact ana = person('Rivera');
			ana.Personal_Email__c = 'ana@home.example';
			insert ana;

			Test.startTest();
			AutomationControl.bypass('Contact_Point_Sync_Membership');
			insert new Household_Member__c(
				Household__c = north.Id,
				Contact__c = ana.Id,
				Start_Date__c = Date.today()
			);
			AutomationControl.clearBypass('Contact_Point_Sync_Membership');
			Test.stopTest();

			Assert.isTrue(streets(individualOf(ana.Id)).isEmpty(), 'Switched off: not copied');
		}
	}

	private static Account personAccount(String lastName, String email) {
		Account record = new Account(RecordTypeId = OrgShapeDetector.creatablePersonRecordTypeId());
		record.put('FirstName', 'Pat');
		record.put('LastName', lastName);
		record.put('PersonEmail', email);
		return record;
	}

	private static Id contactBehind(Id accountId) {
		return (Id) Database.query(
				'SELECT PersonContactId FROM Account WHERE Id = :accountId',
				AccessLevel.SYSTEM_MODE
			)[0]
			.get('PersonContactId');
	}

	@IsTest
	static void aPersonAccountIsCopiedLikeAContact() {
		System.runAs(TestUsers.admin()) {
			if (PersonAccountTestShape.skipReason() != null || !ready()) {
				return;
			}
			HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
			Account north = household('North Household', '1 North St');
			Account pat = personAccount('Alder', 'pat@home.example');

			Test.startTest();
			insert pat;
			Id contactId = contactBehind(pat.Id);
			Integer emails = [
				SELECT COUNT()
				FROM Contact_Point_Link__c
				WHERE Contact__c = :contactId AND Kind__c = 'Email'
				WITH SYSTEM_MODE
			];
			pat.put('PersonEmail', 'pat@work.example');
			update pat;
			Id parent = individualOf(contactId);
			List<SObject> changed = Database.query(
				'SELECT EmailAddress FROM ContactPointEmail WHERE ParentId = :parent', // detection-only: runs only after ready() found the object
				AccessLevel.SYSTEM_MODE
			);
			insert new Address__c(
				Person_Account__c = pat.Id,
				Street__c = '7 Alder Way',
				City__c = 'Portland',
				Status__c = 'Current'
			);
			insert new Household_Member__c(
				Household__c = north.Id,
				Account__c = pat.Id,
				Start_Date__c = Date.today()
			);
			List<String> addresses = streets(parent);
			Test.stopTest();

			Assert.areEqual(1, emails, 'A new person account is copied');
			Assert.areEqual(1, changed.size());
			Assert.areEqual('pat@work.example', changed[0].get('EmailAddress'), 'A change follows');
			Assert.areEqual(
				new List<String>{ '1 North St', '7 Alder Way' },
				addresses,
				'Their own address and the household they joined'
			);

			delete pat;
			Assert.areEqual(
				0,
				[
					SELECT COUNT()
					FROM Contact_Point_Link__c
					WHERE Contact__c = :contactId
					WITH SYSTEM_MODE
				],
				'Deleting the person account removes their links'
			);
		}
	}

	@IsTest
	static void anOrgWithoutPersonAccountsFailsNothing() {
		System.runAs(TestUsers.admin()) {
			if (HouseholdService.isPersonAccountOrg()) {
				return;
			}
			Test.startTest();
			Account organization = new Account(Name = 'Plain Org');
			insert organization;
			organization.Name = 'Plain Org Renamed';
			update organization;
			delete organization;
			Test.stopTest();

			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Error_Log__c WITH SYSTEM_MODE],
				'Account saves are not touched'
			);
			Assert.areEqual(0, [SELECT COUNT() FROM Contact_Point_Link__c WITH SYSTEM_MODE]);
		}
	}
}
