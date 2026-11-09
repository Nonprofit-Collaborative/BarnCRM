/**
 * Finds or creates the Core person an event registration is for (ADR-0182
 * `0182-event-registrations.md`, decision 2; canonical model R-ERG1), with Core's shared
 * `PersonMatcher`, the one Forms calls (ADR-0175 decision 7): email, then last name and postal
 * code, each narrowed by first name, then the org's duplicate rules. A key several people hold
 * is never guessed. A guest is looked for in the registrant's household first, and a new guest joins it.
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

	/** Core's shared person matcher (`PersonMatcher`), worded for Events when it is unsure. */
	@TestVisible
	private static Id find(PersonInput input) {
		PersonMatcher.Person person = new PersonMatcher.Person();
		person.firstName = input.firstName;
		person.lastName = input.lastName;
		person.email = input.email;
		person.postalCode = input.postalCode;
		// The duplicate rules compare the four values a registration asks for, trimmed.
		putIfSet(person.duplicateRuleValues, 'FirstName', input.firstName);
		putIfSet(person.duplicateRuleValues, 'LastName', input.lastName);
		putIfSet(person.duplicateRuleValues, 'Email', input.email);
		putIfSet(person.duplicateRuleValues, 'MailingPostalCode', input.postalCode);
		try {
			return PersonMatcher.find(person);
		} catch (PersonMatcher.AmbiguousException several) {
			throw ambiguous();
		}
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
