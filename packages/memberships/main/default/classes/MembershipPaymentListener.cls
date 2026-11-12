/**
 * Told by BarnCRM Payments when a membership payment changes (ADR-NEXT `NEXT-payments-module.md`,
 * decision 8; canonical model R-MEM7). Paid: a Pending term becomes Current from the payment
 * date, any other term is renewed with the payment on the new term. Refunded: the term the
 * payment made is Cancelled. A notice already applied (the payment id is on a term) changes
 * nothing, so being told twice is safe. Payments builds this class by name and runs it as its
 * processing administrator; it acts for the organization, in system mode, and makes no callout.
 */
@NamespaceAccessible
public with sharing class MembershipPaymentListener implements Callable {
	@NamespaceAccessible
	public MembershipPaymentListener() {
		return;
	}

	public Object call(String action, Map<String, Object> payment) {
		if (action != 'paymentChanged' || payment == null) {
			return null;
		}
		String paymentId = String.valueOf(payment.get('paymentId'));
		String status = (String) payment.get('status');
		List<Membership_Term__c> paidBy = [
			SELECT Id, Status__c
			FROM Membership_Term__c
			WHERE Payment_Id__c = :paymentId
			WITH SYSTEM_MODE
		];
		if (status == 'Refunded') {
			for (Membership_Term__c term : paidBy) {
				term.Status__c = MembershipService.CANCELLED;
			}
			update as system paidBy;
		} else if (status == 'Paid' && paidBy.isEmpty()) {
			paid(payment, paymentId);
		}
		return null;
	}

	private static void paid(Map<String, Object> payment, String paymentId) {
		Object source = payment.get('sourceRecordId');
		Date paidOn = payment.get('paidAt') instanceof Datetime
			? ((Datetime) payment.get('paidAt')).date()
			: MembershipService.today();
		Decimal amount = (Decimal) payment.get('amount');
		List<Membership_Term__c> found = [
			SELECT Id, Status__c, Level__c, Member_Since__c
			FROM Membership_Term__c
			WHERE Id = :String.valueOf(source)
			WITH SYSTEM_MODE
		];
		if (found.isEmpty()) {
			return;
		}
		Membership_Term__c term = found[0];
		if (term.Status__c == MembershipService.PENDING) {
			Membership_Level__c level = MembershipService.levels(new Set<Id>{ term.Level__c })
				.get(term.Level__c);
			update as system new Membership_Term__c(
				Id = term.Id,
				Status__c = MembershipService.CURRENT,
				Start_Date__c = paidOn,
				End_Date__c = MembershipService.endOf(paidOn, level),
				Member_Since__c = term.Member_Since__c != null ? term.Member_Since__c : paidOn,
				Source__c = 'Online Payment',
				Amount_Paid__c = amount,
				Payment_Id__c = paymentId
			);
			return;
		}
		if (
			term.Status__c == MembershipService.RENEWED ||
			term.Status__c == MembershipService.CANCELLED
		) {
			// Renewed meanwhile (by a gift or staff): the payment stands in Payments, nothing to add.
			return;
		}
		MembershipService.Renewal renewal = new MembershipService.Renewal(term.Id);
		renewal.onDate = paidOn;
		renewal.source = 'Online Payment';
		renewal.amountPaid = amount;
		renewal.paymentId = paymentId;
		MembershipService.renew(new List<MembershipService.Renewal>{ renewal }, true);
	}
}
