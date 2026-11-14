/**
 * The Corporate Hub sample data set (C-10): a document library with acknowledgments, a compliance
 * calendar with past cycles, agreements with Core's sample organizations, processing activities,
 * a board and a finance committee seated with Core's sample people, meetings, motions, votes and
 * action items. Counted on the card, removed again with the org's own records left alone, and
 * nothing seated where there are no sample people. Run as a BarnCRM admin holding Corporate Hub
 * Admin, the person who loads sample data.
 *
 * The set ships as CorporateHubSampleData.json and Core's SampleDataFile loads it (D-200 S2). The
 * stages are called directly, as the other modules' tests do, because a test runs only the
 * first stage of a batch.
 */
@IsTest(testFor='ApexClass:SampleDataFile')
private class CorporateHubSampleDataTest {
	private static final String FILE = 'CorporateHubSampleData';
	private static final String ADMIN_SET = 'Corporate_Hub_Admin';

	@TestSetup
	static void makeAdmin() {
		TestUsers.adminWith(ADMIN_SET);
	}

	private static User admin() {
		return TestUsers.adminWith(ADMIN_SET);
	}

	/** Core's sample people and five of its sample organizations. */
	private static void samplePeopleAndOrganizations() {
		List<Contact> people = new List<Contact>();
		List<String> keys = new List<String>{ 'H001-1', 'H002-1', 'H003-1', 'H004-1', 'H005-1' };
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
		for (String key : new List<String>{ 'O002', 'O010', 'O006', 'O023', 'O017' }) {
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

	@IsTest
	static void theLoadBuildsTheLibraryTheCalendarAndTheBoard() {
		System.runAs(admin()) {
			samplePeopleAndOrganizations();

			Test.startTest();
			loadEverything();
			Test.stopTest();

			SampleDataModule module = SampleDataFile.find(FILE);
			Assert.areEqual('CorporateHub', module.moduleName(), 'The name startAfter looks for');
			Assert.areEqual(5, module.countLoaded(), 'Five sample documents are counted');
			Assert.isTrue(module.hasSampleRecords(), 'The card sees them');
			Assert.areEqual(
				3,
				[SELECT COUNT() FROM Policy_Acknowledgment__c WITH SYSTEM_MODE],
				'Three acknowledgments'
			);
			Assert.areEqual(
				5,
				[SELECT COUNT() FROM Compliance_Obligation__c WHERE Sample_Data__c = TRUE],
				'Five obligations'
			);
			Assert.areEqual(
				3,
				[SELECT COUNT() FROM Compliance_Cycle__c WITH SYSTEM_MODE],
				'Three past cycles'
			);
			Assert.areEqual(
				5,
				[
					SELECT COUNT()
					FROM Agreement__c
					WHERE Sample_Data__c = TRUE AND Organization__c != NULL
					WITH SYSTEM_MODE
				],
				'Five agreements, each with a sample organization'
			);
			Assert.areEqual(
				2,
				[SELECT COUNT() FROM Processing_Activity__c WHERE Sample_Data__c = TRUE],
				'Two processing activities'
			);
			Board__c board = [
				SELECT Id
				FROM Board__c
				WHERE Name = 'Board of Directors'
				WITH SYSTEM_MODE
			];
			Assert.areEqual(
				2,
				[SELECT COUNT() FROM Board__c WHERE Sample_Data__c = TRUE],
				'A board and a committee'
			);
			Assert.areEqual(
				5,
				[
					SELECT COUNT()
					FROM Board_Member__c
					WHERE Board__c = :board.Id
					WITH SYSTEM_MODE
				],
				'Five seats on the board'
			);
			Assert.areEqual(
				7,
				[SELECT COUNT() FROM Board_Member__c WITH SYSTEM_MODE],
				'Seven seats in all'
			);
			Assert.areEqual(
				3,
				[SELECT COUNT() FROM Board_Meeting__c WITH SYSTEM_MODE],
				'Three meetings'
			);
			Assert.areEqual(
				9,
				[SELECT COUNT() FROM Meeting_Attendee__c WITH SYSTEM_MODE],
				'Nine attendees'
			);
			Assert.areEqual(
				2,
				[SELECT COUNT() FROM Board_Motion__c WITH SYSTEM_MODE],
				'Two motions'
			);
			Board_Motion__c passed = [
				SELECT Votes_For__c, Abstentions__c
				FROM Board_Motion__c
				WHERE Status__c = 'Passed'
				WITH SYSTEM_MODE
			];
			Assert.areEqual(3, passed.Votes_For__c, 'Three votes for');
			Assert.areEqual(1, passed.Abstentions__c, 'One abstention');
			Assert.areEqual(
				3,
				[SELECT COUNT() FROM Meeting_Action_Item__c WITH SYSTEM_MODE],
				'Three action items'
			);
		}
	}

	@IsTest
	static void theRemovalTakesTheSampleSetAndLeavesRealRecords() {
		System.runAs(admin()) {
			samplePeopleAndOrganizations();
			Hub_Document__c real = new Hub_Document__c(
				Name = 'Real Policy',
				Type__c = 'Policy',
				Status__c = 'Active',
				Version__c = 1
			);
			insert as user real;
			Board__c realBoard = new Board__c(
				Name = 'Real Board',
				Type__c = 'Board',
				Status__c = 'Active'
			);
			insert as user realBoard;

			Test.startTest();
			loadEverything();
			SampleDataFile.removeChunkSize = 3;
			removeEverything();
			Test.stopTest();

			Assert.areEqual(0, [SELECT COUNT() FROM Hub_Document__c WHERE Sample_Data__c = TRUE]);
			Assert.areEqual(1, [SELECT COUNT() FROM Hub_Document__c], 'The real document stays');
			Assert.areEqual(1, [SELECT COUNT() FROM Board__c], 'The real board stays');
			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Policy_Acknowledgment__c WITH SYSTEM_MODE],
				'The sample acknowledgments are gone'
			);
			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Board_Meeting__c WITH SYSTEM_MODE],
				'The sample meetings went with their boards'
			);
			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Board_Member__c WITH SYSTEM_MODE],
				'The sample seats went with their boards'
			);
			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Compliance_Cycle__c WITH SYSTEM_MODE],
				'The sample cycles went with their obligations'
			);
		}
	}

	@IsTest
	static void withoutSamplePeopleNobodyIsSeated() {
		System.runAs(admin()) {
			Test.startTest();
			loadEverything();
			Test.stopTest();

			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Board_Member__c WITH SYSTEM_MODE],
				'No sample people, no seats'
			);
			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Board_Vote__c WITH SYSTEM_MODE],
				'No sample people, no votes'
			);
			Assert.areEqual(
				5,
				[SELECT COUNT() FROM Hub_Document__c WHERE Sample_Data__c = TRUE],
				'The library loads without people'
			);
		}
	}
}
