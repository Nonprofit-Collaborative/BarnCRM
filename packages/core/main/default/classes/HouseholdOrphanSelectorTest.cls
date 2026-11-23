/**
 * HouseholdOrphanSelector (C-21, ADR-0048): the people in no household and the households nobody
 * is in, in both membership modes, leaving out erased people and ended memberships.
 *
 * Runs on any org shape. No test org needs Person Accounts: where people stored as accounts
 * matter, the shape is forced to name Core's Organization record type as the person type, which
 * is all the selector knows about a person account (it never names a person account field).
 */
@IsTest(testFor='ApexClass:HouseholdOrphanSelector')
private class HouseholdOrphanSelectorTest {
	private static final Integer CAP = 1000;

	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	/** The records one scenario builds, so each test can name who should be found. */
	private class Scenario {
		Id householdType;
		Id personType;
		Account emptyHousehold;
		Account membersHousehold;
		Account endedHousehold;
		Contact member;
		Contact loner;
		Contact endedMember;
		Contact erased;
		Contact resident;
		Contact employee;
		Account employer;
		Account standIn;
		Account erasedStandIn;
	}

	private static Id typeId(String developerName) {
		return Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get(developerName).getRecordTypeId();
	}

	private static Scenario build() {
		HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
		Scenario s = new Scenario();
		s.householdType = HouseholdService.householdRecordTypeId();
		s.personType = typeId('BarnCRM_Organization');
		s.emptyHousehold = HouseholdTestDataFactory.newHousehold('Empty Household');
		s.membersHousehold = HouseholdTestDataFactory.newHousehold('Members Household');
		s.endedHousehold = HouseholdTestDataFactory.newHousehold('Ended Household');
		Database.insert(
			new List<Account>{ s.emptyHousehold, s.membersHousehold, s.endedHousehold },
			AccessLevel.SYSTEM_MODE
		);
		s.employer = TestDataFactory.organization(new Account(Name = 'Employer', RecordTypeId = s.personType));
		s.standIn = TestDataFactory.organization(new Account(Name = 'Stand-in Person', RecordTypeId = s.personType));
		s.erasedStandIn = TestDataFactory.organization(
			new Account(Name = 'Erased Stand-in', RecordTypeId = s.personType)
		);
		Database.insert(new List<Account>{ s.employer, s.standIn, s.erasedStandIn }, AccessLevel.SYSTEM_MODE);

		s.member = HouseholdTestDataFactory.newContact('Ana', 'Member');
		s.loner = HouseholdTestDataFactory.newContact('Lou', 'Loner');
		s.endedMember = HouseholdTestDataFactory.newContact('Eve', 'Ended');
		s.erased = HouseholdTestDataFactory.newContact('Ed', 'Erased');
		s.resident = HouseholdTestDataFactory.newContact('Rae', 'Resident');
		s.resident.AccountId = s.membersHousehold.Id;
		s.employee = HouseholdTestDataFactory.newContact('Emi', 'Employee');
		s.employee.AccountId = s.employer.Id;
		insert new List<Contact>{ s.member, s.loner, s.endedMember, s.erased, s.resident, s.employee };

		insert new List<Household_Member__c>{
			new Household_Member__c(Household__c = s.membersHousehold.Id, Contact__c = s.member.Id),
			new Household_Member__c(
				Household__c = s.endedHousehold.Id,
				Contact__c = s.endedMember.Id,
				End_Date__c = OrgDate.today().addDays(-1)
			)
		};
		insert as system new List<Erasure__c>{
			new Erasure__c(Contact__c = s.erased.Id, Erased_Record_Id__c = s.erased.Id, Details__c = 'Test'),
			new Erasure__c(
				Person_Account__c = s.erasedStandIn.Id,
				Erased_Record_Id__c = s.erasedStandIn.Id,
				Details__c = 'Test'
			)
		};
		return s;
	}

	private static Set<Id> ids(List<SObject> records) {
		return new Map<Id, SObject>(records).keySet();
	}

	private static Set<Id> ids(Database.QueryLocator locator) {
		Set<Id> found = new Set<Id>();
		Database.QueryLocatorIterator rows = locator.iterator();
		while (rows.hasNext()) {
			found.add(((SObject) rows.next()).Id);
		}
		return found;
	}

	private static void personTypesAre(Set<Id> types) {
		OrgShapeDetector.OrgShape shape = new OrgShapeDetector.OrgShape();
		shape.personAccountRecordTypeIds = types;
		OrgShapeDetector.overrideShape = shape;
	}

	@IsTest
	static void contactModeFindsContactsWithNoAccountAndLeavesOutErasedPeople() {
		System.runAs(TestUsers.admin()) {
			Scenario s = build();
			Set<Id> expected = new Set<Id>{ s.member.Id, s.loner.Id, s.endedMember.Id };

			Test.startTest();
			Integer counted = HouseholdOrphanSelector.countContactsWithoutAccount(CAP);
			List<Contact> listed = HouseholdOrphanSelector.contactsWithoutAccount(CAP);
			Integer capped = HouseholdOrphanSelector.countContactsWithoutAccount(2);
			Set<Id> locked = ids(HouseholdOrphanSelector.contactsWithoutAccountLocator());
			Test.stopTest();

			Assert.areEqual(expected.size(), counted, 'Contacts with no account, not the erased one');
			Assert.areEqual(expected, ids(listed), 'The same people are listed');
			Assert.areEqual(2, capped, 'A count stops at its cap');
			Assert.areEqual(expected, locked, 'The catch-up batch reads the same people');
		}
	}

	@IsTest
	static void contactModeFindsHouseholdsNoContactPointsAt() {
		System.runAs(TestUsers.admin()) {
			Scenario s = build();

			Integer counted = HouseholdOrphanSelector.countHouseholdsWithoutContacts(s.householdType, CAP);
			List<Account> listed = HouseholdOrphanSelector.householdsWithoutContacts(s.householdType, CAP);

			Assert.areEqual(
				new Set<Id>{ s.emptyHousehold.Id, s.endedHousehold.Id },
				ids(listed),
				'The household with a resident is not empty'
			);
			Assert.areEqual(2, counted, 'Counted the same');
			Assert.areEqual(
				1,
				HouseholdOrphanSelector.householdsWithoutContacts(s.householdType, 1).size(),
				'Listed to its limit'
			);
		}
	}

	@IsTest
	static void junctionModeFindsContactsWithNoCurrentMembership() {
		System.runAs(TestUsers.admin()) {
			Scenario s = build();
			// A contact linked straight to a household is in it by the simple link, and a
			// contact of a person type is counted as the account, so both types are left out.
			Set<Id> excluded = new Set<Id>{ s.householdType, s.personType };
			Set<Id> expected = new Set<Id>{ s.loner.Id, s.endedMember.Id };

			Test.startTest();
			Integer counted = HouseholdOrphanSelector.countContactsWithoutMembership(excluded, CAP);
			List<Contact> listed = HouseholdOrphanSelector.contactsWithoutMembership(excluded, CAP);
			Set<Id> locked = ids(HouseholdOrphanSelector.contactsWithoutMembershipLocator(excluded));
			Integer notExcluded = HouseholdOrphanSelector.countContactsWithoutMembership(
				new Set<Id>{ s.householdType },
				CAP
			);
			Test.stopTest();

			Assert.areEqual(expected.size(), counted, 'No membership, or one that has ended; not erased people');
			Assert.areEqual(expected, ids(listed), 'The same people are listed');
			Assert.areEqual(expected, locked, 'The catch-up batch reads the same people');
			Assert.areEqual(expected.size() + 1, notExcluded, 'An employee of a non-excluded account is counted too');
		}
	}

	@IsTest
	static void junctionModeFindsPeopleStoredAsAccountsWithNoMembership() {
		System.runAs(TestUsers.admin()) {
			Scenario s = build();
			Set<Id> types = new Set<Id>{ s.personType };
			Set<Id> expected = new Set<Id>{ s.employer.Id, s.standIn.Id };

			Test.startTest();
			Integer counted = HouseholdOrphanSelector.countPersonAccountsWithoutMembership(types, CAP);
			List<Account> listed = HouseholdOrphanSelector.personAccountsWithoutMembership(types, CAP);
			Set<Id> locked = ids(HouseholdOrphanSelector.personAccountsWithoutMembershipLocator(types));
			Test.stopTest();

			Assert.areEqual(expected.size(), counted, 'Person types with no membership, not the erased one');
			Assert.areEqual(expected, ids(listed), 'The same accounts are listed');
			Assert.areEqual(expected, locked, 'The catch-up batch reads the same accounts');
		}
	}

	@IsTest
	static void peopleWithoutMembershipAddsContactsAndPersonAccounts() {
		System.runAs(TestUsers.admin()) {
			Scenario s = build();
			personTypesAre(new Set<Id>{ s.personType });

			Integer both = HouseholdOrphanSelector.countPeopleWithoutMembership(s.householdType, CAP);
			Integer stoppedAtTheCap = HouseholdOrphanSelector.countPeopleWithoutMembership(s.householdType, 2);

			// Contacts: the loner and the ended member (the employee's account is a person type,
			// so the employee is counted as that account). Accounts: the employer and the stand-in.
			Assert.areEqual(4, both, 'Two contacts and two person accounts');
			Assert.areEqual(2, stoppedAtTheCap, 'The person accounts are not counted once contacts reach the cap');
		}
	}

	@IsTest
	static void peopleWithoutMembershipCountsOnlyContactsWithoutPersonTypes() {
		System.runAs(TestUsers.admin()) {
			Scenario s = build();
			personTypesAre(new Set<Id>());

			Integer counted = HouseholdOrphanSelector.countPeopleWithoutMembership(s.householdType, CAP);

			Assert.areEqual(3, counted, 'The loner, the ended member and the employee; no accounts are read');
		}
	}

	@IsTest
	static void peopleWithoutMembershipAcceptsNoHouseholdType() {
		System.runAs(TestUsers.admin()) {
			Scenario s = build();
			personTypesAre(new Set<Id>());

			Integer counted = HouseholdOrphanSelector.countPeopleWithoutMembership(null, CAP);
			Integer withType = HouseholdOrphanSelector.countPeopleWithoutMembership(s.householdType, CAP);

			// The resident counts too, unless the org's own automation gave it a membership.
			Assert.isTrue(counted >= withType, 'Without a household type nobody is left out: ' + counted);
			Assert.isTrue(counted <= 4, 'At most the loner, the ended member, the employee and the resident');
		}
	}

	@IsTest
	static void junctionModeFindsHouseholdsNoCurrentMembershipPointsAt() {
		System.runAs(TestUsers.admin()) {
			Scenario s = build();
			Set<Id> expected = new Set<Id>{ s.emptyHousehold.Id, s.endedHousehold.Id };

			Integer counted = HouseholdOrphanSelector.countHouseholdsWithoutMembers(s.householdType, CAP);
			List<Account> listed = HouseholdOrphanSelector.householdsWithoutMembers(s.householdType, CAP);

			Assert.areEqual(expected, ids(listed), 'The household with an ended membership is empty too');
			Assert.areEqual(expected.size(), counted, 'Counted the same');
		}
	}
}
