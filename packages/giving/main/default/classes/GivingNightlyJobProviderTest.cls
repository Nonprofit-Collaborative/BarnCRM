/**
 * Giving's steps of the nightly run (ADR-0166 nightly-job-dispatcher): the five jobs switched
 * together (four shipped on, the pledge reminders shipped off, G-37), then the acknowledgment
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

	@IsTest
	static void scheduleAllSwitchesTheFiveOnAndStopAllOff() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			noRun();
			Boolean before = GivingScheduler.isScheduled();

			GivingScheduler.scheduleAll();
			NightlyJobs.forget();
			ScheduledJobSelector.forget();
			Boolean after = GivingScheduler.isScheduled();
			Boolean remindersOn = PledgeReminderScheduler.isScheduled();
			Datetime next = GivingScheduler.nextRunAt();
			PledgeReminderScheduler.stop();
			NightlyJobs.forget();
			Boolean afterRemindersStopped = GivingScheduler.isScheduled();
			GivingScheduler.stopAll();
			NightlyJobs.forget();

			Assert.isFalse(before, 'Nothing runs before the run is scheduled.');
			Assert.isTrue(after, 'All on, with the run scheduled.');
			Assert.isTrue(remindersOn, 'Schedule switches the pledge reminders on too (G-37).');
			Assert.isTrue(
				afterRemindersStopped,
				'Stopping the reminders on their own page leaves the other four counted as on.'
			);
			Assert.isFalse(PledgeReminderService.isEnabled(), 'Sending stays off (D-162).');
			Assert.isNotNull(next, 'With the next of them.');
			Assert.isFalse(GivingScheduler.isScheduled(), 'Stopped.');
			Assert.isFalse(
				GivingScheduler.isJobScheduled(GivingScheduler.LEVELS_JOB_NAME),
				'Each one is off.'
			);
			Assert.isTrue(NightlyJobs.isScheduled(), 'The run stays for the other steps.');
		}
	}

	@IsTest
	static void schedulingOneJobLeavesTheOthersAsTheyWere() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			noRun();
			GivingScheduler.stopAll();
			GivingScheduler.scheduleJobNamed(GivingScheduler.OVERDUE_JOB_NAME);
			GivingScheduler.scheduleJobNamed('BarnCRM Giving: not a job');
			NightlyJobs.forget();
			ScheduledJobSelector.forget();

			Assert.isTrue(GivingScheduler.isJobScheduled(GivingScheduler.OVERDUE_JOB_NAME));
			Assert.isFalse(GivingScheduler.isJobScheduled(GivingScheduler.TOP_UP_JOB_NAME));
			Assert.isFalse(GivingScheduler.isJobScheduled('BarnCRM Giving: not a job'));
			Assert.isFalse(GivingScheduler.isScheduled(), 'One of four is not on.');
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
