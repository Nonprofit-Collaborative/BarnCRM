/**
 * The Payments Setup page (ADR-0201 `0201-payments-module.md`, decision 7, as amended by ADR-0229): the receiver address of each active Site, for
 * each processor, with the random token every address carries (made on first need, replaced by
 * Regenerate Token); where each processor's secrets go in Setup (External Credential, principal and
 * parameter names, qualified for this org); whether each processor is connected, with Check
 * Connection; and the PayPal webhook id, the one value still typed here (not a secret, shown by
 * its last four characters only). Thin: plain JSON and every text the page shows (plan 9.9).
 *
 * Opened by holders of Payments Admin (class access). Saving, clearing and checking also need
 * Manage BarnCRM Settings, and write the protected setting in system mode.
 */
public with sharing class PaymentsSetupController {
	private static final String CONTEXT = 'PaymentsSetupController';
	private static final String WEBHOOK_ID = 'payPalWebhookId';

	public class KeyStatus {
		@AuraEnabled
		public String name;
		@AuraEnabled
		public String processor;
		/** Null when not entered; otherwise the last four characters only. */
		@AuraEnabled
		public String lastFour;
	}

	/** Where one processor's secrets are entered in Setup; names only, never a value. */
	public class Credential {
		@AuraEnabled
		public String processor;
		@AuraEnabled
		public Boolean connected;
		@AuraEnabled
		public String externalCredential;
		@AuraEnabled
		public String principal;
		@AuraEnabled
		public String parameters;
		@AuraEnabled
		public String namedCredentials;
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
		/** Whether event processing is scheduled (it never is until an admin chooses; D-195). */
		@AuraEnabled
		public Boolean scheduled;
		@AuraEnabled
		public List<Receiver> receivers = new List<Receiver>();
		@AuraEnabled
		public List<KeyStatus> keys = new List<KeyStatus>();
		@AuraEnabled
		public List<Credential> credentials = new List<Credential>();
		/** The outcome of the Check Connection just made; null otherwise. */
		@AuraEnabled
		public String checkMessage;
		@AuraEnabled
		public Boolean checkOk;
	}

	@AuraEnabled
	public static Setup getSetup() {
		try {
			return setup();
		} catch (Exception unexpected) {
			throw UserErrors.wrap(unexpected, CONTEXT, true);
		}
	}

	/** Saves the PayPal webhook id typed; a blank box keeps the one saved before. */
	@AuraEnabled
	public static Setup saveKeys(Map<String, String> keys) {
		refuseUnlessManager();
		Payments_Settings__c stored = stored();
		String value = (keys == null ? new Map<String, String>() : keys).get(WEBHOOK_ID)?.trim();
		if (String.isNotBlank(value)) {
			stored.PayPal_Webhook_Id__c = value.left(
				Payments_Settings__c.PayPal_Webhook_Id__c.getDescribe().getLength()
			);
		}
		return write(stored);
	}

	/**
	 * Forgets one processor's connection (and PayPal's webhook id), so it is not used until it
	 * is checked again. The secrets themselves are removed in Setup, on the External Credential.
	 */
	@AuraEnabled
	public static Setup clearKeys(String processor) {
		refuseUnlessManager();
		Payments_Settings__c stored = stored();
		if (processor == PaymentService.STRIPE) {
			stored.Stripe_Connected__c = false;
		} else if (processor == PaymentService.PAYPAL) {
			stored.PayPal_Connected__c = false;
			stored.PayPal_Webhook_Id__c = null;
		} else {
			throw UserErrors.message(BarnHelp.text('Payments', 'Payments_Error_BadProcessor'));
		}
		return write(stored);
	}

	/**
	 * Calls the processor through its Named Credential as the person checking (Stripe: the
	 * balance; PayPal: a sign-in in the current mode) and records whether it answered. The
	 * callout comes before the write, as Salesforce requires.
	 */
	@AuraEnabled
	public static Setup checkConnection(String processor) {
		refuseUnlessManager();
		Payments_Settings__c stored = stored();
		PaymentStripe.Connection found;
		if (processor == PaymentService.STRIPE) {
			found = PaymentStripe.checkConnection();
			stored.Stripe_Connected__c = found.ok;
		} else if (processor == PaymentService.PAYPAL) {
			found = PaymentPayPal.checkConnection();
			stored.PayPal_Connected__c = found.ok;
		} else {
			throw UserErrors.message(BarnHelp.text('Payments', 'Payments_Error_BadProcessor'));
		}
		Setup result = write(stored);
		if (found.failure != null) {
			ErrorLogger.log(found.failure, CONTEXT + '.checkConnection');
		}
		result.checkOk = found.ok;
		result.checkMessage = found.ok
			? connected(processor, found.live)
			: BarnHelp.text(
					'Payments',
					'Payments_Setup_CheckFailed',
					new List<Object>{
						processor,
						found.statusCode == null ? '-' : String.valueOf(found.statusCode)
					}
			  );
		return result;
	}

	/** Connected; for Stripe, says so plainly when the key is for the other mode. */
	private static String connected(String processor, Boolean live) {
		Boolean liveMode = PaymentService.mode() == PaymentService.LIVE;
		if (live != null && live != liveMode) {
			return BarnHelp.text(
				'Payments',
				'Payments_Health_ModeMismatchDetail',
				new List<Object>{ PaymentService.mode() }
			);
		}
		return BarnHelp.text(
			'Payments',
			'Payments_Setup_Connected',
			new List<Object>{ processor, PaymentService.mode() }
		);
	}

	/**
	 * Replaces the address token: the addresses already given to a processor stop working until
	 * the new ones are pasted in.
	 */
	@AuraEnabled
	public static Setup regenerateToken() {
		refuseUnlessManager();
		try {
			PaymentService.webhookToken(true);
			return setup();
		} catch (Exception unexpected) {
			throw UserErrors.wrap(unexpected, CONTEXT, true);
		}
	}

	/** Schedules event processing as the person choosing it, as the Health Check fix does. */
	@AuraEnabled
	public static Setup scheduleProcessing() {
		refuseUnlessManager();
		try {
			PaymentEventProcessor.schedule();
			return setup();
		} catch (Exception unexpected) {
			throw UserErrors.wrap(unexpected, CONTEXT, true);
		}
	}

	private static void refuseUnlessManager() {
		if (!HealthCheckService.canManageSettings()) {
			throw UserErrors.message(BarnHelp.text('Payments', 'Payments_Setup_NoManage'));
		}
	}

	private static Payments_Settings__c stored() {
		Payments_Settings__c stored = PaymentService.settings();
		stored.SetupOwnerId = UserInfo.getOrganizationId();
		return stored;
	}

	private static Setup write(Payments_Settings__c stored) {
		try {
			upsert as system stored;
			return setup();
		} catch (Exception unexpected) {
			throw UserErrors.wrap(unexpected, CONTEXT, true);
		}
	}

	private static Setup setup() {
		Setup result = new Setup();
		Payments_Settings__c stored = PaymentService.settings();
		result.processor = PaymentService.defaultProcessor();
		result.mode = PaymentService.mode();
		result.canManage = HealthCheckService.canManageSettings();
		result.scheduled = PaymentEventProcessor.isScheduled();
		String token = PaymentService.webhookToken(false);
		for (PaymentSites.SiteInfo site : PaymentSites.active()) {
			if (site.url != null) {
				Receiver receiver = new Receiver();
				receiver.site = site.name;
				receiver.stripeUrl =
					site.url +
					PaymentSites.RECEIVER_PATH +
					'stripe?token=' +
					token;
				receiver.payPalUrl =
					site.url +
					PaymentSites.RECEIVER_PATH +
					'paypal?token=' +
					token;
				result.receivers.add(receiver);
			}
		}
		KeyStatus webhook = new KeyStatus();
		webhook.name = WEBHOOK_ID;
		webhook.processor = PaymentService.PAYPAL;
		webhook.lastFour = String.isBlank(stored.PayPal_Webhook_Id__c)
			? null
			: stored.PayPal_Webhook_Id__c.right(4);
		result.keys.add(webhook);
		result.credentials.add(
			credential(
				PaymentService.STRIPE,
				stored.Stripe_Connected__c == true,
				PaymentStripe.CREDENTIAL,
				'Barn_Stripe_Key',
				'SecretKey',
				PaymentStripe.CREDENTIAL
			)
		);
		result.credentials.add(
			credential(
				PaymentService.PAYPAL,
				stored.PayPal_Connected__c == true,
				PaymentPayPal.CREDENTIAL,
				'Barn_PayPal_App',
				'ClientId, ClientSecret',
				PaymentPayPal.LIVE_BASE.removeStart('callout:') +
					', ' +
					PaymentPayPal.TEST_BASE.removeStart('callout:')
			)
		);
		return result;
	}

	private static Credential credential(
		String processor,
		Boolean connected,
		String externalCredential,
		String principal,
		String parameters,
		String namedCredentials
	) {
		Credential c = new Credential();
		c.processor = processor;
		c.connected = connected;
		c.externalCredential = externalCredential;
		c.principal = principal;
		c.parameters = parameters;
		c.namedCredentials = namedCredentials;
		return c;
	}
}
