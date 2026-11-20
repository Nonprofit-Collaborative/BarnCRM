/**
 * The reads behind Health Check's "no person" findings: relationships and affiliations whose
 * person lookup is blank because the person was deleted (PEOPLE-19). The person lookups are
 * set to blank when a person is deleted, so the other side's relationship or the affiliation is
 * left naming nobody. A merge repoints these rows and never leaves them blank.
 *
 * A side counts as blank when neither of its two lookups (contact, person account) is set,
 * which is the same test the relationship and affiliation domains refuse a save on. Reads run
 * in user mode and stop at the cap they are given. Detection only; nothing here writes.
 */
@NamespaceAccessible
public with sharing class PersonLinkOrphanSelector {
	@NamespaceAccessible
	public static Integer countRelationships(Integer cap) {
		return [
			SELECT COUNT()
			FROM Relationship__c
			WHERE
				(Contact__c = NULL
				AND Person_Account__c = NULL)
				OR (Related_Contact__c = NULL
				AND Related_Person_Account__c = NULL)
			WITH USER_MODE
			LIMIT :cap
		];
	}

	@NamespaceAccessible
	public static List<Relationship__c> relationships(Integer howMany) {
		return [
			SELECT Id, Name
			FROM Relationship__c
			WHERE
				(Contact__c = NULL
				AND Person_Account__c = NULL)
				OR (Related_Contact__c = NULL
				AND Related_Person_Account__c = NULL)
			WITH USER_MODE
			ORDER BY CreatedDate, Id
			LIMIT :howMany
		];
	}

	@NamespaceAccessible
	public static Integer countAffiliations(Integer cap) {
		return [
			SELECT COUNT()
			FROM Affiliation__c
			WHERE Contact__c = NULL AND Person_Account__c = NULL
			WITH USER_MODE
			LIMIT :cap
		];
	}

	@NamespaceAccessible
	public static List<Affiliation__c> affiliations(Integer howMany) {
		return [
			SELECT Id, Name
			FROM Affiliation__c
			WHERE Contact__c = NULL AND Person_Account__c = NULL
			WITH USER_MODE
			ORDER BY CreatedDate, Id
			LIMIT :howMany
		];
	}
}
