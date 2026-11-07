/** One volunteer job kept for an event, as an `EventVolunteerExtension` reports it. */
@NamespaceAccessible
public inherited sharing class EventVolunteerJob {
	@NamespaceAccessible
	public Id id;
	@NamespaceAccessible
	public String name;
	@NamespaceAccessible
	public Boolean active = true;
	@NamespaceAccessible
	public List<EventVolunteerShift> shifts = new List<EventVolunteerShift>();

	@NamespaceAccessible
	public EventVolunteerJob() {
	}
}
