/**
 * Core's generic module sample data loader (D-200 S2), run on a small file of saved queries
 * injected in place of a module's static resource: keys and links between records, a link that
 * does not resolve leaves its record out unless optional, the count and the removal, the
 * Warning naming what removal kept, and the batches the module seam starts. The module files
 * themselves are tested in their own packages (FundersSampleDataTest, ProgramSampleDataTest,
 * EventsSampleDataTest).
 */
@IsTest(testFor='ApexClass:SampleDataFile, ApexClass:SampleDataModules')
private class SampleDataFileTest {
	private static final String FILE = 'TestSampleData';

	@TestSetup
	static void makeAdmin() {
		TestUsers.adminWithInstalledModules();
	}

	private static void injectFile() {
		SampleDataFile.filesByName.put(
			FILE,
			(Map<String, Object>) JSON.deserializeUntyped(
				'{"module": "Testing", "countLabel": "Queries",' +
					' "count": {"object": "Saved_Query__c", "where": "Name LIKE \'Sample %\'"},' +
					' "steps": [' +
					'  {"object": "Saved_Query__c", "records": [' +
					'   {"key": "first", "Name": "Sample first", "Object_Name__c": "Contact"}]},' +
					'  {"object": "Saved_Query__c", "records": [' +
					'   {"Name": "Sample second", "Object_Name__c": {"ref": "first"},' +
					'    "Query_JSON__c": {"currentUser": true}},' +
					'   {"Name": "Sample skipped", "Object_Name__c": {"ref": "nowhere"}},' +
					'   {"Name": "Sample optional", "Object_Name__c": {"sample": "H999-9", "optional": true}}]},' +
					'  {"object": "No_Such_Object__c", "records": [{"Name": "x"}]}],' +
					' "remove": [{"object": "Saved_Query__c", "where": "Name LIKE \'Sample %\'"}]}'
			)
		);
	}

	private static void loadEverything() {
		SampleDataFile.LoadStages stages = new SampleDataFile.LoadStages(FILE);
		for (Integer stage = 0; stage < stages.stageCount(); stage++) {
			stages.runStage(stage);
		}
	}

	@IsTest
	static void theFileLoadsInOrderWithItsLinks() {
		System.runAs(TestUsers.adminWithInstalledModules()) {
			injectFile();

			Test.startTest();
			loadEverything();
			Test.stopTest();

			Map<String, Saved_Query__c> byName = new Map<String, Saved_Query__c>();
			for (Saved_Query__c row : [
				SELECT Id, Name, Object_Name__c, Query_JSON__c
				FROM Saved_Query__c
			]) {
				byName.put(row.Name, row);
			}
			Assert.areEqual(3, byName.size(), 'The record with an unresolved link is left out');
			Assert.areEqual(
				(String) byName.get('Sample first').Id,
				byName.get('Sample second').Object_Name__c,
				'A ref is the Id of the record of that key'
			);
			Assert.areEqual(UserInfo.getUserId(), byName.get('Sample second').Query_JSON__c);
			Assert.isNull(
				byName.get('Sample optional').Object_Name__c,
				'An optional link is blank'
			);

			SampleDataModule module = SampleDataFile.find(FILE);
			Assert.areEqual('Testing', module.moduleName());
			Assert.areEqual('Queries', module.countLabel());
			Assert.areEqual(3, module.countLoaded(), 'The card counts the file\'s count query');
			Assert.isTrue(module.hasSampleRecords());
		}
	}

	@IsTest
	static void theRemovalDeletesInChunksAndNamesWhatItKept() {
		System.runAs(TestUsers.adminWithInstalledModules()) {
			injectFile();
			loadEverything();
			SampleDataFile.removeChunkSize = 2;
			SampleDataFile.RemoveStages stages = new SampleDataFile.RemoveStages(FILE);
			Integer stageCount = stages.stageCount();

			Test.startTest();
			for (Integer stage = 0; stage < stageCount; stage++) {
				stages.runStage(stage);
			}
			Test.stopTest();

			Assert.areEqual(2, stageCount, 'Three rows in chunks of two');
			Assert.areEqual(0, [SELECT COUNT() FROM Saved_Query__c], 'Every sample row went');
			Assert.isFalse(SampleDataFile.find(FILE).hasSampleRecords());

			Saved_Query__c kept = new Saved_Query__c(
				Name = 'Sample kept',
				Object_Name__c = 'Contact'
			);
			insert kept;
			String message = SampleDataFile.logKept(
				'Testing',
				new Map<Id, String>{ kept.Id => 'Saved_Query__c' }
			);
			Assert.isTrue(message.contains('Sample kept'), 'The Warning names the kept record');
			Assert.areEqual(
				1,
				[SELECT COUNT() FROM Error_Log__c WHERE Context__c = 'SampleDataFile']
			);
			Assert.isNull(SampleDataFile.logKept('Testing', new Map<Id, String>()));
		}
	}

	@IsTest
	static void theSeamStartsCoresBatchesAndAMissingFileIsNoModule() {
		System.runAs(TestUsers.adminWithInstalledModules()) {
			injectFile();
			Assert.isNull(SampleDataFile.find('NoSuchSampleData'), 'Not installed, no module');
			Assert.areEqual(FILE + '.load', new SampleDataFile.LoadStages(FILE).name());
			Assert.areEqual(FILE + '.remove', new SampleDataFile.RemoveStages(FILE).name());

			Test.startTest();
			SampleDataFile.find(FILE).enqueueLoad();
			SampleDataFile.find(FILE).enqueueRemove();
			new SampleDataFile.LoadStages(FILE).finish();
			new SampleDataFile.RemoveStages(FILE).finish();
			Test.stopTest();

			Assert.isTrue(
				[
					SELECT COUNT()
					FROM AsyncApexJob
					WHERE ApexClass.Name IN ('SampleDataStageBatch', 'SampleDataRemoveBatch')
				] >= 2,
				'Both run in Core\'s batches'
			);
		}
	}
}
