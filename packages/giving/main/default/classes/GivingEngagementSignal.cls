/**
 * The Gifts part of the engagement score (C-64, canonical model R-ES2 and R-ES4): each person's
 * Received gifts as Donor Contact since the date, summed. Core finds it by name in
 * `EngagementScore.SIGNAL_CLASSES` (ADR-0017), so it is `@NamespaceAccessible` with a public
 * no-argument constructor.
 *
 * `WITH SYSTEM_MODE` (ADR-0021): the score is a fact about the organization, not about the
 * person who scheduled the nightly run. It returns totals only.
 */
@NamespaceAccessible
public without sharing class GivingEngagementSignal implements EngagementSignalExtension {
	@NamespaceAccessible
	public GivingEngagementSignal() {
		return;
	}

	public String key() {
		return 'Gifts';
	}

	/**
	 * In a multi-currency org the platform answers SUM of a currency field in the corporate
	 * currency, whatever each gift was entered in (ADR-0083), so the totals are already in one
	 * currency, the one the Gifts target is set in; nothing is converted here.
	 */
	public Map<Id, Decimal> totals(Set<Id> contactIds, Date since) {
		Map<Id, Decimal> totals = new Map<Id, Decimal>();
		for (AggregateResult row : [
			SELECT Donor_Contact__c person, SUM(Amount__c) total
			FROM Gift__c
			WHERE
				Donor_Contact__c IN :contactIds
				AND Status__c = 'Received'
				AND Gift_Date__c >= :since
			WITH SYSTEM_MODE
			GROUP BY Donor_Contact__c
		]) {
			totals.put((Id) row.get('person'), (Decimal) row.get('total'));
		}
		return totals;
	}
}
