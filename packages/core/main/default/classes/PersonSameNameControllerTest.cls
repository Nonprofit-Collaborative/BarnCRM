/**
 * The same-name hint: people with the exact name typed, with their city and household, in
 * both ways of belonging, leaving out the household someone is being added to.
 */
@IsTest(testFor='ApexClass:PersonSameNameController')
private class PersonSameNameControllerTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	@IsTest
	static void aContactWithTheSameNameIsOfferedWithCityAndHousehold() {
		System.runAs(TestUsers.admin()) {
			HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
			Account household = HouseholdTestDataFactory.newHousehold('Garcia Household');
			Database.insert(household, AccessLevel.SYSTEM_MODE);
			Contact ana = HouseholdTestDataFactory.newContact('Ana', 'Garcia');
			ana.AccountId = household.Id;
			ana.MailingCity = 'Tampa';
			insert ana;
			insert HouseholdTestDataFactory.newContact('Luis', 'Garcia');

			Test.startTest();
			List<PersonSameNameController.Match> matches = PersonSameNameController.findSameName(
				'ana',
				'GARCIA ',
				null
			);
			Test.stopTest();

			Assert.areEqual(1, matches.size(), 'Only Ana matches, whatever the case');
			Assert.areEqual(ana.Id, matches[0].id, 'It is Ana');
			Assert.areEqual('Tampa', matches[0].city, 'Her city is shown');
			Assert.isTrue(String.isNotBlank(matches[0].householdName), 'Her household is shown');
		}
	}

	@IsTest
	static void aMemberOfTheHouseholdBeingAddedToIsLeftOut() {
		System.runAs(TestUsers.admin()) {
			HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
			Account household = HouseholdTestDataFactory.newHousehold('Garcia Household');
			Account other = HouseholdTestDataFactory.newHousehold('Other Garcia Household');
			Database.insert(new List<Account>{ household, other }, AccessLevel.SYSTEM_MODE);
			Contact inside = HouseholdTestDataFactory.newContact('Ana', 'Garcia');
			Contact outside = HouseholdTestDataFactory.newContact('Ana', 'Garcia');
			insert new List<Contact>{ inside, outside };
			insert new List<Household_Member__c>{
				new Household_Member__c(
					Household__c = household.Id,
					Contact__c = inside.Id,
					Start_Date__c = Date.today()
				),
				new Household_Member__c(
					Household__c = other.Id,
					Contact__c = outside.Id,
					Start_Date__c = Date.today()
				)
			};

			Test.startTest();
			List<PersonSameNameController.Match> matches = PersonSameNameController.findSameName(
				'Ana',
				'Garcia',
				household.Id
			);
			Test.stopTest();

			Assert.areEqual(1, matches.size(), 'The member already here is left out');
			Assert.areEqual(outside.Id, matches[0].id, 'The other Ana is offered');
			Assert.areEqual(
				[SELECT Name FROM Account WHERE Id = :other.Id WITH SYSTEM_MODE].Name,
				matches[0].householdName,
				'Her household is the one her membership names'
			);
		}
	}

	@IsTest
	static void aShortOrMissingLastNameAsksNothing() {
		System.runAs(TestUsers.admin()) {
			Assert.isTrue(
				PersonSameNameController.findSameName('Ana', 'G', null).isEmpty(),
				'One letter is too short'
			);
			Assert.isTrue(
				PersonSameNameController.findSameName('Ana', null, null).isEmpty(),
				'No last name, no hint'
			);
		}
	}

	@IsTest
	static void aBlankFirstNameMatchesOnTheLastName() {
		System.runAs(TestUsers.admin()) {
			HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
			HouseholdService.suspendAutomaticCreation();
			insert HouseholdTestDataFactory.newContact('Ana', 'Okafor');

			Test.startTest();
			List<PersonSameNameController.Match> matches = PersonSameNameController.findSameName(
				'',
				'Okafor',
				null
			);
			Test.stopTest();

			Assert.areEqual(1, matches.size(), 'The last name alone matches');
			Assert.isNull(matches[0].householdName, 'Someone in no household shows none');
		}
	}
}
