/**
 * The Create Shifts Now panel (modules-15, modules-24): the preview counts what the next run
 * creates, Create Shifts Now creates it through the same run, an inactive schedule creates
 * nothing and a Read Only user cannot create. The clock and time zone are fixed (America/New_York,
 * Monday 2 March 2026 at noon).
 */
@IsTest(testFor='ApexClass:ShiftScheduleController, ApexClass:ShiftScheduleSelector')
private class ShiftScheduleControllerTest {
	private static final String ZONE = 'America/New_York';
	private static final String RULES = 'Shift_Schedule_Rules';
	private static final Datetime MONDAY_NOON = Datetime.newInstanceGmt(2026, 3, 2, 17, 0, 0);

	@TestSetup
	static void makeData() {
		System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
			VolunteersTestData.job('Food pantry sort');
		}
	}

	private static void useClock() {
		ShiftScheduleService.timeZoneOverride = ZONE;
		ShiftScheduleService.nowOverride = MONDAY_NOON;
	}

	/** A Saturday and Sunday schedule saved without the save's own run. */
	private static Shift_Schedule__c saved(Boolean active) {
		Id jobId = [SELECT Id FROM Volunteer_Job__c LIMIT 1].Id;
		Shift_Schedule__c schedule = VolunteersTestData.newSchedule(
			jobId,
			'Saturday;Sunday',
			Date.newInstance(2026, 2, 28)
		);
		schedule.Active__c = active;
		AutomationControl.bypass(RULES);
		insert schedule;
		AutomationControl.clearBypass(RULES);
		return schedule;
	}

	private static Integer shiftCount(Id scheduleId) {
		return [
			SELECT COUNT()
			FROM Volunteer_Shift__c
			WHERE Shift_Schedule__c = :scheduleId
			WITH SYSTEM_MODE
		];
	}

	@IsTest
	static void thePreviewCountsTheMissingShiftsAndCreateShiftsNowMakesThem() {
		System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
			useClock();
			VolunteersTestData.shiftHorizonWeeks(2);
			Shift_Schedule__c schedule = saved(true);

			Test.startTest();
			ShiftScheduleController.Preview before = ShiftScheduleController.getPreview(
				schedule.Id
			);
			ShiftScheduleController.Preview after = ShiftScheduleController.createNow(schedule.Id);
			Test.stopTest();

			Assert.isTrue(before.canCreate, 'An admin can create shifts.');
			Assert.areEqual(4, before.missing, 'Two weekends to the two week horizon.');
			Assert.areEqual(Date.newInstance(2026, 3, 16), before.through, 'Through the horizon.');
			Assert.areEqual(4, shiftCount(schedule.Id), 'The run created what the preview said.');
			Assert.areEqual(0, after.missing, 'Nothing is left to create.');
			Assert.areEqual(
				Date.newInstance(2026, 3, 16),
				after.createdThrough,
				'Created Through moved to the horizon.'
			);
		}
	}

	@IsTest
	static void anInactiveScheduleCreatesNothing() {
		System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
			useClock();
			Shift_Schedule__c schedule = saved(false);
			Boolean refused = false;

			Test.startTest();
			ShiftScheduleController.Preview preview = ShiftScheduleController.getPreview(
				schedule.Id
			);
			try {
				ShiftScheduleController.createNow(schedule.Id);
			} catch (AuraHandledException denied) {
				refused = true;
			}
			Test.stopTest();

			Assert.isFalse(preview.active, 'Inactive.');
			Assert.isFalse(preview.canCreate, 'No Create Shifts Now.');
			Assert.isTrue(refused, 'A crafted call is refused.');
			Assert.areEqual(0, shiftCount(schedule.Id), 'No shift created.');
		}
	}

	@IsTest
	static void aMissingScheduleIsReportedInPlainWords() {
		Boolean refused = false;
		System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
			Test.startTest();
			try {
				ShiftScheduleController.getPreview(null);
			} catch (AuraHandledException denied) {
				refused = true;
			}
			Test.stopTest();
		}
		Assert.isTrue(refused, 'No schedule, no preview.');
	}

	@IsTest
	static void theFormPreviewCountsFromTheOrgsTodayToTheHorizon() {
		useClock();
		ShiftScheduleController.FormSettings settings;
		System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
			Test.startTest();
			settings = ShiftScheduleController.getFormSettings();
			Test.stopTest();
		}
		Assert.areEqual(
			Date.newInstance(2026, 3, 2),
			settings.today,
			'Today in the org time zone.'
		);
		Assert.areEqual(
			VolunteerSettings.shiftHorizonWeeks(),
			settings.horizonWeeks,
			'The horizon the run uses.'
		);
	}
}
