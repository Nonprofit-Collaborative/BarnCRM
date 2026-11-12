/**
 * R-EN1 and R-SD1, the person half (QA-F4): an enrollment or a service delivery is for a person. A Contact is a
 * person; an Account is one only when it is a person account. An organization or a household
 * account is refused on every path (the tab's New button, import, the API), not only by the
 * record pickers, which already offer people alone.
 *
 * Whether an account is a person is read by name in system mode, because the person account flag
 * exists only in an org that stores people as accounts (ADR-0013). The answer is a fact about the record,
 * not shown, and no user input reaches the query. In an org without person accounts every
 * account is refused, since none of them can be a person.
 */
public with sharing class ProgramPersonRule {
	private static final String PERSON_ACCOUNTS_QUERY = 'SELECT Id FROM Account WHERE Id IN :accountIds AND IsPersonAccount = true'; // detection-only: run only after isPersonAccountOrg found person accounts

	/**
	 * Adds an error to each record whose Account__c is set and is not a person account. Records
	 * whose person did not change (`oldById` given and the same Account__c) are not checked, so
	 * an existing record is never blocked from other edits.
	 *
	 * @param records enrollments or service deliveries about to be saved
	 * @param oldById the records as they were, or null on insert
	 */
	public static void refuseNonPersonAccounts(List<SObject> records, Map<Id, SObject> oldById) {
		Map<Id, List<SObject>> byAccount = new Map<Id, List<SObject>>();
		for (SObject record : records) {
			Id accountId = (Id) record.get('Account__c');
			SObject old = oldById == null ? null : oldById.get(record.Id);
			if (accountId == null || (old != null && old.get('Account__c') == accountId)) {
				continue;
			}
			if (!byAccount.containsKey(accountId)) {
				byAccount.put(accountId, new List<SObject>());
			}
			byAccount.get(accountId).add(record);
		}
		if (byAccount.isEmpty()) {
			return;
		}
		Set<Id> people = personAccountIds(byAccount.keySet());
		for (Id accountId : byAccount.keySet()) {
			if (people.contains(accountId)) {
				continue;
			}
			for (SObject record : byAccount.get(accountId)) {
				record.addError(
					'Account__c',
					BarnHelp.text('Programs', 'Programs_Person_NotAPerson')
				);
			}
		}
	}

	/** Test seam: the accounts to read as person accounts, for an org without them. */
	@TestVisible
	private static Set<Id> personAccountIdsForTest;

	private static Set<Id> personAccountIds(Set<Id> accountIds) {
		if (personAccountIdsForTest != null) {
			return personAccountIdsForTest;
		}
		if (!HouseholdService.isPersonAccountOrg()) {
			return new Set<Id>();
		}
		return new Map<Id, SObject>(
				Database.queryWithBinds(
					PERSON_ACCOUNTS_QUERY,
					new Map<String, Object>{ 'accountIds' => accountIds },
					AccessLevel.SYSTEM_MODE
				)
			)
			.keySet();
	}
}
