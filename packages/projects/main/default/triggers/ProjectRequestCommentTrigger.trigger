/**
 * The one trigger on Project_Request_Comment__c: routes the saves through the Core dispatcher
 * (ADR-0017, ADR-0024). Emails the requester a shared comment (D-201).
 */
trigger ProjectRequestCommentTrigger on Project_Request_Comment__c(after insert) {
	TriggerDispatcher.run('Project_Request_Comment__c');
}
