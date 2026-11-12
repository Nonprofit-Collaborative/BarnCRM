/**
 * The org's own PayPal account (ADR-0201 `0201-payments-module.md`, decisions 2, 4 and 5):
 * Orders with an approve link, PayPal's own webhook verification, and capture of an approved
 * order. Every callout here runs before any write of the transaction it is in.
 */
public with sharing class PaymentPayPal {
	public static final String LIVE_BASE = 'https://api-m.paypal.com';
	public static final String TEST_BASE = 'https://api-m.sandbox.paypal.com';
	/** The headers PayPal signs an event with, kept on the event for verification. */
	public static final List<String> HEADERS = new List<String>{
		'paypal-auth-algo',
		'paypal-cert-url',
		'paypal-transmission-id',
		'paypal-transmission-sig',
		'paypal-transmission-time'
	};
	private static final String CONTEXT = 'PaymentPayPal';
	/** One access token per transaction. */
	private static String token;

	private static String base() {
		return PaymentService.mode() == PaymentService.LIVE ? LIVE_BASE : TEST_BASE;
	}

	/** Creates the Order and sets its id and approve link on the payment. */
	public static void startCheckout(Payment__c payment, String successUrl, String cancelUrl) {
		String value = PaymentService.noDecimals(payment.Currency_Code__c)
			? String.valueOf(payment.Amount__c.setScale(0))
			: String.valueOf(payment.Amount__c.setScale(2));
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
		HttpResponse response = send(
			'/v2/checkout/orders',
			JSON.serialize(order),
			payment.Reference__c
		);
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
		payment.Checkout_Id__c = PaymentStripe.text(body.get('id'));
		payment.Checkout_Url__c = link;
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
