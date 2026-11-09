/**
 * Finds the one Contact a person a module names already is, with Core's matchers only, in one
 * order for every caller (ADR-0175 decision 7, ADR-0182 decision 2): `ImportMatcher` by email,
 * then last name and postal code, each narrowed by first name (R-IB12), then the org's
 * duplicate rules (`ImportDuplicateRuleMatcher`). A key several people hold is never guessed
 * (R-FS2): the caller hears `AmbiguousException` and words it for its own screen.
 *
 * Forms and Events both call it. Nothing here writes; every read runs as the person.
 */
@NamespaceAccessible
public with sharing class PersonMatcher {
	/** Thrown when several people could be the one meant; the caller supplies the wording. */
	@NamespaceAccessible
	public class AmbiguousException extends Exception {
	}

	/** The person as the caller has them. */
	@NamespaceAccessible
	public class Person {
		@NamespaceAccessible
		public String firstName;
		@NamespaceAccessible
		public String lastName;
		@NamespaceAccessible
		public String email;
		@NamespaceAccessible
		public String postalCode;
		/** False skips the last name and postal code step (a form set to match by email only). */
		@NamespaceAccessible
		public Boolean byNameAndPostalCode = true;
		/**
		 * The values the org's duplicate rules compare, keyed by Contact field API name. Each
		 * caller passes its own: blank or empty skips the duplicate rule step.
		 */
		@NamespaceAccessible
		public Map<String, String> duplicateRuleValues = new Map<String, String>();
	}

	/**
	 * The Contact the person already is, or null when nobody matches.
	 *
	 * @param person the person as given
	 * @return the Contact's identifier, or null
	 * @throws AmbiguousException when several people match one step
	 */
	@NamespaceAccessible
	public static Id find(Person person) {
		if (person == null) {
			return null;
		}
		ImportMatcher.forgetHeldKeys();
		String emailKey = ImportMatcher.emailKey(person.email);
		if (emailKey != null) {
			Id found = byKey(
				ImportMatcher.contactsByEmail(new Set<String>{ emailKey }),
				emailKey,
				person.firstName
			);
			if (found != null) {
				return found;
			}
		}
		String namePostal = ImportMatcher.nameAndPostalKey(person.lastName, person.postalCode);
		if (person.byNameAndPostalCode != false && namePostal != null) {
			Id found = byKey(
				ImportMatcher.contactsByNameAndPostalCode(new Set<String>{ namePostal }),
				namePostal,
				person.firstName
			);
			if (found != null) {
				return found;
			}
		}
		return byDuplicateRules(person.duplicateRuleValues);
	}

	/**
	 * The holder of a key. With a first name, only a holder of that first name, or one with no
	 * first name, is taken, so one of two people sharing an email is never taken for the other
	 * (R-IB12). Without one, a key held by several is never guessed (R-FS2).
	 */
	private static Id byKey(Map<String, Id> found, String key, String first) {
		List<String> keys = String.isNotBlank(first)
			? new List<String>{
					ImportMatcher.firstNameKey(key, first),
					ImportMatcher.firstNameKey(key, null)
			  }
			: new List<String>{ key };
		for (String candidate : keys) {
			if (found.containsKey(candidate)) {
				if (ImportMatcher.isHeldByMany(candidate)) {
					throw new AmbiguousException();
				}
				return found.get(candidate);
			}
		}
		return null;
	}

	/** The org's own duplicate rules, when one is active: one match is taken, several held. */
	private static Id byDuplicateRules(Map<String, String> values) {
		if (values == null || values.isEmpty()) {
			return null;
		}
		SObject probe = ImportDuplicateRuleMatcher.probe(Contact.SObjectType, values, null);
		List<List<SObject>> matches = ImportDuplicateRuleMatcher.matchesFor(
			new List<SObject>{ probe },
			null
		);
		if (matches == null || matches.isEmpty() || matches[0].isEmpty()) {
			return null;
		}
		if (matches[0].size() > 1) {
			throw new AmbiguousException();
		}
		return matches[0][0].Id;
	}
}
