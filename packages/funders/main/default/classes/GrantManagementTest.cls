/**
 * Grant management (F-10 to F-13; R-GQ7, R-GQ8, R-BL1, R-BL2, R-FE3, R-GN12): checklist tasks by
 * stage, in bulk and once each; ticking a task done; documents with their files; budget lines
 * against spending; the renewal requirement, Start Renewal and the history; a reader changes
 * nothing.
 */
@IsTest(
	testFor='ApexClass:GrantManagementService, ApexClass:GrantManagementController, ApexClass:GrantChecklistHandler, ApexClass:GrantRenewalHandler'
)
private class GrantManagementTest {
	@TestSetup
	static void createTestUsers() {
		TestUsers.adminWith(GrantTestData.ADMIN);
		TestUsers.standardUserWith(
			'Gmreader',
			new List<String>{ 'BarnCRM_Read_Only', 'Funders_Read_Only' }
		);
	}

	private static User reader() {
		return [SELECT Id FROM User WHERE LastName = 'Gmreader' WITH SYSTEM_MODE LIMIT 1];
	}

	private static List<Grant_Requirement__c> requirementsOf(Id grantId, String type) {
		return [
			SELECT Id, Name, Status__c, Due_Date__c, Assigned_To__c, Checklist_Item__c
			FROM Grant_Requirement__c
			WHERE Grant__c = :grantId AND Type__c = :type
			WITH SYSTEM_MODE
			ORDER BY Due_Date__c
		];
	}

	@IsTest
	static void checklistTasksFollowTheStageOncePerGrant() {
		System.runAs(TestUsers.adminWith(GrantTestData.ADMIN)) {
			Date today = Date.today();
			insert new List<Grant_Checklist_Item__c>{
				new Grant_Checklist_Item__c(
					Name = 'Call the program officer',
					Stage__c = 'Prospect',
					Days_Before_Deadline__c = 7,
					Assigned_To__c = UserInfo.getUserId()
				),
				new Grant_Checklist_Item__c(Name = 'Attach the budget', Stage__c = 'Applied'),
				new Grant_Checklist_Item__c(
					Name = 'Retired step',
					Stage__c = 'Prospect',
					Active__c = false
				)
			};
			Account funder = GrantTestData.funder('Lakeside Foundation');
			List<Grant__c> grants = new List<Grant__c>();
			for (Integer i = 0; i < 60; i++) {
				Grant__c grant = GrantTestData.grant(
					'Grant ' + i,
					funder.Id,
					GrantService.STAGE_PROSPECT
				);
				grant.Application_Deadline__c = today.addDays(30);
				grants.add(grant);
			}

			Test.startTest();
			insert grants;
			Grant__c first = grants[0];
			first.Stage__c = GrantService.STAGE_APPLIED;
			update first;
			Integer added = GrantManagementController.addChecklistTasks(first.Id);
			Test.stopTest();

			List<Grant_Requirement__c> tasks = requirementsOf(first.Id, 'Task');
			Assert.areEqual(2, tasks.size(), 'One task per active item of each stage reached');
			Assert.areEqual(
				today.addDays(23),
				tasks[0].Due_Date__c,
				'Seven days before the deadline'
			);
			Assert.areEqual(
				UserInfo.getUserId(),
				tasks[0].Assigned_To__c,
				'The item names who does it'
			);
			Assert.areEqual(today.addDays(30), tasks[1].Due_Date__c, 'Blank days: the deadline');
			Assert.areEqual(0, added, 'Nothing missing, nothing added');
			Assert.areEqual(
				60,
				[
					SELECT COUNT()
					FROM Grant_Requirement__c
					WHERE Name = 'Call the program officer'
					WITH SYSTEM_MODE
				],
				'Every grant inserted at Prospect got its task'
			);
		}
	}

	@IsTest
	static void aTaskIsNeverDueBeforeTodayAndNoDeadlineGivesTwoWeeks() {
		System.runAs(reader()) {
			Date today = Date.today();
			Assert.areEqual(
				today,
				GrantManagementService.dueDate(today.addDays(3), 10, today),
				'Not in the past'
			);
			Assert.areEqual(
				today.addDays(14),
				GrantManagementService.dueDate(null, 10, today),
				'No deadline'
			);
			Assert.areEqual(
				today.addDays(5),
				GrantManagementService.dueDate(today.addDays(5), null, today),
				'On it'
			);
		}
	}

	@IsTest
	static void aTaskIsTickedDoneAndOpenAgain() {
		System.runAs(TestUsers.adminWith(GrantTestData.ADMIN)) {
			Grant__c grant = GrantTestData.grant(
				'Literacy',
				GrantTestData.funder('Lakeside').Id,
				'Prospect'
			);
			insert grant;
			Grant_Requirement__c task = GrantTestData.requirement('Call', grant.Id, Date.today());
			task.Type__c = 'Task';
			insert task;

			Test.startTest();
			GrantManagementController.setTaskDone(task.Id, true);
			Map<String, Object> done = GrantManagementController.getChecklist(grant.Id);
			GrantManagementController.setTaskDone(task.Id, false);
			Test.stopTest();

			Map<String, Object> row = (Map<String, Object>) ((List<Object>) done.get('tasks'))[0];
			Assert.isTrue((Boolean) row.get('done'), 'Done is a done status');
			Assert.isTrue((Boolean) done.get('canEdit'), 'An admin can tick');
			Assert.areEqual(
				'Not Started',
				requirementsOf(grant.Id, 'Task')[0].Status__c,
				'Open again'
			);
		}
	}

	@IsTest
	static void documentsShowTheirLatestFile() {
		System.runAs(TestUsers.adminWith(GrantTestData.ADMIN)) {
			Grant__c grant = GrantTestData.grant(
				'Literacy',
				GrantTestData.funder('Lakeside').Id,
				'Prospect'
			);
			insert grant;
			Grant_Requirement__c letter = GrantTestData.requirement(
				'Letter',
				grant.Id,
				Date.today()
			);
			letter.Type__c = 'Letter of Inquiry';
			Grant_Requirement__c visit = GrantTestData.requirement('Visit', grant.Id, Date.today());
			visit.Type__c = 'Site Visit';
			insert new List<Grant_Requirement__c>{ letter, visit };
			insert new ContentVersion(
				Title = 'loi',
				PathOnClient = 'loi.pdf',
				VersionData = Blob.valueOf('draft'),
				FirstPublishLocationId = letter.Id
			);

			Test.startTest();
			Map<String, Object> card = GrantManagementController.getDocuments(grant.Id);
			Test.stopTest();

			List<Object> documents = (List<Object>) card.get('documents');
			Assert.areEqual(1, documents.size(), 'A site visit is not a document');
			Map<String, Object> document = (Map<String, Object>) documents[0];
			Assert.areEqual(1, document.get('fileCount'), 'Its file');
			Assert.areEqual('loi', document.get('fileTitle'), 'The latest file');
			Assert.areEqual('1', document.get('fileVersion'), 'Its version number');
		}
	}

	@IsTest
	static void theBudgetComparesLinesWithSpending() {
		System.runAs(TestUsers.adminWith(GrantTestData.ADMIN)) {
			Account funder = GrantTestData.funder('Lakeside');
			Grant__c grant = GrantTestData.grant('Literacy', funder.Id, 'Awarded');
			grant.Amount_Awarded__c = 25000;
			Grant__c other = GrantTestData.grant('Other', funder.Id, 'Awarded');
			insert new List<Grant__c>{ grant, other };
			Grant_Budget_Line__c staff = new Grant_Budget_Line__c(
				Grant__c = grant.Id,
				Name = 'Staff',
				Amount_Requested__c = 20000,
				Amount_Awarded__c = 18000
			);
			insert staff;
			insert new List<Grant_Fund_Entry__c>{
				new Grant_Fund_Entry__c(
					Grant__c = grant.Id,
					Type__c = 'Spent',
					Amount__c = 4000,
					Budget_Line__c = staff.Id
				),
				new Grant_Fund_Entry__c(Grant__c = grant.Id, Type__c = 'Spent', Amount__c = 1000),
				new Grant_Fund_Entry__c(
					Grant__c = grant.Id,
					Type__c = 'Received',
					Amount__c = 9000,
					Budget_Line__c = staff.Id
				)
			};

			Test.startTest();
			Map<String, Object> budget = GrantManagementController.getBudget(grant.Id);
			Boolean refused = false;
			try {
				insert new Grant_Fund_Entry__c(
					Grant__c = other.Id,
					Type__c = 'Spent',
					Amount__c = 5,
					Budget_Line__c = staff.Id
				);
			} catch (DmlException e) {
				refused = true;
			}
			Test.stopTest();

			Map<String, Object> line = (Map<String, Object>) ((List<Object>) budget.get(
				'lines'
			))[0];
			Assert.areEqual(
				4000,
				(Decimal) line.get('spent'),
				'Only Spent entries count toward a line'
			);
			Assert.areEqual(1000, (Decimal) budget.get('unassignedSpent'), 'Spent on no line');
			Assert.areEqual(
				25000,
				(Decimal) budget.get('amountAwarded'),
				'The grant amount to compare'
			);
			Assert.isTrue(refused, 'A line of another grant is refused');
		}
	}

	@IsTest
	static void aRenewableAwardGetsItsRenewalAndStartsTheNextCycle() {
		System.runAs(TestUsers.adminWith(GrantTestData.ADMIN)) {
			Date today = Date.today();
			Grant__c grant = GrantTestData.grant(
				'Literacy',
				GrantTestData.funder('Lakeside').Id,
				'Awarded'
			);
			grant.Amount_Requested__c = 30000;
			grant.Amount_Awarded__c = 25000;
			grant.Award_Start_Date__c = today;
			grant.Award_End_Date__c = today.addDays(200);
			grant.Purpose__c = 'Tutoring';
			insert grant;
			insert new Grant_Budget_Line__c(
				Grant__c = grant.Id,
				Name = 'Staff',
				Amount_Requested__c = 20000,
				Amount_Awarded__c = 18000
			);
			Integer beforeRenewable = requirementsOf(grant.Id, 'Renewal').size();

			Test.startTest();
			update new Grant__c(Id = grant.Id, Renewable__c = true);
			Date firstDue = requirementsOf(grant.Id, 'Renewal')[0].Due_Date__c;
			update new Grant__c(Id = grant.Id, Award_End_Date__c = today.addDays(230));
			Id nextId = GrantManagementController.startRenewal(grant.Id);
			Test.stopTest();

			Assert.areEqual(0, beforeRenewable, 'Not renewable, no requirement');
			Assert.areEqual(today.addDays(110), firstDue, 'Ninety days before the end');
			List<Grant_Requirement__c> renewals = requirementsOf(grant.Id, 'Renewal');
			Assert.areEqual(1, renewals.size(), 'One, moved rather than added');
			Assert.areEqual(today.addDays(140), renewals[0].Due_Date__c, 'Moved with the end date');
			Assert.areEqual('Done', renewals[0].Status__c, 'Done once renewed');
			Grant__c next = [
				SELECT
					Stage__c,
					Renewal_Of__c,
					Renewable__c,
					Amount_Requested__c,
					Purpose__c,
					(SELECT Amount_Requested__c FROM Budget_Lines__r)
				FROM Grant__c
				WHERE Id = :nextId
				WITH SYSTEM_MODE
			];
			Assert.areEqual('Prospect', next.Stage__c, 'Starts at Prospect');
			Assert.areEqual(grant.Id, next.Renewal_Of__c, 'Linked to the award');
			Assert.areEqual(25000, next.Amount_Requested__c, 'The award is the new request');
			Assert.areEqual('Tutoring', next.Purpose__c, 'Copied');
			Assert.areEqual(
				18000,
				next.Budget_Lines__r[0].Amount_Requested__c,
				'Lines ask the awarded amounts'
			);
			try {
				GrantManagementService.startRenewal(grant.Id);
				Assert.fail('A second renewal is refused');
			} catch (GrantService.GrantException expected) {
				Assert.isNotNull(expected.getMessage(), 'Told why');
			}
			Assert.areEqual(
				1,
				[SELECT COUNT() FROM Grant__c WHERE Renewal_Of__c = :grant.Id WITH SYSTEM_MODE],
				'Still one renewal'
			);
			Map<String, Object> history = GrantManagementController.getRenewals(nextId);
			Assert.areEqual(2, ((List<Object>) history.get('chain')).size(), 'Both years');
			Assert.isFalse(
				(Boolean) GrantManagementController.getRenewals(grant.Id).get('canStart'),
				'Renewed once'
			);
		}
	}

	@IsTest
	static void aReaderChangesNothing() {
		Grant__c grant;
		System.runAs(TestUsers.adminWith(GrantTestData.ADMIN)) {
			grant = GrantTestData.grant('Literacy', GrantTestData.funder('Lakeside').Id, 'Awarded');
			insert grant;
		}
		System.runAs(reader()) {
			Test.startTest();
			Map<String, Object> checklist = GrantManagementController.getChecklist(grant.Id);
			Boolean refused = false;
			try {
				GrantManagementController.startRenewal(grant.Id);
			} catch (AuraHandledException e) {
				refused = true;
			}
			Test.stopTest();
			Assert.isFalse((Boolean) checklist.get('canEdit'), 'Cannot tick');
			Assert.isFalse(
				(Boolean) GrantManagementController.getRenewals(grant.Id).get('canStart'),
				'Not offered'
			);
			Assert.isTrue(refused, 'Start Renewal is refused');
			Assert.areEqual(
				0,
				GrantManagementController.addChecklistTasks(grant.Id),
				'Adds nothing'
			);
		}
	}

	@IsTest
	static void bothAutomationsHaveSwitchRows() {
		System.runAs(TestUsers.adminWith(GrantTestData.ADMIN)) {
			List<Automation_Registry__mdt> rows = [
				SELECT Handler_Class__c, Always_Runs__c
				FROM Automation_Registry__mdt
				WHERE Handler_Class__c IN ('GrantChecklistHandler', 'GrantRenewalHandler')
				WITH SYSTEM_MODE
			];
			Assert.areEqual(2, rows.size(), 'Two rows');
			for (Automation_Registry__mdt row : rows) {
				Assert.isFalse(row.Always_Runs__c, 'Switchable');
			}
		}
	}
}
