/**
 * Territory assignment joins the nightly run with a switch that ships off, and when it runs it
 * assigns only records with no territory, and only when there is something to do.
 */
@IsTest(testFor='ApexClass:TerritoryNightlyJobProvider')
private class TerritoryNightlyJobProviderTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith('Territory_Admin');
	}

	@IsTest
	static void theStepShipsOffAt545() {
		System.runAs(TestUsers.adminWith('Territory_Admin')) {
			List<NightlyStep> steps = new TerritoryNightlyJobProvider().nightlySteps();

			Assert.areEqual(1, steps.size(), 'One step');
			Assert.areEqual(TerritoryNightlyJobProvider.JOB_NAME, steps[0].key, 'Its key');
			Assert.isTrue(steps[0].hasSwitch(), 'It has a switch');
		}
	}

	@IsTest
	static void itAssignsOnlyUnassignedRecordsWhenARuleIsActive() {
		System.runAs(TestUsers.adminWith('Territory_Admin')) {
			Test.startTest();
			new TerritoryNightlyJobProvider.Assign().execute(null);
			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Territory_Run__c WITH SYSTEM_MODE],
				'No rule, no run'
			);
			Territory__c north = new Territory__c(
				Name = 'North',
				Priority__c = 1,
				Routing__c = TerritoryRouting.KEEP_OWNER
			);
			insert as user north;
			insert as user new Territory_Rule__c(
				Territory__c = north.Id,
				Applies_To__c = TerritoryRunBatch.KIND_PEOPLE,
				Active__c = true
			);
			insert as user new Contact(LastName = 'Alvarez');
			new TerritoryNightlyJobProvider.Assign().execute(null);
			Test.stopTest();

			Territory_Run__c run = [
				SELECT Mode__c, Only_Unassigned__c, Status__c, Changes__c
				FROM Territory_Run__c
				WITH SYSTEM_MODE
			];
			Assert.areEqual(TerritoryRunBatch.MODE_ASSIGN, run.Mode__c, 'Assigns');
			Assert.isTrue(run.Only_Unassigned__c, 'Only records with no territory');
			Assert.areEqual(TerritoryRunBatch.STATUS_DONE, run.Status__c, 'Done');
			Assert.areEqual(1, run.Changes__c, 'Alvarez moved');
		}
	}
}
