/**
 * All SOQL against Appeal__c.
 */
public with sharing class AppealSelector {
	/**
	 * The appeals with the given identifiers.
	 */
	public static List<Appeal__c> selectById(Set<Id> appealIds) {
		return [
			SELECT Id, Name, Parent_Appeal__c, Active__c, Goal__c, Cost__c
			FROM Appeal__c
			WHERE Id IN :appealIds
			WITH USER_MODE
		];
	}

	/**
	 * Parent references only, keyed by identifier, for walking a hierarchy while looking for a
	 * loop (R-AP2).
	 */
	public static Map<Id, Id> selectParentsById(Set<Id> appealIds) {
		Map<Id, Id> parents = new Map<Id, Id>();
		for (Appeal__c appeal : [
			SELECT Id, Parent_Appeal__c
			FROM Appeal__c
			WHERE Id IN :appealIds
			WITH USER_MODE
		]) {
			parents.put(appeal.Id, appeal.Parent_Appeal__c);
		}
		return parents;
	}
}
