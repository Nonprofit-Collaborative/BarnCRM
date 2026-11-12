/**
 * The Address Verification Setup page (ADR-0209 `0209-address-verification-module.md`,
 * decisions 3 and 5; canonical model R-AV4): which provider is chosen, whether each key is
 * entered (its last four characters only), Save Keys, Clear and Verify Waiting Addresses. Keys
 * are write-only. Thin: plain values and every text from the help catalog (plan 9.9).
 *
 * Opened by holders of Address Verification Admin (class access). Saving, clearing and starting
 * the batch also need Manage BarnCRM Settings; the protected setting is written in system mode,
 * since no permission set grants its fields.
 */
public with sharing class AddressVerificationController {
	private static final String CONTEXT = 'AddressVerificationController';

	@TestVisible
	private static final Map<String, Schema.SObjectField> FIELDS = new Map<String, Schema.SObjectField>{
		'smartyAuthId' => Address_Verification_Keys__c.Smarty_Auth_Id__c,
		'smartyAuthToken' => Address_Verification_Keys__c.Smarty_Auth_Token__c,
		'googleApiKey' => Address_Verification_Keys__c.Google_Api_Key__c
	};
	private static final Map<String, List<String>> BY_PROVIDER = new Map<String, List<String>>{
		AddressVerifier.SMARTY => new List<String>{ 'smartyAuthId', 'smartyAuthToken' },
		AddressVerifier.GOOGLE => new List<String>{ 'googleApiKey' }
	};

	public class KeyStatus {
		@AuraEnabled
		public String name;
		@AuraEnabled
		public String provider;
		/** Null when not entered; otherwise the last four characters only. */
		@AuraEnabled
		public String lastFour;
	}

	public class Setup {
		@AuraEnabled
		public String provider;
		@AuraEnabled
		public Boolean ready;
		@AuraEnabled
		public Boolean canManage;
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
		Address_Verification_Keys__c stored = stored();
		Map<String, String> given = keys == null ? new Map<String, String>() : keys;
		for (String name : given.keySet()) {
			String value = given.get(name)?.trim();
			if (FIELDS.containsKey(name) && String.isNotBlank(value)) {
				stored.put(
					FIELDS.get(name),
					value.left(FIELDS.get(name).getDescribe().getLength())
				);
			}
		}
		return write(stored);
	}

	/** Removes every key of one provider. */
	@AuraEnabled
	public static Setup clearKeys(String provider) {
		refuseUnlessManager();
		if (!BY_PROVIDER.containsKey(provider)) {
			throw UserErrors.message(
				BarnHelp.text('AddressVerification', 'AddressVerification_Error_BadProvider')
			);
		}
		Address_Verification_Keys__c stored = stored();
		for (String name : BY_PROVIDER.get(provider)) {
			stored.put(FIELDS.get(name), null);
		}
		return write(stored);
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
			throw UserErrors.message(
				BarnHelp.text('AddressVerification', 'AddressVerification_Setup_NoManage')
			);
		}
	}

	private static Address_Verification_Keys__c stored() {
		Address_Verification_Keys__c stored = Address_Verification_Keys__c.getOrgDefaults();
		stored.SetupOwnerId = UserInfo.getOrganizationId();
		return stored;
	}

	private static Setup write(Address_Verification_Keys__c stored) {
		try {
			upsert as system stored;
			return setup();
		} catch (Exception unexpected) {
			throw UserErrors.wrap(unexpected, CONTEXT, true);
		}
	}

	private static Setup setup() {
		Setup result = new Setup();
		result.provider = AddressVerifier.provider();
		result.ready = AddressVerifier.isReady();
		result.canManage = HealthCheckService.canManageSettings();
		Address_Verification_Keys__c stored = AddressVerifier.keys();
		for (String provider : BY_PROVIDER.keySet()) {
			for (String name : BY_PROVIDER.get(provider)) {
				KeyStatus key = new KeyStatus();
				key.name = name;
				key.provider = provider;
				String value = (String) stored.get(FIELDS.get(name));
				key.lastFour = String.isBlank(value) ? null : value.right(4);
				result.keys.add(key);
			}
		}
		return result;
	}
}
