/**
 * The org's own Stripe account (ADR-0201 `0201-payments-module.md`, decisions 2, 4 and 5):
 * Checkout Sessions, the Stripe-Signature check on arrival, and reading a verified event into a
 * `PaymentService.Change`. Stripe API version: the account's default.
 */
public with sharing class PaymentStripe {
	public static final String ENDPOINT = 'https://api.stripe.com/v1/checkout/sessions';
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
	@SuppressWarnings('PMD.ApexSuggestUsingNamedCred')
	public static void startCheckout(Payment__c payment, String successUrl, String cancelUrl) {
		String ref = payment.Reference__c;
		Map<String, String> form = new Map<String, String>{
			'mode' => 'payment',
			'success_url' => successUrl,
			'cancel_url' => cancelUrl,
			'client_reference_id' => ref,
			'line_items[0][quantity]' => '1',
			'line_items[0][price_data][currency]' => payment.Currency_Code__c.toLowerCase(),
			'line_items[0][price_data][unit_amount]' => String.valueOf(
				PaymentService.minorUnits(payment.Amount__c, payment.Currency_Code__c)
			),
			'line_items[0][price_data][product_data][name]' => payment.Description__c,
			'metadata[barncrm_reference]' => ref,
			'payment_intent_data[metadata][barncrm_reference]' => ref
		};
		if (String.isNotBlank(payment.Payer_Email__c)) {
			form.put('customer_email', payment.Payer_Email__c);
		}
		List<String> pairs = new List<String>();
		for (String key : form.keySet()) {
			pairs.add(
				EncodingUtil.urlEncode(key, 'UTF-8') +
					'=' +
					EncodingUtil.urlEncode(form.get(key), 'UTF-8')
			);
		}
		HttpRequest request = new HttpRequest();
		request.setEndpoint(ENDPOINT);
		request.setMethod('POST');
		request.setTimeout(20000);
		request.setHeader('Authorization', 'Bearer ' + PaymentService.keys().Stripe_Secret_Key__c);
		request.setHeader('Content-Type', 'application/x-www-form-urlencoded');
		request.setHeader('Idempotency-Key', ref);
		request.setBody(String.join(pairs, '&'));
		HttpResponse response = new Http().send(request);
		Map<String, Object> body = parse(response.getBody());
		if (response.getStatusCode() != 200 || !(body.get('url') instanceof String)) {
			ErrorLogger.logMessage(
				'Stripe answered ' + response.getStatusCode() + ': ' + errorOf(body),
				CONTEXT + '.startCheckout',
				ErrorLogger.SEVERITY_ERROR
			);
			throw PaymentService.problem(
				BarnHelp.text('Payments', 'Payments_Error_Processor', new List<Object>{ 'Stripe' })
			);
		}
		payment.Checkout_Id__c = (String) body.get('id');
		payment.Checkout_Url__c = (String) body.get('url');
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
		}
		switch on type {
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
