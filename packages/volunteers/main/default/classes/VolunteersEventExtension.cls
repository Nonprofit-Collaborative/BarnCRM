/**
 * Keeps an event's volunteer jobs and shifts for Event Management (EV-08, ADR-0177 decision 12).
 * Core finds this class by name (`EventVolunteerExtensions.EXTENSION_CLASSES`) and calls it
 * through `EventVolunteerExtension`, so Events never names a Volunteers object and Volunteers
 * never names an Events one: the event is only its record identifier kept as text on the job
 * (`Volunteer_Job__c.Event_Key__c`). Everything runs in user mode, so Volunteers' own permission
 * sets decide who may list or add.
 *
 * `@NamespaceAccessible`, public, with a public no-argument constructor, because Core resolves
 * it by name under ADR-0017.
 */
@NamespaceAccessible
public with sharing class VolunteersEventExtension implements EventVolunteerExtension {
	/** Jobs and shifts listed per event stop here. */
	@TestVisible
	private static final Integer MAX_JOBS = 200;

	@NamespaceAccessible
	public VolunteersEventExtension() {
	}

	/** The event's jobs by name, each with its shifts in time order. */
	public List<EventVolunteerJob> jobsFor(String eventKey) {
		List<EventVolunteerJob> jobs = new List<EventVolunteerJob>();
		if (String.isBlank(eventKey)) {
			return jobs;
		}
		for (Volunteer_Job__c record : [
			SELECT
				Id,
				Name,
				Active__c,
				(
					SELECT
						Id,
						Start_Time__c,
						End_Time__c,
						Volunteers_Needed__c,
						Slots_Filled__c,
						Status__c
					FROM Shifts__r
					ORDER BY Start_Time__c ASC
					LIMIT 100
				)
			FROM Volunteer_Job__c
			WHERE Event_Key__c = :eventKey
			WITH USER_MODE
			ORDER BY Name
			LIMIT :MAX_JOBS
		]) {
			EventVolunteerJob job = new EventVolunteerJob();
			job.id = record.Id;
			job.name = record.Name;
			job.active = record.Active__c;
			for (Volunteer_Shift__c shift : record.Shifts__r) {
				EventVolunteerShift row = new EventVolunteerShift();
				row.id = shift.Id;
				row.startTime = shift.Start_Time__c;
				row.endTime = shift.End_Time__c;
				row.needed = shift.Volunteers_Needed__c == null
					? null
					: shift.Volunteers_Needed__c.intValue();
				row.filled = shift.Slots_Filled__c == null ? 0 : shift.Slots_Filled__c.intValue();
				row.status = shift.Status__c;
				job.shifts.add(row);
			}
			jobs.add(job);
		}
		return jobs;
	}

	/** Adds an active volunteer job that remembers the event. */
	public Id createJob(String eventKey, String name, String description) {
		Volunteer_Job__c job = new Volunteer_Job__c(
			Name = name,
			Description__c = description,
			Event_Key__c = eventKey,
			Active__c = true
		);
		insert as user job;
		return job.Id;
	}

	/** Adds an open shift to one of the event's jobs. */
	public Id createShift(Id jobId, Datetime startTime, Datetime endTime, Integer needed) {
		Volunteer_Shift__c shift = new Volunteer_Shift__c(
			Volunteer_Job__c = jobId,
			Start_Time__c = startTime,
			End_Time__c = endTime,
			Volunteers_Needed__c = needed == null ? 1 : needed,
			Status__c = 'Open'
		);
		insert as user shift;
		return shift.Id;
	}
}
