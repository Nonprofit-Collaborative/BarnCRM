/**
 * The Hours part of the engagement score (C-64, canonical model R-ES2 and R-ES4): each person's
 * Approved volunteer hours worked since the date, summed. Core finds it by name in
 * `EngagementScore.SIGNAL_CLASSES` (ADR-0017), so it is `@NamespaceAccessible` with a public
 * no-argument constructor.
 *
 * `WITH SYSTEM_MODE` (ADR-0021): the score is a fact about the organization, not about the
 * person who scheduled the nightly run. It returns totals only.
 */
@NamespaceAccessible
public without sharing class VolunteersEngagementSignal implements EngagementSignalExtension {
	@NamespaceAccessible
	public VolunteersEngagementSignal() {
		return;
	}

	public String key() {
		return 'Hours';
	}

	public Map<Id, Decimal> totals(Set<Id> contactIds, Date since) {
		Map<Id, Decimal> totals = new Map<Id, Decimal>();
		for (AggregateResult row : [
			SELECT Contact__c person, SUM(Hours__c) total
			FROM Volunteer_Hours__c
			WHERE Contact__c IN :contactIds AND Status__c = 'Approved' AND Date_Worked__c >= :since
			WITH SYSTEM_MODE
			GROUP BY Contact__c
		]) {
			totals.put((Id) row.get('person'), (Decimal) row.get('total'));
		}
		return totals;
	}
}
