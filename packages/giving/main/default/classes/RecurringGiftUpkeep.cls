/**
 * Matches recurring gift events to their commitments and applies them (G-27, canonical model
 * Section 25V, rules R-RH1 and R-RH2).
 *
 * Without sharing (Upkeep, ADR-0021): an event is usually written by the integration user a
 * Zapier recipe runs as, who cannot see the donor's private commitment, and the match has to see
 * every commitment so it neither misses the right one nor takes an ambiguous email for a match.
 * It reads commitments and writes only their four health fields.
 */
public without sharing class RecurringGiftUpkeep {
	public static final String MATCHED = 'Matched';
	public static final String UNMATCHED = 'Unmatched';
	private static final Set<String> OPEN = new Set<String>{ 'Active', 'Paused' };
	private static final Integer MAX_FAILED = 999;

	/** Before save (R-RH1): fills Commitment from Subscription Id, else Donor Email; sets Match Status. */
	public static void match(List<Recurring_Gift_Event__c> events) {
		Set<String> subscriptions = new Set<String>();
		Set<String> emails = new Set<String>();
		for (Recurring_Gift_Event__c event : events) {
			if (event.Commitment__c == null) {
				addKey(subscriptions, event.Subscription_Id__c);
				addKey(emails, event.Donor_Email__c);
			}
		}
		Map<String, Id> bySubscription = new Map<String, Id>();
		if (!subscriptions.isEmpty()) {
			for (Commitment__c row : [
				SELECT Id, Processor_Subscription_Id__c
				FROM Commitment__c
				WHERE Processor_Subscription_Id__c IN :subscriptions
				WITH SYSTEM_MODE
			]) {
				bySubscription.put(row.Processor_Subscription_Id__c.toLowerCase(), row.Id);
			}
		}
		Map<String, Id> byEmail = new Map<String, Id>();
		Set<String> ambiguous = new Set<String>();
		if (!emails.isEmpty()) {
			for (Commitment__c row : [
				SELECT Id, Donor_Contact__r.Email
				FROM Commitment__c
				WHERE
					Type__c = 'Recurring'
					AND Status__c IN :OPEN
					AND Donor_Contact__r.Email IN :emails
				WITH SYSTEM_MODE
				LIMIT 2000
			]) {
				String key = row.Donor_Contact__r.Email.toLowerCase();
				if (byEmail.containsKey(key)) {
					ambiguous.add(key);
				}
				byEmail.put(key, row.Id);
			}
		}
		for (Recurring_Gift_Event__c event : events) {
			if (event.Commitment__c == null) {
				event.Commitment__c = bySubscription.get(lower(event.Subscription_Id__c));
				String email = lower(event.Donor_Email__c);
				if (event.Commitment__c == null && !ambiguous.contains(email)) {
					event.Commitment__c = byEmail.get(email);
				}
			}
			event.Match_Status__c = event.Commitment__c == null ? UNMATCHED : MATCHED;
		}
	}

	/**
	 * After save (R-RH2): each event that has just gained its commitment changes that commitment's
	 * health, oldest first. An event edited later without a new commitment changes nothing.
	 */
	public static void apply(List<Recurring_Gift_Event__c> events, Map<Id, SObject> before) {
		List<Recurring_Gift_Event__c> fresh = new List<Recurring_Gift_Event__c>();
		Set<Id> commitmentIds = new Set<Id>();
		for (Recurring_Gift_Event__c event : events) {
			Recurring_Gift_Event__c old = before == null
				? null
				: (Recurring_Gift_Event__c) before.get(event.Id);
			if (
				event.Commitment__c != null &&
				(old == null ||
				old.Commitment__c != event.Commitment__c)
			) {
				fresh.add(event);
				commitmentIds.add(event.Commitment__c);
			}
		}
		if (fresh.isEmpty()) {
			return;
		}
		fresh.sort(new OldestFirst());
		Map<Id, Commitment__c> commitments = new Map<Id, Commitment__c>(
			[
				SELECT
					Id,
					Failed_Charges__c,
					Last_Failed_Charge__c,
					Card_Expires__c,
					Processor_Cancelled__c
				FROM Commitment__c
				WHERE Id IN :commitmentIds
				WITH SYSTEM_MODE
			]
		);
		for (Recurring_Gift_Event__c event : fresh) {
			Commitment__c target = commitments.get(event.Commitment__c);
			if (target != null) {
				applyOne(target, event);
			}
		}
		update as system commitments.values();
	}

	@TestVisible
	private static void applyOne(Commitment__c target, Recurring_Gift_Event__c event) {
		Date day = dayOf(event);
		switch on event.Event_Type__c {
			when 'Charge Failed' {
				Decimal failed = target.Failed_Charges__c == null ? 0 : target.Failed_Charges__c;
				target.Failed_Charges__c = Math.min(MAX_FAILED, failed + 1);
				if (target.Last_Failed_Charge__c == null || target.Last_Failed_Charge__c < day) {
					target.Last_Failed_Charge__c = day;
				}
			}
			when 'Charge Succeeded' {
				target.Failed_Charges__c = 0;
				target.Processor_Cancelled__c = null;
			}
			when 'Card Expiring' {
				target.Card_Expires__c = event.Card_Expires__c != null
					? event.Card_Expires__c
					: day.toStartOfMonth().addMonths(1).addDays(-1);
			}
			when 'Card Updated' {
				target.Card_Expires__c = event.Card_Expires__c;
			}
			when 'Cancelled' {
				target.Processor_Cancelled__c = day;
			}
		}
	}

	private static Date dayOf(Recurring_Gift_Event__c event) {
		return event.Event_Date__c == null ? Date.today() : event.Event_Date__c;
	}

	private static void addKey(Set<String> keys, String value) {
		if (String.isNotBlank(value)) {
			keys.add(value.trim().toLowerCase());
		}
	}

	private static String lower(String value) {
		return String.isBlank(value) ? null : value.trim().toLowerCase();
	}

	private class OldestFirst implements Comparator<Recurring_Gift_Event__c> {
		public Integer compare(Recurring_Gift_Event__c left, Recurring_Gift_Event__c right) {
			Date a = dayOf(left);
			Date b = dayOf(right);
			return a == b ? 0 : (a < b ? -1 : 1);
		}
	}
}
