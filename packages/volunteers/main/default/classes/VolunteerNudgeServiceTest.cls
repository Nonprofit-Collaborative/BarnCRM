/**
 * "Still need you" nudges (V-10b): which shifts are nudged, who is emailed, once each.
 *
 * The platform's email call is replaced by a stub that records the messages, so the tests prove
 * what would be sent without depending on the org's email deliverability setting.
 */
@IsTest(
	testFor='ApexClass:VolunteerNudgeService, ApexClass:VolunteerNudgeSelector, ApexClass:VolunteerNudgeBatch, ApexClass:VolunteerNudgeScheduler, ApexClass:VolunteersNightlyJobProvider, ApexClass:VolunteerSettings'
)
private class VolunteerNudgeServiceTest {
	@TestSetup
	static void makeData() {
		System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
			VolunteersTestData.contactModeWithoutAutomaticHouseholds();
			VolunteersTestData.job('Food pantry sort');
		}
	}

	private static void settings(Boolean enabled, Integer leadDays) {
		OrgSettingsSystemWriter.save(
			Volunteer_Settings__c.SObjectType,
			new Map<Schema.SObjectField, Object>{
				Volunteer_Settings__c.Nudges_Enabled__c => enabled,
				Volunteer_Settings__c.Nudge_Lead_Days__c => leadDays,
				Volunteer_Settings__c.Hours_Require_Approval__c => false
			}
		);
		SettingsService.clearCaches();
	}

	/** An active volunteer with approved hours on the job, so a candidate for its nudge. */
	private static Contact regular(String lastName, String email, Boolean optedOut) {
		Contact record = VolunteersTestData.contact(lastName, null);
		record.Email = email;
		record.HasOptedOutOfEmail = optedOut;
		record.Volunteer_Status__c = 'Active';
		update record;
		Volunteer_Job__c job = [SELECT Id FROM Volunteer_Job__c LIMIT 1];
		insert VolunteersTestData.newHours(record.Id, job.Id, 3);
		return record;
	}

	private static Volunteer_Shift__c shiftIn(Integer hoursAhead, Integer needed) {
		Volunteer_Job__c job = [SELECT Id FROM Volunteer_Job__c LIMIT 1];
		Volunteer_Shift__c shift = VolunteersTestData.newShift(
			job.Id,
			ShiftScheduleService.now().addHours(hoursAhead),
			2
		);
		shift.Volunteers_Needed__c = needed;
		insert shift;
		return shift;
	}

	private static Integer stamped() {
		return [SELECT COUNT() FROM Volunteer_Shift__c WHERE Nudge_Sent_On__c != NULL];
	}

	private static void runBatch() {
		Test.startTest();
		VolunteerNudgeBatch.startMorning();
		Test.stopTest();
	}

	@IsTest
	static void anUnfilledShiftNudgesTheJobsRegularsOnceAndIsStamped() {
		System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
			RecordingEmailSender stub = new RecordingEmailSender();
			VolunteerNudgeService.emailSender = stub;
			settings(true, 3);
			regular('Rivera', 'ana@example.org', false);
			regular('Optout', 'no@example.org', true);
			regular('Booked', 'booked@example.org', false);
			Volunteer_Shift__c shift = shiftIn(30, 2);
			insert VolunteersTestData.newSignup(
				shift.Id,
				[SELECT Id FROM Contact WHERE LastName = 'Booked'].Id
			);

			runBatch();
			Database.QueryLocatorIterator stillDue = VolunteerNudgeSelector.dueLocator(
					ShiftScheduleService.now(),
					VolunteerReminderService.windowEnd(3)
				)
				.iterator();

			Assert.isFalse(stillDue.hasNext(), 'A stamped shift is not due a second time.');
			Assert.areEqual(1, stub.received.size(), 'Only the free, reachable regular, once.');
			Assert.areEqual(
				'ana@example.org',
				stub.received[0].getToAddresses()[0],
				'To the Contact.'
			);
			Assert.isTrue(
				stub.received[0].getSubject().contains('Food pantry sort'),
				'The subject names the job.'
			);
			Assert.areEqual(1, stamped(), 'The shift is stamped.');
		}
	}

	@IsTest
	static void shiftsThatAreFullFarAwayCancelledOrAlreadyNudgedAreLeftOut() {
		System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
			RecordingEmailSender stub = new RecordingEmailSender();
			VolunteerNudgeService.emailSender = stub;
			settings(true, 3);
			Contact ana = regular('Rivera', 'ana@example.org', false);
			Volunteer_Shift__c full = shiftIn(30, 1);
			insert VolunteersTestData.newSignup(full.Id, ana.Id);
			shiftIn(24 * 6, 2);
			Volunteer_Shift__c cancelled = shiftIn(30, 2);
			cancelled.Status__c = 'Cancelled';
			update cancelled;
			Volunteer_Shift__c done = shiftIn(30, 2);
			done.Nudge_Sent_On__c = ShiftScheduleService.now();
			update done;

			runBatch();

			Assert.areEqual(0, stub.received.size(), 'Nothing is due.');
		}
	}

	@IsTest
	static void nothingGoesWhileTheSettingOrTheModuleIsOff() {
		System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
			RecordingEmailSender stub = new RecordingEmailSender();
			VolunteerNudgeService.emailSender = stub;
			settings(false, 3);
			regular('Rivera', 'ana@example.org', false);
			shiftIn(30, 2);

			runBatch();

			Assert.areEqual(0, stub.received.size(), 'Off by default.');
			Assert.areEqual(0, stamped(), 'No stamp.');
		}
	}

	@IsTest
	static void aShiftWhoseEmailFailedLosesItsStampSoTomorrowRetries() {
		System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
			RecordingEmailSender stub = new RecordingEmailSender();
			stub.failAll = true;
			VolunteerNudgeService.emailSender = stub;
			settings(true, 3);
			regular('Rivera', 'ana@example.org', false);
			shiftIn(30, 2);

			runBatch();

			Assert.areEqual(1, stub.received.size(), 'It was tried.');
			Assert.areEqual(0, stamped(), 'The stamp was cleared.');
		}
	}

	@IsTest
	static void recipientsAreCappedByOpenSlotsAndTheShiftMaximum() {
		System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
			Assert.areEqual(0, VolunteerNudgeService.recipientCap(0), 'A full shift.');
			Assert.areEqual(0, VolunteerNudgeService.recipientCap(null), 'Unknown.');
			Assert.areEqual(3, VolunteerNudgeService.recipientCap(1), 'Three per open slot.');
			Assert.areEqual(25, VolunteerNudgeService.recipientCap(40), 'Never more than 25.');
		}
	}

	@IsTest
	static void leadDaysReadAsTheShippedValueWhenBlankOrOutOfRange() {
		System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
			Assert.areEqual(3, VolunteerSettings.nudgeLeadDays(), 'Never saved: three days.');
			Assert.isFalse(VolunteerSettings.nudgesEnabled(), 'Ships off.');
			settings(true, 99);
			Assert.areEqual(3, VolunteerSettings.nudgeLeadDays(), 'Out of range: three days.');
			settings(true, 14);
			Assert.areEqual(14, VolunteerSettings.nudgeLeadDays(), 'The top of the range.');
		}
	}

	@IsTest
	static void theNudgeJobIsAStepOfTheNightlyRunAndRuns() {
		System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
			VolunteerNudgeScheduler.jobNameInUse = 'BarnCRM Volunteer Shift Nudges test';
			RecordingEmailSender stub = new RecordingEmailSender();
			VolunteerNudgeService.emailSender = stub;
			settings(true, 3);
			regular('Rivera', 'ana@example.org', false);
			shiftIn(30, 2);
			NightlyStep step = new VolunteersNightlyJobProvider().nightlySteps()[2];

			Test.startTest();
			step.run();
			Test.stopTest();

			Assert.areEqual(435, step.minute, 'A quarter past seven in the morning.');
			Assert.areEqual(Label.Volunteers_NightlyJobs_NudgesName, step.label, 'Its label.');
			Assert.areEqual(1, stub.received.size(), 'The job ran the nudges.');
		}
	}
}
