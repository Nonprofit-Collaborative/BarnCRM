/**
 * Payments' one status flow (canonical model 29PAY1, R-PAY1 to R-PAY3; ADR-0201
 * `0201-payments-module.md`, decisions 3, 6 and 8): starting a checkout, applying what a
 * processor reported, cancelling abandoned checkouts and telling each payment's listener.
 * Subscriptions, renewals and Update Card: R-PAY6, ADR-0218 `0218-payments-subscriptions.md`.
 */
public with sharing class PaymentService {
	/** Subscription news told to listeners (`subscriptionsChanged`, event). */
	public static final String CHARGE_SUCCEEDED = 'chargeSucceeded';
	public static final String CHARGE_FAILED = 'chargeFailed';
	public static final String CARD_UPDATED = 'cardUpdated';
	public static final String SUBSCRIPTION_CANCELLED = 'cancelled';
	private static final Set<String> INTERVALS = new Set<String>{ 'week', 'month', 'year' };
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
		/** Subscriptions (R-PAY6): the news, if any, and what the processor said with it. */
		public String subscriptionId;
		public String customerId;
		public String subscriptionEvent;
		/** A renewal's charged amount. */
		public Decimal amount;
		public Date cardExpires;
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

	// Settings are read from the settings store by DeveloperName; what the module records about
	// this org (connections, the PayPal webhook and product ids, the cap time, the token's hash)
	// is run state (ADR-0238 settings as custom metadata, decisions 6 and 11).
	private static final String STATE_PREFIX = 'Payments';
	public static final String STRIPE_CONNECTED = 'Stripe_Connected__c';
	public static final String PAYPAL_CONNECTED = 'PayPal_Connected__c';
	public static final String PAYPAL_WEBHOOK_ID = 'PayPal_Webhook_Id__c';
	public static final String PAYPAL_PRODUCT_ID = 'PayPal_Product_Id__c';
	private static final String CAP_HIT_AT = 'Webhook_Cap_Hit_At__c';
	private static final String TOKEN_HASH = 'Webhook_Token_Hash';
	/** The legacy field that held the token itself, read only to keep an upgraded org's addresses. */
	private static final String LEGACY_TOKEN = 'Webhook_Token__c';

	/** The run-state key of one of the module's values. */
	public static String stateKey(String name) {
		return SettingsState.moduleKey(STATE_PREFIX, name);
	}

	/** One recorded value of this org, such as `PAYPAL_WEBHOOK_ID`; null when none. */
	public static String stateText(String name) {
		String value = SettingsState.text(stateKey(name));
		return String.isBlank(value) ? null : value;
	}

	public static Boolean stateFlag(String name) {
		return SettingsState.flag(stateKey(name));
	}

	/** Records values of this org by name (`STRIPE_CONNECTED`...), synchronously, in one write. */
	public static void putState(Map<String, Object> valuesByName) {
		Map<String, Object> byKey = new Map<String, Object>();
		for (String name : valuesByName.keySet()) {
			byKey.put(stateKey(name), valuesByName.get(name));
		}
		SettingsState.put(byKey);
	}

	public static String mode() {
		return ModuleSettings.text('Payments_Mode') == LIVE ? LIVE : TEST;
	}

	public static String defaultProcessor() {
		return ModuleSettings.text('Payments_Processor') == PAYPAL ? PAYPAL : STRIPE;
	}

	/** The default currency, upper case; USD when none is set. */
	public static String currencyCode() {
		return (ModuleSettings.text('Payments_Currency') ?? 'USD').toUpperCase();
	}

	public static Boolean recurringOn() {
		return ModuleSettings.flag('Payments_Recurring');
	}

	/**
	 * True when the processor is connected: Check Connection on Payments Setup reached it through
	 * its Named Credential (R-PK1), and for PayPal the webhook id is entered. No secret is read.
	 */
	public static Boolean isReady(String processor) {
		return processor == PAYPAL
			? stateFlag(PAYPAL_CONNECTED) && stateText(PAYPAL_WEBHOOK_ID) != null
			: stateFlag(STRIPE_CONNECTED);
	}

	// ---- The receiver's address token (pre-batch review M1) ----

	/**
	 * Makes a new token, keeps only its SHA-256 hash, and returns the token: the one time it is
	 * known, for Payments Setup to show once. The addresses given before stop working.
	 */
	public static String newWebhookToken() {
		String token = EncodingUtil.convertToHex(Crypto.generateAesKey(256));
		putState(new Map<String, Object>{ TOKEN_HASH => hashOf(token) });
		return token;
	}

	/** True when a token is in use (its hash is kept, or an upgraded org's token is still read). */
	public static Boolean hasWebhookToken() {
		return savedHash() != null;
	}

	/** True when the post's token hashes to the kept hash; every character is compared, so timing tells nothing. */
	public static Boolean tokenMatches(String given) {
		String saved = savedHash();
		if (saved == null || String.isBlank(given)) {
			return false;
		}
		String hash = hashOf(given.trim());
		Integer wrong = Math.abs(hash.length() - saved.length());
		for (Integer i = 0; i < saved.length(); i++) {
			if (i >= hash.length() || hash.charAt(i) != saved.charAt(i)) {
				wrong++;
			}
		}
		return wrong == 0;
	}

	/**
	 * Keeps the hash of an upgraded org's token, from the legacy field, when no hash is kept yet,
	 * so the addresses already given keep working after carry-over. Run at install; safe to rerun.
	 */
	public static void keepLegacyTokenHash() {
		if (stateText(TOKEN_HASH) != null) {
			return;
		}
		String legacy = legacyToken();
		if (legacy != null) {
			putState(new Map<String, Object>{ TOKEN_HASH => hashOf(legacy) });
		}
	}

	private static String savedHash() {
		String kept = stateText(TOKEN_HASH);
		if (kept != null) {
			return kept;
		}
		String legacy = legacyToken();
		return legacy == null ? null : hashOf(legacy);
	}

	/**
	 * Set by a test: stands in for the legacy token of an upgraded org, since the packages no
	 * longer ship `Payments_Settings__c` (canonical model R-STV5). Blank reads as none.
	 */
	@TestVisible
	private static String legacyTokenForTest;

	private static String legacyToken() {
		Object legacy = legacyTokenForTest != null
			? legacyTokenForTest
			: ModuleSettings.legacyValue('Payments_Settings__c', LEGACY_TOKEN);
		return legacy == null || String.isBlank(String.valueOf(legacy)) ? null : String.valueOf(legacy).trim();
	}

	@TestVisible
	private static String hashOf(String token) {
		return EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(token)));
	}

	/** When the receiver last refused a post at its hourly cap, for Health Check; null when never. */
	public static Datetime capHitAt() {
		return SettingsState.moment(stateKey(CAP_HIT_AT));
	}

	/** Records a refusal at the hourly cap; true for the first one in an hour (the one to log). */
	public static Boolean noteCapHit() {
		Datetime now = Datetime.now();
		Datetime last = capHitAt();
		if (last != null && last > now.addHours(-1)) {
			return false;
		}
		putState(new Map<String, Object>{ CAP_HIT_AT => now });
		return true;
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
		String processor = String.isBlank(text(args, 'processor')) ? defaultProcessor() : text(args, 'processor');
		String currencyCode = (String.isBlank(text(args, 'currency'))
				? PaymentService.currencyCode()
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
			throw problem(BarnHelp.text('Payments', 'Payments_Error_NotReady', new List<Object>{ processor }));
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
		// R-PAY6: an interval makes a subscription only while Automatic Recurring Payments is on.
		String interval = text(args, 'interval')?.toLowerCase();
		Object count = args.get('intervalCount');
		Integer every = count instanceof Integer ? Math.max(1, Math.min(12, (Integer) count)) : 1;
		if (!recurringOn() || !INTERVALS.contains(interval)) {
			interval = null;
		}
		try {
			if (processor == PAYPAL) {
				PaymentPayPal.startCheckout(payment, successUrl, cancelUrl, interval, every);
			} else {
				PaymentStripe.startCheckout(payment, successUrl, cancelUrl, interval, every);
			}
		} catch (CalloutException e) {
			ErrorLogger.log(e, CONTEXT + '.startCheckout');
			throw problem(BarnHelp.text('Payments', 'Payments_Error_Processor', new List<Object>{ processor }));
		}
		Database.insert(payment, AccessLevel.SYSTEM_MODE);
		return payment;
	}

	/**
	 * The processor's own page for a subscription's new card (ADR-0218 payments subscriptions,
	 * decision 5): Stripe (`sub_...`) needs the customer; any other id is PayPal's.
	 */
	public static String updateCard(Map<String, Object> args) {
		String subscription = text(args, 'subscriptionId');
		String customer = text(args, 'customerId');
		String back = text(args, 'returnUrl');
		String processor = subscription?.startsWith('sub_') == true ? STRIPE : PAYPAL;
		if (String.isBlank(subscription) || (processor == STRIPE && String.isBlank(customer))) {
			throw problem(BarnHelp.text('Payments', 'Payments_Error_NoSubscription'));
		}
		if (!isHttps(back)) {
			throw problem(BarnHelp.text('Payments', 'Payments_Error_BadUrl'));
		}
		if (!isReady(processor)) {
			throw problem(BarnHelp.text('Payments', 'Payments_Error_NotReady', new List<Object>{ processor }));
		}
		if (processor == PAYPAL) {
			return mode() == LIVE ? PaymentPayPal.AUTOPAY : PaymentPayPal.AUTOPAY_TEST;
		}
		try {
			return PaymentStripe.updateCardUrl(customer, subscription, back);
		} catch (CalloutException e) {
			ErrorLogger.log(e, CONTEXT + '.updateCard');
			throw problem(BarnHelp.text('Payments', 'Payments_Error_Processor', new List<Object>{ processor }));
		}
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
		Set<String> subscriptions = new Set<String>();
		Set<String> keys = new Set<String>();
		for (Outcome o : outcomes) {
			if (o.change != null) {
				addIfSet(refs, o.change.reference);
				addIfSet(checkoutIds, o.change.checkoutId);
				addIfSet(paymentIds, o.change.processorPaymentId);
				addIfSet(subscriptions, o.change.subscriptionId);
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
				Mode__c,
				Subscription_Id__c,
				Description__c,
				Payer_Name__c,
				Payer_Email__c
			FROM Payment__c
			WHERE
				Reference__c IN :refs
				OR Checkout_Id__c IN :checkoutIds
				OR Processor_Payment_Id__c IN :paymentIds
				OR Subscription_Id__c IN :subscriptions
			WITH USER_MODE
			ORDER BY CreatedDate ASC, Id ASC
		];
		Map<Id, Payment__c> touched = new Map<Id, Payment__c>();
		Map<Id, String> previous = new Map<Id, String>();
		Map<Id, Decimal> previousRefunded = new Map<Id, Decimal>();
		Set<String> seen = new Set<String>();
		List<Payment__c> renewals = new List<Payment__c>();
		// Charges first recorded in this run: a resent charge is not news again.
		Set<String> newCharges = new Set<String>();
		for (Outcome o : outcomes) {
			if (
				o.event.Event_Key__c != null &&
				(!seen.add(o.event.Event_Key__c) || usedKeys.contains(o.event.Event_Key__c))
			) {
				// A resend: its key stays with the first, so this event is saved without it.
				o.event.Event_Key__c = null;
				o.nothing('Ignored', BarnHelp.text('Payments', 'Payments_Event_Duplicate'));
			}
			if (o.status == null && o.change == null) {
				o.nothing('Ignored', BarnHelp.text('Payments', 'Payments_Event_NotUsed'));
			}
			Payment__c first = o.status == null ? match(found, o.change) : null;
			if (
				first == null ||
				o.change.status != PAID ||
				o.change.subscriptionId == null ||
				o.change.processorPaymentId == null
			) {
				continue;
			}
			if (String.isBlank(first.Processor_Payment_Id__c)) {
				// The subscription's first charge: its first payment takes it (applyTo agrees).
				first.Processor_Payment_Id__c = o.change.processorPaymentId;
				newCharges.add(o.change.processorPaymentId);
			} else if (first.Processor_Payment_Id__c != o.change.processorPaymentId) {
				// R-PAY6: a later charge on a subscription whose first payment is settled.
				Payment__c renewal = renewalOf(first, o.change);
				renewals.add(renewal);
				found.add(renewal);
				newCharges.add(o.change.processorPaymentId);
			}
		}
		// System mode: the processing administrator edits payments but creates none, and a
		// renewal comes only from a verified processor event (ADR-0218 payments subscriptions, 2).
		Database.insert(renewals, AccessLevel.SYSTEM_MODE);
		Map<String, List<Map<String, Object>>> news = new Map<String, List<Map<String, Object>>>();
		for (Outcome o : outcomes) {
			if (o.status != null) {
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
			// Subscription news with no status (a failed charge, a card, a cancellation) changes
			// no payment.
			Boolean newsOnly = o.change.status == null && o.change.subscriptionEvent != null;
			String refusal = newsOnly ? null : applyTo(payment, o.change);
			o.status = refusal == null ? 'Applied' : 'Ignored';
			o.message = refusal;
			if (refusal == null) {
				if (!newsOnly) {
					touched.put(payment.Id, payment);
				}
				if (
					o.change.subscriptionEvent != null &&
					payment.Listener__c != null &&
					(newsOnly || newCharges.remove(o.change.processorPaymentId))
				) {
					if (!news.containsKey(payment.Listener__c)) {
						news.put(payment.Listener__c, new List<Map<String, Object>>());
					}
					news.get(payment.Listener__c).add(newsOf(o, payment));
				}
			}
		}
		update as user touched.values();
		List<Payment_Event__c> events = new List<Payment_Event__c>();
		List<Id> eventIds = new List<Id>();
		for (Outcome o : outcomes) {
			o.event.Status__c = o.status;
			o.event.Message__c = o.message?.abbreviate(255);
			events.add(o.event);
			eventIds.add(o.event.Id);
		}
		// Events that cannot be saved are logged together, in one statement.
		ErrorLogger.logFailures(
			Database.update(events, false, AccessLevel.USER_MODE),
			eventIds,
			CONTEXT + '.apply',
			ErrorLogger.SEVERITY_WARNING
		);
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
		tellSubscriptions(news);
	}

	/** A later charge on a subscription, copied from its first payment, never its detail. */
	private static Payment__c renewalOf(Payment__c first, Change change) {
		return new Payment__c(
			Status__c = PENDING,
			Processor__c = first.Processor__c,
			Mode__c = first.Mode__c,
			Amount__c = change.amount ?? first.Amount__c,
			Amount_Refunded__c = 0,
			Currency_Code__c = first.Currency_Code__c,
			Description__c = first.Description__c,
			Payer_Name__c = first.Payer_Name__c,
			Payer_Email__c = first.Payer_Email__c,
			Person__c = first.Person__c,
			Source_Record_Id__c = first.Source_Record_Id__c,
			Listener__c = first.Listener__c,
			Subscription_Id__c = change.subscriptionId,
			Processor_Payment_Id__c = change.processorPaymentId,
			Reference__c = newReference()
		);
	}

	/** One subscription change as the seam passes it (`subscriptionsChanged`). */
	private static Map<String, Object> newsOf(Outcome o, Payment__c payment) {
		Change c = o.change;
		Map<String, Object> news = toMap(payment);
		news.putAll(
			new Map<String, Object>{
				'subscriptionId' => c.subscriptionId ?? payment.Subscription_Id__c,
				'customerId' => c.customerId,
				'event' => c.subscriptionEvent,
				'eventKey' => o.event.Event_Key__c,
				'eventDate' => OrgDate.dateOf(c.paidAt ?? Datetime.now()),
				'amount' => c.amount,
				'cardExpires' => c.cardExpires,
				'detail' => c.detail
			}
		);
		return news;
	}

	/** Tells each listener its subscription news once per run, in a savepoint (R-PAY6). */
	private static void tellSubscriptions(Map<String, List<Map<String, Object>>> news) {
		for (String name : news.keySet()) {
			System.Savepoint before = Database.setSavepoint();
			try {
				((Callable) NamespaceUtil.build(name, Callable.class, CONTEXT + '.notify'))
					?.call('subscriptionsChanged', new Map<String, Object>{ 'changes' => news.get(name) });
			} catch (Exception e) {
				Database.rollback(before);
				ErrorLogger.log(e, CONTEXT + '.notify');
			}
		}
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

	/**
	 * The payment with the change's processor payment id; failing that, the first (oldest) with
	 * its reference, checkout or subscription, which for a subscription is its first payment.
	 */
	private static Payment__c match(List<Payment__c> found, Change change) {
		Payment__c first;
		for (Payment__c p : found) {
			if (change.processorPaymentId != null && p.Processor_Payment_Id__c == change.processorPaymentId) {
				return p;
			}
			if (
				first == null &&
				((change.reference != null &&
				p.Reference__c == change.reference) ||
				(change.checkoutId != null &&
				p.Checkout_Id__c == change.checkoutId) ||
				(change.subscriptionId != null &&
				p.Subscription_Id__c == change.subscriptionId))
			) {
				first = p;
			}
		}
		return first;
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
		if (String.isBlank(payment.Subscription_Id__c)) {
			payment.Subscription_Id__c = change.subscriptionId;
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
				listener = (Callable) NamespaceUtil.build(name, Callable.class, CONTEXT + '.notify');
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
				if (listener.call('paymentsChanged', new Map<String, Object>{ 'payments' => told }) == true) {
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
