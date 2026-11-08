/**
 * What a person's Contact Points should be, worked out from plain maps (R-CPL2; ADR-0176 contact
 * point sync module, decisions 4 and 13). No query, no DML, no describe: the service reads the
 * records, hands their values here, and writes what comes back, so the rules can be tested and
 * ported on their own (plan 9.9).
 */
public with sharing class ContactPointPlan {
	public static final String EMAIL = 'Email';
	public static final String PHONE = 'Phone';
	public static final String ADDRESS = 'Address';

	/** Email sources in order of precedence; the standard field last, so a duplicate keeps the named one. */
	@TestVisible
	private static final List<String> EMAIL_FIELDS = new List<String>{
		'Personal_Email__c',
		'Work_Email__c',
		'Alternate_Email__c',
		'Email'
	};

	/** Phone sources in order of precedence; the standard field last, as for email. */
	@TestVisible
	private static final List<String> PHONE_FIELDS = new List<String>{
		'HomePhone',
		'MobilePhone',
		'Work_Phone__c',
		'OtherPhone',
		'Phone'
	};

	/** The Contact Point Phone type each phone source stands for (blank for none). */
	private static final Map<String, String> PHONE_TYPE_BY_FIELD = new Map<String, String>{
		'HomePhone' => 'Home',
		'MobilePhone' => 'Mobile',
		'Work_Phone__c' => 'Work',
		'OtherPhone' => '',
		'Phone' => ''
	};

	/** The person fields the plan reads, for the service's query and the handler's change check. */
	public static List<String> personFields() {
		List<String> fields = new List<String>(EMAIL_FIELDS);
		fields.addAll(PHONE_FIELDS);
		return fields;
	}

	/**
	 * The field a person stored as an account holds a person field's value on: the standard
	 * field's person name (`Email` is `PersonEmail`), a custom field's `__pc` twin. Plain text,
	 * so a person account's changes can be read without naming a field the org may lack.
	 */
	public static String accountFieldFor(String personField) {
		if (personField.endsWith('__c')) {
			return personField.removeEnd('__c') + '__pc';
		}
		// The account's own Phone is the phone on the person behind it.
		return personField == 'Phone' ? 'Phone' : 'Person' + personField;
	}

	/** The account fields a person account's saves are checked against, one per person field. */
	public static List<String> accountFields() {
		List<String> fields = new List<String>();
		for (String field : personFields()) {
			fields.add(accountFieldFor(field));
		}
		return fields;
	}

	/**
	 * Whether the person has an email or phone to copy for the kinds given: the same answer as
	 * `plan` having an email or phone in it, without building it. Asked of every person in a
	 * save, most of whom have neither (ADR-0176 decision 16).
	 */
	public static Boolean hasEmailOrPhone(Map<String, Object> person, Set<String> kinds) {
		if (person == null || kinds == null) {
			return false;
		}
		if (kinds.contains(EMAIL)) {
			for (String field : EMAIL_FIELDS) {
				if (normalEmail(text(person.get(field))) != null) {
					return true;
				}
			}
		}
		if (kinds.contains(PHONE)) {
			for (String field : PHONE_FIELDS) {
				if (digits(text(person.get(field))) != null) {
					return true;
				}
			}
		}
		return false;
	}

	/** One Contact Point the person should have. */
	public class Desired {
		public String kind;
		/** A person field name or an address record ID: with the kind, the link's key. */
		public String source;
		/** Field name to value, in Contact Point field names. */
		public Map<String, Object> values = new Map<String, Object>();

		public String key() {
			return keyOf(kind, source);
		}

		public String matchKey() {
			return ContactPointPlan.matchKey(kind, values);
		}
	}

	public static String keyOf(String kind, String source) {
		return kind + '|' + source;
	}

	/**
	 * The person's Contact Points for the kinds given.
	 *
	 * @param person the person's field values, by the names in `personFields`
	 * @param addresses the person's current addresses (own and household), as `Address__c` values
	 * @param kinds the kinds being kept in step
	 */
	public static List<Desired> plan(
		Map<String, Object> person,
		List<Map<String, Object>> addresses,
		Set<String> kinds
	) {
		List<Desired> result = new List<Desired>();
		if (person == null || kinds == null) {
			return result;
		}
		if (kinds.contains(EMAIL)) {
			result.addAll(emails(person));
		}
		if (kinds.contains(PHONE)) {
			result.addAll(phones(person));
		}
		if (kinds.contains(ADDRESS) && addresses != null) {
			for (Map<String, Object> row : addresses) {
				Desired wanted = addressOf(row);
				if (wanted != null) {
					result.add(wanted);
				}
			}
		}
		return result;
	}

	private static List<Desired> emails(Map<String, Object> person) {
		List<Desired> result = new List<Desired>();
		String preferred = normalEmail(text(person.get('Email')));
		Set<String> seen = new Set<String>();
		for (String field : EMAIL_FIELDS) {
			String value = text(person.get(field));
			String normal = normalEmail(value);
			if (normal == null || seen.contains(normal)) {
				continue;
			}
			seen.add(normal);
			Desired wanted = new Desired();
			wanted.kind = EMAIL;
			wanted.source = field;
			wanted.values.put('EmailAddress', value.trim());
			wanted.values.put('IsPrimary', normal == preferred);
			result.add(wanted);
		}
		return result;
	}

	private static List<Desired> phones(Map<String, Object> person) {
		List<Desired> result = new List<Desired>();
		String preferred = digits(text(person.get('Phone')));
		Set<String> seen = new Set<String>();
		for (String field : PHONE_FIELDS) {
			String value = text(person.get(field));
			String normal = digits(value);
			if (normal == null || seen.contains(normal)) {
				continue;
			}
			seen.add(normal);
			Desired wanted = new Desired();
			wanted.kind = PHONE;
			wanted.source = field;
			wanted.values.put('TelephoneNumber', value.trim());
			wanted.values.put('IsPrimary', normal == preferred);
			String phoneType = PHONE_TYPE_BY_FIELD.get(field);
			if (String.isNotBlank(phoneType)) {
				wanted.values.put('PhoneType', phoneType);
			}
			result.add(wanted);
		}
		return result;
	}

	/** A current address, or null for a former, undeliverable or empty one. */
	private static Desired addressOf(Map<String, Object> row) {
		String status = text(row.get('Status__c'));
		if (String.isNotBlank(status) && status != 'Current') {
			return null;
		}
		String street = text(row.get('Street__c'));
		String city = text(row.get('City__c'));
		String postal = text(row.get('Postal_Code__c'));
		if (String.isBlank(street) && String.isBlank(city) && String.isBlank(postal)) {
			return null;
		}
		Boolean isDefault = row.get('Is_Default__c') == true;
		String type = text(row.get('Type__c'));
		Desired wanted = new Desired();
		wanted.kind = ADDRESS;
		wanted.source = text(row.get('Id'));
		wanted.values.put('Street', street);
		wanted.values.put('City', city);
		wanted.values.put('State', text(row.get('State__c')));
		wanted.values.put('PostalCode', postal);
		wanted.values.put('Country', text(row.get('Country__c')));
		wanted.values.put('IsDefault', isDefault);
		wanted.values.put('IsPrimary', isDefault);
		wanted.values.put('Name', String.isBlank(type) ? ADDRESS : type);
		return wanted;
	}

	/**
	 * What makes two Contact Points of a kind the same value, for adopting one BarnCRM did not
	 * make: the email case ignored, the phone's digits, the street, city and postal code.
	 */
	public static String matchKey(String kind, Map<String, Object> values) {
		if (values == null) {
			return null;
		}
		if (kind == EMAIL) {
			return normalEmail(text(values.get('EmailAddress')));
		}
		if (kind == PHONE) {
			return digits(text(values.get('TelephoneNumber')));
		}
		String joined = (blankAsEmpty(values.get('Street')) +
			'|' +
			blankAsEmpty(values.get('City')) +
			'|' +
			blankAsEmpty(values.get('PostalCode')))
			.toLowerCase()
			.normalizeSpace();
		return joined == '||' ? null : joined;
	}

	/** The fields of `wanted` whose value `current` does not already hold. */
	public static Set<String> differences(Map<String, Object> wanted, Map<String, Object> current) {
		Set<String> result = new Set<String>();
		for (String field : wanted.keySet()) {
			Object have = current == null ? null : current.get(field);
			if (blankAsEmpty(wanted.get(field)) != blankAsEmpty(have)) {
				result.add(field);
			}
		}
		return result;
	}

	private static String text(Object value) {
		return value == null ? null : String.valueOf(value);
	}

	private static String blankAsEmpty(Object value) {
		return value == null ? '' : String.valueOf(value);
	}

	private static String normalEmail(String value) {
		return String.isBlank(value) ? null : value.trim().toLowerCase();
	}

	private static String digits(String value) {
		if (String.isBlank(value)) {
			return null;
		}
		String only = value.replaceAll('[^0-9]', '');
		return String.isEmpty(only) ? null : only;
	}
}
