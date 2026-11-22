/**
 * The Payments Setup page (ADR-0201 `0201-payments-module.md`, decision 7, as amended by ADR-0229): the receiver address of each active Site, for
 * each processor, and the random token every address carries: only its SHA-256 hash is kept, so the
 * token is shown once, in the answer to Generate Token or Regenerate Token; where each processor's
 * secrets go in Setup (External Credential, principal and parameter names, qualified for this org);
 * whether each processor is connected, with Check Connection; and the PayPal webhook id, the one
 * value still typed here (not a secret, shown by its last four characters only). Thin: plain JSON
 * and every text the page shows (plan 9.9).
 *
 * Opened by holders of Payments Admin (class access). Saving, clearing, checking and making a token
 * also need Manage BarnCRM Settings, and record the org's run state in system mode (`SettingsState`).
 */
public with sharing class PaymentsSetupController {
	private static final String CONTEXT = 'PaymentsSetupController';
	private static final String WEBHOOK_ID = 'payPalWebhookId';
	private static final Integer WEBHOOK_ID_LENGTH = 64;

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
		/** Whether the addresses carry a token (its hash is kept). */
		@AuraEnabled
		public Boolean hasToken;
		/** The token just made, in the answer to Generate Token only; null otherwise. */
		@AuraEnabled
		public String token;
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
		Map<String, Object> changes = new Map<String, Object>();
		String value = (keys == null ? new Map<String, String>() : keys).get(WEBHOOK_ID)?.trim();
		if (String.isNotBlank(value)) {
			changes.put(PaymentService.PAYPAL_WEBHOOK_ID, value.left(WEBHOOK_ID_LENGTH));
		}
		return write(changes);
	}

	/**
	 * Forgets one processor's connection (and PayPal's webhook id), so it is not used until it
	 * is checked again. The secrets themselves are removed in Setup, on the External Credential.
	 */
	@AuraEnabled
	public static Setup clearKeys(String processor) {
		refuseUnlessManager();
		Map<String, Object> changes = new Map<String, Object>();
		if (processor == PaymentService.STRIPE) {
			changes.put(PaymentService.STRIPE_CONNECTED, false);
		} else if (processor == PaymentService.PAYPAL) {
			changes.put(PaymentService.PAYPAL_CONNECTED, false);
			changes.put(PaymentService.PAYPAL_WEBHOOK_ID, null);
		} else {
			throw UserErrors.message(BarnHelp.text('Payments', 'Payments_Error_BadProcessor'));
		}
		return write(changes);
	}

	/**
	 * Calls the processor through its Named Credential as the person checking (Stripe: the
	 * balance; PayPal: a sign-in in the current mode) and records whether it answered. The
	 * callout comes before the write, as Salesforce requires.
	 */
	@AuraEnabled
	public static Setup checkConnection(String processor) {
		refuseUnlessManager();
		Map<String, Object> changes = new Map<String, Object>();
		PaymentStripe.Connection found;
		if (processor == PaymentService.STRIPE) {
			found = PaymentStripe.checkConnection();
			changes.put(PaymentService.STRIPE_CONNECTED, found.ok);
		} else if (processor == PaymentService.PAYPAL) {
			found = PaymentPayPal.checkConnection();
			changes.put(PaymentService.PAYPAL_CONNECTED, found.ok);
		} else {
			throw UserErrors.message(BarnHelp.text('Payments', 'Payments_Error_BadProcessor'));
		}
		Setup result = write(changes);
		if (found.failure != null) {
			ErrorLogger.log(found.failure, CONTEXT + '.checkConnection');
		}
		result.checkOk = found.ok;
		result.checkMessage = found.ok
			? connected(processor, found.live)
			: BarnHelp.text(
					'Payments',
					'Payments_Setup_CheckFailed',
					new List<Object>{ processor, found.statusCode == null ? '-' : String.valueOf(found.statusCode) }
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
	 * Makes the address token, or replaces it: the addresses already given to a processor stop
	 * working until the new ones are pasted in. The answer carries the token and the addresses
	 * with it, this once; only its hash is kept.
	 */
	@AuraEnabled
	public static Setup regenerateToken() {
		refuseUnlessManager();
		try {
			return setup(PaymentService.newWebhookToken());
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

	/** Records the org's connection values (run state, synchronous), then answers the page. */
	private static Setup write(Map<String, Object> changes) {
		try {
			if (!changes.isEmpty()) {
				PaymentService.putState(changes);
			}
			return setup();
		} catch (Exception unexpected) {
			throw UserErrors.wrap(unexpected, CONTEXT, true);
		}
	}

	private static Setup setup() {
		return setup(null);
	}

	/**
	 * The page's data. Each address ends in `?token=`, followed by the token only when it was just
	 * made (`token`): the token is not kept, so it is never shown again.
	 */
	private static Setup setup(String token) {
		Setup result = new Setup();
		result.processor = PaymentService.defaultProcessor();
		result.mode = PaymentService.mode();
		result.canManage = HealthCheckService.canManageSettings();
		result.scheduled = PaymentEventProcessor.isScheduled();
		result.hasToken = PaymentService.hasWebhookToken();
		result.token = token;
		String suffix = token == null ? '' : token;
		for (PaymentSites.SiteInfo site : PaymentSites.active()) {
			if (site.url != null) {
				Receiver receiver = new Receiver();
				receiver.site = site.name;
				receiver.stripeUrl = site.url + PaymentSites.RECEIVER_PATH + 'stripe?token=' + suffix;
				receiver.payPalUrl = site.url + PaymentSites.RECEIVER_PATH + 'paypal?token=' + suffix;
				result.receivers.add(receiver);
			}
		}
		String webhookId = PaymentService.stateText(PaymentService.PAYPAL_WEBHOOK_ID);
		KeyStatus webhook = new KeyStatus();
		webhook.name = WEBHOOK_ID;
		webhook.processor = PaymentService.PAYPAL;
		webhook.lastFour = webhookId == null ? null : webhookId.right(4);
		result.keys.add(webhook);
		result.credentials.add(
			credential(
				PaymentService.STRIPE,
				PaymentService.stateFlag(PaymentService.STRIPE_CONNECTED),
				PaymentStripe.CREDENTIAL,
				'Barn_Stripe_Key',
				'SecretKey',
				PaymentStripe.CREDENTIAL
			)
		);
		result.credentials.add(
			credential(
				PaymentService.PAYPAL,
				PaymentService.stateFlag(PaymentService.PAYPAL_CONNECTED),
				PaymentPayPal.CREDENTIAL,
				'Barn_PayPal_App',
				'ClientId, ClientSecret',
				PaymentPayPal.LIVE_BASE.removeStart('callout:') + ', ' + PaymentPayPal.TEST_BASE.removeStart('callout:')
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
