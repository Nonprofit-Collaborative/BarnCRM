/**
 * The hourly Case check (N-10, owner decision "Hourly if cases exist"): one hourly job, scheduled
 * by the nightly step or Run Now while Send Cases to a service provider is on, never doubled; a
 * pass is queued only when an open request or an open Case of the chosen Type exists, so an org
 * with none makes no callout and writes no Error Log entry; turning the setting or the step off
 * removes the job. Case is reached by name, as the class does, so the test compiles where Case
 * is not available.
 */
@IsTest(
	testFor='ApexClass:CaseProviderRequestsHourly, ApexClass:CaseProviderRequests, ApexClass:MirrorNightlyJobProvider'
)
private class CaseProviderRequestsHourlyTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	private static void turnOn(Boolean enabled) {
		ModuleSettings.setForTest('Mirror_Case_Requests', enabled);
		ModuleSettings.setForTest('Mirror_Case_Requests_Type', 'Other');
	}

	private static Integer hourlyJobs() {
		return [
			SELECT COUNT()
			FROM CronTrigger
			WHERE CronJobDetail.Name = :CaseProviderRequestsHourly.JOB_NAME
			WITH SYSTEM_MODE
		];
	}

	private static Integer errorLogEntries() {
		return [SELECT COUNT() FROM Error_Log__c WITH SYSTEM_MODE];
	}

	@IsTest
	static void withNothingOpenTheJobIsKeptButNoPassIsQueued() {
		System.runAs(TestUsers.admin()) {
			if (CaseProviderRequests.caseType() == null) {
				return;
			}
			turnOn(true);
			Integer logsBefore = errorLogEntries();

			Test.startTest();
			new CaseProviderRequestsHourly().execute(null);
			CaseProviderRequests.startHourly();
			Integer queued = Limits.getQueueableJobs();
			Integer callouts = Limits.getCallouts();
			Test.stopTest();

			Assert.areEqual(0, queued, 'Nothing open: no pass is queued.');
			Assert.areEqual(0, callouts, 'Nothing open: no callout.');
			Assert.areEqual(1, hourlyJobs(), 'One hourly job, however often it is asked for.');
			Assert.areEqual(logsBefore, errorLogEntries(), 'Nothing open: no Error Log entry.');
		}
	}

	@IsTest
	static void anOpenCaseOfTheChosenTypeQueuesAPass() {
		System.runAs(TestUsers.admin()) {
			if (CaseProviderRequests.caseType() == null) {
				return;
			}
			turnOn(true);
			SObject record = CaseProviderRequests.caseType().newSObject();
			record.put('Subject', 'The printer is offline');
			record.put('Type', 'Other');
			insert record;
			// The queued pass runs at stopTest; with no callout left it sends nothing.
			CaseProviderRequests.calloutsLeftForTest = 0;

			Test.startTest();
			Assert.isTrue(CaseProviderRequests.hasOpenRequests(), 'An open Case to send.');
			CaseProviderRequests.startHourly();
			Assert.areEqual(1, Limits.getQueueableJobs(), 'One pass queued.');
			Test.stopTest();
		}
	}

	@IsTest
	static void anOpenRequestQueuesAPassAndAFinishedOneDoesNot() {
		System.runAs(TestUsers.admin()) {
			if (CaseProviderRequests.caseType() == null) {
				return;
			}
			turnOn(true);
			Provider_Request__c request = new Provider_Request__c(
				Name = '00001001',
				Case_Id__c = '500000000000001AAA',
				Request_Number__c = 'REQ-000001',
				Status__c = 'Resolved'
			);
			insert as system request;
			Boolean finishedCounts = CaseProviderRequests.hasOpenRequests();
			request.Status__c = 'In Progress';
			update as system request;

			Assert.isFalse(finishedCounts, 'A Resolved request needs no status check.');
			Assert.isTrue(CaseProviderRequests.hasOpenRequests(), 'An open request does.');
		}
	}

	@IsTest
	static void turningTheSettingOrTheStepOffRemovesTheJob() {
		System.runAs(TestUsers.admin()) {
			if (CaseProviderRequests.caseType() == null) {
				return;
			}
			turnOn(true);
			CaseProviderRequestsHourly.ensure();
			ScheduledJobSelector.forget();
			Integer scheduled = hourlyJobs();

			NightlyJobs.turnOff(CaseProviderRequests.JOB_NAME);
			NightlyJobs.forget();
			CaseProviderRequests.startHourly();
			ScheduledJobSelector.forget();
			Integer afterStepOff = hourlyJobs();

			NightlyJobs.turnOn(CaseProviderRequests.JOB_NAME);
			NightlyJobs.forget();
			CaseProviderRequests.startHourly();
			ScheduledJobSelector.forget();
			Integer afterStepOn = hourlyJobs();

			turnOn(false);
			CaseProviderRequests.startHourly();
			ScheduledJobSelector.forget();

			Assert.areEqual(1, scheduled, 'Scheduled.');
			Assert.areEqual(0, afterStepOff, 'Switched off on the Nightly Jobs card: removed.');
			Assert.areEqual(1, afterStepOn, 'Switched on again: scheduled again.');
			Assert.areEqual(0, hourlyJobs(), 'Send Cases turned off: removed.');
		}
	}

	@IsTest
	static void aJobOnAnotherCronIsReplacedNotDoubled() {
		System.runAs(TestUsers.admin()) {
			System.schedule(CaseProviderRequestsHourly.JOB_NAME, '0 0 1 * * ?', new CaseProviderRequestsHourly());
			ScheduledJobSelector.forget();

			CaseProviderRequestsHourly.ensure();
			ScheduledJobSelector.forget();

			Assert.areEqual(1, hourlyJobs(), 'Never two.');
			Assert.areEqual(
				CaseProviderRequestsHourly.HOURLY_CRON,
				ScheduledJobSelector.cronExpressionByName(CaseProviderRequestsHourly.JOB_NAME),
				'On the hourly cron.'
			);
			CaseProviderRequestsHourly.stop();
			ScheduledJobSelector.forget();
			Assert.isFalse(CaseProviderRequestsHourly.isScheduled(), 'Stopped.');
		}
	}

	@IsTest
	static void theNightlyCardShowsTheStepWithRunNowAndItsSchedule() {
		System.runAs(TestUsers.admin()) {
			if (CaseProviderRequests.caseType() == null) {
				return;
			}
			List<NightlyStep> offSteps = new MirrorNightlyJobProvider().nightlySteps();
			turnOn(true);
			NightlyStep before = CaseProviderRequests.step();
			CaseProviderRequestsHourly.ensure();
			ScheduledJobSelector.forget();
			NightlyStep after = CaseProviderRequests.step();

			Assert.areEqual(1, offSteps.size(), 'Mirror has the one step.');
			Assert.isFalse(offSteps[0].active, 'Off at install: not in tonight\'s run.');
			Assert.isNull(offSteps[0].summary, 'Off: nothing to say about the hourly job.');
			Assert.areEqual(100, before.minute, '1:40');
			Assert.isTrue(before.active, 'On: in tonight\'s run.');
			Assert.isTrue(before.canRunNow, 'Run Now starts the hourly check at once.');
			Assert.isTrue(before.switchDefault, 'Shipped on.');
			Assert.areEqual(
				BarnHelp.text('Mirror', 'Mirror_CaseRequests_HourlyNotScheduled'),
				before.summary,
				'Says the hourly job is not scheduled yet.'
			);
			Assert.areEqual(
				BarnHelp.text('Mirror', 'Mirror_CaseRequests_HourlyScheduled'),
				after.summary,
				'Says the hourly job is scheduled.'
			);
		}
	}
}
