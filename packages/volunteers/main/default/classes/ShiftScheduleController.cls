/**
 * What the Create Shifts Now panel on a shift schedule calls (modules-15, modules-24).
 *
 * The preview counts the shifts the next run would create and the day it would create them
 * through, with the same rules as ShiftScheduleService.run: from today, the Start Date or the day
 * after Created Through, whichever is latest, up to the horizon or the End Date, skipping days
 * that already hold a shift and times already past. Create Shifts Now calls that same run for
 * this one schedule, so nobody waits for the nightly job. Anything unexpected is recorded in the
 * Error Log before it is reported (plan Section 7.2).
 */
public with sharing class ShiftScheduleController {
	private static final String CONTEXT = 'Shift schedule panel';

	/** The schedule's state for the panel. */
	public class Preview {
		@AuraEnabled
		public Boolean active = false;
		@AuraEnabled
		public Boolean turnedOff = false;
		@AuraEnabled
		public Boolean canCreate = false;
		@AuraEnabled
		public Integer missing = 0;
		@AuraEnabled
		public Date through;
		@AuraEnabled
		public Date createdThrough;
	}

	@AuraEnabled
	public static Preview getPreview(Id scheduleId) {
		try {
			return previewOf(scheduleId);
		} catch (Exception failure) {
			throw report(failure, scheduleId, loadFailed());
		}
	}

	/** Creates the shifts the schedule is missing now and returns the fresh preview. */
	@AuraEnabled
	public static Preview createNow(Id scheduleId) {
		try {
			Preview before = previewOf(scheduleId);
			if (!before.canCreate) {
				throw UserErrors.message(createFailed());
			}
			ShiftScheduleService.run(new Set<Id>{ scheduleId });
			return previewOf(scheduleId);
		} catch (Exception failure) {
			throw report(failure, scheduleId, createFailed());
		}
	}

	private static Preview previewOf(Id scheduleId) {
		Shift_Schedule__c schedule = scheduleId == null
			? null
			: ShiftScheduleSelector.scheduleForPreview(scheduleId);
		if (schedule == null) {
			throw UserErrors.message(loadFailed());
		}
		Preview preview = new Preview();
		preview.active = schedule.Active__c == true;
		preview.turnedOff = ShiftScheduleService.isTurnedOff();
		preview.createdThrough = schedule.Created_Through__c;
		preview.canCreate =
			preview.active &&
			!preview.turnedOff &&
			Schema.SObjectType.Volunteer_Shift__c.isCreateable() &&
			Schema.SObjectType.Shift_Schedule__c.isUpdateable();
		if (!preview.active) {
			return preview;
		}
		Date runDay = ShiftScheduleService.today();
		Date horizon = runDay.addDays(7 * VolunteerSettings.shiftHorizonWeeks());
		Date untilDay = schedule.End_Date__c != null &&
			schedule.End_Date__c < horizon
			? schedule.End_Date__c
			: horizon;
		preview.through = untilDay;
		Date fromDay = later(runDay, schedule.Start_Date__c);
		if (schedule.Created_Through__c != null) {
			fromDay = later(fromDay, schedule.Created_Through__c.addDays(1));
		}
		if (fromDay > untilDay) {
			return preview;
		}
		Set<Date> taken = new Set<Date>();
		for (
			Volunteer_Shift__c shift : ShiftScheduleSelector.shiftsFrom(
				new Set<Id>{ scheduleId },
				ShiftScheduleService.toOrgDatetime(runDay, Time.newInstance(0, 0, 0, 0))
			)
		) {
			taken.add(ShiftScheduleService.orgDate(shift.Start_Time__c));
		}
		Datetime now = ShiftScheduleService.now();
		for (Date day : ShiftScheduleService.shiftDays(schedule, fromDay, untilDay)) {
			if (
				!taken.contains(day) &&
				ShiftScheduleService.toOrgDatetime(day, schedule.Start_Time__c) >= now
			) {
				preview.missing++;
			}
		}
		return preview;
	}

	private static Date later(Date first, Date second) {
		if (second == null) {
			return first;
		}
		return first == null || second > first ? second : first;
	}

	private static String loadFailed() {
		return BarnHelp.text('Volunteers', 'Volunteers_Schedule_LoadFailed');
	}

	private static String createFailed() {
		return BarnHelp.text('Volunteers', 'Volunteers_Schedule_CreateFailed');
	}

	private static AuraHandledException report(Exception failure, Id recordId, String message) {
		if (failure instanceof AuraHandledException) {
			return (AuraHandledException) failure;
		}
		if (failure instanceof DmlException) {
			return UserErrors.message(((DmlException) failure).getDmlMessage(0));
		}
		ErrorLogger.log(failure, CONTEXT, recordId);
		return UserErrors.message(message);
	}
}
