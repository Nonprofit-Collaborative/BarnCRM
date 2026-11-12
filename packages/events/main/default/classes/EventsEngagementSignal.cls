/**
 * The Events part of the engagement score (C-64, canonical model R-ES2 and R-ES4): how many
 * events each person attended (attendee status Attended) whose event started on or after the
 * date. Core finds it by name in `EngagementScore.SIGNAL_CLASSES` (ADR-0017), so it is
 * `@NamespaceAccessible` with a public no-argument constructor.
 *
 * `WITH SYSTEM_MODE` (ADR-0021): the score is a fact about the organization, not about the
 * person who scheduled the nightly run. It returns counts only.
 */
@NamespaceAccessible
public without sharing class EventsEngagementSignal implements EngagementSignalExtension {
	@NamespaceAccessible
	public EventsEngagementSignal() {
		return;
	}

	public String key() {
		return 'Events';
	}

	public Map<Id, Decimal> totals(Set<Id> contactIds, Date since) {
		Datetime startsFrom = Datetime.newInstance(since, Time.newInstance(0, 0, 0, 0));
		Map<Id, Decimal> totals = new Map<Id, Decimal>();
		for (AggregateResult row : [
			SELECT Contact__c person, COUNT_DISTINCT(Event_Registration__r.Event__c) total
			FROM Event_Attendee__c
			WHERE
				Contact__c IN :contactIds
				AND Status__c = 'Attended'
				AND Event_Registration__r.Event__r.Start__c >= :startsFrom
			WITH SYSTEM_MODE
			GROUP BY Contact__c
		]) {
			totals.put((Id) row.get('person'), (Integer) row.get('total'));
		}
		return totals;
	}
}
