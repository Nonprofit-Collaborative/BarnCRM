/**
 * The org's own PayPal account (ADR-0201 `0201-payments-module.md`, decisions 2, 4 and 5):
 * Orders with an approve link, PayPal's own webhook verification, and capture of an approved
 * order; subscriptions on one shared product and shared plans (ADR-0218
 * `0218-payments-subscriptions.md`, amended for D-198). Every callout here runs before any write
 * of the transaction it is in; the one write here, a new shared product's id, follows the last.
 */
public with sharing class PaymentPayPal {
	public static final String LIVE_BASE = 'https://api-m.paypal.com';
	public static final String TEST_BASE = 'https://api-m.sandbox.paypal.com';
	/** Where a payer changes the funding source of their automatic payments (Update Card). */
	public static final String AUTOPAY = 'https://www.paypal.com/myaccount/autopay/';
	public static final String AUTOPAY_TEST = 'https://www.sandbox.paypal.com/myaccount/autopay/';
	/** The headers PayPal signs an event with, kept on the event for verification. */
	public static final List<String> HEADERS = new List<String>{
		'paypal-auth-algo',
		'paypal-cert-url',
		'paypal-transmission-id',
		'paypal-transmission-sig',
		'paypal-transmission-time'
	};
	/** The event types `read` acts on: the receiver stores no other. Kept beside its switch. */
	public static final Set<String> EVENT_TYPES = new Set<String>{
		'CHECKOUT.ORDER.APPROVED',
		'PAYMENT.CAPTURE.COMPLETED',
		'PAYMENT.SALE.COMPLETED',
		'BILLING.SUBSCRIPTION.PAYMENT.FAILED',
		'BILLING.SUBSCRIPTION.CANCELLED',
		'PAYMENT.CAPTURE.DENIED',
		'PAYMENT.CAPTURE.DECLINED',
		'PAYMENT.CAPTURE.REFUNDED',
		'PAYMENT.CAPTURE.REVERSED'
	};
	private static final String CONTEXT = 'PaymentPayPal';
	private static final String PLANS = '/v1/billing/plans';
	private static final String SUBSCRIPTIONS = '/v1/billing/subscriptions';
	/** One access token per transaction. */
	private static String token;

	private static String base() {
		return PaymentService.mode() == PaymentService.LIVE ? LIVE_BASE : TEST_BASE;
	}

	/**
	 * Creates the Order, or with an interval the payer's subscription on a shared plan
	 * (R-PAY7), and sets its id and approve link on the payment.
	 */
	public static void startCheckout(
		Payment__c payment,
		String successUrl,
		String cancelUrl,
		String interval,
		Integer intervalCount
	) {
		String value = PaymentService.noDecimals(payment.Currency_Code__c)
			? String.valueOf(payment.Amount__c.setScale(0))
			: String.valueOf(payment.Amount__c.setScale(2));
		String ref = payment.Reference__c;
		if (interval != null) {
			subscribe(
				payment,
				new Terms(payment, value, interval.toUpperCase(), intervalCount),
				successUrl,
				cancelUrl
			);
			return;
		}
		Map<String, Object> order = new Map<String, Object>{
			'intent' => 'CAPTURE',
			'purchase_units' => new List<Object>{
				new Map<String, Object>{
					'reference_id' => payment.Reference__c,
					'custom_id' => payment.Reference__c,
					'description' => payment.Description__c.abbreviate(127),
					'amount' => new Map<String, Object>{
						'currency_code' => payment.Currency_Code__c,
						'value' => value
					}
				}
			},
			'payment_source' => new Map<String, Object>{
				'paypal' => new Map<String, Object>{
					'experience_context' => new Map<String, Object>{
						'return_url' => successUrl,
						'cancel_url' => cancelUrl,
						'user_action' => 'PAY_NOW',
						'shipping_preference' => 'NO_SHIPPING'
					}
				}
			}
		};
		approve(payment, send('/v2/checkout/orders', JSON.serialize(order), ref));
	}

	/**
	 * The payer's own subscription on the shared plan for this mode, currency, amount and interval
	 * (R-PAY7, D-198): the plan of the newest payment with the same key, else a new one, which this
	 * payment then carries. A remembered plan or product PayPal refuses (missing, inactive, another
	 * account) is replaced once. PayPal-Request-Id is keyed by the plan key, so checkouts at the
	 * same moment make one plan. Every callout comes first; the product id is written last.
	 */
	private static void subscribe(
		Payment__c payment,
		Terms plan,
		String successUrl,
		String cancelUrl
	) {
		String ref = payment.Reference__c;
		String planId = new PlanReader().latest(plan.key);
		Boolean remembered = planId != null;
		HttpResponse answer = remembered
			? send(SUBSCRIPTIONS, plan.subscription(planId, ref, successUrl, cancelUrl), ref)
			: null;
		Payment_Keys__c keys = PaymentService.keys();
		String product = keys.PayPal_Product_Id__c;
		if (answer == null || refused(answer)) {
			String fresh = remembered ? '-' + ref : '';
			HttpResponse made = product == null
				? null
				: send(PLANS, plan.body(product), 'plan-' + plan.key + '-' + product + fresh);
			if (made == null || refused(made)) {
				// No product yet, or one this account does not have (new keys, the other mode).
				product = idOf(
					send(
						'/v1/catalogs/products',
						JSON.serialize(
							new Map<String, Object>{
								'name' => BarnHelp.text(
										'Payments',
										'Payments_PayPal_ProductName',
										new List<Object>{ UserInfo.getOrganizationName() }
									)
									.abbreviate(127),
								'type' => 'SERVICE'
							}
						),
						'product-' + PaymentService.mode() + (product == null ? '' : '-' + ref)
					)
				);
				made = send(PLANS, plan.body(product), 'plan-' + plan.key + '-' + product + fresh);
			}
			planId = idOf(made);
			answer = send(
				SUBSCRIPTIONS,
				plan.subscription(planId, ref, successUrl, cancelUrl),
				remembered ? ref + '-2' : ref
			);
		}
		approve(payment, answer);
		payment.Subscription_Id__c = payment.Checkout_Id__c;
		payment.Plan_Key__c = plan.key;
		payment.Plan_Id__c = planId;
		if (product != null && !product.equals(keys.PayPal_Product_Id__c)) {
			keys.PayPal_Product_Id__c = product;
			update as system keys;
		}
	}

	/** PayPal refused the request itself (4xx), as for a plan or product it does not have. */
	private static Boolean refused(HttpResponse response) {
		return response.getStatusCode() >= 400 && response.getStatusCode() < 500;
	}

	/** What a shared PayPal billing plan charges (R-PAY7): its key and the bodies that use it. */
	private class Terms {
		String key;
		String currencyCode;
		String value;
		String unit;
		Integer every;

		Terms(Payment__c payment, String value, String unit, Integer every) {
			this.currencyCode = payment.Currency_Code__c;
			this.value = value;
			this.unit = unit;
			this.every = every;
			key = String.join(
				new List<Object>{ PaymentService.mode(), currencyCode, value, unit, every },
				':'
			);
		}

		String body(String product) {
			String period = unit.toLowerCase();
			return JSON.serialize(
				new Map<String, Object>{
					'product_id' => product,
					'name' => BarnHelp.text(
						'Payments',
						'Payments_PayPal_PlanName',
						new List<Object>{
							value,
							currencyCode,
							every == 1 ? period : String.valueOf(every) + ' ' + period + 's'
						}
					),
					'billing_cycles' => new List<Object>{
						new Map<String, Object>{
							'frequency' => new Map<String, Object>{
								'interval_unit' => unit,
								'interval_count' => every
							},
							'tenure_type' => 'REGULAR',
							'sequence' => 1,
							'total_cycles' => 0,
							'pricing_scheme' => new Map<String, Object>{
								'fixed_price' => new Map<String, Object>{
									'value' => value,
									'currency_code' => currencyCode
								}
							}
						}
					},
					'payment_preferences' => new Map<String, Object>{
						'payment_failure_threshold' => 3
					}
				}
			);
		}

		String subscription(String planId, String ref, String successUrl, String cancelUrl) {
			return JSON.serialize(
				new Map<String, Object>{
					'plan_id' => planId,
					'custom_id' => ref,
					'application_context' => new Map<String, Object>{
						'return_url' => successUrl,
						'cancel_url' => cancelUrl,
						'user_action' => 'SUBSCRIBE_NOW',
						'shipping_preference' => 'NO_SHIPPING'
					}
				}
			);
		}
	}

	/**
	 * Reads a shared plan's id past sharing: a donor page's guest or a portal person starts
	 * checkouts and can see no other payment. One Plan Id by its key, nothing else (R-PAY7).
	 */
	private without sharing class PlanReader {
		String latest(String key) {
			for (Payment__c first : [
				SELECT Plan_Id__c
				FROM Payment__c
				WHERE Plan_Key__c = :key AND Plan_Id__c != NULL
				WITH SYSTEM_MODE
				ORDER BY CreatedDate DESC, Id DESC
				LIMIT 1
			]) {
				return first.Plan_Id__c;
			}
			return null;
		}
	}

	/** Sets the order's or subscription's id and approve link on the payment, or refuses. */
	private static void approve(Payment__c payment, HttpResponse response) {
		Map<String, Object> body = PaymentStripe.parse(response.getBody());
		String link;
		for (
			Object item : body.get('links') instanceof List<Object>
				? (List<Object>) body.get('links')
				: new List<Object>()
		) {
			Map<String, Object> one = PaymentStripe.mapOf(item);
			if (one.get('rel') == 'payer-action' || one.get('rel') == 'approve') {
				link = PaymentStripe.text(one.get('href'));
			}
		}
		if (response.getStatusCode() > 201 || link == null) {
			refuse(response);
		}
		payment.Checkout_Id__c = PaymentStripe.text(body.get('id'));
		payment.Checkout_Url__c = link;
	}

	/** The id PayPal gave a created product or plan, or refuses. */
	private static String idOf(HttpResponse response) {
		String id = PaymentStripe.text(PaymentStripe.parse(response.getBody()).get('id'));
		if (id == null) {
			refuse(response);
		}
		return id;
	}

	private static void refuse(HttpResponse response) {
		ErrorLogger.logMessage(
			'PayPal answered ' +
				response.getStatusCode() +
				': ' +
				response.getBody().abbreviate(200),
			CONTEXT + '.startCheckout',
			ErrorLogger.SEVERITY_ERROR
		);
		throw PaymentService.problem(
			BarnHelp.text('Payments', 'Payments_Error_Processor', new List<Object>{ 'PayPal' })
		);
	}

	/**
	 * Verifies a stored event with PayPal, then reads it; an approved order is captured. Callouts
	 * only: the caller writes the outcome afterwards.
	 */
	public static PaymentService.Outcome read(Payment_Event__c event) {
		PaymentService.Outcome outcome = new PaymentService.Outcome(event);
		if (!verify(event)) {
			return outcome.nothing(
				'Rejected',
				BarnHelp.text('Payments', 'Payments_Event_NotVerified')
			);
		}
		Map<String, Object> body = PaymentStripe.parse(event.Payload__c);
		event.Event_Key__c = 'paypal:' + PaymentStripe.text(body.get('id'));
		Map<String, Object> resource = PaymentStripe.mapOf(body.get('resource'));
		PaymentService.Change change = new PaymentService.Change();
		change.reference = PaymentStripe.text(resource.get('custom_id'));
		// Every type handled here is in EVENT_TYPES, which the receiver stores by.
		switch on PaymentStripe.text(body.get('event_type')) {
			when 'CHECKOUT.ORDER.APPROVED' {
				List<Object> units = resource.get('purchase_units') instanceof List<Object>
					? (List<Object>) resource.get('purchase_units')
					: new List<Object>();
				change.reference = units.isEmpty()
					? null
					: PaymentStripe.text(PaymentStripe.mapOf(units[0]).get('custom_id'));
				change.checkoutId = PaymentStripe.text(resource.get('id'));
				capture(change);
			}
			when 'PAYMENT.CAPTURE.COMPLETED' {
				change.processorPaymentId = PaymentStripe.text(resource.get('id'));
				change.status = PaymentService.PAID;
			}
			when 'PAYMENT.SALE.COMPLETED' {
				// A subscription's charge (R-PAY6): the sale names its subscription and reference.
				change.subscriptionId = PaymentStripe.text(resource.get('billing_agreement_id'));
				if (change.subscriptionId == null) {
					return outcome;
				}
				change.reference = PaymentStripe.text(resource.get('custom'));
				change.processorPaymentId = PaymentStripe.text(resource.get('id'));
				change.amount = decimalOf(PaymentStripe.mapOf(resource.get('amount')).get('total'));
				change.status = PaymentService.PAID;
				change.subscriptionEvent = PaymentService.CHARGE_SUCCEEDED;
			}
			when 'BILLING.SUBSCRIPTION.PAYMENT.FAILED' {
				change.subscriptionId = PaymentStripe.text(resource.get('id'));
				change.subscriptionEvent = PaymentService.CHARGE_FAILED;
				change.detail = BarnHelp.text('Payments', 'Payments_Detail_ChargeFailed');
			}
			when 'BILLING.SUBSCRIPTION.CANCELLED' {
				change.subscriptionId = PaymentStripe.text(resource.get('id'));
				change.subscriptionEvent = PaymentService.SUBSCRIPTION_CANCELLED;
				change.detail = BarnHelp.text('Payments', 'Payments_Detail_Cancelled');
			}
			when 'PAYMENT.CAPTURE.DENIED', 'PAYMENT.CAPTURE.DECLINED' {
				change.processorPaymentId = PaymentStripe.text(resource.get('id'));
				change.status = PaymentService.FAILED;
				change.detail = BarnHelp.text('Payments', 'Payments_Detail_Declined');
			}
			when 'PAYMENT.CAPTURE.REFUNDED' {
				Map<String, Object> breakdown = PaymentStripe.mapOf(
					resource.get('seller_payable_breakdown')
				);
				Map<String, Object> total = PaymentStripe.mapOf(
					breakdown.get('total_refunded_amount')
				);
				if (total.isEmpty()) {
					total = PaymentStripe.mapOf(resource.get('amount'));
				}
				change.amountRefunded = decimalOf(total.get('value'));
				change.processorPaymentId = refundedCapture(resource);
				change.detail = BarnHelp.text('Payments', 'Payments_Detail_Refunded');
			}
			when 'PAYMENT.CAPTURE.REVERSED' {
				change.processorPaymentId = PaymentStripe.text(resource.get('id'));
				change.status = PaymentService.REFUNDED;
				change.detail = BarnHelp.text('Payments', 'Payments_Detail_Reversed');
			}
			when else {
				return outcome;
			}
		}
		outcome.change = change;
		return outcome;
	}

	/** Captures an approved order; the capture's result becomes the change's status. */
	private static void capture(PaymentService.Change change) {
		HttpResponse response = send(
			'/v2/checkout/orders/' +
				EncodingUtil.urlEncode(change.checkoutId, 'UTF-8') +
				'/capture',
			'{}',
			change.reference + '-capture'
		);
		Map<String, Object> body = PaymentStripe.parse(response.getBody());
		if (response.getStatusCode() > 201) {
			// Already captured, or declined: the capture event that follows says which.
			change.detail = PaymentStripe.text(body.get('message'));
			return;
		}
		List<Object> units = body.get('purchase_units') instanceof List<Object>
			? (List<Object>) body.get('purchase_units')
			: new List<Object>();
		Map<String, Object> payments = units.isEmpty()
			? new Map<String, Object>()
			: PaymentStripe.mapOf(PaymentStripe.mapOf(units[0]).get('payments'));
		List<Object> captures = payments.get('captures') instanceof List<Object>
			? (List<Object>) payments.get('captures')
			: new List<Object>();
		Map<String, Object> first = captures.isEmpty()
			? new Map<String, Object>()
			: PaymentStripe.mapOf(captures[0]);
		change.processorPaymentId = PaymentStripe.text(first.get('id'));
		String status = PaymentStripe.text(first.get('status'));
		change.status = status == 'COMPLETED'
			? PaymentService.PAID
			: (status == 'DECLINED' ? PaymentService.FAILED : null);
	}

	/** True when PayPal confirms the stored event was signed by it for this webhook. */
	@TestVisible
	private static Boolean verify(Payment_Event__c event) {
		// Apex names ignore case, so this cannot be called `headers` beside HEADERS.
		Map<String, Object> sent = PaymentStripe.parse(event.Headers__c);
		String webhookId = PaymentService.keys().PayPal_Webhook_Id__c;
		if (String.isBlank(webhookId) || String.isBlank(event.Payload__c)) {
			return false;
		}
		List<String> fields = new List<String>();
		for (String name : HEADERS) {
			String value = PaymentStripe.text(sent.get(name));
			if (String.isBlank(value)) {
				return false;
			}
			fields.add(
				JSON.serialize(name.removeStart('paypal-').replace('-', '_')) +
					':' +
					JSON.serialize(value)
			);
		}
		fields.add('"webhook_id":' + JSON.serialize(webhookId));
		// The event goes back exactly as received, so PayPal checks the bytes it signed.
		String request =
			'{' +
			String.join(fields, ',') +
			',"webhook_event":' +
			event.Payload__c +
			'}';
		HttpResponse response = send('/v1/notifications/verify-webhook-signature', request, null);
		return response.getStatusCode() == 200 &&
			PaymentStripe.parse(response.getBody()).get('verification_status') == 'SUCCESS';
	}

	// The org's own PayPal keys live in the protected setting Payment_Keys__c, not a Named
	// Credential (ADR-0201 payments module, decision 7): the same setting holds the webhook id
	// and Stripe's signing secret, which Apex must read, so one write-only place holds them all.
	@SuppressWarnings('PMD.ApexSuggestUsingNamedCred')
	private static HttpResponse send(String path, String body, String requestId) {
		HttpRequest request = new HttpRequest();
		request.setEndpoint(base() + path);
		request.setMethod('POST');
		request.setTimeout(20000);
		request.setHeader('Authorization', 'Bearer ' + accessToken());
		request.setHeader('Content-Type', 'application/json');
		if (requestId != null) {
			request.setHeader('PayPal-Request-Id', requestId);
		}
		request.setBody(body);
		return new Http().send(request);
	}

	// Signs in with the client id and secret from Payment_Keys__c (see send).
	@SuppressWarnings('PMD.ApexSuggestUsingNamedCred')
	private static String accessToken() {
		if (token != null) {
			return token;
		}
		Payment_Keys__c keys = PaymentService.keys();
		HttpRequest request = new HttpRequest();
		request.setEndpoint(base() + '/v1/oauth2/token');
		request.setMethod('POST');
		request.setTimeout(20000);
		request.setHeader(
			'Authorization',
			'Basic ' +
			EncodingUtil.base64Encode(
				Blob.valueOf(keys.PayPal_Client_Id__c + ':' + keys.PayPal_Client_Secret__c)
			)
		);
		request.setHeader('Content-Type', 'application/x-www-form-urlencoded');
		request.setBody('grant_type=client_credentials');
		HttpResponse response = new Http().send(request);
		token = PaymentStripe.text(PaymentStripe.parse(response.getBody()).get('access_token'));
		if (token == null) {
			throw new CalloutException('PayPal sign-in failed: ' + response.getStatusCode());
		}
		return token;
	}

	/** A refund's capture id, from its `up` link (`.../v2/payments/captures/{id}`), or null. */
	@TestVisible
	private static String refundedCapture(Map<String, Object> refund) {
		for (
			Object item : refund.get('links') instanceof List<Object>
				? (List<Object>) refund.get('links')
				: new List<Object>()
		) {
			Map<String, Object> link = PaymentStripe.mapOf(item);
			String href = PaymentStripe.text(link.get('href'));
			if (link.get('rel') == 'up' && href != null && href.contains('/captures/')) {
				return href.substringAfterLast('/captures/').substringBefore('/');
			}
		}
		return null;
	}

	private static Decimal decimalOf(Object value) {
		try {
			return value == null ? null : Decimal.valueOf(String.valueOf(value));
		} catch (Exception notANumber) {
			return null;
		}
	}
}
