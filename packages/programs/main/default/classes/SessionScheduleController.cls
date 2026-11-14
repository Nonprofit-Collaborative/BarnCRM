/**
 * What the Schedule Sessions panel on a cohort or a program calls (P-11, canonical model 29ZA6,
 * R-SE4). The panel works out the dates (one per chosen weekday between two dates) in its
 * framework-free module; this class checks again that the service is an active service of the
 * program, that there are at most 200 dates, and creates one Scheduled session per date, for the
 * cohort when called from one. A day that already has a session of the service for the same
 * cohort (none on a program), other than a cancelled one, is skipped and counted. User mode throughout; plain wrappers (plan Section 9.9); anything
 * unexpected is recorded in the Error Log before it is reported (plan Section 7.2).
 *
 * It also serves repeating session schedules (modules-24, canonical model 29ZA7): the panel's
 * Save as Repeating Schedule (R-SS6), and the schedule page's preview, Create Sessions Now
 * (R-SS3) and Remove Future Sessions (R-SS5), which call `SessionScheduleService`.
 */
public with sharing class SessionScheduleController {
	private static final String CONTEXT = 'Schedule sessions panel';
	private static final UserErrors.Screen ERRORS = new UserErrors.Screen(
			CONTEXT,
			'Programs',
			'Programs_Fail_Schedule'
		)
		.showingDml();
	/** The most sessions created in one action. */
	public static final Integer MAX_SESSIONS = 200;
	private static final Integer NAME_LENGTH = 80;

	public class Option {
		@AuraEnabled
		public String label;
		@AuraEnabled
		public String value;
	}

	/** The panel's whole state. */
	public class Schedule {
		@AuraEnabled
		public Id programId;
		@AuraEnabled
		public Id cohortId;
		@AuraEnabled
		public String cohortName;
		@AuraEnabled
		public List<Option> services = new List<Option>();
		@AuraEnabled
		public Date startDate;
		@AuraEnabled
		public Date endDate;
		@AuraEnabled
		public Boolean canSchedule = false;
		@AuraEnabled
		public Integer maxSessions = MAX_SESSIONS;
		/** After scheduling: how many sessions were created. */
		@AuraEnabled
		public Integer created = 0;
		/** After scheduling: how many chosen days were skipped because they had a session. */
		@AuraEnabled
		public Integer skipped = 0;
		/** Whether the user may save the pattern as a repeating schedule (R-SS6). */
		@AuraEnabled
		public Boolean canSaveSchedule = false;
		/** After saving a repeating schedule: its Id. */
		@AuraEnabled
		public Id scheduleId;
	}

	/** A session schedule's state for its page's panel. */
	public class Preview {
		@AuraEnabled
		public Boolean active = false;
		@AuraEnabled
		public Boolean turnedOff = false;
		@AuraEnabled
		public Boolean canCreate = false;
		@AuraEnabled
		public Boolean canRemove = false;
		/** How many sessions the next run creates, through `through`. */
		@AuraEnabled
		public Integer missing = 0;
		@AuraEnabled
		public Date through;
		@AuraEnabled
		public Date createdThrough;
		@AuraEnabled
		public Integer created = 0;
		@AuraEnabled
		public Integer removed = 0;
	}

	@AuraEnabled
	public static Schedule getSchedule(Id recordId) {
		try {
			return scheduleFor(recordId);
		} catch (Exception failure) {
			throw ERRORS.wrap(failure, CONTEXT, recordId);
		}
	}

	/**
	 * The days from `fromDate` to `toDate` that already have a session of the service for this
	 * cohort (on a program, a program-wide session), so the panel can say they will be skipped.
	 */
	@AuraEnabled
	public static List<Date> getTakenDays(Id recordId, Id serviceId, Date fromDate, Date toDate) {
		if (serviceId == null || fromDate == null || toDate == null || toDate < fromDate) {
			return new List<Date>();
		}
		try {
			Schedule schedule = scheduleFor(recordId);
			List<Date> days = new List<Date>(
				CohortSelector.selectSessionDays(serviceId, schedule.cohortId, fromDate, toDate)
			);
			days.sort();
			return days;
		} catch (Exception failure) {
			throw ERRORS.wrap(failure, CONTEXT, recordId);
		}
	}

	/**
	 * Creates one Scheduled session of the service on each date, at the start and end times when
	 * given ("HH:mm", seconds and more ignored), for the cohort when `recordId` is one. An end
	 * not after the start is refused by the session's validation rule (R-SE6).
	 */
	@AuraEnabled
	public static Schedule scheduleSessions(
		Id recordId,
		Id serviceId,
		List<Date> dates,
		String startTime,
		String endTime
	) {
		if (serviceId == null) {
			throw UserErrors.message(
				BarnHelp.text('Programs', 'Programs_Schedule_ServiceRequired')
			);
		}
		Set<Date> unique = new Set<Date>(dates == null ? new List<Date>() : dates);
		unique.remove(null);
		if (unique.isEmpty()) {
			throw UserErrors.message(BarnHelp.text('Programs', 'Programs_Schedule_NoDates'));
		}
		if (unique.size() > MAX_SESSIONS) {
			throw UserErrors.message(
				String.format(
					BarnHelp.text('Programs', 'Programs_Schedule_TooMany'),
					new List<Object>{ MAX_SESSIONS }
				)
			);
		}
		Time starts = parsedTime(startTime);
		Time ends = parsedTime(endTime);
		try {
			Schedule schedule = scheduleFor(recordId);
			Option service = offeredService(schedule, serviceId);
			List<Date> sorted = new List<Date>(unique);
			sorted.sort();
			// Running it twice must not double the sessions: a day that already has one of this
			// service for this cohort is skipped, and the count says so.
			Set<Date> taken = CohortSelector.selectSessionDays(
				serviceId,
				schedule.cohortId,
				sorted[0],
				sorted[sorted.size() - 1]
			);
			List<Session__c> sessions = new List<Session__c>();
			for (Date day : sorted) {
				if (taken.contains(day)) {
					schedule.skipped++;
					continue;
				}
				sessions.add(
					new Session__c(
						Name = sessionName(service.label, day),
						Service__c = serviceId,
						Cohort__c = schedule.cohortId,
						Session_Date__c = day,
						Start_Time__c = starts,
						End_Time__c = ends,
						Status__c = SessionAttendance.SCHEDULED
					)
				);
			}
			if (!sessions.isEmpty()) {
				Database.insert(sessions, true, AccessLevel.USER_MODE);
			}
			schedule.created = sessions.size();
			return schedule;
		} catch (Exception failure) {
			throw ERRORS.wrap(failure, CONTEXT, recordId);
		}
	}

	/**
	 * R-SS6: saves the panel's pattern as an active weekly session schedule, from `fromDate` to
	 * `toDate`, on the chosen weekdays ("0" is Sunday, as the panel numbers them), and creates its
	 * sessions at once. Returns the panel's state with the schedule's Id and how many it created.
	 */
	@AuraEnabled
	public static Schedule saveRepeatingSchedule(
		Id recordId,
		Id serviceId,
		Date fromDate,
		Date toDate,
		List<String> weekdays,
		String startTime,
		String endTime
	) {
		Time starts = parsedTime(startTime);
		Time ends = parsedTime(endTime);
		try {
			Schedule schedule = scheduleFor(recordId);
			Option service = offeredService(schedule, serviceId);
			String name =
				service.label + (schedule.cohortName == null ? '' : ', ' + schedule.cohortName);
			Session_Schedule__c saved = new Session_Schedule__c(
				Name = name.left(NAME_LENGTH),
				Program__c = schedule.programId,
				Service__c = serviceId,
				Cohort__c = schedule.cohortId,
				Weekdays__c = SessionScheduleService.weekdayNames(weekdays),
				Every_N_Weeks__c = 1,
				Start_Date__c = fromDate,
				End_Date__c = toDate,
				Start_Time__c = starts,
				End_Time__c = ends
			);
			Database.insert(saved, true, AccessLevel.USER_MODE);
			schedule.scheduleId = saved.Id;
			schedule.created = SessionScheduleService.run(new Set<Id>{ saved.Id });
			return schedule;
		} catch (Exception failure) {
			throw ERRORS.wrap(failure, CONTEXT, recordId);
		}
	}

	/** The schedule page's panel: how many sessions the next run creates, through which day. */
	@AuraEnabled
	public static Preview getSchedulePreview(Id scheduleId) {
		try {
			return previewOf(scheduleId);
		} catch (Exception failure) {
			throw ERRORS.wrap(failure, CONTEXT, scheduleId);
		}
	}

	/** R-SS3: runs the schedule now, as the nightly run would, and returns the fresh preview. */
	@AuraEnabled
	public static Preview createSessionsNow(Id scheduleId) {
		try {
			if (!previewOf(scheduleId).canCreate) {
				throw UserErrors.message(failed());
			}
			Integer created = SessionScheduleService.run(new Set<Id>{ scheduleId });
			Preview preview = previewOf(scheduleId);
			preview.created = created;
			return preview;
		} catch (Exception failure) {
			throw ERRORS.wrap(failure, CONTEXT, scheduleId);
		}
	}

	/** R-SS5, after the page's confirm: removes and recreates the schedule's future sessions. */
	@AuraEnabled
	public static Preview removeFutureSessions(Id scheduleId) {
		try {
			if (!previewOf(scheduleId).canRemove) {
				throw UserErrors.message(failed());
			}
			Integer removed = SessionScheduleService.removeFutureSessions(scheduleId);
			Preview preview = previewOf(scheduleId);
			preview.removed = removed;
			return preview;
		} catch (Exception failure) {
			throw ERRORS.wrap(failure, CONTEXT, scheduleId);
		}
	}

	// ------------------------------------------------------------------------------ helpers

	private static Option offeredService(Schedule schedule, Id serviceId) {
		for (Option offered : schedule.services) {
			if ((Id) offered.value == serviceId) {
				return offered;
			}
		}
		throw UserErrors.message(BarnHelp.text('Programs', 'Programs_Schedule_ServiceRequired'));
	}

	private static Preview previewOf(Id scheduleId) {
		Session_Schedule__c schedule = scheduleId == null
			? null
			: SessionScheduleSelector.forPreview(scheduleId);
		if (schedule == null) {
			throw UserErrors.message(failed());
		}
		Preview preview = new Preview();
		preview.active = schedule.Active__c == true;
		preview.turnedOff = SessionScheduleService.isTurnedOff();
		preview.createdThrough = schedule.Created_Through__c;
		preview.through = SessionScheduleService.lastDay(schedule);
		preview.canCreate =
			preview.active &&
			!preview.turnedOff &&
			Schema.SObjectType.Session__c.isCreateable();
		preview.canRemove = !preview.turnedOff && Schema.SObjectType.Session__c.isDeletable();
		List<Date> missing = SessionScheduleService.missingDays(
				new List<Session_Schedule__c>{ schedule }
			)
			.get(schedule.Id);
		preview.missing = missing == null ? 0 : missing.size();
		return preview;
	}

	private static Schedule scheduleFor(Id recordId) {
		Schedule schedule = new Schedule();
		if (recordId != null && recordId.getSObjectType() == Cohort__c.SObjectType) {
			Cohort__c cohort = CohortSelector.selectCohort(recordId);
			if (cohort == null) {
				throw UserErrors.message(BarnHelp.text('Programs', 'Programs_Cohort_NotFound'));
			}
			schedule.cohortId = cohort.Id;
			schedule.cohortName = cohort.Name;
			schedule.programId = cohort.Program__c;
			schedule.startDate = cohort.Start_Date__c;
			schedule.endDate = cohort.End_Date__c;
		} else if (recordId != null && recordId.getSObjectType() == Program__c.SObjectType) {
			if (CohortSelector.selectProgram(recordId) == null) {
				throw UserErrors.message(failed());
			}
			schedule.programId = recordId;
		} else {
			throw UserErrors.message(failed());
		}
		for (Service__c service : CohortSelector.selectActiveServices(schedule.programId)) {
			Option option = new Option();
			option.label = service.Name;
			option.value = service.Id;
			schedule.services.add(option);
		}
		schedule.canSchedule = Schema.SObjectType.Session__c.isCreateable();
		schedule.canSaveSchedule =
			schedule.canSchedule && Schema.SObjectType.Session_Schedule__c.isCreateable();
		return schedule;
	}

	/** "Service name date", cut to fit the name field; schedules name sessions the same way. */
	public static String sessionName(String serviceName, Date day) {
		String suffix = ' ' + day.format();
		String base = serviceName == null ? '' : serviceName;
		return base.left(NAME_LENGTH - suffix.length()) + suffix;
	}

	/** "13:30", "13:30:00.000" or empty; anything else is refused. */
	@TestVisible
	private static Time parsedTime(String value) {
		if (String.isBlank(value)) {
			return null;
		}
		List<String> parts = value.trim().split(':');
		if (
			parts.size() < 2 ||
			!parts[0].isNumeric() ||
			!parts[1].left(2).isNumeric() ||
			Integer.valueOf(parts[0]) > 23 ||
			Integer.valueOf(parts[1].left(2)) > 59
		) {
			throw UserErrors.message(BarnHelp.text('Programs', 'Programs_Schedule_BadTime'));
		}
		return Time.newInstance(Integer.valueOf(parts[0]), Integer.valueOf(parts[1].left(2)), 0, 0);
	}

	/** What staff are told when scheduling failed (modules-1). */
	private static String failed() {
		return BarnHelp.text('Programs', 'Programs_Fail_Schedule');
	}
}
