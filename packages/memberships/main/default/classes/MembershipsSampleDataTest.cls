/**
 * The Memberships sample data set (release 1.25): five levels with their benefits and fourteen
 * memberships for Core's sample people and organizations, some current, some due for renewal, one
 * in grace and some lapsed. Counted on the card, removed again with real levels and memberships
 * left alone, and nothing loaded for people who are not there. Run as a BarnCRM admin holding
 * Memberships Admin, the person who loads sample data.
 *
 * The set ships as MembershipsSampleData.json and Core's SampleDataFile loads it (D-200 S2). The
 * stages are called directly, as the other modules' tests do, because a test runs only the first
 * stage of a batch.
 */
@IsTest(testFor='ApexClass:SampleDataFile')
private class MembershipsSampleDataTest {
	private static final String FILE = 'MembershipsSampleData';

	@TestSetup
	static void makeAdmin() {
		TestUsers.adminWith('Memberships_Admin');
	}

	private static User admin() {
		return TestUsers.adminWith('Memberships_Admin');
	}

	/** The sample people and organizations the set points at. */
	private static void samplePeopleAndOrganizations() {
		List<Contact> people = new List<Contact>();
		List<String> keys = new List<String>{
			'H001-1',
			'H003-1',
			'H004-1',
			'H005-1',
			'H006-1',
			'H007-1',
			'H009-1',
			'H010-1',
			'H013-2',
			'H014-3'
		};
		for (Integer i = 0; i < keys.size(); i++) {
			people.add(
				TestDataFactory.person(
					new Contact(
						FirstName = 'Sample',
						LastName = 'Person' + i,
						Email = 'sample' + i + '@example.org',
						Sample_Data__c = true,
						Sample_Data_Key__c = keys[i]
					)
				)
			);
		}
		insert people;
		List<Account> organizations = new List<Account>();
		for (String key : new List<String>{ 'O001', 'O007', 'O011' }) {
			Account organization = (Account) TestDataFactory.pastDuplicateRules(
				AccountKindsTestData.organization('Sample Org ' + key)
			);
			organization.Sample_Data__c = true;
			organization.Sample_Data_Key__c = key;
			organizations.add(organization);
		}
		insert organizations;
	}

	private static void loadEverything() {
		SampleDataFile.LoadStages stages = new SampleDataFile.LoadStages(FILE);
		for (Integer stage = 0; stage < stages.stageCount(); stage++) {
			stages.runStage(stage);
		}
	}

	private static void removeEverything() {
		SampleDataFile.RemoveStages stages = new SampleDataFile.RemoveStages(FILE);
		Integer stageCount = stages.stageCount();
		for (Integer stage = 0; stage < stageCount; stage++) {
			stages.runStage(stage);
		}
	}

	private static Integer terms(String status) {
		return [
			SELECT COUNT()
			FROM Membership_Term__c
			WHERE Sample_Data__c = TRUE AND Status__c = :status
			WITH SYSTEM_MODE
		];
	}

	@IsTest
	static void theLoadBuildsLevelsBenefitsAndMemberships() {
		System.runAs(admin()) {
			samplePeopleAndOrganizations();

			Test.startTest();
			loadEverything();
			Test.stopTest();

			SampleDataModule module = SampleDataFile.find(FILE);
			Assert.areEqual('Memberships', module.moduleName(), 'The name startAfter looks for');
			Assert.areEqual(14, module.countLoaded(), 'Fourteen sample memberships are counted');
			Assert.isTrue(module.hasSampleRecords(), 'The card sees them');
			Assert.areEqual(
				5,
				[
					SELECT COUNT()
					FROM Membership_Level__c
					WHERE Sample_Data__c = TRUE
					WITH SYSTEM_MODE
				],
				'Five levels'
			);
			Assert.areEqual(
				11,
				[SELECT COUNT() FROM Membership_Benefit__c WITH SYSTEM_MODE],
				'Eleven benefits'
			);
			Assert.areEqual(1, terms('Renewed'), 'One earlier term was renewed');
			Assert.areEqual(1, terms('Grace'), 'One member is in grace');
			Assert.areEqual(2, terms('Lapsed'), 'Two have lapsed');
			Assert.areEqual(1, terms('Pending'), 'One is waiting for payment');
			Assert.areEqual(1, terms('Cancelled'), 'One was cancelled');
			Assert.areEqual(
				1,
				[
					SELECT COUNT()
					FROM Membership_Term__c
					WHERE
						Sample_Data__c = TRUE
						AND Previous_Term__c != NULL
						AND Origin__c = 'Renewal'
						AND Previous_Term__r.Status__c = 'Renewed'
						AND Level__r.Name = 'Family Member'
						AND Contact__r.Sample_Data_Key__c = 'H001-1'
					WITH SYSTEM_MODE
				],
				'The renewal points back to the term it renewed'
			);
			Assert.areEqual(
				3,
				[
					SELECT COUNT()
					FROM Membership_Term__c
					WHERE Sample_Data__c = TRUE AND Account__r.Sample_Data_Key__c LIKE 'O%'
					WITH SYSTEM_MODE
				],
				'Three organization memberships'
			);
		}
	}

	@IsTest
	static void theRemovalTakesTheSampleSetAndLeavesRealRecords() {
		System.runAs(admin()) {
			samplePeopleAndOrganizations();
			Membership_Level__c realLevel = new Membership_Level__c(
				Name = 'Real Level',
				Dues__c = 20,
				Term_Months__c = 12
			);
			insert as user realLevel;
			Contact person = TestDataFactory.person(new Contact(LastName = 'Real Person'));
			insert as user person;
			insert as user new Membership_Term__c(
				Level__c = realLevel.Id,
				Contact__c = person.Id,
				Status__c = 'Current'
			);

			Test.startTest();
			loadEverything();
			SampleDataFile.removeChunkSize = 4;
			removeEverything();
			Test.stopTest();

			Assert.areEqual(
				0,
				[
					SELECT COUNT()
					FROM Membership_Term__c
					WHERE Sample_Data__c = TRUE
					WITH SYSTEM_MODE
				]
			);
			Assert.areEqual(
				0,
				[
					SELECT COUNT()
					FROM Membership_Level__c
					WHERE Sample_Data__c = TRUE
					WITH SYSTEM_MODE
				]
			);
			Assert.areEqual(
				1,
				[SELECT COUNT() FROM Membership_Term__c WITH SYSTEM_MODE],
				'The real membership stays'
			);
			Assert.areEqual(
				1,
				[SELECT COUNT() FROM Membership_Level__c WITH SYSTEM_MODE],
				'The real level stays'
			);
			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Membership_Benefit__c WITH SYSTEM_MODE],
				'The sample benefits went with their levels'
			);
		}
	}

	@IsTest
	static void withoutSamplePeopleNoMembershipIsCreated() {
		System.runAs(admin()) {
			Test.startTest();
			loadEverything();
			Test.stopTest();

			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Membership_Term__c WITH SYSTEM_MODE],
				'No sample people or organizations, no memberships'
			);
			Assert.areEqual(
				5,
				[SELECT COUNT() FROM Membership_Level__c WITH SYSTEM_MODE],
				'The levels still load'
			);
		}
	}
}
