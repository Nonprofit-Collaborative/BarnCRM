/**
 * Finds or creates the Core person an event registration is for (ADR-0182
 * `0182-event-registrations.md`, decision 2; canonical model R-ERG1), with Core's matchers only,
 * in the order Forms uses (ADR-0175 decision 7): email, then last name and postal code, each
 * narrowed by first name, then the org's duplicate rules. A key several people hold is never
 * guessed. A guest is looked for in the registrant's household first, and a new guest joins it.
 *
 * Runs with the person's own access: every read is user mode and every write is
 * `AccessLevel.USER_MODE`.
 */
public with sharing class EventPersonMatcher {
	/** Thrown when several people could be the one meant, so staff choose. */
	public class AmbiguousPersonException extends Exception {
	}

	/** One person as a registration names them. */
	public class PersonInput {
		@AuraEnabled
		public String contactId;
		@AuraEnabled
		public String firstName;
		@AuraEnabled
		public String lastName;
		@AuraEnabled
		public String email;
		@AuraEnabled
		public String postalCode;
	}

	/**
	 * The person's record: the one chosen, else the one Core's matchers find, else a new Contact.
	 *
	 * @param input the person as given
	 * @param householdId the registrant's household for a guest, or null for the registrant
	 * @return the Contact's identifier
	 */
	public static Id resolve(PersonInput input, Id householdId) {
		if (input == null) {
			return null;
		}
		if (String.isNotBlank(input.contactId)) {
			return Id.valueOf(input.contactId);
		}
		if (String.isBlank(input.lastName)) {
			throw new AmbiguousPersonException(
				BarnHelp.text('Events', 'Events_Register_LastNameNeeded')
			);
		}
		Id found = householdId == null ? null : inHousehold(input, householdId);
		if (found == null) {
			found = find(input);
		}
		return found != null ? found : create(input, householdId);
	}

	/** The household a person belongs to, or null. */
	public static Id householdOf(Id personId) {
		if (personId == null) {
			return null;
		}
		return HouseholdService.getHouseholdIdsFor(new Set<Id>{ personId }).get(personId);
	}

	/** A household member of the same first and last name, ignoring case and spacing. */
	private static Id inHousehold(PersonInput input, Id householdId) {
		List<HouseholdService.Person> members = HouseholdService.getMembersAsUser(
				new Set<Id>{ householdId }
			)
			.get(householdId);
		if (members == null) {
			return null;
		}
		String first = ImportMatcher.comparableFirstName(input.firstName);
		String last = ImportMatcher.nameKey(input.lastName);
		Id match;
		for (HouseholdService.Person member : members) {
			if (
				ImportMatcher.comparableFirstName(member.firstName) == first &&
				ImportMatcher.nameKey(member.lastName) == last
			) {
				if (match != null) {
					throw ambiguous();
				}
				match = member.id;
			}
		}
		return match;
	}

	@TestVisible
	private static Id find(PersonInput input) {
		ImportMatcher.forgetHeldKeys();
		String emailKey = ImportMatcher.emailKey(input.email);
		if (emailKey != null) {
			Id found = byKey(
				ImportMatcher.contactsByEmail(new Set<String>{ emailKey }),
				emailKey,
				input.firstName
			);
			if (found != null) {
				return found;
			}
		}
		String namePostal = ImportMatcher.nameAndPostalKey(input.lastName, input.postalCode);
		if (namePostal != null) {
			Id found = byKey(
				ImportMatcher.contactsByNameAndPostalCode(new Set<String>{ namePostal }),
				namePostal,
				input.firstName
			);
			if (found != null) {
				return found;
			}
		}
		return byDuplicateRules(input);
	}

	/** The holder of a key, narrowed by first name when one is given (R-IB12). */
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
					throw ambiguous();
				}
				return found.get(candidate);
			}
		}
		return null;
	}

	private static Id byDuplicateRules(PersonInput input) {
		Map<String, String> values = new Map<String, String>();
		putIfSet(values, 'FirstName', input.firstName);
		putIfSet(values, 'LastName', input.lastName);
		putIfSet(values, 'Email', input.email);
		putIfSet(values, 'MailingPostalCode', input.postalCode);
		SObject probe = ImportDuplicateRuleMatcher.probe(Contact.SObjectType, values, null);
		List<List<SObject>> matches = ImportDuplicateRuleMatcher.matchesFor(
			new List<SObject>{ probe },
			null
		);
		if (matches == null || matches.isEmpty() || matches[0].isEmpty()) {
			return null;
		}
		if (matches[0].size() > 1) {
			throw ambiguous();
		}
		return matches[0][0].Id;
	}

	/**
	 * A new Contact. A guest joins the registrant's household in Contact membership mode; in
	 * Junction mode, and for a registrant, Core makes the household as for any new person.
	 */
	private static Id create(PersonInput input, Id householdId) {
		Contact person = new Contact(
			FirstName = trimmed(input.firstName),
			LastName = trimmed(input.lastName),
			Email = trimmed(input.email),
			MailingPostalCode = trimmed(input.postalCode)
		);
		if (householdId != null && !HouseholdService.isJunctionMode()) {
			person.AccountId = householdId;
		}
		insert as user person;
		return person.Id;
	}

	private static void putIfSet(Map<String, String> values, String field, String value) {
		if (String.isNotBlank(value)) {
			values.put(field, value.trim());
		}
	}

	private static String trimmed(String value) {
		return String.isBlank(value) ? null : value.trim();
	}

	private static AmbiguousPersonException ambiguous() {
		return new AmbiguousPersonException(BarnHelp.text('Events', 'Events_Register_ManyPeople'));
	}
}
