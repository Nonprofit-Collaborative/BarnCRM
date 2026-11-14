/**
 * Core's own module-format sample file (C-10, D-200 S2): three saved Find queries, one marked as
 * a Backup Set, two seasonal addresses and three interaction notes on Core's sample households
 * and people, counted on the card and removed again with the organization's own records left
 * alone. Run as a BarnCRM admin, the person who loads sample data.
 *
 * The stages are called directly, as the module files' tests do, because a test runs only the
 * first stage of a batch.
 */
@IsTest(testFor='ApexClass:SampleDataFile')
private class CoreSampleDataTest {
	private static final String FILE = 'CoreSampleData';

	@TestSetup
	static void makeAdmin() {
		TestUsers.admin();
	}

	/** The sample households and people the file points at, flagged and keyed. */
	private static void sampleHouseholdsAndPeople() {
		List<Account> households = new List<Account>();
		for (String key : new List<String>{ 'H007', 'H008' }) {
			households.add(
				TestDataFactory.household(
					new Account(
						Name = 'Sample Household ' + key,
						Sample_Data__c = true,
						Sample_Data_Key__c = key
					)
				)
			);
		}
		insert households;
		List<Contact> people = new List<Contact>();
		for (String key : new List<String>{ 'H002-1', 'H004-1', 'H007-1' }) {
			people.add(
				TestDataFactory.person(
					new Contact(
						FirstName = 'Sample',
						LastName = 'Person ' + key,
						Sample_Data__c = true,
						Sample_Data_Key__c = key
					)
				)
			);
		}
		insert people;
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
	static void theLoadSavesQueriesABackupSetSeasonalAddressesAndNotes() {
		System.runAs(TestUsers.admin()) {
			sampleHouseholdsAndPeople();

			Test.startTest();
			loadEverything();
			Test.stopTest();

			SampleDataModule module = SampleDataFile.find(FILE);
			Assert.areEqual('Core', module.moduleName(), 'The name startAfter looks for');
			Assert.areEqual(3, module.countLoaded(), 'Three saved queries are counted');
			Assert.isTrue(module.hasSampleRecords(), 'The card sees them');
			Integer backupSets = 0;
			for (Saved_Query__c saved : [
				SELECT Name, Object_Name__c, Query_JSON__c
				FROM Saved_Query__c
				WHERE Sample_Data__c = TRUE
				WITH SYSTEM_MODE
			]) {
				QueryCompiler.Compiled compiled = QueryCompiler.compile(saved.Query_JSON__c);
				Assert.areEqual(
					saved.Object_Name__c,
					compiled.objectName,
					saved.Name + ' compiles in Find'
				);
				if (BackupSetService.isBackupSet(saved.Query_JSON__c)) {
					backupSets++;
				}
			}
			Assert.areEqual(1, backupSets, 'One of them is a Backup Set');
			Assert.areEqual(
				2,
				[
					SELECT COUNT()
					FROM Address__c
					WHERE
						Type__c = 'Seasonal'
						AND Seasonal_Start_Month__c = 12
						AND Account__r.Sample_Data__c = TRUE
					WITH SYSTEM_MODE
				],
				'Two winter addresses that cross the new year'
			);
			Assert.areEqual(
				3,
				[
					SELECT COUNT()
					FROM Task
					WHERE Type = 'Meeting' AND Status = 'Completed'
					WITH SYSTEM_MODE
				],
				'Three interaction notes'
			);
		}
	}

	@IsTest
	static void theRemovalTakesTheSampleRowsAndLeavesRealOnes() {
		System.runAs(TestUsers.admin()) {
			sampleHouseholdsAndPeople();
			Account realHousehold = TestDataFactory.household(new Account(Name = 'Real Household'));
			insert realHousehold;
			insert new Saved_Query__c(Name = 'My Query', Object_Name__c = 'Contact');
			insert new Address__c(
				Account__c = realHousehold.Id,
				Type__c = 'Seasonal',
				Street__c = '1 Example Street',
				Seasonal_Start_Month__c = 12,
				Seasonal_Start_Day__c = 1,
				Seasonal_End_Month__c = 3,
				Seasonal_End_Day__c = 31
			);

			Test.startTest();
			loadEverything();
			SampleDataFile.removeChunkSize = 1;
			removeEverything();
			Test.stopTest();

			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Saved_Query__c WHERE Sample_Data__c = TRUE WITH SYSTEM_MODE],
				'The sample queries are gone'
			);
			Assert.areEqual(
				1,
				[SELECT COUNT() FROM Saved_Query__c WITH SYSTEM_MODE],
				'The real query stays'
			);
			Assert.areEqual(
				1,
				[SELECT COUNT() FROM Address__c WHERE Type__c = 'Seasonal' WITH SYSTEM_MODE],
				'Only the real household keeps its seasonal address'
			);
			Assert.isFalse(SampleDataFile.find(FILE).hasSampleRecords(), 'Nothing is left');
		}
	}
}
