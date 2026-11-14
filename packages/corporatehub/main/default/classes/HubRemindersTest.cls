/**
 * The nightly Corporate Hub step: Maria is reminded once of the annual report and the lease's
 * notice date, a lapsed agreement renews or expires, and the settings switch reminders off
 * (R-AG1, R-CR1, 29CH6; ADR-0166).
 */
@IsTest(
	testFor='ApexClass:HubReminders, ApexClass:CorporateHubNightlyJobProvider, ApexClass:CorporateHubSettings'
)
private class HubRemindersTest {
	private static final String ADMIN_SET = 'Corporate_Hub_Admin';

	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(ADMIN_SET);
	}

	private static Compliance_Obligation__c obligation(String name, Date due) {
		Compliance_Obligation__c row = new Compliance_Obligation__c(
			Name = name,
			Status__c = 'Active',
			Recurrence__c = 'Yearly',
			Due_Date__c = due
		);
		insert row;
		return row;
	}

	private static Agreement__c agreement(Date endDate, Boolean autoRenews) {
		Agreement__c row = new Agreement__c(
			Name = 'Office lease',
			Status__c = 'Active',
			Start_Date__c = endDate.addYears(-1),
			End_Date__c = endDate,
			Auto_Renews__c = autoRenews,
			Renewal_Months__c = 12,
			Notice_Days__c = 30
		);
		insert row;
		return row;
	}

	@IsTest
	static void theStepIsListedAtQuarterToSevenAndShipsOn() {
		System.runAs(TestUsers.adminWith(ADMIN_SET)) {
			List<NightlyStep> steps = new CorporateHubNightlyJobProvider().nightlySteps();

			Assert.areEqual(1, steps.size(), 'One step');
			Assert.areEqual(HubReminders.JOB_NAME, steps[0].key, 'Its key');
			Assert.areEqual(405, steps[0].minute, '6:45');
			Assert.isTrue(steps[0].hasSwitch(), 'Has a switch');
			Assert.isTrue(steps[0].switchDefault, 'Ships on');
			Assert.isFalse(String.isBlank(steps[0].label), 'Named from the help catalog');
		}
	}

	@IsTest
	static void theBoardOwnerHearsOfATermEndingOnce() {
		System.runAs(TestUsers.adminWith(ADMIN_SET)) {
			Board__c board = new Board__c(Name = 'Board', Type__c = 'Board', Status__c = 'Active');
			insert board;
			Contact ade = TestDataFactory.person(
				new Contact(FirstName = 'Ade', LastName = 'Member')
			);
			insert ade;
			Board_Member__c seat = new Board_Member__c(
				Board__c = board.Id,
				Person__c = ade.Id,
				Role__c = 'Member',
				Term_Start__c = Date.today().addYears(-3),
				Term_End__c = Date.today().addDays(20)
			);
			insert seat;

			new HubReminders().execute(null);
			new HubReminders().execute(null);

			Assert.areEqual(
				1,
				HubReminders.sentTitles.size(),
				'One reminder for the ending term (R-BM2)'
			);
			Assert.isTrue(HubReminders.sentTitles[0].contains('Ade Member'), 'Names the member');
			Assert.areEqual(
				seat.Term_End__c,
				[SELECT Reminded_For__c FROM Board_Member__c WHERE Id = :seat.Id WITH USER_MODE]
				.Reminded_For__c,
				'Marked'
			);
		}
	}

	@IsTest
	static void eachOwnerIsRemindedOncePerDueDate() {
		System.runAs(TestUsers.adminWith(ADMIN_SET)) {
			Compliance_Obligation__c report = obligation('Annual report', Date.today().addDays(10));
			Compliance_Obligation__c later = obligation('Audit', Date.today().addDays(90));
			Hub_Document__c policy = new Hub_Document__c(
				Name = 'Whistleblower',
				Status__c = 'Active',
				Version__c = 1,
				Review_Date__c = Date.today().addDays(5)
			);
			insert policy;
			Agreement__c lease = agreement(Date.today().addDays(40), false);

			new HubReminders().execute(null);
			Integer firstNight = HubReminders.sentTitles.size();
			new HubReminders().execute(null);

			Assert.areEqual(3, firstNight, 'The report, the review and the lease notice date');
			Assert.areEqual(firstNight, HubReminders.sentTitles.size(), 'Never twice for one date');
			Assert.areEqual(
				report.Due_Date__c,
				[
					SELECT Reminded_For__c
					FROM Compliance_Obligation__c
					WHERE Id = :report.Id
					WITH USER_MODE
				]
				.Reminded_For__c,
				'Marked'
			);
			Assert.isNull(
				[
					SELECT Reminded_For__c
					FROM Compliance_Obligation__c
					WHERE Id = :later.Id
					WITH USER_MODE
				]
				.Reminded_For__c,
				'Ninety days out is beyond the shipped 30'
			);
			Assert.areEqual(
				Date.today().addDays(10),
				[SELECT Reminded_For__c FROM Agreement__c WHERE Id = :lease.Id WITH USER_MODE]
				.Reminded_For__c,
				'The lease is reminded for its notice date'
			);
			Assert.areEqual(
				policy.Review_Date__c,
				[SELECT Reminded_For__c FROM Hub_Document__c WHERE Id = :policy.Id WITH USER_MODE]
				.Reminded_For__c,
				'The review too'
			);
		}
	}

	@IsTest
	static void aMonthEndAgreementRenewsToEachMonthEnd() {
		System.runAs(TestUsers.adminWith(ADMIN_SET)) {
			HubReminders reminders = new HubReminders();
			reminders.today = Date.newInstance(2026, 4, 15);
			Agreement__c row = new Agreement__c(
				Status__c = 'Active',
				End_Date__c = Date.newInstance(2026, 1, 31),
				Auto_Renews__c = true,
				Renewal_Months__c = 1
			);

			Assert.isTrue(reminders.renew(row), 'Renewed');
			Assert.areEqual(
				Date.newInstance(2026, 4, 30),
				row.End_Date__c,
				'31 January renews through 28 February and 31 March to 30 April, not the 28th'
			);
		}
	}

	@IsTest
	static void aLapsedAgreementRenewsByItsTermOrExpires() {
		System.runAs(TestUsers.adminWith(ADMIN_SET)) {
			Date lapsed = Date.today().addDays(-2);
			Agreement__c renewing = agreement(lapsed, true);
			Agreement__c ending = agreement(lapsed, false);
			insert new Corporate_Hub_Settings__c(
				SetupOwnerId = UserInfo.getOrganizationId(),
				Reminders_Enabled__c = false
			);

			new HubReminders().execute(null);

			Agreement__c renewed = [
				SELECT Status__c, End_Date__c
				FROM Agreement__c
				WHERE Id = :renewing.Id
				WITH USER_MODE
			];
			Assert.areEqual('Active', renewed.Status__c, 'Still active');
			Assert.areEqual(HubCompliance.nextDue(lapsed, 12), renewed.End_Date__c, 'One term on');
			Assert.areEqual(
				'Expired',
				[SELECT Status__c FROM Agreement__c WHERE Id = :ending.Id WITH USER_MODE].Status__c,
				'No renewal: expired'
			);
			Assert.areEqual(
				0,
				HubReminders.sentTitles.size(),
				'Reminders switched off send nothing'
			);
		}
	}

	@IsTest
	static void oneNightSendsNoMoreThanTheCap() {
		System.runAs(TestUsers.adminWith(ADMIN_SET)) {
			obligation('First', Date.today().addDays(1));
			obligation('Second', Date.today().addDays(2));
			HubReminders.maxReminders = 1;

			new HubReminders().execute(null);

			Assert.areEqual(1, HubReminders.sentTitles.size(), 'One tonight');
			Assert.areEqual(
				1,
				[
					SELECT COUNT()
					FROM Compliance_Obligation__c
					WHERE Reminded_For__c != NULL
					WITH USER_MODE
				],
				'The other waits for tomorrow'
			);
		}
	}

	@IsTest
	static void aBlankOrOutOfRangeNumberReadsAsTheShipped30() {
		System.runAs(TestUsers.adminWith(ADMIN_SET)) {
			insert new Corporate_Hub_Settings__c(
				SetupOwnerId = UserInfo.getOrganizationId(),
				Reminder_Days__c = 0,
				Acknowledgment_Days__c = 45
			);

			Assert.isTrue(CorporateHubSettings.remindersEnabled(), 'Ships on');
			Assert.areEqual(30, CorporateHubSettings.reminderDays(), 'Zero is out of range');
			Assert.areEqual(45, CorporateHubSettings.acknowledgmentDays(), 'As saved');
		}
	}
}
