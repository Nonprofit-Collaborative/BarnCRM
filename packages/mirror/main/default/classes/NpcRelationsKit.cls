/**
 * The Nonprofit Cloud Relationships and Affiliations kit's rows (MIG-02, relations part;
 * canonical model R-MK1), named by the kit `NPC_Relations`. A Contact Contact Relation becomes
 * one BarnCRM relationship (BarnCRM writes the other side itself, so where Nonprofit Cloud holds
 * both directions only one is copied); an Account Contact Relation becomes an affiliation,
 * except with a household (an account with a Party Relationship Group of type Household) or a
 * person account, which are not organizations. Households themselves are not converted (plan
 * Section 11.2 item 9). Nonprofit Cloud is read by describe only, in the running user's access;
 * its names are text here, and Mirror may name standard objects as text (plan Section 4.2).
 * Core builds this class by name (ADR-0017).
 */
@NamespaceAccessible
public with sharing class NpcRelationsKit implements MigrationKitExtension {
	@TestVisible
	private static final String KIT = 'NPC_Relations';
	private static final Integer MOST = 50000;

	@NamespaceAccessible
	public NpcRelationsKit() {
		// Built by name from the kit's Extension Class; holds no state.
		return;
	}

	@NamespaceAccessible
	public List<Map<String, Object>> rows(String stepKey, List<SObject> records) {
		List<Map<String, Object>> rows = new MigrationKitService.Source(
				MigrationKitService.stepNamed(MigrationKitService.kitNamed(KIT), stepKey)
			)
			.rows(records);
		if (stepKey == 'relationships') {
			return oneSide(rows, reversed(rows));
		}
		return organizations(rows, notOrganizations(column(rows, 'AccountId')));
	}

	/** Each step's check: what there is to copy, and how much of it BarnCRM now has. */
	@NamespaceAccessible
	public MigrationCheck verify(String stepKey) {
		Set<String> wanted = new Set<String>();
		Set<String> have = new Set<String>();
		if (stepKey == 'relationships') {
			for (
				SObject link : read(
					'SELECT ContactId, RelatedContactId FROM ContactContactRelation LIMIT ' + // detection-only: text
					MOST,
					null
				)
			) {
				wanted.add(
					pair((String) link.get('ContactId'), (String) link.get('RelatedContactId'))
				);
			}
			for (Relationship__c held : [
				SELECT Contact__c, Related_Contact__c
				FROM Relationship__c
				WITH USER_MODE
				LIMIT :MOST
			]) {
				have.add(pair(held.Contact__c, held.Related_Contact__c));
			}
		} else {
			List<SObject> links = read(
				'SELECT ContactId, AccountId FROM AccountContactRelation LIMIT ' + // detection-only: text
				MOST,
				null
			);
			Set<String> accounts = new Set<String>();
			for (SObject link : links) {
				accounts.add((String) link.get('AccountId'));
			}
			Set<String> skipped = notOrganizations(accounts);
			for (SObject link : links) {
				String account = (String) link.get('AccountId');
				if (!skipped.contains(account)) {
					wanted.add((String) link.get('ContactId') + account);
				}
			}
			for (Affiliation__c held : [
				SELECT Contact__c, Organization__c
				FROM Affiliation__c
				WITH USER_MODE
				LIMIT :MOST
			]) {
				have.add(held.Contact__c + '' + held.Organization__c);
			}
		}
		Integer done = 0;
		for (String key : wanted) {
			done += have.contains(key) ? 1 : 0;
		}
		return new MigrationCheck(wanted.size(), done);
	}

	/**
	 * The relationship rows to copy: where the same two people are also related the other way
	 * round, only the row whose person Id sorts first.
	 */
	@TestVisible
	private static List<Map<String, Object>> oneSide(
		List<Map<String, Object>> rows,
		Set<String> reversed
	) {
		List<Map<String, Object>> result = new List<Map<String, Object>>();
		for (Map<String, Object> row : rows) {
			String contact = (String) row.get('ContactId');
			String related = (String) row.get('RelatedContactId');
			if (!reversed.contains(related + contact) || contact < related) {
				result.add(row);
			}
		}
		return result;
	}

	/** The affiliation rows with an organization, each role list as text. */
	@TestVisible
	private static List<Map<String, Object>> organizations(
		List<Map<String, Object>> rows,
		Set<String> skipped
	) {
		List<Map<String, Object>> result = new List<Map<String, Object>>();
		for (Map<String, Object> row : rows) {
			if (skipped.contains((String) row.get('AccountId'))) {
				continue;
			}
			String roles = (String) row.get('Roles');
			row.put('Role', String.isBlank(roles) ? '' : roles.replace(';', ', '));
			result.add(row);
		}
		return result;
	}

	/** The pairs (contact then related) also held the other way round. */
	private static Set<String> reversed(List<Map<String, Object>> rows) {
		Set<String> contacts = column(rows, 'ContactId');
		Set<String> related = column(rows, 'RelatedContactId');
		Set<String> result = new Set<String>();
		if (contacts.isEmpty() || related.isEmpty()) {
			return result;
		}
		for (
			SObject link : Database.queryWithBinds(
				'SELECT ContactId, RelatedContactId FROM ContactContactRelation' + // detection-only: text
				' WHERE ContactId IN :related AND RelatedContactId IN :contacts',
				new Map<String, Object>{ 'related' => related, 'contacts' => contacts },
				AccessLevel.USER_MODE
			)
		) {
			result.add((String) link.get('ContactId') + (String) link.get('RelatedContactId'));
		}
		return result;
	}

	/** Of these accounts, the households and person accounts. */
	private static Set<String> notOrganizations(Set<String> ids) {
		Set<String> result = new Set<String>();
		if (ids.isEmpty()) {
			return result;
		}
		for (
			SObject grouped : read(
				'SELECT AccountId FROM PartyRelationshipGroup' + // detection-only: text
				' WHERE AccountId IN :ids AND Type = \'Household\'',
				ids
			)
		) {
			result.add((String) grouped.get('AccountId'));
		}
		if (Schema.SObjectType.Account.fields.getMap().containsKey('ispersonaccount')) {
			for (
				SObject person : Database.queryWithBinds(
					'SELECT Id FROM Account WHERE Id IN :ids AND IsPersonAccount = true',
					new Map<String, Object>{ 'ids' => ids },
					AccessLevel.USER_MODE
				)
			) {
				result.add(person.Id);
			}
		}
		return result;
	}

	/** The distinct non-blank values of one column. */
	private static Set<String> column(List<Map<String, Object>> rows, String name) {
		Set<String> result = new Set<String>();
		for (Map<String, Object> row : rows) {
			if (String.isNotBlank((String) row.get(name))) {
				result.add((String) row.get(name));
			}
		}
		return result;
	}

	/** Two people as one key, whichever way round they are named. */
	private static String pair(String one, String other) {
		return one < other ? one + other : other + one;
	}

	/** The records of a Nonprofit Cloud object, in the user's access; none without it. */
	private static List<SObject> read(String query, Set<String> ids) {
		String objectName = query.substringAfter(' FROM ').substringBefore(' ').trim();
		if (!NamespaceUtil.globalDescribe().containsKey(objectName.toLowerCase())) {
			return new List<SObject>();
		}
		// Every name is Nonprofit Cloud's own, fixed here; the only value is a bind.
		return Database.queryWithBinds(
			query,
			new Map<String, Object>{ 'ids' => ids },
			AccessLevel.USER_MODE
		);
	}
}
