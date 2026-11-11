/**
 * The gifts online donation pages write (G-34; ADR-NEXT `NEXT-online-donation-pages.md`,
 * decision 5; canonical model R-AP5). Two paths reach the same gift, found by Payment Reference
 * (the payment's identifier), and whichever comes second settles it:
 * - `record`, when Forms processes a donation page's submission as staff: writes the gift for
 *   the person Forms matched, with the status Payments reports then;
 * - `paymentChanged`, the Payments listener (this class, built by name): moves an existing gift
 *   to Received, Refunded or Cancelled; with no gift yet it does nothing.
 * Both are safe to run twice. User mode throughout: the processing staff user, or the Payments
 * processing administrator.
 *
 * Giving does not depend on Payments: the seam is `PaymentsApi`, built by name (ADR-0017).
 */
@NamespaceAccessible
public with sharing class GivingDonations implements Callable {
	public static final String LISTENER = 'GivingDonations';
	private static final String REFUNDED = 'Refunded';
	private static final String CANCELLED = 'Cancelled';
	private static final String CONTEXT = 'GivingDonations';

	/** Stands in for BarnCRM Payments in tests. */
	@TestVisible
	private static Callable paymentsForTest;

	@NamespaceAccessible
	public GivingDonations() {
		// Built by name by BarnCRM Payments, so it needs a public constructor.
	}

	/** The Payments seam; raises when Payments is not installed. */
	public static Callable payments() {
		Callable found = paymentsForTest != null
			? paymentsForTest
			: (Callable) NamespaceUtil.build('PaymentsApi', Callable.class, CONTEXT);
		if (found == null) {
			throw new CalloutException(BarnHelp.text('Giving', 'Giving_Donate_NoPayments'));
		}
		return found;
	}

	/** Whether Payments is installed and its default processor's keys are entered. */
	public static Boolean paymentsReady() {
		try {
			return payments().call('isReady', new Map<String, Object>()) == true;
		} catch (Exception notReady) {
			return false;
		}
	}

	/** Writes a donation page's gift, once (decision 5). */
	public static void record(FormSubmissionReceipt receipt) {
		Object paymentId = receipt?.answers?.get('_payment');
		if (paymentId == null || receipt.contextRecordId == null) {
			return;
		}
		String reference = String.valueOf(paymentId);
		if (giftsFor(reference).size() > 0) {
			return;
		}
		Map<String, Object> payment = (Map<String, Object>) payments()
			.call('getPayment', new Map<String, Object>{ 'paymentId' => reference });
		if (payment == null || (receipt.personId == null && receipt.organizationId == null)) {
			ErrorLogger.logMessage(
				BarnHelp.text('Giving', 'Giving_Donate_NoGift', new List<Object>{ reference }),
				CONTEXT + '.record',
				ErrorLogger.SEVERITY_WARNING
			);
			return;
		}
		Gift__c gift = new Gift__c(
			Appeal__c = receipt.contextRecordId,
			Amount__c = (Decimal) payment.get('amount'),
			Gift_Date__c = Date.today(),
			Type__c = String.valueOf(payment.get('processor')) == 'Stripe' ? 'Card' : 'Other',
			Payment_Reference__c = reference,
			Status__c = giftStatus(String.valueOf(payment.get('status'))) ?? 'Pending'
		);
		if (receipt.personId != null) {
			gift.Donor_Contact__c = receipt.personId;
		} else {
			gift.Donor_Account__c = receipt.organizationId;
		}
		settleDate(gift, payment);
		insert as user gift;
	}

	/** The Payments listener (`NEXT-payments-module.md`, decision 8). */
	public Object call(String action, Map<String, Object> args) {
		if (action != 'paymentChanged' || args == null || args.get('paymentId') == null) {
			return null;
		}
		String status = giftStatus(String.valueOf(args.get('status')));
		if (status == null) {
			return null;
		}
		List<Gift__c> changed = new List<Gift__c>();
		for (Gift__c gift : giftsFor(String.valueOf(args.get('paymentId')))) {
			if (gift.Status__c != status) {
				gift.Status__c = status;
				settleDate(gift, args);
				changed.add(gift);
			}
		}
		update as user changed;
		return null;
	}

	/** Paid is Received, Refunded and Cancelled are themselves; Pending and Failed change nothing. */
	private static String giftStatus(String paymentStatus) {
		switch on paymentStatus {
			when 'Paid' {
				return 'Received';
			}
			when 'Refunded' {
				return REFUNDED;
			}
			when 'Cancelled' {
				return CANCELLED;
			}
			when else {
				return null;
			}
		}
	}

	private static void settleDate(Gift__c gift, Map<String, Object> payment) {
		if (gift.Status__c == 'Received' && payment.get('paidAt') instanceof Datetime) {
			gift.Gift_Date__c = ((Datetime) payment.get('paidAt')).date();
		}
	}

	private static List<Gift__c> giftsFor(String reference) {
		return [
			SELECT Id, Status__c, Gift_Date__c
			FROM Gift__c
			WHERE Payment_Reference__c = :reference AND Appeal__c != NULL
			WITH USER_MODE
			LIMIT 10
		];
	}
}
