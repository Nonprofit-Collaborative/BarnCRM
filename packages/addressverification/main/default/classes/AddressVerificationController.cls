/**
 * The Address Verification Setup page (ADR-0209 `0209-address-verification-module.md`,
 * decisions 3 and 5, as amended by ADR-0229;
 * canonical model R-AV4): which provider is chosen and whether it is connected; where each
 * provider's key goes in Setup (External Credential, principal and parameter names, qualified for
 * this org); Check Connection, Clear and Verify Waiting Addresses. No key passes through here.
 * Thin: plain values and every text from the help catalog (plan 9.9).
 *
 * Opened by holders of Address Verification Admin (class access). Checking, clearing and starting
 * the batch also need Manage BarnCRM Settings; the protected setting is written in system mode.
 */
public with sharing class AddressVerificationController {
	private static final String CONTEXT = 'AddressVerificationController';

	/** Where one provider's key is entered in Setup; names only, never a value. */
	public class Credential {
		@AuraEnabled
		public String provider;
		@AuraEnabled
		public Boolean connected;
		@AuraEnabled
		public String externalCredential;
		@AuraEnabled
		public String principal;
		@AuraEnabled
		public String parameters;
	}

	public class Setup {
		@AuraEnabled
		public String provider;
		@AuraEnabled
		public Boolean ready;
		@AuraEnabled
		public Boolean canManage;
		@AuraEnabled
		public List<Credential> credentials = new List<Credential>();
	}

	@AuraEnabled
	public static Setup getSetup() {
		try {
			return setup();
		} catch (Exception unexpected) {
			throw UserErrors.wrap(unexpected, CONTEXT, true);
		}
	}

	/**
	 * Looks one known address up through the provider's Named Credential as the person checking,
	 * then records the provider as connected when it answered 200 (the callout comes before the
	 * write). Returns the message to show.
	 */
	@AuraEnabled
	public static String checkConnection(String provider) {
		refuseUnlessManager();
		refuseUnlessProvider(provider);
		List<Exception> failure = new List<Exception>();
		Integer status = AddressVerifier.checkConnection(provider, failure);
		Boolean ok = status == 200;
		if (ok) {
			remember(provider);
		} else if (AddressVerifier.connectedProvider() == provider) {
			remember(null);
		}
		if (!failure.isEmpty()) {
			ErrorLogger.log(failure[0], CONTEXT + '.checkConnection');
		}
		return ok
			? BarnHelp.text('AddressVerification', 'AddressVerification_Setup_Connected', new List<Object>{ provider })
			: BarnHelp.text(
					'AddressVerification',
					'AddressVerification_Setup_CheckFailed',
					new List<Object>{ provider, status == null ? '-' : String.valueOf(status) }
			  );
	}

	/**
	 * Forgets one provider's connection, so nothing is looked up with it until it is checked
	 * again. The key itself is removed in Setup, on the External Credential.
	 */
	@AuraEnabled
	public static Setup clearKeys(String provider) {
		refuseUnlessManager();
		refuseUnlessProvider(provider);
		if (AddressVerifier.connectedProvider() == provider) {
			remember(null);
		}
		return getSetup();
	}

	/** Starts the nightly batch now; returns the message to show. */
	@AuraEnabled
	public static String verifyWaiting() {
		refuseUnlessManager();
		try {
			return AddressVerificationJob.startBatch() == null
				? BarnHelp.text('AddressVerification', 'AddressVerification_Setup_NotStarted')
				: BarnHelp.text('AddressVerification', 'AddressVerification_Setup_Started');
		} catch (Exception unexpected) {
			throw UserErrors.wrap(unexpected, CONTEXT, true);
		}
	}

	private static void refuseUnlessManager() {
		if (!HealthCheckService.canManageSettings()) {
			throw UserErrors.message(BarnHelp.text('AddressVerification', 'AddressVerification_Setup_NoManage'));
		}
	}

	private static void refuseUnlessProvider(String provider) {
		if (provider != AddressVerifier.SMARTY && provider != AddressVerifier.GOOGLE) {
			throw UserErrors.message(BarnHelp.text('AddressVerification', 'AddressVerification_Error_BadProvider'));
		}
	}

	/** Records which provider is connected (null for none) as run state, at once (SET-03). */
	private static void remember(String provider) {
		try {
			SettingsState.put(new Map<String, Object>{ AddressVerifier.KEY_CONNECTED => provider });
		} catch (Exception unexpected) {
			throw UserErrors.wrap(unexpected, CONTEXT, true);
		}
	}

	private static Setup setup() {
		Setup result = new Setup();
		result.provider = AddressVerifier.provider();
		result.ready = AddressVerifier.isReady();
		result.canManage = HealthCheckService.canManageSettings();
		String connected = AddressVerifier.connectedProvider();
		result.credentials.add(credential(AddressVerifier.SMARTY, connected, 'Barn_Smarty_Key', 'AuthId, AuthToken'));
		result.credentials.add(credential(AddressVerifier.GOOGLE, connected, 'Barn_Google_Address_Key', 'ApiKey'));
		return result;
	}

	private static Credential credential(String provider, String connected, String principal, String parameters) {
		Credential c = new Credential();
		c.provider = provider;
		c.connected = connected == provider;
		c.externalCredential = AddressVerifier.credential(provider);
		c.principal = principal;
		c.parameters = parameters;
		return c;
	}
}
