/**
 * The gifts online donation pages write (G-34; ADR-0211 `0211-online-donation-pages.md`,
 * decision 5; canonical model R-AP5). Two paths reach the same gift, found by Payment Reference
 * (the payment's identifier), and whichever comes second settles it:
 * - `record`, when Forms processes a donation page's submission as staff: writes the gift for
 *   the person Forms matched, with the status Payments reports then;
 * - `paymentsChanged` (or `paymentChanged` for one), the Payments listener (this class, built by
 *   name): moves an existing gift
 *   to Received, Refunded or Cancelled; with no gift yet it does nothing, except for a donor
 *   portal payment on a commitment (PAY-03), whose Paid report writes the Received gift.
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
	/** Payments' subscription news as Recurring Gift Event types (R-RH5). */
	private static final Map<String, String> EVENT_TYPES = new Map<String, String>{
		'chargeSucceeded' => 'Charge Succeeded',
		'chargeFailed' => 'Charge Failed',
		'cardUpdated' => 'Card Updated',
		'cancelled' => 'Cancelled'
	};

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
		if (!giftsFor(new Set<String>{ reference }).isEmpty()) {
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

	/**
	 * The Payments listener (ADR-0201 `0201-payments-module.md`, decision 8): `paymentsChanged` with every
	 * changed payment of a run at once (answers true), or `paymentChanged` with one; and
	 * `subscriptionsChanged` with a run's subscription news (R-RH5).
	 */
	public Object call(String action, Map<String, Object> args) {
		List<Map<String, Object>> told = new List<Map<String, Object>>();
		String key = action == 'subscriptionsChanged' ? 'changes' : 'payments';
		if (
			(action == 'paymentsChanged' || action == 'subscriptionsChanged') &&
			args?.get(key) instanceof List<Object>
		) {
			for (Object one : (List<Object>) args.get(key)) {
				if (one instanceof Map<String, Object>) {
					told.add((Map<String, Object>) one);
				}
			}
			if (key == 'changes') {
				subscriptionsChanged(told);
			} else {
				paymentsChanged(told);
			}
			return true;
		}
		if (action == 'paymentChanged' && args != null) {
			told.add(args);
			paymentsChanged(told);
		}
		return null;
	}

	/**
	 * Moves each payment's gifts to its status. A gift the status rules let move only through a
	 * step (R-G16, R-G3: Cancelled to Received through Pending, Pending to Refunded through
	 * Received) is moved one step per update. A Paid payment with no gift may be a portal payment.
	 */
	private static void paymentsChanged(List<Map<String, Object>> payments) {
		Map<String, Map<String, Object>> byReference = new Map<String, Map<String, Object>>();
		for (Map<String, Object> payment : payments) {
			if (
				payment.get('paymentId') != null &&
				giftStatus(String.valueOf(payment.get('status'))) != null
			) {
				byReference.put(String.valueOf(payment.get('paymentId')), payment);
			}
		}
		if (byReference.isEmpty()) {
			return;
		}
		Map<String, List<Gift__c>> gifts = giftsFor(byReference.keySet());
		List<Map<String, Object>> portal = new List<Map<String, Object>>();
		List<Gift__c> toPending = new List<Gift__c>();
		List<Gift__c> toReceived = new List<Gift__c>();
		List<Gift__c> changed = new List<Gift__c>();
		for (String reference : byReference.keySet()) {
			Map<String, Object> payment = byReference.get(reference);
			String status = giftStatus(String.valueOf(payment.get('status')));
			if (!gifts.containsKey(reference)) {
				if (status == 'Received') {
					portal.add(payment);
				}
				continue;
			}
			for (Gift__c gift : gifts.get(reference)) {
				if (gift.Status__c == status) {
					continue;
				}
				Boolean wasCancelled = gift.Status__c == CANCELLED;
				if (wasCancelled) {
					toPending.add(new Gift__c(Id = gift.Id, Status__c = 'Pending'));
				}
				if (status == REFUNDED && (wasCancelled || gift.Status__c == 'Pending')) {
					Gift__c received = new Gift__c(Id = gift.Id, Status__c = 'Received');
					settleDate(received, payment);
					toReceived.add(received);
				}
				gift.Status__c = status;
				settleDate(gift, payment);
				changed.add(gift);
			}
		}
		update as user toPending;
		update as user toReceived;
		update as user changed;
		recordPortalPayments(portal);
	}

	/**
	 * Donor portal payments (PAY-03; ADR-0210 `0210-donor-portal-payments.md`, decision 4): the
	 * first Paid report for a payment whose source is a commitment writes its Received gift, on
	 * the scheduled payment the checkout charged (its id is the payment's detail), else Giving's
	 * commitment rule links it to the earliest unpaid payment.
	 */
	private static void recordPortalPayments(List<Map<String, Object>> payments) {
		Set<Id> sources = new Set<Id>();
		Set<Id> installments = new Set<Id>();
		for (Map<String, Object> payment : payments) {
			Id source = idOf(payment.get('sourceRecordId'));
			Id installment = idOf(payment.get('detail'));
			if (source != null && source.getSObjectType() == Commitment__c.SObjectType) {
				sources.add(source);
			}
			if (installment != null && installment.getSObjectType() == Installment__c.SObjectType) {
				installments.add(installment);
			}
		}
		if (sources.isEmpty()) {
			return;
		}
		Map<Id, Commitment__c> commitments = new Map<Id, Commitment__c>(
			[
				SELECT Id, Donor_Contact__c, Appeal__c
				FROM Commitment__c
				WHERE Id IN :sources
				WITH USER_MODE
			]
		);
		Map<Id, Installment__c> scheduled = new Map<Id, Installment__c>(
			[
				SELECT Id, Commitment__c
				FROM Installment__c
				WHERE Id IN :installments AND Commitment__c IN :sources
				WITH USER_MODE
			]
		);
		List<Gift__c> gifts = new List<Gift__c>();
		for (Map<String, Object> payment : payments) {
			Id source = idOf(payment.get('sourceRecordId'));
			Commitment__c commitment = commitments.get(source);
			if (commitment == null) {
				continue;
			}
			String reference = String.valueOf(payment.get('paymentId'));
			Id person = idOf(payment.get('personId'));
			if (commitment.Donor_Contact__c != person) {
				ErrorLogger.logMessage(
					BarnHelp.text('Giving', 'Giving_Donate_NoGift', new List<Object>{ reference }),
					CONTEXT + '.recordPortalPayment',
					ErrorLogger.SEVERITY_WARNING
				);
				continue;
			}
			Installment__c charged = scheduled.get(idOf(payment.get('detail')));
			Gift__c gift = new Gift__c(
				Donor_Contact__c = person,
				Commitment__c = source,
				Installment__c = charged?.Commitment__c == source ? charged.Id : null,
				Appeal__c = commitment.Appeal__c,
				Amount__c = (Decimal) payment.get('amount'),
				Gift_Date__c = Date.today(),
				Type__c = String.valueOf(payment.get('processor')) == 'Stripe' ? 'Card' : 'Other',
				Payment_Reference__c = reference,
				Status__c = 'Received'
			);
			settleDate(gift, payment);
			gifts.add(gift);
		}
		insert as user gifts;
	}

	/**
	 * Payments subscriptions (PAY-04, R-RH5; ADR-NEXT `NEXT-payments-subscriptions.md`, decision
	 * 4): fills each commitment's processor ids when blank and records each change once as a
	 * Recurring Gift Event (upsert by its event key), which G-27's rules then apply.
	 */
	private static void subscriptionsChanged(List<Map<String, Object>> changes) {
		Set<Id> sources = new Set<Id>();
		for (Map<String, Object> change : changes) {
			sources.add(idOf(change.get('sourceRecordId')));
		}
		Map<Id, Commitment__c> commitments = new Map<Id, Commitment__c>(
			[
				SELECT Id, Processor_Subscription_Id__c, Processor_Customer_Id__c
				FROM Commitment__c
				WHERE Id IN :sources
				WITH USER_MODE
			]
		);
		Map<Id, Commitment__c> filled = new Map<Id, Commitment__c>();
		Map<String, Recurring_Gift_Event__c> events = new Map<String, Recurring_Gift_Event__c>();
		for (Map<String, Object> change : changes) {
			Commitment__c commitment = commitments.get(idOf(change.get('sourceRecordId')));
			String type = EVENT_TYPES.get(String.valueOf(change.get('event')));
			String eventKey = (String) change.get('eventKey');
			if (commitment == null) {
				continue;
			}
			String subscription = (String) change.get('subscriptionId');
			String customer = (String) change.get('customerId');
			if (
				(commitment.Processor_Subscription_Id__c == null && subscription != null) ||
				(commitment.Processor_Customer_Id__c == null &&
				customer != null)
			) {
				commitment.Processor_Subscription_Id__c = commitment.Processor_Subscription_Id__c ??
					subscription;
				commitment.Processor_Customer_Id__c = commitment.Processor_Customer_Id__c ??
					customer;
				filled.put(commitment.Id, commitment);
			}
			if (type != null && eventKey != null) {
				events.put(
					eventKey.left(100),
					new Recurring_Gift_Event__c(
						Commitment__c = commitment.Id,
						Event_Type__c = type,
						Event_Date__c = (Date) change.get('eventDate'),
						Subscription_Id__c = subscription?.left(100),
						Card_Expires__c = (Date) change.get('cardExpires'),
						Amount__c = (Decimal) change.get('amount'),
						Detail__c = ((String) change.get('detail'))?.abbreviate(255),
						External_Id__c = eventKey.left(100)
					)
				);
			}
		}
		update as user filled.values();
		upsert as user events.values() Recurring_Gift_Event__c.External_Id__c;
	}

	/**
	 * Where a payer returns after an emailed checkout: the first active Salesforce Site's address,
	 * else the org's own (the Memberships Pay Dues pattern).
	 */
	public static String returnUrl() {
		for (Site found : [
			SELECT Id
			FROM Site
			WHERE Status = 'Active' AND SiteType = 'Visualforce'
			WITH SYSTEM_MODE
			ORDER BY MasterLabel
			LIMIT 1
		]) {
			Set<String> ids = new Set<String>{
				String.valueOf(found.Id),
				String.valueOf(found.Id).left(15)
			};
			for (SiteDetail detail : [
				SELECT SecureUrl
				FROM SiteDetail
				WHERE DurableId IN :ids
				WITH SYSTEM_MODE
			]) {
				if (String.isNotBlank(detail.SecureUrl)) {
					return detail.SecureUrl;
				}
			}
		}
		return Url.getOrgDomainUrl().toExternalForm();
	}

	private static Id idOf(Object value) {
		try {
			return value == null ? null : Id.valueOf(String.valueOf(value));
		} catch (StringException notAnId) {
			return null;
		}
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

	/** The online gifts of each payment reference given. */
	private static Map<String, List<Gift__c>> giftsFor(Set<String> references) {
		Map<String, List<Gift__c>> found = new Map<String, List<Gift__c>>();
		for (Gift__c gift : [
			SELECT Id, Status__c, Gift_Date__c, Payment_Reference__c
			FROM Gift__c
			WHERE
				Payment_Reference__c IN :references
				AND (Appeal__c != NULL
				OR Commitment__c != NULL)
			WITH USER_MODE
			LIMIT 2000
		]) {
			if (!found.containsKey(gift.Payment_Reference__c)) {
				found.put(gift.Payment_Reference__c, new List<Gift__c>());
			}
			found.get(gift.Payment_Reference__c).add(gift);
		}
		return found;
	}
}
