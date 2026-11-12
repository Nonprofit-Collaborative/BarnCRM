/**
 * Payments' one status flow (canonical model 29PAY1, R-PAY1 to R-PAY3; ADR-NEXT
 * `NEXT-payments-module.md`, decisions 3, 6 and 8): starting a checkout, applying what a
 * processor reported, cancelling abandoned checkouts and telling each payment's listener.
 */
public with sharing class PaymentService {
	public static final String PENDING = 'Pending';
	public static final String PAID = 'Paid';
	public static final String FAILED = 'Failed';
	public static final String REFUNDED = 'Refunded';
	public static final String CANCELLED = 'Cancelled';
	public static final String STRIPE = 'Stripe';
	public static final String PAYPAL = 'PayPal';
	public static final String LIVE = 'Live';
	public static final String TEST = 'Test';
	/** A Pending payment with no processor payment this many days old is abandoned (R-PAY3). */
	@TestVisible
	private static final Integer ABANDONED_DAYS = 2;
	private static final String CONTEXT = 'PaymentService';
	/** Currencies with no minor unit, at both processors. */
	private static final Set<String> NO_DECIMALS = new Set<String>{
		'BIF',
		'CLP',
		'DJF',
		'GNF',
		'HUF',
		'JPY',
		'KMF',
		'KRW',
		'MGA',
		'PYG',
		'RWF',
		'TWD',
		'UGX',
		'VND',
		'VUV',
		'XAF',
		'XOF',
		'XPF'
	};

	/** What a processor said about one payment; a null field means no news about it. */
	public class Change {
		public String reference;
		public String checkoutId;
		public String processorPaymentId;
		public String status;
		/** The processor's total refunded so far. */
		public Decimal amountRefunded;
		public Datetime paidAt;
		public String detail;
	}

	/** One event read by its processor: what to change, or why nothing, ready to be applied. */
	public class Outcome {
		public Payment_Event__c event;
		public Change change;
		/** Ignored, Rejected or Failed with this message when there is no change. */
		public String status;
		public String message;

		public Outcome(Payment_Event__c event) {
			this.event = event;
		}

		public Outcome nothing(String status, String message) {
			this.status = status;
			this.message = message;
			return this;
		}
	}

	// ---- Settings and keys ----

	public static Payments_Settings__c settings() {
		Payments_Settings__c s = Payments_Settings__c.getOrgDefaults();
		return s == null ? new Payments_Settings__c() : s;
	}

	public static Payment_Keys__c keys() {
		Payment_Keys__c k = Payment_Keys__c.getOrgDefaults();
		return k == null ? new Payment_Keys__c() : k;
	}

	public static String mode() {
		return settings().Mode__c == LIVE ? LIVE : TEST;
	}

	public static String defaultProcessor() {
		return settings().Processor__c == PAYPAL ? PAYPAL : STRIPE;
	}

	/** True when every key the processor needs is entered. */
	public static Boolean isReady(String processor) {
		Payment_Keys__c k = keys();
		return processor == PAYPAL
			? String.isNotBlank(k.PayPal_Client_Id__c) &&
			  String.isNotBlank(k.PayPal_Client_Secret__c) &&
			  String.isNotBlank(k.PayPal_Webhook_Id__c)
			: String.isNotBlank(k.Stripe_Secret_Key__c) &&
			  String.isNotBlank(k.Stripe_Webhook_Secret__c);
	}

	// ---- Starting a checkout ----

	/**
	 * Asks the processor for a hosted checkout page, then writes the Pending payment (system mode:
	 * the API is Apex only and a public page's guest must be able to start one; ADR decision 8).
	 * The callout comes first, so the caller makes it before its own writes.
	 */
	public static Payment__c startCheckout(Map<String, Object> args) {
		Object given = args.get('amount');
		Decimal amount = given instanceof Decimal ||
			given instanceof Integer ||
			given instanceof Long
			? Decimal.valueOf(String.valueOf(given))
			: null;
		String description = text(args, 'description');
		String successUrl = text(args, 'successUrl');
		String cancelUrl = text(args, 'cancelUrl');
		String processor = String.isBlank(text(args, 'processor'))
			? defaultProcessor()
			: text(args, 'processor');
		String currencyCode = (String.isBlank(text(args, 'currency'))
				? (settings().Currency__c ?? 'USD')
				: text(args, 'currency'))
			.toUpperCase();
		if (amount == null || amount <= 0) {
			throw problem(BarnHelp.text('Payments', 'Payments_Error_BadAmount'));
		}
		if (String.isBlank(description)) {
			throw problem(BarnHelp.text('Payments', 'Payments_Error_NoDescription'));
		}
		if (!isHttps(successUrl) || !isHttps(cancelUrl)) {
			throw problem(BarnHelp.text('Payments', 'Payments_Error_BadUrl'));
		}
		if (processor != STRIPE && processor != PAYPAL) {
			throw problem(BarnHelp.text('Payments', 'Payments_Error_BadProcessor'));
		}
		if (!Pattern.matches('[A-Z]{3}', currencyCode)) {
			throw problem(BarnHelp.text('Payments', 'Payments_Error_BadCurrency'));
		}
		if (!isReady(processor)) {
			throw problem(
				BarnHelp.text('Payments', 'Payments_Error_NotReady', new List<Object>{ processor })
			);
		}
		Payment__c payment = new Payment__c(
			Status__c = PENDING,
			Processor__c = processor,
			Mode__c = mode(),
			Amount__c = amount.setScale(NO_DECIMALS.contains(currencyCode) ? 0 : 2),
			Amount_Refunded__c = 0,
			Currency_Code__c = currencyCode,
			Description__c = description.abbreviate(255),
			Payer_Name__c = text(args, 'payerName')?.abbreviate(255),
			Payer_Email__c = text(args, 'payerEmail'),
			Person__c = idOf(args.get('personId'), Contact.SObjectType),
			Source_Record_Id__c = text(args, 'sourceRecordId')?.left(18),
			Listener__c = text(args, 'listener')?.left(255),
			Detail__c = text(args, 'detail')?.abbreviate(255),
			Reference__c = newReference()
		);
		try {
			if (processor == PAYPAL) {
				PaymentPayPal.startCheckout(payment, successUrl, cancelUrl);
			} else {
				PaymentStripe.startCheckout(payment, successUrl, cancelUrl);
			}
		} catch (CalloutException e) {
			ErrorLogger.log(e, CONTEXT + '.startCheckout');
			throw problem(
				BarnHelp.text('Payments', 'Payments_Error_Processor', new List<Object>{ processor })
			);
		}
		Database.insert(payment, AccessLevel.SYSTEM_MODE);
		return payment;
	}

	/** The amount in the processor's smallest unit (cents), and back. */
	public static Long minorUnits(Decimal amount, String currencyCode) {
		return (amount * (NO_DECIMALS.contains(currencyCode) ? 1 : 100)).setScale(0).longValue();
	}

	public static Decimal fromMinorUnits(Object units, String currencyCode) {
		if (!(units instanceof Long) && !(units instanceof Integer)) {
			return null;
		}
		Decimal value = Decimal.valueOf(String.valueOf(units));
		return NO_DECIMALS.contains(currencyCode == null ? '' : currencyCode.toUpperCase())
			? value
			: value.divide(100, 2);
	}

	public static Boolean noDecimals(String currencyCode) {
		return NO_DECIMALS.contains(currencyCode);
	}

	// ---- Applying processor events ----

	/**
	 * Writes the outcomes of one run: payment status moves (R-PAY1, R-PAY2), each event's result,
	 * then each changed payment's listener. User mode, as the administrator who scheduled it.
	 */
	public static void apply(List<Outcome> outcomes) {
		Set<String> refs = new Set<String>();
		Set<String> checkoutIds = new Set<String>();
		Set<String> paymentIds = new Set<String>();
		Set<String> keys = new Set<String>();
		for (Outcome o : outcomes) {
			if (o.change != null) {
				addIfSet(refs, o.change.reference);
				addIfSet(checkoutIds, o.change.checkoutId);
				addIfSet(paymentIds, o.change.processorPaymentId);
			}
			if (o.event.Event_Key__c != null && o.event.Id != null) {
				keys.add(o.event.Event_Key__c);
			}
		}
		Set<String> usedKeys = usedKeys(keys, outcomes);
		List<Payment__c> found = [
			SELECT
				Id,
				Status__c,
				Amount__c,
				Amount_Refunded__c,
				Reference__c,
				Checkout_Id__c,
				Processor_Payment_Id__c,
				Paid_At__c,
				Detail__c,
				Listener__c,
				Source_Record_Id__c,
				Person__c,
				Currency_Code__c,
				Processor__c,
				Mode__c
			FROM Payment__c
			WHERE
				Reference__c IN :refs
				OR Checkout_Id__c IN :checkoutIds
				OR Processor_Payment_Id__c IN :paymentIds
			WITH USER_MODE
		];
		Map<Id, Payment__c> touched = new Map<Id, Payment__c>();
		Map<Id, String> previous = new Map<Id, String>();
		Map<Id, Decimal> previousRefunded = new Map<Id, Decimal>();
		Set<String> seen = new Set<String>();
		for (Outcome o : outcomes) {
			if (
				o.event.Event_Key__c != null &&
				(!seen.add(o.event.Event_Key__c) || usedKeys.contains(o.event.Event_Key__c))
			) {
				// A resend: its key stays with the first, so this event is saved without it.
				o.event.Event_Key__c = null;
				o.nothing('Ignored', BarnHelp.text('Payments', 'Payments_Event_Duplicate'));
			}
			if (o.status != null || o.change == null) {
				if (o.status == null) {
					o.nothing('Ignored', BarnHelp.text('Payments', 'Payments_Event_NotUsed'));
				}
				continue;
			}
			Payment__c payment = match(found, o.change);
			if (payment == null) {
				o.nothing('Ignored', BarnHelp.text('Payments', 'Payments_Event_NoPayment'));
				continue;
			}
			if (!previous.containsKey(payment.Id)) {
				previous.put(payment.Id, payment.Status__c);
				previousRefunded.put(payment.Id, payment.Amount_Refunded__c);
			}
			o.event.Payment__c = payment.Id;
			String refusal = applyTo(payment, o.change);
			o.status = refusal == null ? 'Applied' : 'Ignored';
			o.message = refusal;
			if (refusal == null) {
				touched.put(payment.Id, payment);
			}
		}
		update as user touched.values();
		List<Payment_Event__c> events = new List<Payment_Event__c>();
		for (Outcome o : outcomes) {
			o.event.Status__c = o.status;
			o.event.Message__c = o.message?.abbreviate(255);
			events.add(o.event);
		}
		List<Database.SaveResult> saved = Database.update(events, false, AccessLevel.USER_MODE);
		for (Integer i = 0; i < saved.size(); i++) {
			if (!saved[i].isSuccess()) {
				ErrorLogger.logMessage(
					saved[i].getErrors()[0].getMessage(),
					CONTEXT + '.apply',
					ErrorLogger.SEVERITY_WARNING,
					events[i].Id
				);
			}
		}
		List<Payment__c> changed = new List<Payment__c>();
		for (Payment__c payment : touched.values()) {
			if (
				payment.Status__c != previous.get(payment.Id) ||
				payment.Amount_Refunded__c != previousRefunded.get(payment.Id)
			) {
				changed.add(payment);
			}
		}
		notifyAll(changed, previous);
	}

	/** Keys already taken by an earlier event (PayPal keys are set only once verified). */
	private static Set<String> usedKeys(Set<String> keys, List<Outcome> outcomes) {
		Set<Id> mine = new Set<Id>();
		for (Outcome o : outcomes) {
			mine.add(o.event.Id);
		}
		Set<String> used = new Set<String>();
		for (Payment_Event__c e : [
			SELECT Event_Key__c
			FROM Payment_Event__c
			WHERE Event_Key__c IN :keys AND Id NOT IN :mine
			WITH USER_MODE
		]) {
			used.add(e.Event_Key__c);
		}
		return used;
	}

	private static Payment__c match(List<Payment__c> found, Change change) {
		for (Payment__c p : found) {
			if (
				(change.reference != null &&
				p.Reference__c == change.reference) ||
				(change.checkoutId != null &&
				p.Checkout_Id__c == change.checkoutId) ||
				(change.processorPaymentId != null &&
				p.Processor_Payment_Id__c == change.processorPaymentId)
			) {
				return p;
			}
		}
		return null;
	}

	/** Applies one change to the payment in memory; returns why it was refused, or null. */
	@TestVisible
	private static String applyTo(Payment__c payment, Change change) {
		String target = change.status;
		if (change.amountRefunded != null) {
			Decimal total = Math.min(change.amountRefunded, payment.Amount__c);
			if (payment.Amount_Refunded__c == null || total > payment.Amount_Refunded__c) {
				payment.Amount_Refunded__c = total;
			}
			if (payment.Amount_Refunded__c >= payment.Amount__c) {
				target = REFUNDED;
			}
		}
		if (target != null && target != payment.Status__c) {
			if (!canMove(payment.Status__c, target)) {
				return BarnHelp.text(
					'Payments',
					'Payments_Event_NoMove',
					new List<Object>{ payment.Status__c, target }
				);
			}
			payment.Status__c = target;
		}
		if (String.isBlank(payment.Processor_Payment_Id__c)) {
			payment.Processor_Payment_Id__c = change.processorPaymentId;
		}
		if (String.isBlank(payment.Checkout_Id__c)) {
			payment.Checkout_Id__c = change.checkoutId;
		}
		if (payment.Status__c == PAID && payment.Paid_At__c == null) {
			payment.Paid_At__c = change.paidAt == null ? Datetime.now() : change.paidAt;
		}
		if (change.detail != null) {
			payment.Detail__c = change.detail.abbreviate(255);
		}
		return null;
	}

	/** R-PAY1: Pending to any; Failed or Cancelled to Paid; Paid to Refunded. */
	@TestVisible
	private static Boolean canMove(String fromStatus, String toStatus) {
		return fromStatus == PENDING ||
			(toStatus == PAID && (fromStatus == FAILED || fromStatus == CANCELLED)) ||
			(fromStatus == PAID &&
			toStatus == REFUNDED);
	}

	/** R-PAY3: up to `count` abandoned checkouts are Cancelled and their listeners told; returns how many. */
	public static Integer cancelAbandoned(Integer count) {
		Datetime before = Datetime.now().addDays(-ABANDONED_DAYS);
		List<Payment__c> stale = [
			SELECT
				Id,
				Status__c,
				Amount__c,
				Amount_Refunded__c,
				Listener__c,
				Source_Record_Id__c,
				Person__c,
				Currency_Code__c,
				Processor__c,
				Mode__c,
				Paid_At__c,
				Detail__c
			FROM Payment__c
			WHERE Status__c = :PENDING AND Processor_Payment_Id__c = NULL AND CreatedDate < :before
			WITH USER_MODE
			ORDER BY CreatedDate ASC
			LIMIT :count
		];
		Map<Id, String> previous = new Map<Id, String>();
		String expired = BarnHelp.text('Payments', 'Payments_Detail_Expired');
		for (Payment__c p : stale) {
			previous.put(p.Id, p.Status__c);
			p.Status__c = CANCELLED;
			p.Detail__c = expired;
		}
		update as user stale;
		notifyAll(stale, previous);
		return stale.size();
	}

	// ---- Listeners ----

	/**
	 * Tells each listener once, with every changed payment of its own (`paymentsChanged`,
	 * `{ payments: [payment map, ...] }`; a listener that handled them answers true). A listener
	 * that answers anything else, or fails, is told one payment at a time (`paymentChanged`), each
	 * failure rolled back on its own.
	 */
	private static void notifyAll(List<Payment__c> payments, Map<Id, String> previous) {
		Map<String, List<Payment__c>> byListener = new Map<String, List<Payment__c>>();
		for (Payment__c payment : payments) {
			if (String.isNotBlank(payment.Listener__c)) {
				if (!byListener.containsKey(payment.Listener__c)) {
					byListener.put(payment.Listener__c, new List<Payment__c>());
				}
				byListener.get(payment.Listener__c).add(payment);
			}
		}
		for (String name : byListener.keySet()) {
			List<Payment__c> mine = byListener.get(name);
			Callable listener;
			try {
				listener = (Callable) NamespaceUtil.build(
					name,
					Callable.class,
					CONTEXT + '.notify'
				);
			} catch (Exception e) {
				ErrorLogger.log(e, CONTEXT + '.notify', mine[0].Id);
			}
			if (listener == null) {
				continue;
			}
			List<Map<String, Object>> told = new List<Map<String, Object>>();
			for (Payment__c payment : mine) {
				Map<String, Object> one = toMap(payment);
				one.put('previousStatus', previous.get(payment.Id));
				told.add(one);
			}
			System.Savepoint before = Database.setSavepoint();
			try {
				if (
					listener.call(
						'paymentsChanged',
						new Map<String, Object>{ 'payments' => told }
					) == true
				) {
					continue;
				}
			} catch (Exception e) {
				Database.rollback(before);
				ErrorLogger.log(e, CONTEXT + '.notify', mine[0].Id);
			}
			for (Integer i = 0; i < mine.size(); i++) {
				before = Database.setSavepoint();
				try {
					listener.call('paymentChanged', told[i]);
				} catch (Exception e) {
					Database.rollback(before);
					ErrorLogger.log(e, CONTEXT + '.notify', mine[i].Id);
				}
			}
		}
	}

	/** The payment as the seam passes it (ADR decision 8). */
	public static Map<String, Object> toMap(Payment__c p) {
		return new Map<String, Object>{
			'paymentId' => p.Id,
			'sourceRecordId' => p.Source_Record_Id__c,
			'personId' => p.Person__c,
			'status' => p.Status__c,
			'amount' => p.Amount__c,
			'amountRefunded' => p.Amount_Refunded__c,
			'currency' => p.Currency_Code__c,
			'processor' => p.Processor__c,
			'mode' => p.Mode__c,
			'paidAt' => p.Paid_At__c,
			'detail' => p.Detail__c
		};
	}

	// ---- Small helpers ----

	public static PaymentsApi.PaymentException problem(String message) {
		return new PaymentsApi.PaymentException(message);
	}

	private static String text(Map<String, Object> args, String key) {
		Object value = args.get(key);
		return value == null ? null : String.valueOf(value).trim();
	}

	private static Boolean isHttps(String url) {
		return url != null && url.startsWithIgnoreCase('https://') && url.length() <= 1000;
	}

	private static Id idOf(Object value, Schema.SObjectType expected) {
		try {
			Id given = Id.valueOf(String.valueOf(value));
			return given.getSObjectType() == expected ? given : null;
		} catch (Exception notAnId) {
			return null;
		}
	}

	private static void addIfSet(Set<String> values, String value) {
		if (String.isNotBlank(value)) {
			values.add(value);
		}
	}

	/** A random identifier, 32 hex characters, sent to the processor and matched on its events. */
	@TestVisible
	private static String newReference() {
		return EncodingUtil.convertToHex(Crypto.generateAesKey(128));
	}
}
