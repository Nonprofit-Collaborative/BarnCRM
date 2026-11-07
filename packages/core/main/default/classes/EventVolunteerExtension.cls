/**
 * The seam Event Management uses to show and create an event's volunteer jobs and shifts without
 * naming Volunteers, and without Volunteers naming Events (ADR-0177 decision 12; the ADR-0017
 * mechanism). Volunteers implements it (`VolunteersEventExtension`) and stores the event's record
 * identifier as text; with Volunteers absent nothing implements it and Events shows no volunteer
 * panel.
 *
 * Found by `EventVolunteerExtensions` with `NamespaceUtil.resolveType`, the mechanism of
 * `FormAttachmentExtensions` and `HealthCheckExtensions`. Everything runs with the person's own
 * access, so Volunteers' own permission sets decide who may list or create.
 */
@NamespaceAccessible
public interface EventVolunteerExtension {
	/** The volunteer jobs kept for this event, each with its shifts in time order. */
	List<EventVolunteerJob> jobsFor(String eventKey);

	/** Adds a volunteer job for the event and returns its identifier. */
	Id createJob(String eventKey, String name, String description);

	/** Adds a shift to a job this extension listed and returns its identifier. */
	Id createShift(Id jobId, Datetime startTime, Datetime endTime, Integer needed);
}
