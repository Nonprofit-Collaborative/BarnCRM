/**
 * One Project Resource per person (canonical model 29PM6): a second made by hand is ignored, the
 * oldest wins. The one place that rule lives, for the Staffing page, rate stamping and the
 * utilization capacity.
 */
public with sharing class ProjectResources {
	/** The resources by person, from rows the caller queried ordered by CreatedDate, oldest first. */
	public static Map<Id, Project_Resource__c> byUser(List<Project_Resource__c> oldestFirst) {
		Map<Id, Project_Resource__c> byUser = new Map<Id, Project_Resource__c>();
		for (Project_Resource__c resource : oldestFirst) {
			if (!byUser.containsKey(resource.User__c)) {
				byUser.put(resource.User__c, resource);
			}
		}
		return byUser;
	}
}
