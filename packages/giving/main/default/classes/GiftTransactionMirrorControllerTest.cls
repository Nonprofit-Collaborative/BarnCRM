/**
 * The Gift Transaction mirror page's controller (X-07) as Maria and Ana use it. The present path
 * runs against the stand-ins of `GiftTransactionMirrorSchema.useStandIns` (ADR-0157 decision 9),
 * with Pending as the paid status so stand-in Gift Transactions are never copied themselves; the
 * absent path is forced with `absentForTest`.
 */
@IsTest(testFor='ApexClass:GiftTransactionMirrorController')
private class GiftTransactionMirrorControllerTest {
	// The mirror's settings for every test: a store value lasts one transaction, so it is put here.
	static {
		ModuleSettings.setForTest(
			'Mirror_Gift_Transaction_Mirror_Direction',
			GiftTransactionMirrorService.GIFTS_TO_GIFT_TRANSACTIONS
		);
		ModuleSettings.setForTest('Mirror_Gift_Transaction_Mirror_Status', 'Pending');
		ModuleSettings.setForTest('Mirror_Gift_Transaction_Mirror_Start', Datetime.newInstance(2026, 1, 1, 12, 0, 0));
	}

	@TestSetup
	static void setup() {
		TestUsers.adminWith('Giving_Admin');
	}

	/** Maria: an administrator who runs the mirror. */
	private static User maria() {
		return TestDataFactory.createUserOnTheRunningUsersProfile(
			'Maria',
			new List<String>{ 'BarnCRM_Admin', 'Giving_Admin', 'Salesforce_Records_Sync' }
		);
	}

	private static String refusalOf(Callable call) {
		try {
			call.call('', null);
		} catch (AuraHandledException refused) {
			return refused.getMessage();
		}
		return null;
	}

	/** Each page action, callable so a refusal can be read the same way for all of them. */
	private class Action implements Callable {
		private final String name;
		Action(String name) {
			this.name = name;
		}
		public Object call(String unused, Map<String, Object> args) {
			Date day = Date.newInstance(2026, 9, 20);
			switch on name {
				when 'status' {
					return GiftTransactionMirrorController.getStatus();
				}
				when 'run' {
					return GiftTransactionMirrorController.runNow();
				}
				when 'schedule' {
					return GiftTransactionMirrorController.schedule();
				}
				when 'stop' {
					return GiftTransactionMirrorController.stop();
				}
				when 'copyNoDates' {
					return GiftTransactionMirrorController.copyRangeAgain(null, null);
				}
				when 'copyBackwards' {
					return GiftTransactionMirrorController.copyRangeAgain(day, day.addDays(-1));
				}
				when else {
					return GiftTransactionMirrorController.compare(day, day.addDays(-1));
				}
			}
		}
	}

	@IsTest
	static void maryRunsSchedulesStopsAndCompares() {
		System.runAs(maria()) {
			TestDataFactory.clearScheduledJobs(new List<String>{ GiftTransactionMirrorSchedulable.JOB_NAME });
			ScheduledJobSelector.forget();
			GiftTransactionMirrorSchema.useStandIns();
			Test.startTest();
			GiftTransactionMirrorController.Status status = GiftTransactionMirrorController.getStatus();
			Assert.isTrue(status.available);
			Assert.areEqual('Pending', status.paidStatus);
			Assert.isNull(status.notReadyReason, 'Ready.');
			Assert.isTrue(status.canRun && status.canManage);

			Assert.isTrue(GiftTransactionMirrorController.runNow().running, 'Run Now starts a run.');
			Assert.isNotNull(GiftTransactionMirrorController.schedule().nextRunAt);
			Assert.isNull(GiftTransactionMirrorController.stop().nextRunAt);
			Assert.areEqual(
				0,
				GiftTransactionMirrorController.compare(Date.newInstance(2026, 9, 1), Date.newInstance(2026, 9, 30))
					.differenceCount
			);
			Assert.areEqual(
				BarnHelp.text('Giving', 'Mirror_OpportunityMirror_ErrorDateOrder'),
				refusalOf(new Action('compare'))
			);
			Assert.areEqual(
				BarnHelp.text('Giving', 'Mirror_OpportunityMirror_Running'),
				refusalOf(new Action('copyBackwards')),
				'A second run waits for the first.'
			);
			Test.stopTest();
		}
	}

	@IsTest
	static void copyingARangeAgainChecksTheDatesThenStartsARun() {
		System.runAs(maria()) {
			TestDataFactory.clearScheduledJobs(new List<String>{ GiftTransactionMirrorSchedulable.JOB_NAME });
			ScheduledJobSelector.forget();
			GiftTransactionMirrorSchema.useStandIns();
			Date day = Date.newInstance(2026, 9, 20);

			Test.startTest();
			Assert.areEqual(
				BarnHelp.text('Giving', 'Mirror_OpportunityMirror_ErrorDateOrder'),
				refusalOf(new Action('copyBackwards')),
				'An end date before the start is refused before anything starts.'
			);
			Assert.isTrue(
				GiftTransactionMirrorController.copyRangeAgain(day, day).running,
				'A valid range starts a run.'
			);
			Test.stopTest();
		}
	}

	@IsTest
	static void refusalsAreInWords() {
		System.runAs(maria()) {
			GiftTransactionMirrorSchema.absentForTest = true;
			Assert.isFalse(GiftTransactionMirrorController.getStatus().available);
			Assert.areEqual(
				BarnHelp.text('Giving', 'Mirror_GiftTransactionMirror_Unavailable'),
				refusalOf(new Action('run'))
			);

			GiftTransactionMirrorSchema.absentForTest = false;
			GiftTransactionMirrorSchema.useStandIns();
			Assert.areEqual(
				BarnHelp.text('Giving', 'Mirror_OpportunityMirror_ErrorDatesRequired'),
				refusalOf(new Action('copyNoDates'))
			);
			ModuleSettings.setForTest('Mirror_Gift_Transaction_Mirror_Start', null);
			Assert.areEqual(
				BarnHelp.text('Giving', 'Mirror_GiftTransactionMirror_NoStartDate'),
				refusalOf(new Action('schedule')),
				'Not ready (R-GT2).'
			);
			ModuleSettings.setForTest('Mirror_Gift_Transaction_Mirror_Direction', GiftTransactionMirrorService.OFF);
			Assert.areEqual(
				BarnHelp.text('Giving', 'Mirror_GiftTransactionMirror_SwitchedOff'),
				refusalOf(new Action('run'))
			);
		}
	}

	@IsTest
	static void thePageNeedsItsPermissionSet() {
		User ana = TestDataFactory.createUserOnTheRunningUsersProfile('Ana', new List<String>{ 'Giving_Admin' });
		System.runAs(ana) {
			for (String action : new List<String>{ 'status', 'stop', 'compare' }) {
				Assert.areEqual(
					BarnHelp.text('Giving', 'Mirror_GiftTransactionMirror_NoUsePermission'),
					refusalOf(new Action(action)),
					action
				);
			}
		}
	}
}
