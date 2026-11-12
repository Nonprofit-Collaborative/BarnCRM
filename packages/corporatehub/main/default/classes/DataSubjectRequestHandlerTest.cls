/**
 * A data subject request's due date follows its received date: one month on, unless a person
 * set it (R-DS1).
 */
@IsTest(testFor='ApexClass:DataSubjectRequestHandler')
private class DataSubjectRequestHandlerTest {
	private static final String ADMIN_SET = 'Corporate_Hub_Admin';

	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(ADMIN_SET);
	}

	private static Data_Subject_Request__c request(Date received, Date due) {
		return new Data_Subject_Request__c(
			Request_Type__c = 'Access',
			Status__c = 'Received',
			Received_Date__c = received,
			Due_Date__c = due
		);
	}

	private static Data_Subject_Request__c reload(Id id) {
		return [
			SELECT Received_Date__c, Due_Date__c
			FROM Data_Subject_Request__c
			WHERE Id = :id
			WITH USER_MODE
		];
	}

	@IsTest
	static void aBlankDueDateIsThirtyDaysAfterReceipt() {
		System.runAs(TestUsers.adminWith(ADMIN_SET)) {
			Date received = Date.today().addDays(-10);
			List<Data_Subject_Request__c> rows = new List<Data_Subject_Request__c>{
				request(received, null),
				request(received.addDays(-5), null)
			};
			insert as user rows;

			Assert.areEqual(received.addDays(30), reload(rows[0].Id).Due_Date__c, 'First');
			Assert.areEqual(
				received.addDays(25),
				reload(rows[1].Id).Due_Date__c,
				'Second, in bulk'
			);
		}
	}

	@IsTest
	static void aDueDateSetByAPersonStays() {
		System.runAs(TestUsers.adminWith(ADMIN_SET)) {
			Date received = Date.today();
			Data_Subject_Request__c row = request(received, received.addDays(90));
			insert as user row;
			Assert.areEqual(received.addDays(90), reload(row.Id).Due_Date__c, 'Extension kept');

			row.Received_Date__c = received.addDays(-3);
			update as user row;
			Assert.areEqual(received.addDays(90), reload(row.Id).Due_Date__c, 'Still kept');
		}
	}

	@IsTest
	static void anUneditedDueDateFollowsAChangedReceivedDate() {
		System.runAs(TestUsers.adminWith(ADMIN_SET)) {
			Date received = Date.today();
			Data_Subject_Request__c row = request(received, null);
			insert as user row;

			row.Received_Date__c = received.addDays(-7);
			update as user row;

			Assert.areEqual(received.addDays(23), reload(row.Id).Due_Date__c, 'Moved with receipt');
		}
	}
}
