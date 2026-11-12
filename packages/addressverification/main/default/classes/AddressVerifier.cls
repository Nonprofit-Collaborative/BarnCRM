/**
 * Looks addresses up with the org's own provider and writes what it learned (ADR-NEXT
 * `NEXT-address-verification-module.md`, decisions 2 to 5; canonical model R-AV1 to R-AV3).
 *
 * Every callout is made first and every write after, since Salesforce allows no callout after a
 * write in one transaction. Only Verification Status and Latest Verified Date are written, plus
 * the standardized street, city, state and postal code when Apply Corrections is on. Writes run
 * in user mode as the person whose save or job it is; a refused write is logged, never raised.
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
	private static final String SMARTY_URL = 'https://us-street.api.smarty.com/street-address';
	private static final String GOOGLE_URL = 'https://addressvalidation.googleapis.com/v1:validateAddress';
	private static final String CONTEXT = 'AddressVerifier';

	/** True while the module saves addresses, so its own handler leaves them alone (R-AV2). */
	public static Boolean writing = false;

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

	/** The org-wide choices, each blank one at its default; never saved, the shipped values. */
	public static Address_Verification_Settings__c settings() {
		Address_Verification_Settings__c stored = Address_Verification_Settings__c.getOrgDefaults();
		if (stored.Id == null) {
			// getOrgDefaults() returns checkboxes false, not their shipped value (ADR-0035).
			stored.Verify_On_Save__c = true;
		}
		if (String.isBlank(stored.Provider__c)) {
			stored.Provider__c = SMARTY;
		}
		if (stored.Recheck_Months__c == null) {
			stored.Recheck_Months__c = 12;
		}
		if (stored.Nightly_Limit__c == null) {
			stored.Nightly_Limit__c = 200;
		}
		return stored;
	}

	public static String provider() {
		return settings().Provider__c == GOOGLE ? GOOGLE : SMARTY;
	}

	/** The org's keys. Read in Apex only: no permission set grants the setting (R-AV4). */
	public static Address_Verification_Keys__c keys() {
		return Address_Verification_Keys__c.getOrgDefaults();
	}

	/** Whether the chosen provider's keys are entered. */
	public static Boolean isReady() {
		Address_Verification_Keys__c stored = keys();
		return provider() == GOOGLE
			? String.isNotBlank(stored.Google_Api_Key__c)
			: String.isNotBlank(stored.Smarty_Auth_Id__c) &&
			  String.isNotBlank(stored.Smarty_Auth_Token__c);
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
			if (System.currentTimeMillis() - started > calloutBudgetMs) {
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
		Boolean correct = settings().Apply_Corrections__c == true;
		List<Address__c> changes = new List<Address__c>();
		for (Address__c address : looked) {
			Outcome outcome = found.get(address.Id);
			Address__c change = new Address__c(
				Id = address.Id,
				Verification_Status__c = outcome.status
			);
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
			List<Database.SaveResult> results = Database.update(
				changes,
				false,
				AccessLevel.USER_MODE
			);
			for (Integer i = 0; i < results.size(); i++) {
				if (!results[i].isSuccess()) {
					ErrorLogger.logMessage(
						results[i].getErrors()[0].getMessage(),
						CONTEXT + '.write',
						ErrorLogger.SEVERITY_WARNING,
						changes[i].Id
					);
				}
			}
		} finally {
			writing = false;
		}
	}

	private static void putIfGiven(Address__c change, Schema.SObjectField field, String value) {
		if (String.isNotBlank(value)) {
			change.put(field, value.left(field.getDescribe().getLength()));
		}
	}

	/** One lookup; null when the provider did not answer usefully (the address stays as it is). */
	@TestVisible
	private static Outcome lookUp(Address__c address) {
		try {
			return provider() == GOOGLE ? google(address) : smarty(address);
		} catch (Exception failed) {
			ErrorLogger.log(failed, CONTEXT + '.lookUp', address.Id);
			return null;
		}
	}

	private static Outcome smarty(Address__c address) {
		Address_Verification_Keys__c stored = keys();
		HttpRequest request = new HttpRequest();
		request.setMethod('GET');
		request.setTimeout(20000);
		request.setEndpoint(
			SMARTY_URL +
				'?auth-id=' +
				encode(stored.Smarty_Auth_Id__c) +
				'&auth-token=' +
				encode(stored.Smarty_Auth_Token__c) +
				'&candidates=1&street=' +
				encode(address.Street__c) +
				'&city=' +
				encode(address.City__c) +
				'&state=' +
				encode(address.State__c) +
				'&zipcode=' +
				encode(address.Postal_Code__c)
		);
		HttpResponse response = new Http().send(request);
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
		outcome.street = joined(
			new List<Object>{ candidate.get('delivery_line_1'), candidate.get('delivery_line_2') }
		);
		outcome.city = textOf(parts.get('city_name'));
		outcome.state = textOf(parts.get('state_abbreviation'));
		String plus4 = textOf(parts.get('plus4_code'));
		outcome.postalCode =
			textOf(parts.get('zipcode')) + (String.isBlank(plus4) ? '' : '-' + plus4);
		return outcome;
	}

	private static Outcome google(Address__c address) {
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
		request.setEndpoint(GOOGLE_URL + '?key=' + encode(keys().Google_Api_Key__c));
		request.setBody(JSON.serialize(new Map<String, Object>{ 'address' => given }, true));
		HttpResponse response = new Http().send(request);
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
		return value instanceof Map<String, Object>
			? (Map<String, Object>) value
			: new Map<String, Object>();
	}

	private static String textOf(Object value) {
		return value == null ? null : String.valueOf(value);
	}

	private static String encode(String value) {
		return EncodingUtil.urlEncode(value == null ? '' : value, 'UTF-8');
	}
}
