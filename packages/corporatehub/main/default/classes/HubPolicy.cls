/**
 * Library documents and their acknowledgments (CH-01, CH-02; canonical model R-HD1, R-HD2,
 * R-PAK1 to R-PAK3). Everything runs as the person, in user mode; publishing, retiring, asking
 * people and recording for someone else also need the custom permission Manage Corporate Hub.
 *
 * The reads in system mode are who holds a BarnCRM role and who is in a public group: Id lists
 * from setup data that a Corporate Hub admin without View Setup could not read, used only to
 * address requests.
 */
public with sharing class HubPolicy {
	public static final String MANAGE = 'Corporate_Hub_Manage';
	public static final String REQUESTED = 'Requested';
	public static final String ACKNOWLEDGED = 'Acknowledged';
	public static final String SUPERSEDED = 'Superseded';

	/** The Core sets and roles that mean "this person uses BarnCRM" (R-PAK2). */
	private static final Set<String> BARNCRM_SETS = new Set<String>{
		'BarnCRM_Admin',
		'BarnCRM_Staff',
		'BarnCRM_Read_Only'
	};
	private static final Set<String> BARNCRM_ROLES = new Set<String>{
		'BarnCRM_Admin_Group',
		'Program_Staff',
		'Fundraising_Staff',
		'Read_Only'
	};

	/** A refusal written for the person. */
	public class PolicyException extends Exception {
	}

	public static Boolean canManage() {
		return FeatureManagement.checkPermission(MANAGE);
	}

	/**
	 * Asks everyone with a BarnCRM role, or the active direct user members of one public group, to
	 * acknowledge the document's current version. Nobody is asked twice for one version.
	 *
	 * @param documentId the document
	 * @param groupName a public group's developer name, or blank for everyone with a BarnCRM role
	 * @return how many people were asked
	 */
	public static Integer requestAcknowledgments(Id documentId, String groupName) {
		requireManage();
		Hub_Document__c document = document(documentId);
		if (document.Status__c != 'Active' || document.Requires_Acknowledgment__c != true) {
			throw new PolicyException(
				BarnHelp.text('CorporateHub', 'CorporateHub_Policy_NotAskable')
			);
		}
		Set<Id> userIds = String.isBlank(groupName) ? barnCrmUsers() : groupUsers(groupName);
		return ask(document, userIds, new Set<Id>());
	}

	/**
	 * R-PAK4 (CH-12): asks the board's current seat holders, as Person rows owned by the
	 * requester. Nobody is notified: they answer in the board portal or on paper.
	 */
	public static Integer requestFromBoard(Id documentId, Id boardId) {
		requireManage();
		Hub_Document__c document = document(documentId);
		if (document.Status__c != 'Active' || document.Requires_Acknowledgment__c != true) {
			throw new PolicyException(
				BarnHelp.text('CorporateHub', 'CorporateHub_Policy_NotAskable')
			);
		}
		Set<Id> personIds = new Set<Id>();
		for (Board_Member__c seat : HubBoard.currentSeats(boardId)) {
			personIds.add(seat.Person__c);
		}
		return ask(document, new Set<Id>(), personIds);
	}

	/** R-HD1: the next version, Active from today; open requests superseded and asked again. */
	public static void publishNewVersion(Id documentId) {
		requireManage();
		Hub_Document__c document = document(documentId);
		Integer previous = document.Version__c == null ? 0 : document.Version__c.intValue();
		Set<Id> userIds = new Set<Id>();
		Set<Id> personIds = new Set<Id>();
		for (Policy_Acknowledgment__c row : [
			SELECT User__c, Person__c
			FROM Policy_Acknowledgment__c
			WHERE Document__c = :documentId AND Version__c = :previous
			WITH USER_MODE
		]) {
			if (row.User__c != null) {
				userIds.add(row.User__c);
			} else if (row.Person__c != null) {
				personIds.add(row.Person__c);
			}
		}
		supersedeOpen(documentId);
		document.Version__c = previous + 1;
		document.Status__c = 'Active';
		document.Effective_Date__c = Date.today();
		update as user document;
		if (document.Requires_Acknowledgment__c == true) {
			ask(document, userIds, personIds);
		}
	}

	/** R-HD2: reviewed today, next review one interval on. Needs only edit access. */
	public static void markReviewed(Id documentId) {
		Hub_Document__c document = document(documentId);
		Integer months = document.Review_Months__c == null
			? 12
			: document.Review_Months__c.intValue();
		document.Last_Reviewed_On__c = Date.today();
		document.Review_Date__c = Date.today().addMonths(Math.max(1, months));
		update as user document;
	}

	/** R-HD2: retired today; a retired document asks no one, so open requests are superseded. */
	public static void retire(Id documentId) {
		requireManage();
		Hub_Document__c document = document(documentId);
		document.Status__c = 'Retired';
		document.Retired_On__c = Date.today();
		update as user document;
		supersedeOpen(documentId);
	}

	/**
	 * Marks one request Acknowledged: the person's own, or, for a holder of Manage Corporate Hub,
	 * anyone's (a paper attestation). The validation rule `Own_Acknowledgment` enforces the same.
	 */
	public static void acknowledge(Id acknowledgmentId) {
		Policy_Acknowledgment__c row = [
			SELECT Id, Status__c, User__c
			FROM Policy_Acknowledgment__c
			WHERE Id = :acknowledgmentId
			WITH USER_MODE
		];
		if (row.Status__c != REQUESTED) {
			throw new PolicyException(BarnHelp.text('CorporateHub', 'CorporateHub_Policy_NotOpen'));
		}
		if (row.User__c != UserInfo.getUserId()) {
			requireManage();
		}
		row.Status__c = ACKNOWLEDGED;
		row.Acknowledged_On__c = System.now();
		update as user row;
	}

	/** The current user's open requests, soonest due first. */
	public static List<Policy_Acknowledgment__c> myRequests() {
		Id me = UserInfo.getUserId();
		return [
			SELECT Id, Document__c, Document__r.Name, Version__c, Due_Date__c
			FROM Policy_Acknowledgment__c
			WHERE User__c = :me AND Status__c = :REQUESTED
			WITH USER_MODE
			ORDER BY Due_Date__c NULLS LAST
			LIMIT 100
		];
	}

	/** Every request for the document's current version, outstanding first. */
	public static List<Policy_Acknowledgment__c> currentRequests(Hub_Document__c document) {
		return [
			SELECT
				Id,
				Status__c,
				Due_Date__c,
				Acknowledged_On__c,
				User__c,
				User__r.Name,
				Person__c,
				Person__r.Name
			FROM Policy_Acknowledgment__c
			WHERE
				Document__c = :document.Id
				AND Version__c = :document.Version__c
				AND Status__c != :SUPERSEDED
			WITH USER_MODE
			ORDER BY Status__c DESC, Due_Date__c
			LIMIT 2000
		];
	}

	public static Hub_Document__c document(Id documentId) {
		return [
			SELECT
				Id,
				Name,
				Status__c,
				Version__c,
				Requires_Acknowledgment__c,
				Annual__c,
				Review_Months__c,
				Review_Date__c,
				Effective_Date__c
			FROM Hub_Document__c
			WHERE Id = :documentId
			WITH USER_MODE
		];
	}

	private static void requireManage() {
		if (!canManage()) {
			throw new PolicyException(
				BarnHelp.text('CorporateHub', 'CorporateHub_Policy_NoPermission')
			);
		}
	}

	private static void supersedeOpen(Id documentId) {
		List<Policy_Acknowledgment__c> open = [
			SELECT Id
			FROM Policy_Acknowledgment__c
			WHERE Document__c = :documentId AND Status__c = :REQUESTED
			WITH USER_MODE
			LIMIT 10000
		];
		for (Policy_Acknowledgment__c row : open) {
			row.Status__c = SUPERSEDED;
		}
		update as user open;
	}

	/** R-PAK1, R-PAK2: one request per person not yet asked for this version; users are notified. */
	private static Integer ask(Hub_Document__c document, Set<Id> userIds, Set<Id> personIds) {
		Integer version = document.Version__c.intValue();
		Set<String> asked = new Set<String>();
		for (Policy_Acknowledgment__c row : [
			SELECT Key__c
			FROM Policy_Acknowledgment__c
			WHERE Document__c = :document.Id AND Version__c = :version
			WITH USER_MODE
		]) {
			asked.add(row.Key__c);
		}
		Date due = Date.today().addDays(CorporateHubSettings.acknowledgmentDays());
		List<Policy_Acknowledgment__c> rows = new List<Policy_Acknowledgment__c>();
		Set<Id> everyone = new Set<Id>(userIds);
		everyone.addAll(personIds);
		// R-PAK1: an Ask Every Year document carries the year, so the same version is asked yearly.
		String stem =
			document.Id +
			':' +
			version +
			(document.Annual__c == true ? ':' + Date.today().year() : '') +
			':';
		for (Id personId : everyone) {
			String key = stem + personId;
			if (asked.contains(key)) {
				continue;
			}
			Boolean isUser = userIds.contains(personId);
			rows.add(
				new Policy_Acknowledgment__c(
					Document__c = document.Id,
					Version__c = version,
					User__c = isUser ? personId : null,
					Person__c = isUser ? null : personId,
					OwnerId = isUser ? personId : UserInfo.getUserId(),
					Status__c = REQUESTED,
					Requested_On__c = Date.today(),
					Due_Date__c = due,
					Key__c = key
				)
			);
		}
		Set<String> notified = new Set<String>();
		Integer created = 0;
		List<Database.SaveResult> results = Database.insert(rows, false, AccessLevel.USER_MODE);
		for (Integer i = 0; i < results.size(); i++) {
			if (results[i].isSuccess()) {
				created++;
				if (rows[i].User__c != null) {
					notified.add(rows[i].User__c);
				}
			}
		}
		HubReminders.notify(
			notified,
			BarnHelp.text(
				'CorporateHub',
				'CorporateHub_Policy_RequestTitle',
				new List<Object>{ document.Name }
			),
			BarnHelp.text('CorporateHub', 'CorporateHub_Policy_RequestBody'),
			document.Id
		);
		return created;
	}

	private static Set<Id> barnCrmUsers() {
		Set<Id> ids = new Set<Id>();
		for (PermissionSetAssignment row : [
			SELECT AssigneeId
			FROM PermissionSetAssignment
			WHERE
				Assignee.IsActive = TRUE
				AND (PermissionSet.Name IN :BARNCRM_SETS
				OR PermissionSetGroup.DeveloperName IN :BARNCRM_ROLES)
			WITH SYSTEM_MODE
			LIMIT 10000
		]) {
			ids.add(row.AssigneeId);
		}
		return ids;
	}

	private static Set<Id> groupUsers(String groupName) {
		Set<Id> memberIds = new Set<Id>();
		for (GroupMember member : [
			SELECT UserOrGroupId
			FROM GroupMember
			WHERE Group.DeveloperName = :groupName AND Group.Type = 'Regular'
			WITH SYSTEM_MODE
			LIMIT 10000
		]) {
			if (member.UserOrGroupId.getSObjectType() == User.SObjectType) {
				memberIds.add(member.UserOrGroupId);
			}
		}
		return new Map<Id, User>(
				[SELECT Id FROM User WHERE Id IN :memberIds AND IsActive = TRUE WITH SYSTEM_MODE]
			)
			.keySet();
	}
}
