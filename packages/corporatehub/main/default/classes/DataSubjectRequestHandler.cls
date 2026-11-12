/**
 * Data Subject Request due date (CH-05; canonical model R-DS1), run by the Core trigger
 * dispatcher through the registry row `Data_Subject_Request_Due`.
 *
 * The due date is one month (30 days) from the day the request was received. A blank Due Date
 * takes Received Date plus 30. When the Received Date changes and the Due Date is still the
 * old Received Date plus 30 (never edited), it follows the new date. A Due Date a person set
 * stays as set, and stays editable.
 */
@NamespaceAccessible
public with sharing class DataSubjectRequestHandler extends TriggerHandler {
	private static final Integer DAYS = 30;

	@NamespaceAccessible
	public DataSubjectRequestHandler() {
		return;
	}

	public override String getName() {
		return 'DataSubjectRequestHandler';
	}

	public override void beforeInsert() {
		fill((List<Data_Subject_Request__c>) newRecords(), null);
	}

	public override void beforeUpdate() {
		fill((List<Data_Subject_Request__c>) newRecords(), oldRecordsById());
	}

	@TestVisible
	private static void fill(List<Data_Subject_Request__c> requests, Map<Id, SObject> oldById) {
		for (Data_Subject_Request__c request : requests) {
			if (request.Received_Date__c == null) {
				continue;
			}
			Date due = request.Received_Date__c.addDays(DAYS);
			if (request.Due_Date__c == null) {
				request.Due_Date__c = due;
				continue;
			}
			Data_Subject_Request__c before = oldById == null
				? null
				: (Data_Subject_Request__c) oldById.get(request.Id);
			if (
				before != null &&
				before.Received_Date__c != null &&
				before.Received_Date__c != request.Received_Date__c &&
				request.Due_Date__c == before.Due_Date__c &&
				before.Due_Date__c == before.Received_Date__c.addDays(DAYS)
			) {
				request.Due_Date__c = due;
			}
		}
	}
}
