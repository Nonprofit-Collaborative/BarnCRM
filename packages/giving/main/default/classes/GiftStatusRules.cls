/**
 * How a gift's Status may move around Cancelled (R-G16, ADR-0054).
 *
 * Cancelled is a Pending gift that will never be paid. It is not money, so it creates no negative
 * gift and every total, the accounting export and receipts leave it out by reading only Received,
 * Refunded and Written off. Status moves Pending to Cancelled and Cancelled back to Pending, and
 * nothing else moves to or from Cancelled; Pending does not move to Refunded or Written off,
 * which are for money received (R-G3).
 *
 * Run from `GiftTriggerHandler`, the switchable Gift core rules, so a data load with automation
 * paused may set any status. A gift may be created Cancelled; it is then linked to no installment.
 */
public with sharing class GiftStatusRules {
	public static final String STATUS_RECEIVED = 'Received';
	public static final String STATUS_PENDING = 'Pending';
	public static final String STATUS_CANCELLED = 'Cancelled';
	private static final Set<String> REVERSED = new Set<String>{ 'Refunded', 'Written off' };
	private static final String LOG_CONTEXT = 'Gift cancelled';

	/**
	 * Before update: refuses a move the rule does not allow, and unlinks a gift being cancelled
	 * from its installment, so the commitment handler recalculates the installment it left
	 * (R-CM4), as it would after a delete.
	 */
	public static void enforceTransitions(List<Gift__c> gifts, Map<Id, Gift__c> oldGifts) {
		for (Gift__c gift : gifts) {
			Gift__c previous = oldGifts.get(gift.Id);
			if (previous == null) {
				continue;
			}
			String before = statusOf(previous);
			String after = statusOf(gift);
			if (before == after) {
				continue;
			}
			if (after == STATUS_CANCELLED) {
				if (before != STATUS_PENDING) {
					gift.Status__c.addError(Label.Giving_Gift_CancelOnlyPending);
					continue;
				}
				gift.Installment__c = null;
			} else if (before == STATUS_CANCELLED && after != STATUS_PENDING) {
				gift.Status__c.addError(Label.Giving_Gift_CancelledOnlyToPending);
			} else if (before == STATUS_PENDING && REVERSED.contains(after)) {
				gift.Status__c.addError(
					String.format(
						Label.Giving_Gift_ReverseNeedsReceived,
						new List<String>{ STATUS_PENDING }
					)
				);
			}
		}
	}

	/** Before insert: a gift created Cancelled pays no installment, so it holds none (R-G16). */
	public static void unlinkCancelledOnInsert(List<Gift__c> gifts) {
		for (Gift__c gift : gifts) {
			if (statusOf(gift) == STATUS_CANCELLED) {
				gift.Installment__c = null;
			}
		}
	}

	/** After update: every move into or out of Cancelled is written down, with who made it. */
	public static void logCancellations(List<Gift__c> gifts, Map<Id, Gift__c> oldGifts) {
		List<String> entries = new List<String>();
		for (Gift__c gift : gifts) {
			Gift__c previous = oldGifts.get(gift.Id);
			if (previous == null) {
				continue;
			}
			String before = statusOf(previous);
			String after = statusOf(gift);
			if (after == STATUS_CANCELLED && before != STATUS_CANCELLED) {
				entries.add(
					String.format(Label.Giving_Gift_CancelledLogged, new List<String>{ gift.Name })
				);
			} else if (before == STATUS_CANCELLED && after != STATUS_CANCELLED) {
				entries.add(
					String.format(
						Label.Giving_Gift_UncancelledLogged,
						new List<String>{ gift.Name }
					)
				);
			}
		}
		if (!entries.isEmpty()) {
			ErrorLogger.logMessages(entries, LOG_CONTEXT, ErrorLogger.SEVERITY_INFO);
		}
	}

	/** A blank status is the field's default, Received. */
	private static String statusOf(Gift__c gift) {
		return String.isBlank(gift.Status__c) ? STATUS_RECEIVED : gift.Status__c;
	}
}
