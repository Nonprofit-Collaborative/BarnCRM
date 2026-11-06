/**
 * Repeating sessions (modules-24, ADR-0171, canonical model 29ZA7):
 * which days a schedule falls on, the run that creates its sessions up to the horizon, and
 * Remove Future Sessions.
 *
 * A run (R-SS2) locks its schedules first (R-SS3), creates the days after Created Through (or
 * from today or Start Date, if later) up to the horizon and End Date, skips a day that already
 * has a session of the schedule or of the same service and cohort (or that another schedule
 * took earlier in the same run), and moves Created Through
 * forward. Sessions are a date and a local time, so no time zone applies. Editing or ending a
 * schedule never deletes a session (R-SS4); only Remove Future Sessions does, after a confirm
 * (R-SS5).
 *
 * Sessions are created and removed in user mode. Created Through is read only in every
 * permission set, so the run writes it in system mode: it is the schedule's own bookkeeping.
 */
public with sharing class SessionScheduleService {
	public static final String MODULE_NAME = 'Programs';
	/** Weeks Ahead to Create Sessions when never saved, blank or out of range (R-SS2). */
	public static final Integer DEFAULT_HORIZON_WEEKS = 8;
	private static final String SETTINGS_OBJECT = 'Programs_Settings__c';
	private static Integer horizonWeeks;

	/** Monday first, as the multi-select stores them. Not named WEEKDAYS (case-insensitive). */
	private static final List<String> DAY_NAMES = new List<String>{
		'Monday',
		'Tuesday',
		'Wednesday',
		'Thursday',
		'Friday',
		'Saturday',
		'Sunday'
	};
	/** A Monday, from which the weekday of any later date is counted. */
	private static final Date A_MONDAY = Date.newInstance(1900, 1, 1);

	/** Set by tests so a run does not depend on the real date. */
	@TestVisible
	private static Date todayOverride;

	/** Whether Programs is turned off in Module Manager, when nothing here runs. */
	public static Boolean isTurnedOff() {
		return ModuleManagerService.turnedOff().contains(MODULE_NAME.toLowerCase());
	}

	public static Date today() {
		return todayOverride == null ? Date.today() : todayOverride;
	}

	/** How far ahead an active schedule keeps sessions: Weeks Ahead to Create Sessions, 1 to 26. */
	public static Integer horizonWeeks() {
		if (horizonWeeks == null) {
			horizonWeeks = DEFAULT_HORIZON_WEEKS;
			try {
				Object stored = SettingsService.getValue(
					SETTINGS_OBJECT,
					'Session_Horizon_Weeks__c'
				);
				Integer weeks = stored == null
					? null
					: Decimal.valueOf(String.valueOf(stored)).intValue();
				if (weeks != null && weeks >= 1 && weeks <= 26) {
					horizonWeeks = weeks;
				}
			} catch (Exception unreadable) {
				// Never saved or unreadable: the shipped value applies.
				horizonWeeks = DEFAULT_HORIZON_WEEKS;
			}
		}
		return horizonWeeks;
	}

	/** The last day a run fills: the horizon, or End Date when sooner. */
	public static Date lastDay(Session_Schedule__c schedule) {
		Date horizon = today().addDays(7 * horizonWeeks());
		return schedule.End_Date__c != null &&
			schedule.End_Date__c < horizon
			? schedule.End_Date__c
			: horizon;
	}

	/**
	 * Creates the sessions these schedules are missing up to the horizon (R-SS2) and returns how
	 * many it created. Inactive schedules create nothing.
	 */
	public static Integer run(Set<Id> scheduleIds) {
		if (scheduleIds == null || scheduleIds.isEmpty() || isTurnedOff()) {
			return 0;
		}
		List<Session_Schedule__c> schedules = SessionScheduleSelector.lockForRun(scheduleIds);
		Map<Id, List<Date>> planned = missingDays(schedules);
		List<Session__c> created = new List<Session__c>();
		List<Session_Schedule__c> bookkeeping = new List<Session_Schedule__c>();
		for (Session_Schedule__c schedule : schedules) {
			if (!planned.containsKey(schedule.Id)) {
				continue;
			}
			for (Date day : planned.get(schedule.Id)) {
				created.add(newSession(schedule, day));
			}
			bookkeeping.add(
				new Session_Schedule__c(Id = schedule.Id, Created_Through__c = lastDay(schedule))
			);
		}
		if (!created.isEmpty()) {
			insert as user created;
		}
		if (!bookkeeping.isEmpty()) {
			// System mode: Created Through is read only in every permission set (R-SS7).
			update as system bookkeeping;
		}
		return created.size();
	}

	/**
	 * Per active schedule with days left to fill, the days a run would create now, skipping the
	 * days already taken (R-SS2). A schedule with nothing to fill has no entry.
	 */
	public static Map<Id, List<Date>> missingDays(List<Session_Schedule__c> schedules) {
		Map<Id, List<Date>> missing = new Map<Id, List<Date>>();
		Map<Id, Date> fromDays = new Map<Id, Date>();
		Set<Id> serviceIds = new Set<Id>();
		for (Session_Schedule__c schedule : schedules) {
			Date fromDay = firstDay(schedule);
			if (schedule.Active__c == true && fromDay <= lastDay(schedule)) {
				fromDays.put(schedule.Id, fromDay);
				serviceIds.add(schedule.Service__c);
			}
		}
		if (fromDays.isEmpty()) {
			return missing;
		}
		List<Session__c> existing = SessionScheduleSelector.sessionsFrom(
			fromDays.keySet(),
			serviceIds,
			today()
		);
		// Days a schedule earlier in this run claims for its service and cohort, so two schedules
		// for the same group never both create one (R-SS2).
		Set<String> claimed = new Set<String>();
		for (Session_Schedule__c schedule : schedules) {
			if (!fromDays.containsKey(schedule.Id)) {
				continue;
			}
			Set<Date> taken = new Set<Date>();
			for (Session__c session : existing) {
				Boolean own = session.Session_Schedule__c == schedule.Id;
				Boolean sameGroup =
					session.Service__c == schedule.Service__c &&
					session.Cohort__c == schedule.Cohort__c &&
					session.Status__c != SessionAttendance.CANCELLED;
				if (own || sameGroup) {
					taken.add(session.Session_Date__c);
				}
			}
			List<Date> days = new List<Date>();
			for (Date day : sessionDays(schedule, fromDays.get(schedule.Id), lastDay(schedule))) {
				String key = schedule.Service__c + '|' + schedule.Cohort__c + '|' + day;
				if (!taken.contains(day) && claimed.add(key)) {
					days.add(day);
				}
			}
			missing.put(schedule.Id, days);
		}
		return missing;
	}

	/**
	 * The days from `fromDay` to `untilDay`, both included, that are session days (R-SS2, by
	 * R-SSC1): the weekday is chosen, the day is within Start Date and End Date, and the whole
	 * weeks between the Monday of Start Date's week and the Monday of its own divide by Repeat
	 * Every.
	 */
	public static List<Date> sessionDays(
		Session_Schedule__c schedule,
		Date fromDay,
		Date untilDay
	) {
		List<Date> days = new List<Date>();
		Set<Integer> chosen = new Set<Integer>();
		for (String part : (schedule.Weekdays__c == null ? '' : schedule.Weekdays__c).split(';')) {
			Integer index = DAY_NAMES.indexOf(part.trim());
			if (index >= 0) {
				chosen.add(index);
			}
		}
		if (chosen.isEmpty() || schedule.Start_Date__c == null || fromDay == null) {
			return days;
		}
		Integer everyN = schedule.Every_N_Weeks__c == null ||
			schedule.Every_N_Weeks__c < 1
			? 1
			: schedule.Every_N_Weeks__c.intValue();
		Date firstMonday = mondayOf(schedule.Start_Date__c);
		Date day = fromDay < schedule.Start_Date__c ? schedule.Start_Date__c : fromDay;
		Date endDay = schedule.End_Date__c != null &&
			schedule.End_Date__c < untilDay
			? schedule.End_Date__c
			: untilDay;
		while (day <= endDay) {
			Integer weeks = firstMonday.daysBetween(mondayOf(day)) / 7;
			if (chosen.contains(weekdayIndex(day)) && Math.mod(weeks, everyN) == 0) {
				days.add(day);
			}
			day = day.addDays(1);
		}
		return days;
	}

	/**
	 * R-SS5: deletes the schedule's Scheduled sessions after today with no service delivery, in
	 * user mode, then sets Created Through to today and runs the schedule, which recreates those
	 * days from its current pattern when it is active. Returns how many it deleted.
	 */
	public static Integer removeFutureSessions(Id scheduleId) {
		List<Session__c> removable = SessionScheduleSelector.removableAfter(scheduleId, today());
		if (!removable.isEmpty()) {
			delete as user removable;
		}
		// System mode: Created Through is read only in every permission set (R-SS7).
		update as system new Session_Schedule__c(Id = scheduleId, Created_Through__c = today());
		run(new Set<Id>{ scheduleId });
		return removable.size();
	}

	/** Monday to Sunday names, from the panel's JavaScript weekday numbers (0 is Sunday). */
	public static String weekdayNames(List<String> jsWeekdays) {
		List<String> names = new List<String>();
		for (Integer index = 0; index < DAY_NAMES.size(); index++) {
			if (jsWeekdays != null && jsWeekdays.contains(String.valueOf(Math.mod(index + 1, 7)))) {
				names.add(DAY_NAMES[index]);
			}
		}
		return String.join(names, ';');
	}

	private static Date firstDay(Session_Schedule__c schedule) {
		Date fromDay = today();
		if (schedule.Start_Date__c != null && schedule.Start_Date__c > fromDay) {
			fromDay = schedule.Start_Date__c;
		}
		if (schedule.Created_Through__c != null && schedule.Created_Through__c >= fromDay) {
			fromDay = schedule.Created_Through__c.addDays(1);
		}
		return fromDay;
	}

	private static Session__c newSession(Session_Schedule__c schedule, Date day) {
		return new Session__c(
			Name = SessionScheduleController.sessionName(schedule.Service__r?.Name, day),
			Service__c = schedule.Service__c,
			Cohort__c = schedule.Cohort__c,
			Session_Schedule__c = schedule.Id,
			Session_Date__c = day,
			Start_Time__c = schedule.Start_Time__c,
			End_Time__c = schedule.End_Time__c,
			Status__c = SessionAttendance.SCHEDULED
		);
	}

	/** 0 for Monday to 6 for Sunday, whatever the user's locale calls the first day. */
	private static Integer weekdayIndex(Date day) {
		return Math.mod(A_MONDAY.daysBetween(day), 7);
	}

	private static Date mondayOf(Date day) {
		return day.addDays(-weekdayIndex(day));
	}
}
