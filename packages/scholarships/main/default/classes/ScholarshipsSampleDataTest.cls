/**
 * The Scholarships and Outbound Grants sample data set (release 1.25): a scholarship program with
 * a decided cycle (awards, disbursements, requirements) and an open one (applications at each
 * stage), and a small grants program in review, for Core's sample people and organizations.
 * Counted on the card, removed again with a real program left alone, and nothing loaded for
 * people who are not there. Run as a BarnCRM admin holding Scholarships Admin (which carries
 * Manage Scholarships, needed to mark a disbursement Paid), the person who loads sample data.
 *
 * The set ships as ScholarshipsSampleData.json and Core's SampleDataFile loads it (D-200 S2).
 * The stages are called directly, as the other modules' tests do, because a test runs only the
 * first stage of a batch.
 */
@IsTest(testFor='ApexClass:SampleDataFile')
private class ScholarshipsSampleDataTest {
	private static final String FILE = 'ScholarshipsSampleData';

	@TestSetup
	static void makeAdmin() {
		TestUsers.adminWith('Scholarships_Admin');
	}

	private static User admin() {
		return TestUsers.adminWith('Scholarships_Admin');
	}

	/** The sample people and organizations the set points at. */
	private static void samplePeopleAndOrganizations() {
		List<Contact> people = new List<Contact>();
		List<String> keys = new List<String>{
			'H002-3',
			'H005-2',
			'H014-1',
			'H014-2',
			'H016-4',
			'H013-1',
			'H012-1',
			'H003-2',
			'H016-3',
			'H012-2'
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
		for (String key : new List<String>{ 'O007', 'O011', 'O015', 'O018' }) {
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
	static void theLoadBuildsProgramsCyclesApplicationsAndAwards() {
		System.runAs(admin()) {
			samplePeopleAndOrganizations();

			Test.startTest();
			loadEverything();
			Test.stopTest();

			SampleDataModule module = SampleDataFile.find(FILE);
			Assert.areEqual('Scholarships', module.moduleName(), 'The name startAfter looks for');
			Assert.areEqual(2, module.countLoaded(), 'Two sample programs are counted');
			Assert.isTrue(module.hasSampleRecords(), 'The card sees them');
			Assert.areEqual(
				3,
				[SELECT COUNT() FROM Award_Cycle__c WITH SYSTEM_MODE],
				'Three cycles'
			);
			Assert.areEqual(
				14,
				[SELECT COUNT() FROM Award_Application__c WITH SYSTEM_MODE],
				'Fourteen applications at every stage'
			);
			Assert.areEqual(
				14,
				[SELECT COUNT() FROM Application_Review__c WITH SYSTEM_MODE],
				'Fourteen reviews'
			);
			Assert.areEqual(3, [SELECT COUNT() FROM Award__c WITH SYSTEM_MODE], 'Three awards');
			Assert.areEqual(
				5,
				[SELECT COUNT() FROM Award_Payment__c WITH SYSTEM_MODE],
				'Five disbursements'
			);
			Assert.areEqual(
				4,
				[SELECT COUNT() FROM Award_Requirement__c WITH SYSTEM_MODE],
				'Four requirements'
			);
			Assert.areEqual(
				2,
				[
					SELECT COUNT()
					FROM Award_Payment__c
					WHERE Status__c = 'Paid'
					WITH SYSTEM_MODE
				],
				'Two disbursements are paid'
			);
			Award_Application__c awarded = [
				SELECT Review_Count__c, Average_Score__c, Total_Score__c
				FROM Award_Application__c
				WHERE Title__c = 'Nursing program tuition'
				WITH SYSTEM_MODE
			];
			Assert.areEqual(2, awarded.Review_Count__c, 'Two submitted reviews');
			Assert.areEqual(8.5, awarded.Average_Score__c, 'Their average');
			Award__c active = [
				SELECT Paid_Amount__c, Scheduled_Amount__c
				FROM Award__c
				WHERE Status__c = 'Active'
				WITH SYSTEM_MODE
			];
			Assert.areEqual(1250, active.Paid_Amount__c, 'One installment is paid');
			Assert.areEqual(2500, active.Scheduled_Amount__c, 'Both installments are scheduled');
			Assert.areEqual(
				1,
				[
					SELECT COUNT()
					FROM Application_Review__c
					WHERE Status__c = 'Recused'
					WITH SYSTEM_MODE
				],
				'One reviewer stepped aside'
			);
		}
	}

	@IsTest
	static void theRemovalTakesTheSampleProgramsAndLeavesARealOne() {
		System.runAs(admin()) {
			samplePeopleAndOrganizations();
			Award_Program__c real = new Award_Program__c(
				Name = 'Real Program',
				Type__c = 'Grant',
				Active__c = true
			);
			insert as user real;
			insert as user new Award_Cycle__c(
				Program__c = real.Id,
				Name = 'Real Cycle',
				Status__c = 'Planned'
			);

			Test.startTest();
			loadEverything();
			SampleDataFile.removeChunkSize = 1;
			removeEverything();
			Test.stopTest();

			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Award_Program__c WHERE Sample_Data__c = TRUE WITH SYSTEM_MODE]
			);
			Assert.areEqual(
				1,
				[SELECT COUNT() FROM Award_Program__c WITH SYSTEM_MODE],
				'The real program stays'
			);
			Assert.areEqual(
				1,
				[SELECT COUNT() FROM Award_Cycle__c WITH SYSTEM_MODE],
				'Only the real cycle stays'
			);
			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Award_Application__c WITH SYSTEM_MODE],
				'The sample applications went with their cycles'
			);
			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Award__c WITH SYSTEM_MODE],
				'The sample awards went too'
			);
			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Award_Payment__c WITH SYSTEM_MODE],
				'And their disbursements'
			);
		}
	}

	@IsTest
	static void withoutSamplePeopleTheProgramsStillLoad() {
		System.runAs(admin()) {
			Test.startTest();
			loadEverything();
			Test.stopTest();

			Assert.areEqual(
				2,
				[SELECT COUNT() FROM Award_Program__c WITH SYSTEM_MODE],
				'The programs load'
			);
			Assert.areEqual(
				3,
				[SELECT COUNT() FROM Award_Cycle__c WITH SYSTEM_MODE],
				'The cycles load'
			);
		}
	}
}
