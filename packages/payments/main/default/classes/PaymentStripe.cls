/**
 * The org's own Stripe account (ADR-0201 `0201-payments-module.md`, decisions 2, 4 and 5):
 * Checkout Sessions, the Stripe-Signature check on arrival, and reading a verified event into a
 * `PaymentService.Change`; subscriptions and the setup-mode card update (ADR-0218
 * `0218-payments-subscriptions.md`). Stripe API version: the account's default.
 */
public with sharing class PaymentStripe {
	public static final String ENDPOINT = 'https://api.stripe.com/v1/';
	/** How far the signed time may be from now, in seconds (Stripe's own default). */
	@TestVisible
	private static final Integer TOLERANCE_SECONDS = 300;
	private static final String CONTEXT = 'PaymentStripe';

	/**
	 * Starts a Checkout Session and sets its id and page address on the payment. The org's own
	 * secret key comes from the protected setting Payment_Keys__c, not a Named Credential
	 * (ADR-0201 payments module, decision 7): its signing secret must be readable by Apex for
	 * the HMAC check, so both Stripe keys are kept in the one write-only place.
	 */
	public static void startCheckout(
		Payment__c payment,
		String successUrl,
		String cancelUrl,
		String interval,
		Integer intervalCount
	) {
		String ref = payment.Reference__c;
		String item = 'line_items[0][price_data]';
		Map<String, String> form = new Map<String, String>{
			'mode' => interval == null ? 'payment' : 'subscription',
			'success_url' => successUrl,
			'cancel_url' => cancelUrl,
			'client_reference_id' => ref,
			'line_items[0][quantity]' => '1',
			item + '[currency]' => payment.Currency_Code__c.toLowerCase(),
			item + '[unit_amount]' => String.valueOf(
				PaymentService.minorUnits(payment.Amount__c, payment.Currency_Code__c)
			),
			item + '[product_data][name]' => payment.Description__c,
			'metadata[barncrm_reference]' => ref
		};
		if (interval == null) {
			form.put('payment_intent_data[metadata][barncrm_reference]', ref);
		} else {
			// The reference rides on the subscription, so its invoices and cancellation carry it.
			form.put(item + '[recurring][interval]', interval);
			form.put(item + '[recurring][interval_count]', String.valueOf(intervalCount));
			form.put('subscription_data[metadata][barncrm_reference]', ref);
		}
		if (String.isNotBlank(payment.Payer_Email__c)) {
			form.put('customer_email', payment.Payer_Email__c);
		}
		Map<String, Object> body = send('POST', 'checkout/sessions', form, ref);
		payment.Checkout_Id__c = text(body.get('id'));
		payment.Checkout_Url__c = text(body.get('url'));
	}

	/**
	 * A Checkout Session in setup mode for the customer, with the subscription in its metadata
	 * (ADR-0218 payments subscriptions, decision 5): Stripe's own card form, valid 24 hours.
	 */
	public static String updateCardUrl(String customerId, String subscriptionId, String back) {
		return text(
			send(
					'POST',
					'checkout/sessions',
					new Map<String, String>{
						'mode' => 'setup',
						'customer' => customerId,
						'currency' => (PaymentService.settings().Currency__c ?? 'USD')
							.toLowerCase(),
						'success_url' => back,
						'cancel_url' => back,
						'metadata[barncrm_subscription]' => subscriptionId
					},
					null
				)
				.get('url')
		);
	}

	/**
	 * One Stripe API call with the org's own secret key, from the protected setting
	 * Payment_Keys__c, not a Named Credential (ADR-0201 payments module, decision 7): its signing
	 * secret must be readable by Apex for the HMAC check, so both Stripe keys are kept in the one
	 * write-only place. Throws a PaymentException unless Stripe answers 200 with an id.
	 */
	@SuppressWarnings('PMD.ApexSuggestUsingNamedCred')
	private static Map<String, Object> send(
		String method,
		String path,
		Map<String, String> form,
		String idempotencyKey
	) {
		HttpRequest request = new HttpRequest();
		request.setEndpoint(ENDPOINT + path);
		request.setMethod(method);
		request.setTimeout(20000);
		request.setHeader('Authorization', 'Bearer ' + PaymentService.keys().Stripe_Secret_Key__c);
		if (form != null) {
			List<String> pairs = new List<String>();
			for (String key : form.keySet()) {
				pairs.add(
					EncodingUtil.urlEncode(key, 'UTF-8') +
						'=' +
						EncodingUtil.urlEncode(form.get(key) ?? '', 'UTF-8')
				);
			}
			request.setHeader('Content-Type', 'application/x-www-form-urlencoded');
			request.setBody(String.join(pairs, '&'));
		}
		if (idempotencyKey != null) {
			request.setHeader('Idempotency-Key', idempotencyKey);
		}
		HttpResponse response = new Http().send(request);
		Map<String, Object> body = parse(response.getBody());
		if (response.getStatusCode() != 200 || !(body.get('id') instanceof String)) {
			ErrorLogger.logMessage(
				'Stripe answered ' + response.getStatusCode() + ': ' + errorOf(body),
				CONTEXT + '.' + path.substringBefore('/'),
				ErrorLogger.SEVERITY_ERROR
			);
			throw PaymentService.problem(
				BarnHelp.text('Payments', 'Payments_Error_Processor', new List<Object>{ 'Stripe' })
			);
		}
		return body;
	}

	/**
	 * True when the Stripe-Signature header (`t=...,v1=...`) signs this exact body with the
	 * endpoint's secret, within the tolerance of now (in seconds since 1970).
	 */
	public static Boolean verify(String rawBody, String header, Long nowSeconds) {
		String secret = PaymentService.keys().Stripe_Webhook_Secret__c;
		if (String.isBlank(secret) || String.isBlank(header) || rawBody == null) {
			return false;
		}
		String signedAt;
		List<String> signatures = new List<String>();
		for (String part : header.split(',')) {
			String name = part.substringBefore('=').trim();
			String value = part.substringAfter('=').trim();
			if (name == 't') {
				signedAt = value;
			} else if (name == 'v1') {
				signatures.add(value);
			}
		}
		if (
			signedAt == null ||
			!signedAt.isNumeric() ||
			signedAt.length() > 12 ||
			signatures.isEmpty()
		) {
			return false;
		}
		if (Math.abs(nowSeconds - Long.valueOf(signedAt)) > TOLERANCE_SECONDS) {
			return false;
		}
		String expected = EncodingUtil.convertToHex(
			Crypto.generateMac(
				'hmacSHA256',
				Blob.valueOf(signedAt + '.' + rawBody),
				Blob.valueOf(secret)
			)
		);
		for (String signature : signatures) {
			if (sameText(expected, signature)) {
				return true;
			}
		}
		return false;
	}

	/** Compares in time that does not depend on where the first difference is. */
	@TestVisible
	private static Boolean sameText(String a, String b) {
		if (a == null || b == null || a.length() != b.length()) {
			return false;
		}
		Integer difference = 0;
		for (Integer i = 0; i < a.length(); i++) {
			difference |= a.charAt(i) ^ b.charAt(i);
		}
		return difference == 0;
	}

	/** Reads a verified event; no callout. */
	public static PaymentService.Outcome read(Payment_Event__c event) {
		PaymentService.Outcome outcome = new PaymentService.Outcome(event);
		Map<String, Object> body = parse(event.Payload__c);
		Map<String, Object> data = mapOf(body.get('data'));
		Map<String, Object> obj = mapOf(data.get('object'));
		Map<String, Object> metadata = mapOf(obj.get('metadata'));
		String type = text(body.get('type'));
		PaymentService.Change change = new PaymentService.Change();
		change.reference = text(metadata.get('barncrm_reference'));
		Datetime eventTime = body.get('created') instanceof Long ||
			body.get('created') instanceof Integer
			? Datetime.newInstance(Long.valueOf(String.valueOf(body.get('created'))) * 1000)
			: null;
		if (type != null && type.startsWith('checkout.session.')) {
			change.reference = text(obj.get('client_reference_id')) ?? change.reference;
			change.checkoutId = text(obj.get('id'));
			change.processorPaymentId = text(obj.get('payment_intent'));
			change.subscriptionId = text(obj.get('subscription'));
		}
		change.customerId = text(obj.get('customer'));
		if (type == 'checkout.session.completed' && obj.get('mode') == 'setup') {
			outcome.change = cardUpdated(obj, text(metadata.get('barncrm_subscription')));
			return outcome;
		}
		if (type != null && type.startsWith('invoice.')) {
			// Older API versions name the subscription on the invoice, newer ones under parent.
			Map<String, Object> details = mapOf(
				mapOf(obj.get('parent')).get('subscription_details') ??
					obj.get('subscription_details')
			);
			change.subscriptionId = text(obj.get('subscription')) ??
				text(details.get('subscription'));
			change.reference = text(mapOf(details.get('metadata')).get('barncrm_reference'));
			if (change.subscriptionId == null) {
				return outcome;
			}
		}
		switch on type {
			when 'invoice.paid' {
				// Newer API versions put no payment intent on the invoice: its own id stands in.
				change.processorPaymentId = text(obj.get('payment_intent')) ?? text(obj.get('id'));
				change.amount = PaymentService.fromMinorUnits(
					obj.get('amount_paid'),
					text(obj.get('currency'))
				);
				change.status = PaymentService.PAID;
				change.paidAt = eventTime;
				change.subscriptionEvent = PaymentService.CHARGE_SUCCEEDED;
			}
			when 'invoice.payment_failed' {
				change.subscriptionEvent = PaymentService.CHARGE_FAILED;
				change.detail = BarnHelp.text('Payments', 'Payments_Detail_ChargeFailed');
			}
			when 'customer.subscription.deleted' {
				change.subscriptionId = text(obj.get('id'));
				change.subscriptionEvent = PaymentService.SUBSCRIPTION_CANCELLED;
				change.detail = BarnHelp.text('Payments', 'Payments_Detail_Cancelled');
			}
			when 'checkout.session.completed', 'checkout.session.async_payment_succeeded' {
				String paymentStatus = text(obj.get('payment_status'));
				if (paymentStatus == 'paid' || paymentStatus == 'no_payment_required') {
					change.status = PaymentService.PAID;
					change.paidAt = eventTime;
				}
			}
			when 'checkout.session.async_payment_failed' {
				change.status = PaymentService.FAILED;
				change.detail = BarnHelp.text('Payments', 'Payments_Detail_BankFailed');
			}
			when 'checkout.session.expired' {
				change.status = PaymentService.CANCELLED;
				change.detail = BarnHelp.text('Payments', 'Payments_Detail_Expired');
			}
			when 'payment_intent.payment_failed' {
				change.processorPaymentId = text(obj.get('id'));
				change.status = PaymentService.FAILED;
				change.detail = text(mapOf(obj.get('last_payment_error')).get('message'));
			}
			when 'charge.refunded' {
				change.processorPaymentId = text(obj.get('payment_intent'));
				change.amountRefunded = PaymentService.fromMinorUnits(
					obj.get('amount_refunded'),
					text(obj.get('currency'))
				);
				change.detail = BarnHelp.text('Payments', 'Payments_Detail_Refunded');
			}
			when else {
				return outcome;
			}
		}
		outcome.change = change;
		return outcome;
	}

	/**
	 * A completed setup-mode session: reads the card it saved and makes it the subscription's
	 * default (two callouts, before any write; ADR-0218 payments subscriptions, decision 5).
	 */
	private static PaymentService.Change cardUpdated(Map<String, Object> obj, String subscription) {
		if (subscription == null || text(obj.get('setup_intent')) == null) {
			return null;
		}
		Map<String, Object> method = mapOf(
			send(
					'GET',
					'setup_intents/' +
						EncodingUtil.urlEncode(text(obj.get('setup_intent')), 'UTF-8') +
						'?expand%5B%5D=payment_method',
					null,
					null
				)
				.get('payment_method')
		);
		send(
			'POST',
			'subscriptions/' + EncodingUtil.urlEncode(subscription, 'UTF-8'),
			new Map<String, String>{ 'default_payment_method' => text(method.get('id')) },
			null
		);
		PaymentService.Change change = new PaymentService.Change();
		change.subscriptionId = subscription;
		change.customerId = text(obj.get('customer'));
		change.subscriptionEvent = PaymentService.CARD_UPDATED;
		Map<String, Object> card = mapOf(method.get('card'));
		if (card.get('exp_year') instanceof Integer && card.get('exp_month') instanceof Integer) {
			change.cardExpires = Date.newInstance(
					(Integer) card.get('exp_year'),
					(Integer) card.get('exp_month'),
					1
				)
				.addMonths(1)
				.addDays(-1);
		}
		return change;
	}

	public static Map<String, Object> parse(String json) {
		try {
			return mapOf(System.JSON.deserializeUntyped(json));
		} catch (Exception notJson) {
			return new Map<String, Object>();
		}
	}

	public static Map<String, Object> mapOf(Object value) {
		return value instanceof Map<String, Object>
			? (Map<String, Object>) value
			: new Map<String, Object>();
	}

	public static String text(Object value) {
		return value instanceof String ? (String) value : null;
	}

	private static String errorOf(Map<String, Object> body) {
		return String.valueOf(mapOf(body.get('error')).get('message')).abbreviate(200);
	}
}
