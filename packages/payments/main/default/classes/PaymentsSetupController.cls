/**
 * The Payments Setup page (ADR-NEXT `NEXT-payments-module.md`, decision 7): the receiver address
 * of each active Site, for each processor, and whether each key is entered, showing only its
 * last four characters. Keys are write-only: a saved key is never returned. Thin: plain JSON and
 * every text the page shows (plan 9.9).
 *
 * Opened by holders of Payments Admin (class access). Saving or clearing keys also needs Manage
 * BarnCRM Settings, and writes the protected setting in system mode, since no permission set
 * grants the protected setting's fields.
 */
public with sharing class PaymentsSetupController {
	private static final String CONTEXT = 'PaymentsSetupController';

	/** The keys the page can save, by the name the page sends. */
	@TestVisible
	private static final Map<String, Schema.SObjectField> FIELDS = new Map<String, Schema.SObjectField>{
		'stripeSecretKey' => Payment_Keys__c.Stripe_Secret_Key__c,
		'stripeWebhookSecret' => Payment_Keys__c.Stripe_Webhook_Secret__c,
		'payPalClientId' => Payment_Keys__c.PayPal_Client_Id__c,
		'payPalClientSecret' => Payment_Keys__c.PayPal_Client_Secret__c,
		'payPalWebhookId' => Payment_Keys__c.PayPal_Webhook_Id__c
	};
	private static final Map<String, List<String>> BY_PROCESSOR = new Map<String, List<String>>{
		PaymentService.STRIPE => new List<String>{ 'stripeSecretKey', 'stripeWebhookSecret' },
		PaymentService.PAYPAL => new List<String>{
			'payPalClientId',
			'payPalClientSecret',
			'payPalWebhookId'
		}
	};

	public class KeyStatus {
		@AuraEnabled
		public String name;
		@AuraEnabled
		public String processor;
		/** Null when not entered; otherwise the last four characters only. */
		@AuraEnabled
		public String lastFour;
	}

	public class Receiver {
		@AuraEnabled
		public String site;
		@AuraEnabled
		public String stripeUrl;
		@AuraEnabled
		public String payPalUrl;
	}

	public class Setup {
		@AuraEnabled
		public String processor;
		@AuraEnabled
		public String mode;
		@AuraEnabled
		public Boolean canManage;
		@AuraEnabled
		public List<Receiver> receivers = new List<Receiver>();
		@AuraEnabled
		public List<KeyStatus> keys = new List<KeyStatus>();
	}

	@AuraEnabled
	public static Setup getSetup() {
		try {
			return setup();
		} catch (Exception unexpected) {
			throw UserErrors.wrap(unexpected, CONTEXT, true);
		}
	}

	/** Saves the keys typed; a blank box keeps the key saved before. */
	@AuraEnabled
	public static Setup saveKeys(Map<String, String> keys) {
		refuseUnlessManager();
		Payment_Keys__c stored = stored();
		for (String name : (keys == null ? new Map<String, String>() : keys).keySet()) {
			String value = keys.get(name)?.trim();
			if (FIELDS.containsKey(name) && String.isNotBlank(value)) {
				stored.put(
					FIELDS.get(name),
					value.left(FIELDS.get(name).getDescribe().getLength())
				);
			}
		}
		return write(stored);
	}

	/** Removes every key of one processor. */
	@AuraEnabled
	public static Setup clearKeys(String processor) {
		refuseUnlessManager();
		if (!BY_PROCESSOR.containsKey(processor)) {
			throw UserErrors.message(BarnHelp.text('Payments', 'Payments_Error_BadProcessor'));
		}
		Payment_Keys__c stored = stored();
		for (String name : BY_PROCESSOR.get(processor)) {
			stored.put(FIELDS.get(name), null);
		}
		return write(stored);
	}

	private static void refuseUnlessManager() {
		if (!HealthCheckService.canManageSettings()) {
			throw UserErrors.message(BarnHelp.text('Payments', 'Payments_Setup_NoManage'));
		}
	}

	private static Payment_Keys__c stored() {
		Payment_Keys__c stored = Payment_Keys__c.getOrgDefaults();
		stored.SetupOwnerId = UserInfo.getOrganizationId();
		return stored;
	}

	private static Setup write(Payment_Keys__c stored) {
		try {
			upsert as system stored;
			return setup();
		} catch (Exception unexpected) {
			throw UserErrors.wrap(unexpected, CONTEXT, true);
		}
	}

	private static Setup setup() {
		Setup result = new Setup();
		result.processor = PaymentService.defaultProcessor();
		result.mode = PaymentService.mode();
		result.canManage = HealthCheckService.canManageSettings();
		for (PaymentSites.SiteInfo site : PaymentSites.active()) {
			if (site.url != null) {
				Receiver receiver = new Receiver();
				receiver.site = site.name;
				receiver.stripeUrl = site.url + PaymentSites.RECEIVER_PATH + 'stripe';
				receiver.payPalUrl = site.url + PaymentSites.RECEIVER_PATH + 'paypal';
				result.receivers.add(receiver);
			}
		}
		Payment_Keys__c stored = PaymentService.keys();
		for (String processor : BY_PROCESSOR.keySet()) {
			for (String name : BY_PROCESSOR.get(processor)) {
				KeyStatus key = new KeyStatus();
				key.name = name;
				key.processor = processor;
				String value = (String) stored.get(FIELDS.get(name));
				key.lastFour = String.isBlank(value) ? null : value.right(4);
				result.keys.add(key);
			}
		}
		return result;
	}
}
