/**
 * Looks addresses up with the org's own provider and writes what it learned (ADR-0209
 * `0209-address-verification-module.md`, decisions 2 to 5; canonical model R-AV1 to R-AV3).
 *
 * Every callout is made first and every write after, since Salesforce allows no callout after a
 * write in one transaction. Only Verification Status and Latest Verified Date are written, plus
 * the standardized street, city, state and postal code when Apply Corrections is on. Writes run
 * in user mode as the person whose save or job it is; a refused write is logged, never raised.
 *
 * Every lookup goes through the provider's Named Credential (`Barn_Smarty`, `Barn_Google_Address`);
 * the key is the External Credential principal's, merged into a header by Salesforce and never
 * read by Apex (R-AV4; ADR-0229). The person whose
 * save or job it is needs principal access: Address Verification Admin or Address Verification
 * User. Without it the lookup fails, is logged, and the address stays Unverified for the night.
 */
public with sharing class AddressVerifier {
	public static final String MODULE = 'AddressVerification';
	public static final String SMARTY = 'Smarty';
	public static final String GOOGLE = 'Google';
	public static final String VERIFIED = 'Verified';
	public static final String FAILED = 'Failed';
	public static final String UNVERIFIED = 'Unverified';
	/** Lookups one transaction makes, inside the 100 callouts Salesforce allows. */
	public static final Integer PER_TRANSACTION = 50;
	/**
	 * Lookups stop after this long: a transaction allows 120 seconds of callouts and one lookup may
	 * wait 20, so the rest stay Unverified for the next run.
	 */
	@TestVisible
	private static Long calloutBudgetMs = 95000;
	/** The fields whose change makes an address Unverified (R-AV2). */
	public static final List<Schema.SObjectField> WATCHED = new List<Schema.SObjectField>{
		Address__c.Street__c,
		Address__c.City__c,
		Address__c.State__c,
		Address__c.Postal_Code__c,
		Address__c.Country__c
	};
	/** Country values Smarty's United States service takes, in capitals (blank counts too). */
	public static final Set<String> US_NAMES = new Set<String>{
		'US',
		'USA',
		'U.S.',
		'U.S.A.',
		'UNITED STATES',
		'UNITED STATES OF AMERICA'
	};
	private static final Map<String, String> REGION_BY_NAME = new Map<String, String>{
		'united states' => 'US',
		'united states of america' => 'US',
		'usa' => 'US',
		'canada' => 'CA',
		'united kingdom' => 'GB',
		'great britain' => 'GB',
		'australia' => 'AU',
		'new zealand' => 'NZ',
		'ireland' => 'IE',
		'germany' => 'DE',
		'france' => 'FR',
		'mexico' => 'MX'
	};
	/** Paths under the `Barn_Smarty` and `Barn_Google_Address` Named Credentials. */
	private static final String SMARTY_PATH = '/street-address';
	private static final String GOOGLE_PATH = '/v1:validateAddress';
	private static final String CONTEXT = 'AddressVerifier';

	/** True while the module saves addresses, so its own handler leaves them alone (R-AV2). */
	public static Boolean writing = false;

	/** Set when a lookup's callout failed outright; the rest of the run is left for later. */
	private static Boolean calloutFailed = false;

	/** What one lookup found: a status, and the standardized parts when verified. */
	public class Outcome {
		public String status;
		public String street;
		public String city;
		public String state;
		public String postalCode;

		public Outcome(String status) {
			this.status = status;
		}
	}

	/** Run state: the provider Check Connection last reached (`AddressVerification.Connected_Provider__c`). */
	public static final String KEY_CONNECTED = SettingsState.moduleKey(MODULE, 'Connected_Provider__c');

	// The org-wide choices, read through the settings store: an unsaved one is its shipped value.

	/** Whether a saved address is looked up as it is saved. Ships on. */
	public static Boolean verifyOnSave() {
		return ModuleSettings.flag('Address_Verification_On_Save');
	}

	/** Whether verified corrections are written to the address. Ships off. */
	public static Boolean applyCorrections() {
		return ModuleSettings.flag('Address_Verification_Corrections');
	}

	/** Months before a verified address is looked up again; 0 never re-checks. */
	public static Integer recheckMonths() {
		return ModuleSettings.integerValue('Address_Verification_Recheck');
	}

	/** Addresses looked up per night. */
	public static Integer nightlyLimit() {
		return ModuleSettings.integerValue('Address_Verification_Nightly_Limit');
	}

	public static String provider() {
		return ModuleSettings.text('Address_Verification_Provider') == GOOGLE ? GOOGLE : SMARTY;
	}

	/** The provider last connected, or null (run state, written when Check Connection runs). */
	public static String connectedProvider() {
		return SettingsState.text(KEY_CONNECTED);
	}

	/**
	 * Whether the chosen provider is connected: Check Connection on the setup page last reached it
	 * through its Named Credential (R-AV4). No key is read; Apex never holds one.
	 */
	public static Boolean isReady() {
		return connectedProvider() == provider();
	}

	private static final List<String> ACCESS_SETS = new List<String>{
		'Address_Verification_User',
		'Address_Verification_Admin'
	};
	@TestVisible
	private static Boolean userAccess;
	@TestVisible
	private static Boolean noAccessChecked = false;

	/**
	 * Whether the person saving holds `Address_Verification_User` or `Address_Verification_Admin`
	 * (the principal access a lookup on save runs with), read once per transaction. A person
	 * without it is not looked up on save; the nightly step covers their addresses.
	 */
	public static Boolean canLookUpOnSave() {
		if (userAccess == null) {
			Id me = UserInfo.getUserId();
			userAccess =
				[
					SELECT COUNT()
					FROM PermissionSetAssignment
					WHERE AssigneeId = :me AND PermissionSet.Name IN :ACCESS_SETS
					WITH SYSTEM_MODE
				] > 0;
		}
		return userAccess;
	}

	/** Logs the missing access as one Warning a day, not one per save. */
	public static void logNoAccessOnce() {
		if (noAccessChecked) {
			return;
		}
		noAccessChecked = true;
		Datetime dayAgo = Datetime.now().addDays(-1);
		String context = CONTEXT + '.noAccess';
		if (
			[
				SELECT COUNT()
				FROM Error_Log__c
				WHERE Context__c = :context AND CreatedDate > :dayAgo
				WITH SYSTEM_MODE
			] == 0
		) {
			ErrorLogger.logMessage(
				'An address was saved by someone without Address Verification User or Admin, so it waits for the nightly check. Give them the permission set on the Access page to look up their saves at once.',
				context,
				ErrorLogger.SEVERITY_WARNING
			);
		}
	}

	/** The Named Credential of a provider, qualified for this org. */
	public static String credential(String provider) {
		return NamespaceUtil.qualify(provider == GOOGLE ? 'Barn_Google_Address' : 'Barn_Smarty');
	}

	/**
	 * A test lookup of one known address through the provider's Named Credential, for Check
	 * Connection. Never throws and writes nothing: the HTTP status (200 when the provider took the
	 * key), or null with the exception in `failure` (no principal access, nothing entered).
	 */
	public static Integer checkConnection(String provider, List<Exception> failure) {
		Address__c sample = new Address__c(
			Street__c = '1600 Amphitheatre Pkwy',
			City__c = 'Mountain View',
			State__c = 'CA',
			Postal_Code__c = '94043',
			Country__c = 'US'
		);
		try {
			return new Http().send(provider == GOOGLE ? googleRequest(sample) : smartyRequest(sample)).getStatusCode();
		} catch (Exception failed) {
			failure.add(failed);
			return null;
		}
	}

	/** Whether the module is turned on in the Module Manager. */
	public static Boolean isOn() {
		return !ModuleManagerService.turnedOff().contains(MODULE.toLowerCase());
	}

	/** Whether the chosen provider can look this address up (Smarty: United States only). */
	public static Boolean supports(Address__c address) {
		return provider() == GOOGLE || isUnitedStates(address.Country__c);
	}

	public static Boolean isUnitedStates(String country) {
		return String.isBlank(country) || US_NAMES.contains(country.trim().toUpperCase());
	}

	/**
	 * Looks up each Current address of the given ones the provider supports, at most
	 * `PER_TRANSACTION`, then writes the outcomes. Returns how many were looked up.
	 */
	public static Integer verify(List<Id> addressIds) {
		if (addressIds == null || addressIds.isEmpty() || !isReady()) {
			return 0;
		}
		Map<Id, Outcome> found = new Map<Id, Outcome>();
		List<Address__c> looked = new List<Address__c>();
		Integer providerErrors = 0;
		Long started = System.currentTimeMillis();
		for (Address__c address : [
			SELECT Id, Street__c, City__c, State__c, Postal_Code__c, Country__c, Status__c
			FROM Address__c
			WHERE Id IN :addressIds AND (Status__c = 'Current' OR Status__c = NULL)
			WITH USER_MODE
			LIMIT :PER_TRANSACTION
		]) {
			if (!supports(address) || String.isBlank(address.Street__c)) {
				continue;
			}
			if (calloutFailed || System.currentTimeMillis() - started > calloutBudgetMs) {
				break;
			}
			Outcome outcome = lookUp(address);
			if (outcome == null) {
				providerErrors++;
				continue;
			}
			found.put(address.Id, outcome);
			looked.add(address);
		}
		if (providerErrors > 0) {
			ErrorLogger.logMessage(
				BarnHelp.text(
					'AddressVerification',
					'AddressVerification_Error_Provider',
					new List<Object>{ provider(), providerErrors }
				),
				CONTEXT + '.verify',
				ErrorLogger.SEVERITY_WARNING
			);
		}
		write(looked, found);
		return looked.size();
	}

	private static void write(List<Address__c> looked, Map<Id, Outcome> found) {
		if (looked.isEmpty()) {
			return;
		}
		Boolean correct = applyCorrections();
		List<Address__c> changes = new List<Address__c>();
		for (Address__c address : looked) {
			Outcome outcome = found.get(address.Id);
			Address__c change = new Address__c(Id = address.Id, Verification_Status__c = outcome.status);
			if (outcome.status == VERIFIED) {
				change.Latest_Verified_Date__c = Date.today();
				if (correct) {
					putIfGiven(change, Address__c.Street__c, outcome.street);
					putIfGiven(change, Address__c.City__c, outcome.city);
					putIfGiven(change, Address__c.State__c, outcome.state);
					putIfGiven(change, Address__c.Postal_Code__c, outcome.postalCode);
				}
			}
			changes.add(change);
		}
		writing = true;
		try {
			List<Database.SaveResult> results = Database.update(changes, false, AccessLevel.USER_MODE);
			List<Id> changedIds = new List<Id>();
			for (SObject change : changes) {
				changedIds.add(change.Id);
			}
			ErrorLogger.logFailures(results, changedIds, CONTEXT + '.write', ErrorLogger.SEVERITY_WARNING);
		} finally {
			writing = false;
		}
	}

	private static void putIfGiven(Address__c change, Schema.SObjectField field, String value) {
		if (String.isNotBlank(value)) {
			change.put(field, value.left(field.getDescribe().getLength()));
		}
	}

	/**
	 * One lookup; null when the provider did not answer usefully (the address stays as it is). A
	 * callout that fails before any answer (no principal access for this person, nothing entered
	 * on the credential, or the network) stops the run's other lookups, so one cause is logged
	 * once, not once per address.
	 */
	@TestVisible
	private static Outcome lookUp(Address__c address) {
		try {
			return provider() == GOOGLE ? google(address) : smarty(address);
		} catch (CalloutException failed) {
			calloutFailed = true;
			ErrorLogger.log(failed, CONTEXT + '.lookUp', address.Id);
			return null;
		} catch (Exception failed) {
			ErrorLogger.log(failed, CONTEXT + '.lookUp', address.Id);
			return null;
		}
	}

	/**
	 * Smarty's secret key pair goes in an `Authorization: Basic` header (Smarty accepts it there
	 * as well as in the query string), merged by Salesforce from the `Barn_Smarty` External
	 * Credential, so the key never appears in Apex or in a logged address.
	 */
	@SuppressWarnings('PMD.ApexSuggestUsingNamedCred')
	private static HttpRequest smartyRequest(Address__c address) {
		String principal = '$Credential.' + credential(SMARTY);
		HttpRequest request = new HttpRequest();
		request.setMethod('GET');
		request.setTimeout(20000);
		request.setHeader(
			'Authorization',
			'Basic {!BASE64ENCODE(BLOB(' + principal + '.AuthId & ":" & ' + principal + '.AuthToken))}'
		);
		request.setEndpoint(
			'callout:' +
				credential(SMARTY) +
				SMARTY_PATH +
				'?candidates=1&street=' +
				encode(address.Street__c) +
				'&city=' +
				encode(address.City__c) +
				'&state=' +
				encode(address.State__c) +
				'&zipcode=' +
				encode(address.Postal_Code__c)
		);
		return request;
	}

	private static Outcome smarty(Address__c address) {
		HttpResponse response = new Http().send(smartyRequest(address));
		if (response.getStatusCode() != 200) {
			return null;
		}
		List<Object> candidates = (List<Object>) JSON.deserializeUntyped(response.getBody());
		if (candidates.isEmpty()) {
			return new Outcome(FAILED);
		}
		Map<String, Object> candidate = (Map<String, Object>) candidates[0];
		Map<String, Object> analysis = mapOf(candidate.get('analysis'));
		String code = String.valueOf(analysis.get('dpv_match_code'));
		if (code != 'Y' && code != 'S' && code != 'D') {
			return new Outcome(FAILED);
		}
		Map<String, Object> parts = mapOf(candidate.get('components'));
		Outcome outcome = new Outcome(VERIFIED);
		outcome.street = joined(new List<Object>{ candidate.get('delivery_line_1'), candidate.get('delivery_line_2') });
		outcome.city = textOf(parts.get('city_name'));
		outcome.state = textOf(parts.get('state_abbreviation'));
		String plus4 = textOf(parts.get('plus4_code'));
		outcome.postalCode = textOf(parts.get('zipcode')) + (String.isBlank(plus4) ? '' : '-' + plus4);
		return outcome;
	}

	/**
	 * Google's key goes in the `X-Goog-Api-Key` header, merged by Salesforce from the
	 * `Barn_Google_Address` External Credential.
	 */
	private static HttpRequest googleRequest(Address__c address) {
		Map<String, Object> given = new Map<String, Object>{
			'addressLines' => linesOf(address.Street__c),
			'locality' => address.City__c,
			'administrativeArea' => address.State__c,
			'postalCode' => address.Postal_Code__c
		};
		String region = regionOf(address.Country__c);
		if (region != null) {
			given.put('regionCode', region);
		} else if (String.isNotBlank(address.Country__c)) {
			((List<String>) given.get('addressLines')).add(address.Country__c);
		}
		HttpRequest request = new HttpRequest();
		request.setMethod('POST');
		request.setTimeout(20000);
		request.setHeader('Content-Type', 'application/json');
		request.setHeader('X-Goog-Api-Key', '{!$Credential.' + credential(GOOGLE) + '.ApiKey}');
		request.setEndpoint('callout:' + credential(GOOGLE) + GOOGLE_PATH);
		request.setBody(JSON.serialize(new Map<String, Object>{ 'address' => given }, true));
		return request;
	}

	private static Outcome google(Address__c address) {
		HttpResponse response = new Http().send(googleRequest(address));
		if (response.getStatusCode() != 200) {
			return null;
		}
		Map<String, Object> result = mapOf(
			((Map<String, Object>) JSON.deserializeUntyped(response.getBody())).get('result')
		);
		Map<String, Object> verdict = mapOf(result.get('verdict'));
		String granularity = textOf(verdict.get('validationGranularity'));
		if (
			(granularity != 'PREMISE' && granularity != 'SUB_PREMISE') ||
			verdict.get('hasUnconfirmedComponents') == true
		) {
			return new Outcome(FAILED);
		}
		Map<String, Object> postal = mapOf(mapOf(result.get('address')).get('postalAddress'));
		Outcome outcome = new Outcome(VERIFIED);
		outcome.street = joined(
			postal.get('addressLines') instanceof List<Object>
				? (List<Object>) postal.get('addressLines')
				: new List<Object>()
		);
		outcome.city = textOf(postal.get('locality'));
		outcome.state = textOf(postal.get('administrativeArea'));
		outcome.postalCode = textOf(postal.get('postalCode'));
		return outcome;
	}

	/** A two-letter country code as is, a known country name as its code, else null. */
	@TestVisible
	private static String regionOf(String country) {
		if (String.isBlank(country)) {
			return null;
		}
		String trimmed = country.trim();
		if (trimmed.length() == 2 && trimmed.isAlpha()) {
			return trimmed.toUpperCase();
		}
		return REGION_BY_NAME.get(trimmed.toLowerCase());
	}

	private static List<String> linesOf(String street) {
		List<String> lines = new List<String>();
		for (String line : (street == null ? '' : street).split('\n')) {
			if (String.isNotBlank(line)) {
				lines.add(line.trim());
			}
		}
		return lines;
	}

	private static String joined(List<Object> lines) {
		List<String> kept = new List<String>();
		for (Object line : lines) {
			if (line != null && String.isNotBlank(String.valueOf(line))) {
				kept.add(String.valueOf(line));
			}
		}
		return String.join(kept, '\n');
	}

	private static Map<String, Object> mapOf(Object value) {
		return value instanceof Map<String, Object> ? (Map<String, Object>) value : new Map<String, Object>();
	}

	private static String textOf(Object value) {
		return value == null ? null : String.valueOf(value);
	}

	private static String encode(String value) {
		return EncodingUtil.urlEncode(value == null ? '' : value, 'UTF-8');
	}
}
