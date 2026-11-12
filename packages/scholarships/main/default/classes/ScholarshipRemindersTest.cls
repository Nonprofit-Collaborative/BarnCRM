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

	/** Stands in for Forms: every form has a public link for the record. */
	private class Catalog implements FormCatalogExtension {
		public List<FormCatalogEntry> publicForms() {
			return new List<FormCatalogEntry>();
		}

		public List<FormCatalogEntry> questions(Id formId) {
			return new List<FormCatalogEntry>();
		}

		public String publicLink(Id formId, Id contextRecordId) {
			return 'https://zzforms.example.org/FormsPublic?record=' + contextRecordId;
		}
	}

	private static void saveSettings(Boolean reminders, Boolean email) {
		Scholarships_Settings__c settings = Scholarships_Settings__c.getOrgDefaults();
		settings.SetupOwnerId = UserInfo.getOrganizationId();
		settings.Reminders_Enabled__c = reminders;
		settings.Email_Recipients__c = email;
		upsert settings;
		SettingsService.clearCaches();
	}

	private static Award_Requirement__c requirement(Id awardId, String name, Integer inDays) {
		Award_Requirement__c row = new Award_Requirement__c(
			Award__c = awardId,
			Name = name,
			Type__c = 'Progress Report',
			Due_Date__c = Date.today().addDays(inDays)
		);
		insert row;
		return row;
	}

	@IsTest
	static void formLinksAreFilledAndTheRecipientIsEmailed() {
		System.runAs(ScholarshipsTestData.admin()) {
			saveSettings(true, true);
			FormCatalogTestSupport.install(new Catalog());
			Award_Cycle__c cycle = ScholarshipsTestData.cycle(null, null);
			String formKey = String.valueOf(cycle.Program__c);
			update new Award_Cycle__c(
				Id = cycle.Id,
				Application_Form_Key__c = formKey,
				Report_Form_Key__c = formKey
			);
			Contact lee = ScholarshipsTestData.person('Lee');
			Award_Application__c draft = ScholarshipsTestData.application(
				cycle.Id,
				lee.Id,
				'Draft'
			);
			Award__c award = ScholarshipsTestData.award(cycle.Id, null, lee.Id, 500);
			Award_Requirement__c report = requirement(award.Id, 'Progress report', 3);

			Test.startTest();
			new ScholarshipReminders().execute(null);
			Integer emailsSent = Limits.getEmailInvocations();
			Test.stopTest();

			Assert.isNotNull(
				[SELECT Form_Link__c FROM Award_Application__c WHERE Id = :draft.Id].Form_Link__c,
				'The draft has its signed form link'
			);
			Award_Requirement__c after = [
				SELECT Form_Link__c, Reminded_For__c
				FROM Award_Requirement__c
				WHERE Id = :report.Id
			];
			Assert.isNotNull(after.Form_Link__c, 'The report has its form link');
			Assert.areEqual(report.Due_Date__c, after.Reminded_For__c, 'Reminded for the date');
			Assert.areEqual(1, Scholarships.sentTitles.size(), 'The program owner is told');
			Assert.areEqual(1, emailsSent, 'The recipient is emailed');
		}
	}

	@IsTest
	static void aNightSendsNoMoreThanTheCapAndNothingWhenRemindersAreOff() {
		System.runAs(ScholarshipsTestData.admin()) {
			saveSettings(true, false);
			Award_Cycle__c cycle = ScholarshipsTestData.cycle(null, null);
			Award__c award = ScholarshipsTestData.award(
				cycle.Id,
				null,
				ScholarshipsTestData.person('Lee').Id,
				500
			);
			Award_Requirement__c first = requirement(award.Id, 'First report', 2);
			Award_Requirement__c second = requirement(award.Id, 'Second report', 4);
			ScholarshipReminders.maxReminders = 1;

			Test.startTest();
			new ScholarshipReminders().execute(null);
			Test.stopTest();

			Assert.areEqual(1, Scholarships.sentTitles.size(), 'Only one reminder tonight');
			Assert.isNotNull(
				[SELECT Reminded_For__c FROM Award_Requirement__c WHERE Id = :first.Id]
				.Reminded_For__c,
				'The earliest due date goes first'
			);
			Assert.isNull(
				[SELECT Reminded_For__c FROM Award_Requirement__c WHERE Id = :second.Id]
				.Reminded_For__c,
				'The rest wait for the next night'
			);

			saveSettings(false, false);
			ScholarshipReminders.maxReminders = 200;
			Scholarships.sentTitles.clear();
			new ScholarshipReminders().execute(null);
			Assert.isTrue(Scholarships.sentTitles.isEmpty(), 'Reminders off sends none');
			Assert.isNull(
				[SELECT Reminded_For__c FROM Award_Requirement__c WHERE Id = :second.Id]
				.Reminded_For__c,
				'Nothing is marked'
			);
		}
	}

	@IsTest
	static void theStepIsListedWithItsSwitchOn() {
		// runs-as: deploying user (pure construction, no records or permissions)
		NightlyStep step = ScholarshipReminders.step();

		Assert.areEqual(ScholarshipReminders.JOB_NAME, step.key, 'Named for the job');
		Assert.isTrue(step.hasSwitch(), 'It has a switch');
		Assert.isTrue(step.switchDefault, 'Shipped on');
	}
}
