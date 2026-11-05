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
		}
	}

	private class NoWork implements Schedulable {
		public void execute(SchedulableContext context) {
			return;
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
