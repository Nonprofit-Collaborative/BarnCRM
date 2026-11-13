/**
 * Giving's steps of the nightly run (ADR-0166 nightly-job-dispatcher): the five jobs, each
 * switched on its own (four shipped on, the pledge reminders shipped off, G-37), then the acknowledgment
 * send, shipped off because it emails donors. Switching is checked under the test name of the run, so nothing
 * depends on what the org has scheduled.
 */
@IsTest(testFor='ApexClass:GivingNightlyJobProvider, ApexClass:GivingScheduler')
private class GivingNightlyJobProviderTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith('Giving_Admin');
	}

	private static void noRun() {
		TestDataFactory.clearScheduledJobs(new List<String>{ NightlyJobs.jobName() });
		ScheduledJobSelector.forget();
		NightlyJobs.forget();
	}

	@IsTest
	static void listsSixStepsWithTheEmailingOnesShippedOff() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			List<NightlyStep> steps = new GivingNightlyJobProvider().nightlySteps();

			Assert.areEqual(6, steps.size(), 'Five jobs and the acknowledgments.');
			Map<String, NightlyStep> byKey = new Map<String, NightlyStep>();
			for (NightlyStep step : steps) {
				byKey.put(step.key, step);
				Assert.isTrue(step.hasSwitch(), step.key + ' has a switch.');
			}
			Assert.areEqual(6, byKey.size(), 'No step is listed twice.');
			Assert.areEqual(195, byKey.get(GivingScheduler.PLEDGE_JOB_NAME).minute, '3:15');
			Assert.areEqual(75, byKey.get(GivingScheduler.TOP_UP_JOB_NAME).minute, '1:15');
			Assert.areEqual(105, byKey.get(GivingScheduler.OVERDUE_JOB_NAME).minute, '1:45');
			Assert.areEqual(180, byKey.get(GivingScheduler.LEVELS_JOB_NAME).minute, '3:00');
			Assert.areEqual(210, byKey.get(GivingScheduler.ASK_JOB_NAME).minute, '3:30');
			Assert.isTrue(byKey.get(GivingScheduler.LEVELS_JOB_NAME).switchDefault, 'On');
			Assert.isFalse(
				byKey.get(AcknowledgmentScheduler.JOB_NAME).switchDefault,
				'The acknowledgment send ships off, because it emails donors.'
			);
			Assert.isFalse(byKey.get(PledgeReminderScheduler.JOB_NAME).switchDefault, 'Off');
		}
	}

	/** The shared Nightly Jobs card offers Run Now and shows summaries as the old page did. */
	@IsTest
	static void theCardOffersRunNowWhereTheOldPageDidAndShowsEachSummary() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			Giving_Settings__c settings = Giving_Settings__c.getOrgDefaults();
			settings.Installment_Top_Up_Last_Run_Summary__c = '3 payments added';
			Database.upsert(settings, AccessLevel.SYSTEM_MODE);

			Map<String, NightlyStep> byKey = new Map<String, NightlyStep>();
			for (NightlyStep step : new GivingNightlyJobProvider().nightlySteps()) {
				byKey.put(step.key, step);
			}

			Assert.areEqual(
				'3 payments added',
				byKey.get(GivingScheduler.TOP_UP_JOB_NAME).summary,
				'The top up shows its own summary.'
			);
			for (
				String key : new List<String>{
					GivingScheduler.TOP_UP_JOB_NAME,
					GivingScheduler.OVERDUE_JOB_NAME,
					GivingScheduler.PLEDGE_JOB_NAME,
					GivingScheduler.ASK_JOB_NAME
				}
			) {
				Assert.isTrue(byKey.get(key).canRunNow, key + ' can be started now.');
			}
			Assert.isFalse(
				byKey.get(GivingScheduler.LEVELS_JOB_NAME).canRunNow,
				'Donor levels keep their own Recalculate Now (ADR-0038).'
			);
			Assert.isFalse(
				byKey.get(AcknowledgmentScheduler.JOB_NAME).canRunNow,
				'Acknowledgments are sent from their own page.'
			);
		}
	}

	@IsTest
	static void switchingOneJobLeavesTheOthersAsTheyWere() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			noRun();
			NightlyJobs.turnOff(GivingScheduler.TOP_UP_JOB_NAME);
			NightlyJobs.turnOn(GivingScheduler.OVERDUE_JOB_NAME);
			NightlyJobs.forget();
			ScheduledJobSelector.forget();

			Assert.isTrue(NightlyJobs.isStepScheduled(GivingScheduler.OVERDUE_JOB_NAME, true));
			Assert.isFalse(NightlyJobs.isStepScheduled(GivingScheduler.TOP_UP_JOB_NAME, true));
			Assert.isTrue(
				NightlyJobs.isStepScheduled(GivingScheduler.LEVELS_JOB_NAME, true),
				'A job never switched keeps its shipped value.'
			);
		}
	}

	@IsTest
	static void theAcknowledgmentAndReminderSwitchesFollowTheirPages() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			noRun();
			Boolean before = AcknowledgmentScheduler.isScheduled();
			AcknowledgmentScheduler.start();
			PledgeReminderScheduler.start();
			NightlyJobs.forget();
			ScheduledJobSelector.forget();
			Boolean ackOn = AcknowledgmentScheduler.isScheduled();
			Datetime ackNext = AcknowledgmentScheduler.nextRunAt();
			Boolean remindersOn = PledgeReminderScheduler.isScheduled();
			AcknowledgmentScheduler.stop();
			NightlyJobs.forget();

			Assert.isFalse(before, 'Shipped off.');
			Assert.isTrue(ackOn, 'On once switched on.');
			Assert.areEqual(45, ackNext.minute(), 'At quarter to three.');
			Assert.isTrue(remindersOn, 'The reminders too.');
			Assert.isFalse(AcknowledgmentScheduler.isScheduled(), 'Off again.');
			Assert.isNull(AcknowledgmentScheduler.nextRunAt(), 'With no next run.');
		}
	}
}
