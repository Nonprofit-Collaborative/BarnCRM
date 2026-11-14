/**
 * The Territory sample data set (release 1.25): three state regions, one each of Keep Owner,
 * Territory Owner and Round Robin routing, with a household rule and a people rule apiece and one
 * member on the Round Robin region. It is counted on the card and removed again with real
 * territories left alone, and removing a territory clears the Territory of the records assigned
 * to it. Run as a BarnCRM admin holding Territory Admin, the person who loads sample data.
 *
 * The set ships as TerritorySampleData.json and Core's SampleDataFile loads it (D-200 S2). The
 * stages are called directly, as the other modules' tests do, because a test runs only the
 * first stage of a batch.
 */
@IsTest(testFor='ApexClass:SampleDataFile')
private class TerritorySampleDataTest {
	private static final String FILE = 'TerritorySampleData';

	@TestSetup
	static void makeAdmin() {
		TestUsers.adminWith('Territory_Admin');
	}

	private static User admin() {
		return TestUsers.adminWith('Territory_Admin');
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
	static void theLoadBuildsThreeRegionsWithRulesAndAMember() {
		System.runAs(admin()) {
			Test.startTest();
			loadEverything();
			Test.stopTest();

			SampleDataModule module = SampleDataFile.find(FILE);
			Assert.areEqual('Territory', module.moduleName(), 'The name startAfter looks for');
			Assert.areEqual(3, module.countLoaded(), 'Three sample territories are counted');
			Assert.isTrue(module.hasSampleRecords(), 'The card sees them');

			Map<String, Territory__c> territories = new Map<String, Territory__c>();
			for (Territory__c territory : [
				SELECT Name, Routing__c, Priority__c, Owner_User__c, Active__c
				FROM Territory__c
				WHERE Sample_Data__c = TRUE
				WITH SYSTEM_MODE
			]) {
				territories.put(territory.Name, territory);
			}
			Assert.areEqual('Keep Owner', territories.get('Minnesota Region').Routing__c);
			Assert.areEqual('Territory Owner', territories.get('Georgia Region').Routing__c);
			Assert.areEqual(
				UserInfo.getUserId(),
				territories.get('Georgia Region').Owner_User__c,
				'The territory owner is the person who loaded the sample'
			);
			Assert.areEqual('Round Robin', territories.get('Ohio Region').Routing__c);
			Assert.areEqual(
				6,
				[SELECT COUNT() FROM Territory_Rule__c WITH SYSTEM_MODE],
				'A household rule and a people rule for each'
			);
			Assert.areEqual(
				3,
				[
					SELECT COUNT()
					FROM Territory_Rule__c
					WHERE Applies_To__c = 'Households'
					WITH SYSTEM_MODE
				],
				'Three household rules'
			);
			Assert.areEqual(
				1,
				[
					SELECT COUNT()
					FROM Territory_Member__c
					WHERE Territory__r.Name = 'Ohio Region'
					WITH SYSTEM_MODE
				],
				'One member takes turns on the Round Robin region'
			);
		}
	}

	@IsTest
	static void theRemovalTakesTheSampleTerritoriesAndClearsAssignments() {
		System.runAs(admin()) {
			Territory__c real = new Territory__c(
				Name = 'Real Region',
				Routing__c = 'Keep Owner',
				Priority__c = 5
			);
			insert as user real;
			Contact person = TestDataFactory.person(new Contact(LastName = 'Real Person'));
			insert as user person;

			Test.startTest();
			loadEverything();
			Territory__c sample = [
				SELECT Id
				FROM Territory__c
				WHERE Name = 'Minnesota Region'
				WITH SYSTEM_MODE
			];
			person.Territory__c = sample.Id;
			update as user person;
			SampleDataFile.removeChunkSize = 2;
			removeEverything();
			Test.stopTest();

			Assert.areEqual(0, [SELECT COUNT() FROM Territory__c WHERE Sample_Data__c = TRUE]);
			Assert.areEqual(1, [SELECT COUNT() FROM Territory__c], 'The real territory stays');
			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Territory_Rule__c WITH SYSTEM_MODE],
				'The sample rules went with their territories'
			);
			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Territory_Member__c WITH SYSTEM_MODE],
				'The sample member went with the territory'
			);
			Assert.isNull(
				[SELECT Territory__c FROM Contact WHERE Id = :person.Id WITH SYSTEM_MODE]
				.Territory__c,
				'A record assigned to a sample territory is cleared, not deleted'
			);
		}
	}
}
