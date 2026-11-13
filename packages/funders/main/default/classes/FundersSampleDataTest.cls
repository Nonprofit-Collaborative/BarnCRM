/**
 * The Funders sample data (C-10), shipped as FundersSampleData.json and loaded by Core's
 * SampleDataFile (D-200 S2): three grants to Core's sample organizations, counted on the card,
 * removed again with real grants left alone, and nothing loaded where there are no sample
 * organizations.
 */
@IsTest
private class FundersSampleDataTest {
	private static final String FILE = 'FundersSampleData';

	@TestSetup
	static void makeAdmin() {
		TestUsers.adminWith(GrantTestData.ADMIN);
	}

	private static User admin() {
		return TestUsers.adminWith(GrantTestData.ADMIN);
	}

	/** The three of Core's sample organizations the file names. */
	private static void sampleOrganizations() {
		List<Account> organizations = new List<Account>();
		for (String key : new List<String>{ 'O022', 'O014', 'O001' }) {
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
	static void theCardCountsTheSampleGrants() {
		System.runAs(admin()) {
			sampleOrganizations();

			Test.startTest();
			loadEverything();
			Test.stopTest();

			SampleDataModule module = SampleDataFile.find(FILE);
			Assert.areEqual('Funders', module.moduleName(), 'The name startAfter looks for');
			Assert.areEqual(3, module.countLoaded(), 'Three sample grants are counted');
			Assert.isTrue(module.hasSampleRecords(), 'The card sees them');
			Grant__c awarded = [
				SELECT
					Amount_Awarded__c,
					Amount_Scheduled__c,
					Amount_Received__c,
					Restricted__c,
					Restricted_Spent__c,
					Restricted_Balance__c
				FROM Grant__c
				WHERE Stage__c = :GrantService.STAGE_AWARDED
			];
			Assert.areEqual(35000, awarded.Amount_Awarded__c, 'The award is filled in');
			Assert.areEqual(35000, awarded.Amount_Scheduled__c, 'The whole award is scheduled');
			Assert.areEqual(17500, awarded.Amount_Received__c, 'The first half is received');
			Assert.isTrue(awarded.Restricted__c, 'The award is restricted');
			Assert.areEqual(6000, awarded.Restricted_Spent__c, 'Some of it is spent');
			Assert.areEqual(11500, awarded.Restricted_Balance__c, 'And the balance is the rest');
			Assert.areEqual(
				3,
				[
					SELECT COUNT()
					FROM Grant_Requirement__c
					WHERE Grant__c = :awarded.Id
					WITH SYSTEM_MODE
				],
				'The award has its three requirements'
			);
		}
	}

	@IsTest
	static void eachStageIsLoadedAndTheRemovalLeavesRealGrants() {
		System.runAs(admin()) {
			sampleOrganizations();
			Account real = GrantTestData.funder('Real Foundation');
			insert GrantTestData.grant('Real grant', real.Id, GrantService.STAGE_PROSPECT);

			Test.startTest();
			loadEverything();
			Map<String, Integer> byStage = new Map<String, Integer>();
			for (Grant__c grant : [SELECT Stage__c FROM Grant__c WHERE Sample_Data__c = TRUE]) {
				Integer seen = byStage.get(grant.Stage__c);
				byStage.put(grant.Stage__c, seen == null ? 1 : seen + 1);
			}
			removeEverything();
			Test.stopTest();

			Assert.areEqual(
				new Map<String, Integer>{
					GrantService.STAGE_PROSPECT => 1,
					GrantService.STAGE_APPLIED => 1,
					GrantService.STAGE_AWARDED => 1
				},
				byStage,
				'One grant at each point of the pipeline'
			);
			Assert.areEqual(0, [SELECT COUNT() FROM Grant__c WHERE Sample_Data__c = TRUE]);
			Assert.areEqual(1, [SELECT COUNT() FROM Grant__c], 'The real grant stays');
			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Grant_Requirement__c WITH SYSTEM_MODE],
				'The sample requirements went with their grant'
			);
		}
	}

	@IsTest
	static void nothingLoadsWithoutSampleOrganizations() {
		System.runAs(admin()) {
			Test.startTest();
			loadEverything();
			Test.stopTest();

			Assert.areEqual(0, [SELECT COUNT() FROM Grant__c], 'No sample organizations, no grants');
			Assert.isFalse(SampleDataFile.find(FILE).hasSampleRecords());
		}
	}
}
