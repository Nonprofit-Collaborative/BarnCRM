/**
 * The Logic Models sample data set (C-10), shipped as LogicModelsSampleData.json and loaded by
 * Core's SampleDataFile after the Programs set: a logic model for each Programs sample program,
 * named with `find`, with every column, arrows with assumptions and evidence, and indicators
 * with periods. Without the sample programs nothing loads, so the set never claims the
 * organization's own model (R-LM1). The removal takes the sample models with their parts and
 * leaves the organization's own model alone. Run as a BarnCRM admin holding every installed
 * module's admin set (Logic Models Admin, and Programs Admin where Programs is installed), the
 * person who loads sample data. Programs is reached by describe only: Logic Models never
 * depends on it (R-LM2). The stages are called directly, because a test runs only the first
 * stage of a batch.
 */
@IsTest(testFor='ApexClass:SampleDataFile')
private class LogicModelsSampleDataTest {
	private static final String FILE = 'LogicModelsSampleData';
	private static final String TUTORING = 'After-school tutoring';
	private static final String PANTRY = 'Food pantry';

	@TestSetup
	static void makeAdmin() {
		TestUsers.adminWithInstalledModules();
	}

	private static User admin() {
		return TestUsers.adminWithInstalledModules();
	}

	/** The two Programs sample programs the file names, or none when Programs is not installed. */
	private static Map<String, Id> samplePrograms() {
		Map<String, Id> idsByName = new Map<String, Id>();
		Schema.SObjectType programType = NamespaceUtil.objectType('Program__c');
		if (programType == null) {
			return idsByName;
		}
		List<SObject> programs = new List<SObject>();
		for (String name : new List<String>{ TUTORING, PANTRY }) {
			SObject program = programType.newSObject();
			program.put(NamespaceUtil.field(programType, 'Name'), name);
			program.put(NamespaceUtil.field(programType, 'Status__c'), 'Active');
			program.put(NamespaceUtil.field(programType, 'Sample_Data__c'), true);
			programs.add(program);
		}
		insert programs;
		for (SObject program : programs) {
			idsByName.put((String) program.get('Name'), program.Id);
		}
		return idsByName;
	}

	private static Logic_Model__c organizationModel() {
		Logic_Model__c own = new Logic_Model__c(Name = 'Our theory of change');
		insert own;
		insert new Logic_Model_Element__c(
			Logic_Model__c = own.Id,
			Name = 'Our staff',
			Type__c = 'Input'
		);
		return own;
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
		stages.finish();
	}

	private static Integer partsOf(String modelName, String type) {
		return [
			SELECT COUNT()
			FROM Logic_Model_Element__c
			WHERE Logic_Model__r.Name = :modelName AND Type__c = :type
		];
	}

	@IsTest
	static void theLoadBuildsAModelForEachSampleProgram() {
		System.runAs(admin()) {
			Map<String, Id> programs = samplePrograms();

			Test.startTest();
			loadEverything();
			Test.stopTest();

			SampleDataModule module = SampleDataFile.find(FILE);
			Assert.areEqual('Logic Models', module.moduleName(), 'The name startAfter looks for.');
			if (programs.isEmpty()) {
				Assert.areEqual(0, [SELECT COUNT() FROM Logic_Model__c], 'No program, no model.');
				return;
			}
			Map<String, Logic_Model__c> byName = new Map<String, Logic_Model__c>();
			for (Logic_Model__c model : [
				SELECT Name, Program_Id__c, Scope_Key__c, Sample_Data__c
				FROM Logic_Model__c
			]) {
				byName.put(model.Name, model);
			}
			Assert.areEqual(2, byName.size(), 'A model for each sample program.');
			Logic_Model__c reading = byName.get('After-school tutoring logic model');
			Assert.areEqual(String.valueOf(programs.get(TUTORING)), reading.Program_Id__c);
			Assert.areEqual(reading.Program_Id__c, reading.Scope_Key__c, 'The program scope.');
			Assert.isTrue(reading.Sample_Data__c, 'Flagged for removal.');
			Assert.areEqual(
				String.valueOf(programs.get(PANTRY)),
				byName.get('Food pantry logic model').Program_Id__c
			);

			String model = reading.Name;
			Assert.areEqual(4, partsOf(model, 'Input'), 'Four inputs.');
			Assert.areEqual(3, partsOf(model, 'Activity'), 'Three activities.');
			Assert.areEqual(3, partsOf(model, 'Output'), 'Three outputs.');
			Assert.areEqual(4, partsOf(model, 'Outcome'), 'Outcomes of every term.');
			Assert.areEqual(1, partsOf(model, 'Impact'), 'One impact.');
			Assert.areEqual(
				3,
				[
						SELECT COUNT_DISTINCT(Outcome_Term__c) terms
						FROM Logic_Model_Element__c
						WHERE Logic_Model__r.Name = :model AND Type__c = 'Outcome'
					][0]
					.get('terms'),
				'Short, intermediate and long term outcomes.'
			);
			Assert.areEqual(
				0,
				[
					SELECT COUNT()
					FROM Logic_Model_Element__c
					WHERE
						Logic_Model__r.Name = :model
						AND Type__c = 'Outcome'
						AND Indicator_Count__c = 0
				],
				'Every tutoring outcome has an indicator, so Things to Look At is clear.'
			);
			Assert.areEqual(
				1,
				[
					SELECT COUNT()
					FROM Logic_Model_Element__c
					WHERE
						Logic_Model__r.Name = 'Food pantry logic model'
						AND Type__c = 'Outcome'
						AND Indicator_Count__c = 0
				],
				'One pantry outcome without an indicator shows a reminder.'
			);
			Assert.areEqual(25, [SELECT COUNT() FROM Logic_Model_Element__c], 'Every part.');
			Assert.areEqual(24, [SELECT COUNT() FROM Logic_Model_Link__c], 'Every arrow.');
			Assert.areEqual(8, [SELECT COUNT() FROM Assumption_Evidence__c], 'Evidence.');
			Assert.areEqual(
				4,
				[SELECT COUNT_DISTINCT(Strength__c) strengths FROM Assumption_Evidence__c][0]
					.get('strengths'),
				'Every strength, challenges included.'
			);
			Assert.areEqual(11, [SELECT COUNT() FROM Indicator__c], 'Indicators.');
			Assert.areEqual(
				2,
				[SELECT COUNT() FROM Indicator__c WHERE Better_When__c = 'Lower'],
				'Two where lower is better.'
			);
			Assert.areEqual(31, [SELECT COUNT() FROM Indicator_Period__c], 'Periods.');
			Assert.areEqual(
				20,
				[SELECT COUNT() FROM Indicator_Period__c WHERE Result_Value__c != NULL],
				'Results for the past periods, targets only for the current ones.'
			);
			Assert.areEqual(2, module.countLoaded(), 'The card counts them.');
			Assert.isTrue(module.hasSampleRecords(), 'Sample models exist.');
		}
	}

	@IsTest
	static void withoutTheSampleProgramsNothingLoads() {
		System.runAs(admin()) {
			Logic_Model__c own = organizationModel();

			Test.startTest();
			loadEverything();
			Test.stopTest();

			Assert.areEqual(
				new List<Id>{ own.Id },
				new List<Id>(new Map<Id, Logic_Model__c>([SELECT Id FROM Logic_Model__c]).keySet()),
				'No model is loaded, so none claims the organization scope.'
			);
			Assert.areEqual(1, [SELECT COUNT() FROM Logic_Model_Element__c], 'Only our own part.');
			Assert.areEqual(0, SampleDataFile.find(FILE).countLoaded(), 'Nothing counted.');
		}
	}

	@IsTest
	static void removalTakesTheSampleModelsAndLeavesTheOrganizationsOwn() {
		System.runAs(admin()) {
			Map<String, Id> programs = samplePrograms();
			Logic_Model__c own = organizationModel();
			loadEverything();
			Assert.areEqual(
				programs.isEmpty() ? 1 : 3,
				[SELECT COUNT() FROM Logic_Model__c],
				'The sample models sit beside our own.'
			);
			SampleDataFile.removeChunkSize = 1;

			Test.startTest();
			removeEverything();
			Test.stopTest();

			Assert.areEqual(own.Id, [SELECT Id FROM Logic_Model__c].Id, 'Our own model stays.');
			Assert.areEqual(1, [SELECT COUNT() FROM Logic_Model_Element__c], 'With its part.');
			Assert.areEqual(0, [SELECT COUNT() FROM Logic_Model_Link__c], 'Arrows went.');
			Assert.areEqual(0, [SELECT COUNT() FROM Indicator__c], 'Indicators went.');
			Assert.areEqual(0, [SELECT COUNT() FROM Indicator_Period__c], 'Periods went.');
			Assert.areEqual(0, [SELECT COUNT() FROM Assumption_Evidence__c], 'Evidence went.');
			Assert.isFalse(SampleDataFile.find(FILE).hasSampleRecords(), 'Nothing left.');
			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Error_Log__c WHERE Context__c = 'SampleDataFile'],
				'Nothing was kept.'
			);
		}
	}
}
