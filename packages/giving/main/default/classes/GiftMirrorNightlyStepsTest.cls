/**
 * Fundraising's gift mirror steps of the nightly run (ADR-0166 nightly-job-dispatcher), added by
 * `GivingNightlyJobProvider`: the Opportunity mirror's run is in tonight's run only while a
 * direction is chosen, and its page switches it on and off.
 */
@IsTest(
	testFor='ApexClass:GivingNightlyJobProvider, ApexClass:OpportunityMirrorSchedulable, ApexClass:GiftTransactionMirrorSchedulable'
)
private class GiftMirrorNightlyStepsTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith('Giving_Admin');
	}

	private static void choose(String direction) {
		Giving_Settings__c settings = Giving_Settings__c.getOrgDefaults();
		settings.Opportunity_Mirror_Direction__c = direction;
		upsert settings;
	}

	private static NightlyStep stepNamed(String key) {
		for (NightlyStep step : new GivingNightlyJobProvider().nightlySteps()) {
			if (step.key == key) {
				return step;
			}
		}
		return null;
	}

	private static NightlyStep opportunityStep() {
		return stepNamed(OpportunityMirrorSchedulable.JOB_NAME);
	}

	@IsTest
	static void bothMirrorsAreStepsAtTheirTimes() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			NightlyStep opportunity = opportunityStep();
			NightlyStep giftTransaction = stepNamed(GiftTransactionMirrorSchedulable.JOB_NAME);

			Assert.isNotNull(opportunity, 'The Opportunity mirror is a Fundraising step.');
			Assert.isNotNull(giftTransaction, 'So is the Gift Transaction mirror.');
			Assert.areEqual(90, opportunity.minute, '1:30');
			Assert.areEqual(95, giftTransaction.minute, '1:35');
			Assert.areEqual(System.Label.Mirror_OpportunityMirror_Title, opportunity.label);
			Assert.isTrue(opportunity.switchDefault, 'Shipped on.');
		}
	}

	@IsTest
	static void theMirrorRunIsLeftOutWhileTheMirrorIsOff() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			choose(OpportunityMirrorService.OFF);

			Assert.isFalse(NightlyJobs.isOn(opportunityStep()), 'A mirror that is Off has no run worth doing.');
		}
	}

	@IsTest
	static void theMirrorRunIsInTonightsRunOnceADirectionIsChosen() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			choose(OpportunityMirrorService.GIFTS_TO_OPPORTUNITIES);

			Assert.areEqual(
				OpportunityMirrorService.isAvailable(),
				NightlyJobs.isOn(opportunityStep()),
				'On wherever the org has Opportunities.'
			);
		}
	}

	@IsTest
	static void thePageSwitchesTheRunOnAndOff() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			TestDataFactory.clearScheduledJobs(new List<String>{ NightlyJobs.jobName() });
			ScheduledJobSelector.forget();
			Boolean before = OpportunityMirrorSchedulable.isScheduled();

			Id first = OpportunityMirrorSchedulable.schedule();
			Id second = OpportunityMirrorSchedulable.schedule();
			ScheduledJobSelector.forget();
			NightlyJobs.forget();
			Boolean switchedOn = OpportunityMirrorSchedulable.isScheduled();
			Datetime scheduledAt = OpportunityMirrorSchedulable.scheduledAt();
			OpportunityMirrorSchedulable.stop();
			NightlyJobs.forget();

			Assert.isFalse(before, 'Not before the run is scheduled.');
			Assert.areEqual(first, second, 'A second press returns the run already there.');
			Assert.isTrue(switchedOn, 'Switched on.');
			Assert.isNotNull(scheduledAt, 'Health Check sees when.');
			Assert.isFalse(OpportunityMirrorSchedulable.isScheduled(), 'Switched off.');
			Assert.isNull(OpportunityMirrorSchedulable.nextRunAt(), 'With no next run.');
		}
	}
}
