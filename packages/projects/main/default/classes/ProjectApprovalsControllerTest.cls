/**
 * The Approvals page (PM-07, PM-08): a project's owner sees and decides the Submitted time and
 * expenses of their own projects, a Projects admin sees every project, nobody else can decide,
 * a rejection needs a reason, approved time is locked and counts, and with approvals off the
 * page does nothing.
 */
@IsTest(testFor='ApexClass:ProjectApprovalsController, ApexClass:ProjectEntryHandler')
private class ProjectApprovalsControllerTest {
	@TestSetup
	static void setup() {
		TestUsers.adminWith(ProjectsTestData.ADMIN_SET);
	}

	private static Time_Entry__c submitted(Id projectId, Id personId, Decimal hours) {
		return new Time_Entry__c(
			Project__c = projectId,
			User__c = personId,
			Date__c = Date.today(),
			Hours__c = hours,
			Billable__c = true,
			Status__c = 'Submitted'
		);
	}

	private static void turnOn() {
		SettingsService.saveValues(
			'Projects_Settings__c',
			new Map<String, Object>{ 'Approvals_Enabled__c' => true, 'Expenses_Enabled__c' => true }
		);
	}

	@IsTest
	static void anOwnerSeesAndApprovesTheirProjectsAndAdminSeesAll() {
		User owner = ProjectsTestData.staff('Owner');
		User worker = ProjectsTestData.staff('Worker');
		Project__c mine;
		Project__c theirs;
		List<Time_Entry__c> mineEntries = new List<Time_Entry__c>();
		System.runAs(ProjectsTestData.admin()) {
			turnOn();
			theirs = ProjectsTestData.project('Active', null);
			insert new Project_Expense__c(
				Project__c = theirs.Id,
				User__c = worker.Id,
				Date__c = Date.today(),
				Category__c = 'Meals',
				Amount__c = 20,
				Status__c = 'Submitted'
			);
			insert submitted(theirs.Id, worker.Id, 2);
		}
		System.runAs(owner) {
			mine = new Project__c(
				Name = 'Owner Project',
				Type__c = 'Salesforce Implementation',
				Status__c = 'Active',
				Start_Date__c = Date.today().addDays(-30),
				Target_Date__c = Date.today().addDays(30),
				Hourly_Rate__c = 50
			);
			insert mine;
			for (Integer i = 0; i < 200; i++) {
				mineEntries.add(submitted(mine.Id, worker.Id, 1));
			}
			// Submitted on insert is allowed here: the owner is the manager of the project.
			insert mineEntries;

			ProjectApprovalsController.Queue queue = ProjectApprovalsController.getQueue();
			Assert.isTrue(queue.enabled, 'On');
			Assert.areEqual(
				200,
				queue.entries.size(),
				'Only the owner\'s project, not the admin\'s'
			);
			Assert.areEqual(0, queue.expenses.size(), 'The expense is on the other project');

			List<Id> ids = new List<Id>();
			for (Time_Entry__c entry : queue.entries) {
				ids.add(entry.Id);
			}
			Test.startTest();
			Integer decided = ProjectApprovalsController.decide(ids, true, null);
			Test.stopTest();

			Assert.areEqual(200, decided, 'All approved in one call');
			Assert.areEqual(
				200,
				[
					SELECT COUNT()
					FROM Time_Entry__c
					WHERE Status__c = 'Approved' AND Approved_By__c = :owner.Id
					WITH SYSTEM_MODE
				],
				'Approved By is the owner'
			);
			Assert.areEqual(
				200,
				[SELECT Actual_Hours__c FROM Project__c WHERE Id = :mine.Id WITH SYSTEM_MODE]
				.Actual_Hours__c,
				'Approved hours count'
			);
		}
		System.runAs(ProjectsTestData.admin()) {
			ProjectApprovalsController.Queue all = ProjectApprovalsController.getQueue();
			Assert.areEqual(
				1,
				all.entries.size(),
				'Admin sees the other project\'s Submitted entry'
			);
			Assert.areEqual(1, all.expenses.size(), 'and its expense');
		}
	}

	@IsTest
	static void anotherPersonCannotDecideAndARejectionNeedsAReason() {
		User worker = ProjectsTestData.staff('Worker');
		User bystander = ProjectsTestData.staff('Bystander');
		Time_Entry__c entry;
		System.runAs(ProjectsTestData.admin()) {
			turnOn();
			Project__c project = ProjectsTestData.project('Active', null);
			entry = submitted(project.Id, worker.Id, 2);
			insert entry;
		}
		System.runAs(bystander) {
			try {
				ProjectApprovalsController.decide(new List<Id>{ entry.Id }, true, null);
				Assert.fail('Only the owner or an admin approves');
			} catch (AuraHandledException refused) {
				Assert.isTrue(refused.getMessage().contains('owner'), refused.getMessage());
			}
		}
		System.runAs(ProjectsTestData.admin()) {
			try {
				ProjectApprovalsController.decide(new List<Id>{ entry.Id }, false, ' ');
				Assert.fail('A reason is needed');
			} catch (AuraHandledException refused) {
				Assert.isNotNull(refused.getMessage(), 'Told in words');
			}
			Assert.areEqual(
				1,
				ProjectApprovalsController.decide(new List<Id>{ entry.Id }, false, 'Wrong project'),
				'Rejected'
			);
			Time_Entry__c saved = [
				SELECT Status__c, Rejection_Reason__c
				FROM Time_Entry__c
				WHERE Id = :entry.Id
				WITH SYSTEM_MODE
			];
			Assert.areEqual('Rejected', saved.Status__c, 'Rejected');
			Assert.areEqual('Wrong project', saved.Rejection_Reason__c, 'With the reason');
			Assert.areEqual(
				0,
				ProjectApprovalsController.decide(new List<Id>{ entry.Id }, true, null),
				'Only Submitted entries are decided'
			);
		}
	}

	@IsTest
	static void approvedTimeIsLockedToThePersonAndWithApprovalsOffTheQueueIsEmpty() {
		User worker = ProjectsTestData.staff('Worker');
		Time_Entry__c entry;
		System.runAs(ProjectsTestData.admin()) {
			Assert.isFalse(ProjectApprovalsController.getQueue().enabled, 'Off by default');
			try {
				ProjectApprovalsController.decide(new List<Id>(), true, null);
				Assert.fail('Refused while off');
			} catch (AuraHandledException refused) {
				Assert.isTrue(
					refused.getMessage().contains('Approve time and expenses'),
					refused.getMessage()
				);
			}
			turnOn();
			Project__c project = ProjectsTestData.project('Active', null);
			entry = submitted(project.Id, worker.Id, 2);
			insert entry;
			ProjectApprovalsController.decide(new List<Id>{ entry.Id }, true, null);
		}
		System.runAs(worker) {
			try {
				update new Time_Entry__c(Id = entry.Id, Hours__c = 8);
				Assert.fail('Approved time is locked');
			} catch (DmlException locked) {
				Assert.isTrue(locked.getMessage().contains('locked'), locked.getMessage());
			}
		}
	}
}
