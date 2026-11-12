/**
 * The morning run opens and closes cycles by their dates and reminds the program owner once per
 * report due date (R-SG2, R-SG13).
 */
@IsTest(
	testFor='ApexClass:ScholarshipReminders, ApexClass:ScholarshipsNightlyJobProvider, ApexClass:ScholarshipsSettings'
)
private class ScholarshipRemindersTest {
	@TestSetup
	static void setup() {
		TestUsers.adminWith(ScholarshipsTestData.ADMIN_SET);
	}

	@IsTest
	static void cyclesMoveOnAndEachDueDateIsRemindedOnce() {
		System.runAs(ScholarshipsTestData.admin()) {
			Award_Cycle__c open = ScholarshipsTestData.cycle(null, null);
			update new Award_Cycle__c(Id = open.Id, Close_Date__c = Date.today().addDays(-1));
			Award_Cycle__c planned = new Award_Cycle__c(
				Name = 'Next',
				Program__c = [SELECT Program__c FROM Award_Cycle__c WHERE Id = :open.Id]
				.Program__c,
				Status__c = 'Planned',
				Open_Date__c = Date.today()
			);
			insert planned;
			Award__c award = ScholarshipsTestData.award(
				open.Id,
				null,
				ScholarshipsTestData.person('Lee').Id,
				500
			);
			Award_Requirement__c report = new Award_Requirement__c(
				Award__c = award.Id,
				Name = 'Progress report',
				Type__c = 'Progress Report',
				Due_Date__c = Date.today().addDays(5)
			);
			insert report;
			Assert.areEqual(
				1,
				new ScholarshipsNightlyJobProvider().nightlySteps().size(),
				'One step'
			);
			Assert.isTrue(ScholarshipsSettings.remindersEnabled(), 'Ships on');
			Assert.isFalse(ScholarshipsSettings.emailRecipients(), 'Email ships off');
			Assert.areEqual(14, ScholarshipsSettings.reminderDays(), 'Ships 14');

			Test.startTest();
			new ScholarshipReminders().execute(null);
			new ScholarshipReminders().execute(null);
			Test.stopTest();

			Assert.areEqual(
				'Reviewing',
				[SELECT Status__c FROM Award_Cycle__c WHERE Id = :open.Id].Status__c,
				'Closed for applications'
			);
			Assert.areEqual(
				'Open',
				[SELECT Status__c FROM Award_Cycle__c WHERE Id = :planned.Id].Status__c,
				'Opened'
			);
			Assert.areEqual(
				report.Due_Date__c,
				[SELECT Reminded_For__c FROM Award_Requirement__c WHERE Id = :report.Id]
				.Reminded_For__c,
				'Reminded for the date'
			);
			Assert.areEqual(1, Scholarships.sentTitles.size(), 'Once, not twice');
		}
	}
}
