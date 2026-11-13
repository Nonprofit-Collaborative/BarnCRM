/**
 * Requests and issues (D-201): staff log, triage and resolve; the switches refuse new and
 * outside requests; a portal save (a user with no request access, saving in system mode as the
 * portal does) keeps the sent fields, lands in the Requests queue and turns a reply into a shared
 * comment; requesters and owners are told; tasks and change requests are made from a request;
 * 200 requests save in one go.
 */
@IsTest(testFor='ApexClass:ProjectRequestHandler, ApexClass:ProjectRequestsController')
private class ProjectRequestsTest {
	@TestSetup
	static void setup() {
		TestUsers.adminWith(ProjectsTestData.ADMIN_SET);
	}

	private static void turnOn(Boolean external) {
		SettingsService.saveValues(
			'Projects_Settings__c',
			new Map<String, Object>{
				'Requests_Enabled__c' => true,
				'Requests_External_Enabled__c' => external,
				'Change_Requests_Enabled__c' => true
			}
		);
	}

	private static Contact requester() {
		Contact person = TestDataFactory.person(
			new Contact(FirstName = 'Rae', LastName = 'Asker', Email = 'rae@example.org')
		);
		Database.DMLOptions options = new Database.DMLOptions();
		options.DuplicateRuleHeader.allowSave = true;
		Database.insert(person, options, AccessLevel.USER_MODE);
		return person;
	}

	private static Project_Request__c request(String subject, String priority, Id requesterId) {
		return new Project_Request__c(
			Subject__c = subject,
			Priority__c = priority,
			Requester__c = requesterId
		);
	}

	@IsTest
	static void staffLogTriageAndResolve() {
		User staff = ProjectsTestData.staff('Triager');
		Contact person;
		Id organizationId;
		System.runAs(ProjectsTestData.admin()) {
			turnOn(false);
			person = requester();
			organizationId = [SELECT AccountId FROM Contact WHERE Id = :person.Id].AccountId;
		}
		System.runAs(staff) {
			Project_Request__c saved = request('Report totals are wrong', 'High', person.Id);
			insert saved;
			saved = [
				SELECT Channel__c, Due_Date__c, Account__c, Status__c, OwnerId
				FROM Project_Request__c
				WHERE Id = :saved.Id
			];
			Assert.areEqual('Staff', saved.Channel__c, 'Staff channel');
			Assert.areEqual(
				ProjectRequestHandler.addWeekdays(Date.today(), 2),
				saved.Due_Date__c,
				'High is due in two weekdays'
			);
			Assert.areEqual(organizationId, saved.Account__c, 'Organization from the requester');

			ProjectRequestsController.RequestList mine = ProjectRequestsController.getRequests(
				'mine'
			);
			Assert.isTrue(mine.enabled, 'On');
			Assert.areEqual(1, mine.rows.size(), 'Mine lists it');

			try {
				ProjectRequestsController.saveRequest(
					saved.Id,
					new Map<String, Object>{ 'Status__c' => 'Resolved' }
				);
				Assert.fail('Resolved needs a resolution');
			} catch (AuraHandledException expected) {
				Assert.isNotNull(expected.getMessage(), 'Refused in words');
			}
			ProjectRequestsController.addComment(saved.Id, 'Looking into it', true);
			ProjectRequestsController.addComment(saved.Id, 'Staff note', false);
			ProjectRequestsController.saveRequest(
				saved.Id,
				new Map<String, Object>{
					'Status__c' => 'Resolved',
					'Resolution__c' => 'Fixed the filter',
					'Due_Date__c' => String.valueOf(Date.today()),
					'Name' => 'ignored'
				}
			);
			ProjectRequestsController.Detail detail = ProjectRequestsController.getRequest(
				saved.Id
			);
			Assert.areEqual('Resolved', detail.status, 'Resolved');
			Assert.areEqual(2, detail.comments.size(), 'Both comments');
			Assert.isNotNull(
				[SELECT Resolved_Date__c FROM Project_Request__c WHERE Id = :saved.Id]
				.Resolved_Date__c,
				'Resolved Date stamped'
			);
			Assert.areEqual(
				2,
				ProjectRequestHandler.sent.size(),
				'Requester emailed the shared comment and the resolution, not the staff note'
			);
			Assert.areEqual(
				1,
				ProjectRequestsController.getRequests('closed').rows.size(),
				'Closed view'
			);
		}
	}

	@IsTest
	static void switchesRefuseNewAndOutsideRequests() {
		System.runAs(ProjectsTestData.admin()) {
			Database.SaveResult off = Database.insert(request('Off', 'Low', null), false);
			Assert.isFalse(off.isSuccess(), 'Refused while requests are off');
			Assert.isFalse(ProjectRequestsController.getRequests('open').enabled, 'Page off');
			turnOn(false);
			Project_Request__c outside = request('Outside', 'Low', null);
			outside.Channel__c = ProjectRequestHandler.PARTNER;
			Assert.isFalse(
				Database.insert(outside, false).isSuccess(),
				'Outside refused while external is off'
			);
			Assert.isTrue(
				Database.insert(request('Inside', 'Low', null), false).isSuccess(),
				'Staff request saved'
			);
		}
	}

	@IsTest
	static void aPortalSaveKeepsSentFieldsAndRepliesBecomeComments() {
		User portal = TestUsers.standardUser('PortalApi');
		User owner = ProjectsTestData.staff('Owner');
		Contact person;
		System.runAs(ProjectsTestData.admin()) {
			turnOn(true);
			person = requester();
		}
		Project_Request__c incoming = request('Please add a user', 'Medium', person.Id);
		System.runAs(portal) {
			Database.insert(incoming, AccessLevel.SYSTEM_MODE);
		}
		System.runAs(ProjectsTestData.admin()) {
			Project_Request__c saved = [
				SELECT Channel__c, OwnerId
				FROM Project_Request__c
				WHERE Id = :incoming.Id
			];
			Assert.areEqual('Portal', saved.Channel__c, 'Portal channel');
			Assert.areEqual(
				ProjectsTestData.requestsQueueId(),
				saved.OwnerId,
				'Lands in the Requests queue'
			);
			update new Project_Request__c(
				Id = incoming.Id,
				OwnerId = owner.Id,
				Status__c = 'Waiting on Requester'
			);
			Assert.isTrue(ProjectRequestHandler.sent.size() >= 1, 'The new owner is told');
		}
		System.runAs(portal) {
			Database.update(
				new Project_Request__c(
					Id = incoming.Id,
					Priority__c = 'Urgent',
					Reply__c = 'It is for Sam'
				),
				AccessLevel.SYSTEM_MODE
			);
		}
		System.runAs(ProjectsTestData.admin()) {
			Project_Request__c after = [
				SELECT
					Priority__c,
					Status__c,
					Reply__c,
					(SELECT Body__c, Shared__c, From_Requester__c FROM Comments__r)
				FROM Project_Request__c
				WHERE Id = :incoming.Id
			];
			Assert.areEqual('Medium', after.Priority__c, 'The requester cannot re-prioritize');
			Assert.areEqual('In Progress', after.Status__c, 'A reply reopens');
			Assert.isNull(after.Reply__c, 'Reply cleared');
			Assert.areEqual(1, after.Comments__r.size(), 'One comment');
			Assert.isTrue(after.Comments__r[0].From_Requester__c, 'From the requester');
			Assert.isTrue(after.Comments__r[0].Shared__c, 'Shared');
		}
	}

	@IsTest
	static void tasksAndChangeRequestsComeFromARequest() {
		System.runAs(ProjectsTestData.admin()) {
			turnOn(false);
			Project_Request__c saved = request('Build an intake form', 'Low', null);
			saved.Description__c = 'For the spring program';
			insert saved;
			try {
				ProjectRequestsController.createTask(saved.Id);
				Assert.fail('Needs a project');
			} catch (AuraHandledException expected) {
				Assert.isNotNull(expected.getMessage(), 'Refused in words');
			}
			Project__c project = ProjectsTestData.project('Active', 10);
			ProjectRequestsController.saveRequest(
				saved.Id,
				new Map<String, Object>{ 'Project__c' => project.Id }
			);
			Id taskId = ProjectRequestsController.createTask(saved.Id);
			Id changeId = ProjectRequestsController.createChangeRequest(saved.Id);
			ProjectRequestsController.Detail detail = ProjectRequestsController.getRequest(
				saved.Id
			);
			Assert.areEqual(taskId, detail.taskId, 'Task linked');
			Assert.areEqual(changeId, detail.changeRequestId, 'Change request linked');
			Assert.areEqual('In Progress', detail.status, 'New moves to In Progress');
			Assert.areEqual(
				'Draft',
				[SELECT Status__c FROM Project_Change_Request__c WHERE Id = :changeId].Status__c,
				'Draft change request'
			);
		}
	}

	/**
	 * QA review Q4: replies are taken off the rows before update and kept in a static map until
	 * after update writes them as comments. 205 rows run in two chunks, and every reply becomes
	 * a comment only while each chunk adds to the map rather than replacing it.
	 */
	@IsTest
	static void repliesOnMoreThanTwoHundredRequestsAllBecomeComments() {
		System.runAs(ProjectsTestData.admin()) {
			turnOn(false);
			List<Project_Request__c> rows = new List<Project_Request__c>();
			for (Integer i = 0; i < 205; i++) {
				rows.add(request('Bulk reply ' + i, 'Low', null));
			}
			insert rows;
			List<Project_Request__c> replies = new List<Project_Request__c>();
			for (Project_Request__c row : rows) {
				replies.add(new Project_Request__c(Id = row.Id, Reply__c = 'Looking at it'));
			}

			Test.startTest();
			update replies;
			Test.stopTest();

			Assert.areEqual(
				205,
				[SELECT COUNT() FROM Project_Request_Comment__c WHERE Request__c IN :rows],
				'One comment per reply, in both chunks'
			);
			// Reply__c is long text, which SOQL cannot filter on, so it is checked row by row.
			for (Project_Request__c row : [
				SELECT Reply__c
				FROM Project_Request__c
				WHERE Id IN :rows
			]) {
				Assert.isNull(row.Reply__c, 'Every reply is cleared');
			}
		}
	}

	@IsTest
	static void twoHundredRequestsSaveTogether() {
		User owner = ProjectsTestData.staff('Bulk');
		System.runAs(ProjectsTestData.admin()) {
			turnOn(false);
			List<Project_Request__c> rows = new List<Project_Request__c>();
			for (Integer i = 0; i < 200; i++) {
				Project_Request__c row = request('Bulk ' + i, 'Urgent', null);
				row.OwnerId = owner.Id;
				rows.add(row);
			}
			Test.startTest();
			insert rows;
			Test.stopTest();
			Assert.areEqual(
				200,
				[SELECT COUNT() FROM Project_Request__c WHERE Due_Date__c != NULL],
				'Every request has a due date'
			);
			Assert.areEqual(50, ProjectRequestHandler.sent.size(), 'Notices capped at 50');
			Assert.areEqual(
				0,
				ProjectRequestsController.getRequests('overdue').rows.size(),
				'None overdue yet'
			);
		}
	}

	@IsTest
	static void weekdaysSkipTheWeekend() {
		// runs-as: deploying user (pure logic: date arithmetic, no DML or SOQL)
		Date friday = Date.newInstance(2026, 11, 13);
		Assert.areEqual(
			Date.newInstance(2026, 11, 16),
			ProjectRequestHandler.addWeekdays(friday, 1),
			'Monday'
		);
		Assert.areEqual(
			Date.newInstance(2026, 11, 20),
			ProjectRequestHandler.addWeekdays(friday, 5),
			'Next Friday'
		);
	}
}
