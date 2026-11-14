/**
 * The Corporate Hub page and the document and obligation panels (ADR-0196
 * `0196-corporate-hub-module.md` decision 11). Thin by design (plan Section 9.9): it returns plain
 * shapes and leaves the work to `HubPolicy`, `HubCompliance` and `HubTemplates`, all in user
 * mode. A refusal written for the person, or a validation rule's own words, is shown as it is;
 * anything else is logged and shown as one message.
 */
public with sharing class CorporateHubController {
	private static final String CONTEXT = 'CorporateHubController';
	private static final UserErrors.Screen ERRORS = new UserErrors.Screen(
			CONTEXT,
			'CorporateHub',
			'CorporateHub_Error_Generic'
		)
		.showingDml();
	/** How far ahead the page lists obligations and agreements. */
	private static final Integer OBLIGATION_DAYS = 60;
	private static final Integer AGREEMENT_DAYS = 90;

	/** One line of a list: a record, its name, its date and who or what it concerns. */
	public class Row {
		@AuraEnabled
		public String id;
		@AuraEnabled
		public String name;
		@AuraEnabled
		public Date due;
		@AuraEnabled
		public String detail;
		@AuraEnabled
		public String status;
		/** The record the line opens, when it is not the line's own. */
		@AuraEnabled
		public String recordId;
	}

	/** Everything the Corporate Hub page draws. */
	public class Home {
		@AuraEnabled
		public List<Row> requests = new List<Row>();
		@AuraEnabled
		public List<Row> obligations = new List<Row>();
		@AuraEnabled
		public List<Row> agreements = new List<Row>();
		/** Open data subject requests and breaches not yet reported (CH-05), the person's share. */
		@AuraEnabled
		public List<Row> privacy = new List<Row>();
		@AuraEnabled
		public Boolean canManage = false;
		/** True when the person may create a board or committee and none exists yet (D-200 R4). */
		@AuraEnabled
		public Boolean firstRun = false;
	}

	/** The document panel: its version and who has and has not acknowledged it. */
	public class DocumentStatus {
		@AuraEnabled
		public Integer version;
		@AuraEnabled
		public String status;
		@AuraEnabled
		public Boolean needsAcknowledgment = false;
		@AuraEnabled
		public Integer acknowledged = 0;
		@AuraEnabled
		public Integer outstanding = 0;
		@AuraEnabled
		public List<Row> people = new List<Row>();
		@AuraEnabled
		public Boolean canManage = false;
		@AuraEnabled
		public Boolean canEdit = false;
	}

	@AuraEnabled
	public static Home getHome() {
		try {
			Home home = new Home();
			home.canManage = HubPolicy.canManage();
			home.firstRun =
				Schema.SObjectType.Board__c.isCreateable() &&
				[SELECT Id FROM Board__c WITH USER_MODE LIMIT 1]
				.isEmpty();
			for (Policy_Acknowledgment__c request : HubPolicy.myRequests()) {
				home.requests.add(
					row(
						request.Id,
						request.Document__r.Name,
						request.Due_Date__c,
						null,
						null,
						request.Document__c
					)
				);
			}
			Date until = Date.today().addDays(OBLIGATION_DAYS);
			for (Compliance_Obligation__c obligation : [
				SELECT Id, Name, Due_Date__c, Owner.Name, Category__c
				FROM Compliance_Obligation__c
				WHERE Status__c = 'Active' AND Due_Date__c <= :until
				WITH USER_MODE
				ORDER BY Due_Date__c
				LIMIT 50
			]) {
				home.obligations.add(
					row(
						obligation.Id,
						obligation.Name,
						obligation.Due_Date__c,
						obligation.Owner.Name,
						obligation.Category__c,
						null
					)
				);
			}
			until = Date.today().addDays(AGREEMENT_DAYS);
			for (Agreement__c agreement : [
				SELECT Id, Name, Notice_Date__c, End_Date__c, Owner.Name, Organization__r.Name
				FROM Agreement__c
				WHERE Status__c = 'Active' AND (Notice_Date__c <= :until OR End_Date__c <= :until)
				WITH USER_MODE
				ORDER BY End_Date__c
				LIMIT 50
			]) {
				Date due = agreement.Notice_Date__c == null
					? agreement.End_Date__c
					: agreement.Notice_Date__c;
				home.agreements.add(
					row(
						agreement.Id,
						agreement.Name,
						due,
						agreement.Owner.Name,
						agreement.Organization__r?.Name,
						null
					)
				);
			}
			addPrivacy(home);
			return home;
		} catch (Exception e) {
			throw ERRORS.wrap(e);
		}
	}

	/** CH-05: open requests by due date, then breaches not yet reported by their 72-hour deadline. */
	private static void addPrivacy(Home home) {
		if (Schema.SObjectType.Data_Subject_Request__c.isAccessible()) {
			for (Data_Subject_Request__c request : [
				SELECT Id, Name, Due_Date__c, Owner.Name, Request_Type__c
				FROM Data_Subject_Request__c
				WHERE Status__c IN ('Received', 'In Progress')
				WITH USER_MODE
				ORDER BY Due_Date__c
				LIMIT 50
			]) {
				String title = BarnHelp.text(
					'CorporateHub',
					'CorporateHub_Home_PrivacyRequest',
					new List<Object>{ request.Name }
				);
				home.privacy.add(
					row(
						request.Id,
						title,
						request.Due_Date__c,
						request.Owner.Name,
						request.Request_Type__c,
						null
					)
				);
			}
		}
		if (Schema.SObjectType.Data_Breach__c.isAccessible()) {
			for (Data_Breach__c breach : [
				SELECT Id, Name, Authority_Deadline__c, Owner.Name, Status__c
				FROM Data_Breach__c
				WHERE
					Status__c != 'Closed'
					AND Risk__c != 'Unlikely'
					AND Authority_Notified_At__c = NULL
				WITH USER_MODE
				ORDER BY Discovered_At__c
				LIMIT 50
			]) {
				String title = BarnHelp.text(
					'CorporateHub',
					'CorporateHub_Home_PrivacyBreach',
					new List<Object>{ breach.Name }
				);
				home.privacy.add(
					row(
						breach.Id,
						title,
						breach.Authority_Deadline__c?.date(),
						breach.Owner.Name,
						breach.Status__c,
						null
					)
				);
			}
		}
	}

	@AuraEnabled
	public static DocumentStatus getDocumentStatus(Id documentId) {
		try {
			Hub_Document__c document = HubPolicy.document(documentId);
			DocumentStatus result = new DocumentStatus();
			result.version = document.Version__c == null ? null : document.Version__c.intValue();
			result.status = document.Status__c;
			result.needsAcknowledgment = document.Requires_Acknowledgment__c == true;
			result.canManage = HubPolicy.canManage();
			result.canEdit = Schema.SObjectType.Hub_Document__c.isUpdateable();
			for (Policy_Acknowledgment__c request : HubPolicy.currentRequests(document)) {
				Boolean done = request.Status__c == HubPolicy.ACKNOWLEDGED;
				if (done) {
					result.acknowledged++;
				} else {
					result.outstanding++;
				}
				String who = request.User__c != null
					? request.User__r.Name
					: request.Person__r?.Name;
				Date onDate = done ? request.Acknowledged_On__c?.date() : request.Due_Date__c;
				result.people.add(row(request.Id, who, onDate, null, request.Status__c, null));
			}
			return result;
		} catch (Exception e) {
			throw ERRORS.wrap(e);
		}
	}

	@AuraEnabled
	public static Integer requestAcknowledgments(Id documentId, String groupName) {
		try {
			return HubPolicy.requestAcknowledgments(documentId, groupName);
		} catch (Exception e) {
			throw ERRORS.wrap(e);
		}
	}

	@AuraEnabled
	public static void publishNewVersion(Id documentId) {
		try {
			HubPolicy.publishNewVersion(documentId);
		} catch (Exception e) {
			throw ERRORS.wrap(e);
		}
	}

	@AuraEnabled
	public static void markReviewed(Id documentId) {
		try {
			HubPolicy.markReviewed(documentId);
		} catch (Exception e) {
			throw ERRORS.wrap(e);
		}
	}

	@AuraEnabled
	public static void retire(Id documentId) {
		try {
			HubPolicy.retire(documentId);
		} catch (Exception e) {
			throw ERRORS.wrap(e);
		}
	}

	/** The person's own request, or anyone's for a holder of Manage Corporate Hub. */
	@AuraEnabled
	public static void acknowledge(Id acknowledgmentId) {
		try {
			HubPolicy.acknowledge(acknowledgmentId);
		} catch (Exception e) {
			throw ERRORS.wrap(e);
		}
	}

	@AuraEnabled
	public static Id completeCycle(
		Id obligationId,
		Date completedOn,
		String outcome,
		String notes
	) {
		try {
			return HubCompliance.completeCycle(obligationId, completedOn, outcome, notes);
		} catch (Exception e) {
			throw ERRORS.wrap(e);
		}
	}

	/** Add Missing Templates (R-CT1), for holders of Manage Corporate Hub. */
	@AuraEnabled
	public static Integer addMissingTemplates() {
		try {
			if (!HubPolicy.canManage()) {
				throw new HubPolicy.PolicyException(
					BarnHelp.text('CorporateHub', 'CorporateHub_Policy_NoPermission')
				);
			}
			return HubTemplates.loadMissing(null, false);
		} catch (Exception e) {
			throw ERRORS.wrap(e);
		}
	}

	private static Row row(
		Id id,
		String name,
		Date due,
		String detail,
		String status,
		Id recordId
	) {
		Row line = new Row();
		line.id = id;
		line.name = name;
		line.due = due;
		line.detail = detail;
		line.status = status;
		line.recordId = recordId;
		return line;
	}
}
