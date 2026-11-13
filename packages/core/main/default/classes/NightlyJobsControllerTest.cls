/**
 * NightlyJobsController: the Nightly Jobs panel on the General page of BarnCRM Settings shows
 * the one schedule and every step with how it last ran, and only someone who manages settings
 * can schedule the run from it (ADR-0166 nightly-job-dispatcher).
 */
@IsTest(testFor='ApexClass:NightlyJobsController')
private class NightlyJobsControllerTest {
	private static final String STEP_KEY = 'BarnCRM Panel Test Step';

	@TestSetup
	static void grantPermission() {
		System.runAs(TestUsers.admin()) {
			SettingsTestPermissions.grantTo('Nightly_Jobs_Panel_Test', UserInfo.getUserId());
			TestUsers.standardUser('Reader');
		}
	}

	private class NoWork implements Schedulable {
		public void execute(SchedulableContext context) {
			return;
		}
	}

	private static Integer runs = 0;

	private class CountingWork implements Schedulable {
		public void execute(SchedulableContext context) {
			runs++;
		}
	}

	/** One step with a switch that allows Run Now, and one with neither. */
	private static void twoSteps() {
		NightlyJobs.overrideStepsForTest(
			new List<NightlyStep>{
				new NightlyStep(STEP_KEY, 'Panel step', 1, 15, new CountingWork())
					.withSwitch(true)
					.withSummary('3 payments added')
					.runnableNow(),
				new NightlyStep('BarnCRM Panel Plain Step', 'Plain', 2, 0, new NoWork())
			}
		);
	}

	private static String refusal(String key, Boolean isSwitch) {
		try {
			if (isSwitch) {
				NightlyJobsController.setStep(key, false);
			} else {
				NightlyJobsController.runStep(key);
			}
		} catch (AuraHandledException expected) {
			return expected.getMessage();
		}
		return null;
	}

	@IsTest
	static void aManagerSwitchesAStepAndStartsItNow() {
		System.runAs(TestUsers.admin()) {
			twoSteps();

			Test.startTest();
			NightlyJobsController.PanelView afterOff = NightlyJobsController.setStep(
				STEP_KEY,
				false
			);
			NightlyJobsController.PanelView afterOn = NightlyJobsController.setStep(STEP_KEY, true);
			NightlyJobsController.runStep(STEP_KEY);
			Test.stopTest();

			Assert.isFalse(afterOff.steps[0].switchedOn, 'Turned off');
			Assert.isTrue(afterOn.steps[0].switchedOn, 'Turned on again');
			Assert.isTrue(afterOn.scheduled, 'Turning on schedules the run');
			Assert.isTrue(afterOn.steps[0].canRunNow, 'Offers Run Now');
			Assert.areEqual('3 payments added', afterOn.steps[0].summary, 'Shows its summary');
			Assert.isFalse(afterOn.steps[1].hasSwitch, 'The plain step has no switch');
			Assert.areEqual(1, runs, 'Run Now started its work once');
		}
	}

	@IsTest
	static void aStepWithoutASwitchOrRunNowOrThatIsUnknownIsRefused() {
		System.runAs(TestUsers.admin()) {
			twoSteps();
			Test.startTest();
			String noSwitch = refusal('BarnCRM Panel Plain Step', true);
			String noRun = refusal('BarnCRM Panel Plain Step', false);
			String unknown = refusal('BarnCRM Not A Step', false);
			Test.stopTest();

			Assert.areEqual(BarnHelp.text('Core', 'Core_NightlyJobs_NoSwitch'), noSwitch);
			Assert.areEqual(BarnHelp.text('Core', 'Core_NightlyJobs_NoRunNow'), noRun);
			Assert.areEqual(BarnHelp.text('Core', 'Core_NightlyJobs_NoSuchJob'), unknown);
		}
	}

	@IsTest
	static void someoneWhoDoesNotManageSettingsCannotSwitchOrRun() {
		System.runAs(TestUsers.admin()) {
			twoSteps();
			User reader = TestUsers.standardUser('Reader');
			Test.startTest();
			System.runAs(reader) {
				Assert.areEqual(
					BarnHelp.text('Core', 'Core_HealthCheck_PermissionRequired'),
					refusal(STEP_KEY, true),
					'Switching needs Manage BarnCRM Settings'
				);
				Assert.areEqual(
					BarnHelp.text('Core', 'Core_HealthCheck_PermissionRequired'),
					refusal(STEP_KEY, false),
					'So does Run Now'
				);
			}
			Test.stopTest();
			Assert.areEqual(0, runs, 'Nothing ran');
		}
	}

	@IsTest
	static void thePanelListsEachStepWithItsTimeSwitchAndLastResult() {
		System.runAs(TestUsers.admin()) {
			NightlyJobs.overrideStepsForTest(
				new List<NightlyStep>{
					new NightlyStep(STEP_KEY, 'Panel step', 2, 45, new NoWork()).withSwitch(false)
				}
			);
			Nightly_Job__c row = NightlyJobs.rowFor(STEP_KEY);
			row.Last_Started__c = Datetime.now().addHours(-3);
			row.Last_Outcome__c = NightlyJobs.DONE_WITH_ERRORS;
			row.Last_Message__c = 'Two rows failed';
			Nightly_Job__c run = NightlyJobs.rowFor(NightlyJobs.JOB_NAME);
			run.Last_Started__c = Datetime.now().addHours(-4);
			run.Last_Outcome__c = NightlyJobs.DONE;
			NightlyJobs.save(new List<Nightly_Job__c>{ row, run });
			NightlyJobs.forget();

			Test.startTest();
			NightlyJobsController.PanelView view = NightlyJobsController.getPanel();
			Test.stopTest();

			Assert.isTrue(view.canManage, 'The administrator manages settings');
			Assert.areEqual(1, view.steps.size(), 'One step');
			NightlyJobsController.StepView step = view.steps[0];
			Assert.areEqual(165, step.minute, 'At 2:45');
			Assert.isFalse(step.isOn, 'Shipped off');
			Assert.isNotNull(step.outcome, 'With its last result');
			Assert.areEqual('Two rows failed', step.message, 'And what it said');
			Assert.isNotNull(view.lastRunStarted, 'The run\'s last start');
			Assert.isNotNull(view.lastRunOutcome, 'And result');
		}
	}

	@IsTest
	static void theScheduleButtonSchedulesTheRun() {
		System.runAs(TestUsers.admin()) {
			TestDataFactory.clearScheduledJobs(new List<String>{ NightlyJobs.jobName() });
			ScheduledJobSelector.forget();
			NightlyRun.chain = false;
			NightlyJobs.overrideStepsForTest(new List<NightlyStep>());

			Test.startTest();
			NightlyJobsController.PanelView view = NightlyJobsController.schedule();
			Test.stopTest();

			Assert.isTrue(view.scheduled, 'Scheduled');
		}
	}

	@IsTest
	static void anOutcomeMapsToAKitStatusWord() {
		System.runAs(TestUsers.admin()) {
			Assert.areEqual('done', NightlyJobsController.outcomeStatus('Done'), 'Done');
			Assert.areEqual('failed', NightlyJobsController.outcomeStatus('Failed'), 'Failed');
			Assert.areEqual('skipped', NightlyJobsController.outcomeStatus('Skipped'), 'Skipped');
			Assert.areEqual(
				'in-progress',
				NightlyJobsController.outcomeStatus('Running'),
				'Running'
			);
			Assert.areEqual(
				'attention',
				NightlyJobsController.outcomeStatus('Done With Errors'),
				'Done with errors needs a look'
			);
			Assert.isNull(NightlyJobsController.outcomeStatus(null), 'No run yet shows no badge');
		}
	}

	@IsTest
	static void someoneWhoDoesNotManageSettingsCannotSchedule() {
		System.runAs(TestUsers.admin()) {
			User reader = TestUsers.standardUser('Reader');
			Test.startTest();
			System.runAs(reader) {
				try {
					NightlyJobsController.schedule();
					Assert.fail('Scheduling needs Manage BarnCRM Settings');
				} catch (AuraHandledException expected) {
					Assert.areEqual(
						BarnHelp.text('Core', 'Core_HealthCheck_PermissionRequired'),
						expected.getMessage(),
						'Names the permission'
					);
				}
			}
			Test.stopTest();
		}
	}
}
