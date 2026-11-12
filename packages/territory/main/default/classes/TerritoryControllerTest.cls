/**
 * The Territory Management page's server side: the page's data, a rule's count, starting a run
 * (one at a time) and undoing an Assign run from its Data job.
 */
@IsTest(testFor='ApexClass:TerritoryController')
private class TerritoryControllerTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith('Territory_Admin');
	}

	private static final String ALVAREZ = '{"version": 1, "conditions": [{"id": 1, "field": "LastName", "operator": "equals", "value": "Alvarez"}]}';

	private static Territory__c northWithRule() {
		Territory__c north = new Territory__c(
			Name = 'North',
			Priority__c = 10,
			Routing__c = TerritoryRouting.KEEP_OWNER
		);
		insert as user north;
		insert as user new Territory_Rule__c(
			Territory__c = north.Id,
			Applies_To__c = TerritoryRunBatch.KIND_PEOPLE,
			Filter_JSON__c = ALVAREZ,
			Active__c = true
		);
		return north;
	}

	@IsTest
	static void thePageListsTerritoriesAndCountsARule() {
		System.runAs(TestUsers.adminWith('Territory_Admin')) {
			northWithRule();
			insert as user new List<Contact>{
				new Contact(LastName = 'Alvarez'),
				new Contact(LastName = 'Brooks')
			};

			Map<String, Object> page = TerritoryController.getPage();
			Integer counted = TerritoryController.countRule(TerritoryRunBatch.KIND_PEOPLE, ALVAREZ);

			List<Object> territories = (List<Object>) page.get('territories');
			Assert.areEqual(1, territories.size(), 'North');
			Map<String, Object> north = (Map<String, Object>) territories[0];
			Assert.areEqual(1, ((List<Object>) north.get('rules')).size(), 'With its rule');
			Assert.areEqual(false, page.get('busy'), 'Nothing running');
			Assert.areEqual(1, counted, 'One Alvarez');
			Assert.isNotNull(
				TerritoryController.countRule(TerritoryRunBatch.KIND_ORGANIZATIONS, null),
				'A kind counts without a filter'
			);
		}
	}

	@IsTest
	static void oneRunAtATimeAndAnAssignRunIsUndone() {
		System.runAs(TestUsers.adminWith('Territory_Admin')) {
			northWithRule();
			insert as user new Contact(LastName = 'Alvarez');

			Test.startTest();
			Id runId = TerritoryController.startRun(TerritoryRunBatch.MODE_ASSIGN, false);
			try {
				TerritoryController.startRun(TerritoryRunBatch.MODE_PREVIEW, false);
				Assert.fail('A second run waits');
			} catch (AuraHandledException refused) {
				Assert.areEqual(
					BarnHelp.text('Territory', 'Territory_Error_Busy'),
					refused.getMessage(),
					'Told why'
				);
			}
			Test.stopTest();

			Assert.isNotNull(TerritoryController.undoRun(runId), 'The undo starts');
			Territory_Run__c run = [
				SELECT Data_Job_Id__c
				FROM Territory_Run__c
				WHERE Id = :runId
				WITH SYSTEM_MODE
			];
			Assert.areEqual(
				ImportBatchService.STATUS_UNDOING,
				[
					SELECT Status__c
					FROM Import_Batch__c
					WHERE Id = :run.Data_Job_Id__c
					WITH SYSTEM_MODE
				]
				.Status__c,
				'The job is being undone'
			);
		}
	}

	@IsTest
	static void refusalsAreShownAsWritten() {
		System.runAs(TestUsers.adminWith('Territory_Admin')) {
			try {
				TerritoryController.startRun(TerritoryRunBatch.MODE_PREVIEW, false);
				Assert.fail('No rules, nothing to run');
			} catch (AuraHandledException refused) {
				Assert.areEqual(
					BarnHelp.text('Territory', 'Territory_Error_NothingToRun'),
					refused.getMessage(),
					'Told why'
				);
			}
			Territory_Run__c preview = new Territory_Run__c(
				Mode__c = TerritoryRunBatch.MODE_PREVIEW,
				Status__c = TerritoryRunBatch.STATUS_DONE
			);
			insert as system preview;
			try {
				TerritoryController.undoRun(preview.Id);
				Assert.fail('A preview has nothing to undo');
			} catch (AuraHandledException refused) {
				Assert.areEqual(
					BarnHelp.text('Territory', 'Territory_Error_NoJob'),
					refused.getMessage(),
					'Told why'
				);
			}
		}
	}
}
