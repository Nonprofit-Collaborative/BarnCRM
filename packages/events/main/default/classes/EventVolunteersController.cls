/**
 * The Volunteers section of the event page's Details tab (EV-08, ADR-0177 decision 12): the
 * event's volunteer jobs and shifts. They live in Volunteers; this class reaches them only
 * through Core's `EventVolunteerExtensions`, so it never names a Volunteers object and the
 * section is simply absent (`available` false) when Volunteers is not installed. Thin by design
 * (plan Section 9.9): the browser module `eventVolunteersModel` works out defaults, checks and
 * totals. Everything runs with the person's own access, so Volunteers' permission sets decide.
 */
public with sharing class EventVolunteersController {
	private static final String CONTEXT = 'EventVolunteersController';

	/** Everything the section draws. */
	public class Volunteers {
		/** Whether a module keeps volunteer jobs; when false the section shows nothing. */
		@AuraEnabled
		public Boolean available = false;
		@AuraEnabled
		public Datetime eventStart;
		@AuraEnabled
		public Datetime eventEnd;
		@AuraEnabled
		public List<JobRow> jobs = new List<JobRow>();
	}

	/** One job. */
	public class JobRow {
		@AuraEnabled
		public String id;
		@AuraEnabled
		public String name;
		@AuraEnabled
		public Boolean active;
		@AuraEnabled
		public String href;
		@AuraEnabled
		public List<ShiftRow> shifts = new List<ShiftRow>();
	}

	/** One shift. */
	public class ShiftRow {
		@AuraEnabled
		public String id;
		@AuraEnabled
		public Datetime startTime;
		@AuraEnabled
		public Datetime endTime;
		@AuraEnabled
		public Integer needed;
		@AuraEnabled
		public Integer filled;
		@AuraEnabled
		public String status;
	}

	/**
	 * The event's volunteer jobs and shifts, or an unavailable result when no module keeps them.
	 *
	 * @param eventId the event
	 * @return the section's jobs and the event's dates
	 */
	@AuraEnabled
	public static Volunteers getVolunteers(Id eventId) {
		try {
			Volunteers result = new Volunteers();
			result.available = EventVolunteerExtensions.isAvailable();
			if (!result.available) {
				return result;
			}
			for (Event__c record : [
				SELECT Start__c, End__c
				FROM Event__c
				WHERE Id = :eventId
				WITH USER_MODE
			]) {
				result.eventStart = record.Start__c;
				result.eventEnd = record.End__c;
			}
			for (
				EventVolunteerJob job : EventVolunteerExtensions.jobsFor(String.valueOf(eventId))
			) {
				JobRow row = new JobRow();
				row.id = job.id;
				row.name = job.name;
				row.active = job.active;
				row.href = '/lightning/r/' + job.id + '/view';
				for (EventVolunteerShift shift : job.shifts) {
					ShiftRow shiftRow = new ShiftRow();
					shiftRow.id = shift.id;
					shiftRow.startTime = shift.startTime;
					shiftRow.endTime = shift.endTime;
					shiftRow.needed = shift.needed;
					shiftRow.filled = shift.filled;
					shiftRow.status = shift.status;
					row.shifts.add(shiftRow);
				}
				result.jobs.add(row);
			}
			return result;
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.getVolunteers', eventId);
			throw UserErrors.wrapShowingDml(
				e,
				BarnHelp.text('Events', 'Events_Volunteers_LoadFailed')
			);
		}
	}

	/**
	 * Adds a volunteer job for the event.
	 *
	 * @param eventId the event
	 * @param name the job's name
	 * @param description what the volunteers will do, or empty
	 * @return the new job's identifier
	 */
	@AuraEnabled
	public static String addJob(Id eventId, String name, String description) {
		try {
			if (String.isBlank(name)) {
				throw new System.IllegalArgumentException(
					BarnHelp.text('Events', 'Events_Volunteers_NameRequired')
				);
			}
			return EventVolunteerExtensions.createJob(
				String.valueOf(eventId),
				name.trim().left(80),
				String.isBlank(description) ? null : description
			);
		} catch (Exception e) {
			fail(e, '.addJob', eventId);
			return null;
		}
	}

	/**
	 * Adds a shift to one of the event's volunteer jobs.
	 *
	 * @param eventId the event the job belongs to
	 * @param jobId the job
	 * @param startTime when the shift starts
	 * @param endTime when it ends, after the start
	 * @param needed how many volunteers are wanted, at least one
	 * @return the new shift's identifier
	 */
	@AuraEnabled
	public static String addShift(
		Id eventId,
		Id jobId,
		Datetime startTime,
		Datetime endTime,
		Integer needed
	) {
		try {
			if (
				startTime == null ||
				endTime == null ||
				endTime <= startTime ||
				needed == null ||
				needed < 1
			) {
				throw new System.IllegalArgumentException(
					BarnHelp.text('Events', 'Events_Volunteers_BadShift')
				);
			}
			return EventVolunteerExtensions.createShift(jobId, startTime, endTime, needed);
		} catch (Exception e) {
			fail(e, '.addShift', eventId);
			return null;
		}
	}

	private static void fail(Exception e, String method, Id eventId) {
		ErrorLogger.log(e, CONTEXT + method, eventId);
		throw e instanceof System.IllegalArgumentException
			? UserErrors.message(e.getMessage())
			: UserErrors.wrapShowingDml(e, BarnHelp.text('Events', 'Events_Volunteers_SaveFailed'));
	}
}
