/**
 * The Project Management sample data set (C-10): four projects with their phases, tasks, hours,
 * expenses, status updates, assignments, a resource and open resource requests, plus requests and
 * change requests while those settings are on; counted on the card, removed again with the
 * org's own projects, resources and requests left alone. Run as a BarnCRM admin holding Projects
 * Admin, the person who loads sample data.
 *
 * The set ships as ProjectsSampleData.json and Core's SampleDataFile loads it (D-200 S2). The
 * stages are called directly, as the other modules' tests do, because a test runs only the
 * first stage of a batch.
 */
@IsTest(testFor='ApexClass:SampleDataFile')
private class ProjectsSampleDataTest {
	private static final String FILE = 'ProjectsSampleData';

	@TestSetup
	static void makeAdmin() {
		TestUsers.adminWith(ProjectsTestData.ADMIN_SET);
	}

	private static User admin() {
		return TestUsers.adminWith(ProjectsTestData.ADMIN_SET);
	}

	private static void turnOnRequests() {
		SettingsService.saveValues(
			'Projects_Settings__c',
			new Map<String, Object>{
				'Requests_Enabled__c' => true,
				'Change_Requests_Enabled__c' => true
			}
		);
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
	static void theLoadBuildsFourProjectsWithTheirWork() {
		System.runAs(admin()) {
			turnOnRequests();

			Test.startTest();
			loadEverything();
			Test.stopTest();

			SampleDataModule module = SampleDataFile.find(FILE);
			Assert.areEqual('Projects', module.moduleName(), 'The name startAfter looks for');
			Assert.areEqual(4, module.countLoaded(), 'Four sample projects are counted');
			Assert.isTrue(module.hasSampleRecords(), 'The card sees them');
			Project__c caseManagement = [
				SELECT Id, Tasks__c, Tasks_Done__c
				FROM Project__c
				WHERE Name = 'Client Intake Implementation'
				WITH SYSTEM_MODE
			];
			Assert.areEqual(6, caseManagement.Tasks__c, 'Six tasks count on the project');
			Assert.areEqual(2, caseManagement.Tasks_Done__c, 'Two are done');
			Assert.areEqual(
				3,
				[
					SELECT COUNT()
					FROM Project_Phase__c
					WHERE Project__c = :caseManagement.Id
					WITH SYSTEM_MODE
				],
				'Three phases'
			);
			Assert.areEqual(
				2,
				[
					SELECT COUNT()
					FROM Project_Task__c
					WHERE Project__c = :caseManagement.Id AND Milestone__c = TRUE
					WITH SYSTEM_MODE
				],
				'Two milestones'
			);
			Assert.areEqual(
				12,
				[SELECT COUNT() FROM Project_Task__c WITH SYSTEM_MODE],
				'Twelve tasks in all'
			);
			Assert.areEqual(
				11,
				[SELECT COUNT() FROM Time_Entry__c WITH SYSTEM_MODE],
				'Eleven time entries'
			);
			Assert.areEqual(
				3,
				[SELECT COUNT() FROM Project_Expense__c WITH SYSTEM_MODE],
				'Three expenses'
			);
			Assert.areEqual(
				3,
				[SELECT COUNT() FROM Project_Status_Update__c WITH SYSTEM_MODE],
				'Three status updates'
			);
			Assert.areEqual(
				2,
				[SELECT COUNT() FROM Project_Assignment__c WITH SYSTEM_MODE],
				'Two assignments'
			);
			Assert.areEqual(
				1,
				[SELECT COUNT() FROM Project_Resource__c WHERE Sample_Data__c = TRUE],
				'One resource'
			);
			Assert.areEqual(
				2,
				[SELECT COUNT() FROM Resource_Request__c WITH SYSTEM_MODE],
				'Two resource requests'
			);
			Assert.areEqual(
				3,
				[SELECT COUNT() FROM Project_Request__c WHERE Sample_Data__c = TRUE],
				'Three requests while requests are on'
			);
			Assert.areEqual(
				2,
				[SELECT COUNT() FROM Project_Change_Request__c WITH SYSTEM_MODE],
				'Two change requests while they are on'
			);
		}
	}

	@IsTest
	static void withRequestsOffNoRequestsAreLoaded() {
		System.runAs(admin()) {
			Test.startTest();
			loadEverything();
			Test.stopTest();

			Assert.areEqual(
				4,
				[SELECT COUNT() FROM Project__c WHERE Sample_Data__c = TRUE],
				'The projects load either way'
			);
			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Project_Request__c WITH SYSTEM_MODE],
				'Requests are off, so none are loaded'
			);
			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Project_Change_Request__c WITH SYSTEM_MODE],
				'Change requests are off, so none are loaded'
			);
		}
	}

	@IsTest
	static void theRemovalTakesTheSampleSetAndLeavesRealRecords() {
		System.runAs(admin()) {
			turnOnRequests();
			Project__c real = new Project__c(
				Name = 'Real Project',
				Type__c = 'Internal',
				Status__c = 'Active'
			);
			insert as user real;
			insert as user new Project_Task__c(
				Name = 'Real Task',
				Project__c = real.Id,
				Status__c = 'Not Started'
			);
			insert as user new Project_Request__c(
				Subject__c = 'Real Request',
				Priority__c = 'Medium',
				Status__c = 'New'
			);

			Test.startTest();
			loadEverything();
			SampleDataFile.removeChunkSize = 3;
			removeEverything();
			Test.stopTest();

			Assert.areEqual(0, [SELECT COUNT() FROM Project__c WHERE Sample_Data__c = TRUE]);
			Assert.areEqual(1, [SELECT COUNT() FROM Project__c], 'The real project stays');
			Assert.areEqual(
				1,
				[SELECT COUNT() FROM Project_Task__c WITH SYSTEM_MODE],
				'The sample tasks went with their projects'
			);
			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Time_Entry__c WITH SYSTEM_MODE],
				'The sample hours went with their projects'
			);
			Assert.areEqual(
				1,
				[SELECT COUNT() FROM Project_Request__c WITH SYSTEM_MODE],
				'The real request stays'
			);
			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Project_Resource__c WHERE Sample_Data__c = TRUE],
				'The sample resource is gone'
			);
		}
	}
}
