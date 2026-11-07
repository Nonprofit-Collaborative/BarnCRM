/** One shift of an event's volunteer job, as an `EventVolunteerExtension` reports it. */
@NamespaceAccessible
public inherited sharing class EventVolunteerShift {
	@NamespaceAccessible
	public Id id;
	@NamespaceAccessible
	public Datetime startTime;
	@NamespaceAccessible
	public Datetime endTime;
	@NamespaceAccessible
	public Integer needed;
	@NamespaceAccessible
	public Integer filled;
	@NamespaceAccessible
	public String status;

	@NamespaceAccessible
	public EventVolunteerShift() {
	}
}
