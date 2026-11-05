/**
 * The one account query the Giving package needs: which record type a donor account carries,
 * so a gift can tell a household giving in its own name from an organization from a person
 * held as an account. The test is made at run time on record type developer names, never on a
 * person account field, so the package installs and behaves in an org where people are
 * contacts (canonical model Section 4, ADR-0009).
 *
 * It is named for its package because class names are unique within a namespace, and Core
 * owns the account queries that everything else uses.
 */
public with sharing class GivingAccountSelector {
	/**
	 * The record type developer name of each of the given accounts. An account with no record
	 * type is absent from the map.
	 */
	public static Map<Id, String> selectRecordTypeNamesById(Set<Id> accountIds) {
		Map<Id, String> names = new Map<Id, String>();
		if (accountIds == null || accountIds.isEmpty()) {
			return names;
		}
		for (Account donorAccount : [
			SELECT Id, RecordTypeId, RecordType.DeveloperName
			FROM Account
			WHERE Id IN :accountIds
			WITH USER_MODE
		]) {
			if (donorAccount.RecordTypeId != null) {
				names.put(donorAccount.Id, donorAccount.RecordType.DeveloperName);
			}
		}
		return names;
	}
}
