/**
 * The request rules (registry rows `Project_Request_Rules` on Request and
 * `Project_Request_Comment_Notices` on Request Comment, both Always Runs; ADR-0221
 * `0221-projects-requests-and-issues.md` decision 3, canonical model R-PM23 to R-PM25).
 *
 * Before save: the channel, the external switch, the due date from the priority, the
 * requesting organization from the requester, Resolved Date, and a portal save that keeps the
 * request's own fields as they were. After save: a requester's reply becomes a shared comment,
 * owners get a bell notice, requesters an email. Notices and emails never fail a save.
 */
@NamespaceAccessible
public with sharing class ProjectRequestHandler extends TriggerHandler {
	public static final String STAFF = 'Staff';
	public static final String PORTAL = 'Portal';
	public static final String PARTNER = 'Partner Organization';
	public static final String IN_PROGRESS = 'In Progress';
	public static final String RESOLVED = 'Resolved';
	private static final Set<String> FINISHED = new Set<String>{ RESOLVED, 'Closed' };
	private static final Set<String> REOPENED_BY_REPLY = new Set<String>{
		'Waiting on Requester',
		RESOLVED
	};
	/** The fields a requester sets once, when sending; a portal save keeps them as they were. */
	private static final List<String> SENT_FIELDS = new List<String>{
		'Subject__c',
		'Description__c',
		'Type__c',
		'Category__c',
		'Priority__c'
	};
	/** Bell notices kept to this many a transaction, so a bulk load cannot flood the bell. */
	private static final Integer NOTICE_CAP = 50;
	private static final String NOTICE_TYPE = 'Projects_Request';
	private static final String CONTEXT = 'ProjectRequestHandler';

	/** Replies taken off requests before save, written as comments after it. */
	private static Map<Id, String> replies = new Map<Id, String>();

	/** Every notice title and email subject handed on this transaction, for the tests. */
	@TestVisible
	private static List<String> sent = new List<String>();

	@NamespaceAccessible
	public ProjectRequestHandler() {
		return;
	}

	public override void beforeInsert() {
		if (isComment()) {
			return;
		}
		Boolean canCreate = Schema.SObjectType.Project_Request__c.isCreateable();
		List<Project_Request__c> needAccount = new List<Project_Request__c>();
		Id me = UserInfo.getUserId();
		for (Project_Request__c row : (List<Project_Request__c>) newRecords()) {
			if (row.Channel__c == null) {
				row.Channel__c = canCreate ? STAFF : PORTAL;
			}
			if (row.Channel__c != STAFF) {
				if (!ProjectsSettings.requestsExternalEnabled()) {
					row.addError(BarnHelp.text('Projects', 'Projects_Requests_ExternalOff'));
				}
				// A request from outside is never left with the integration user that saved it.
				if (row.OwnerId == null || row.OwnerId == me) {
					Id queue = new Elevated().requestsQueue();
					row.OwnerId = queue == null ? row.OwnerId : queue;
				}
			}
			if (row.Due_Date__c == null) {
				row.Due_Date__c = addWeekdays(
					Date.today(),
					ProjectsSettings.requestDueDays(row.Priority__c)
				);
			}
			if (row.Account__c == null && row.Requester__c != null) {
				needAccount.add(row);
			}
			row.Reply__c = null;
			stampResolved(row, null);
		}
		if (!needAccount.isEmpty()) {
			new Elevated().fillAccounts(needAccount);
		}
	}

	public override void beforeUpdate() {
		if (isComment()) {
			return;
		}
		Boolean canEdit = Schema.SObjectType.Project_Request__c.isUpdateable();
		Map<Id, SObject> before = oldRecordsById();
		for (Project_Request__c row : (List<Project_Request__c>) newRecords()) {
			Project_Request__c old = (Project_Request__c) before.get(row.Id);
			if (!canEdit) {
				for (String field : SENT_FIELDS) {
					row.put(field, old.get(field));
				}
			}
			if (String.isNotBlank(row.Reply__c)) {
				replies.put(row.Id, row.Reply__c);
				row.Reply__c = null;
				if (REOPENED_BY_REPLY.contains(row.Status__c)) {
					row.Status__c = IN_PROGRESS;
				}
			}
			stampResolved(row, old);
		}
	}

	public override void afterInsert() {
		if (isComment()) {
			emailSharedComments((List<Project_Request_Comment__c>) newRecords());
			return;
		}
		Map<Id, String> titles = new Map<Id, String>();
		for (Project_Request__c row : (List<Project_Request__c>) newRecords()) {
			if (row.Channel__c != STAFF) {
				titles.put(
					row.Id,
					BarnHelp.text('Projects', 'Projects_Requests_Notice_Arrived', named(row))
				);
			} else if (isOthersUser(row.OwnerId)) {
				titles.put(
					row.Id,
					BarnHelp.text('Projects', 'Projects_Requests_Notice_Assigned', named(row))
				);
			}
		}
		notifyOwners(titles, (List<Project_Request__c>) newRecords());
	}

	public override void afterUpdate() {
		if (isComment()) {
			return;
		}
		Map<Id, SObject> before = oldRecordsById();
		Map<Id, String> titles = new Map<Id, String>();
		List<Project_Request_Comment__c> fromRequesters = new List<Project_Request_Comment__c>();
		Set<Id> nowResolved = new Set<Id>();
		for (Project_Request__c row : (List<Project_Request__c>) newRecords()) {
			Project_Request__c old = (Project_Request__c) before.get(row.Id);
			String reply = replies.remove(row.Id);
			if (reply != null) {
				fromRequesters.add(
					new Project_Request_Comment__c(
						Request__c = row.Id,
						Body__c = reply,
						Shared__c = true,
						From_Requester__c = true
					)
				);
				titles.put(
					row.Id,
					BarnHelp.text('Projects', 'Projects_Requests_Notice_Reply', named(row))
				);
			} else if (row.OwnerId != old.OwnerId && isOthersUser(row.OwnerId)) {
				titles.put(
					row.Id,
					BarnHelp.text('Projects', 'Projects_Requests_Notice_Assigned', named(row))
				);
			}
			if (row.Status__c == RESOLVED && old.Status__c != RESOLVED) {
				nowResolved.add(row.Id);
			}
		}
		if (!fromRequesters.isEmpty()) {
			new Elevated().insertComments(fromRequesters);
		}
		notifyOwners(titles, (List<Project_Request__c>) newRecords());
		if (!nowResolved.isEmpty()) {
			emailRequesters(nowResolved, null);
		}
	}

	/** Today plus a number of weekdays: Saturday and Sunday are not counted. */
	public static Date addWeekdays(Date start, Integer days) {
		Date day = start;
		Integer added = 0;
		while (added < days) {
			day = day.addDays(1);
			// 0 is Sunday and 6 Saturday, counted from a known Sunday.
			Integer weekday = Math.mod(Date.newInstance(1900, 1, 7).daysBetween(day), 7);
			if (weekday != 0 && weekday != 6) {
				added++;
			}
		}
		return day;
	}

	private Boolean isComment() {
		List<SObject> rows = newRecords();
		return rows != null && !rows.isEmpty() && rows[0] instanceof Project_Request_Comment__c;
	}

	private static void stampResolved(Project_Request__c row, Project_Request__c old) {
		if (FINISHED.contains(row.Status__c)) {
			if (row.Resolved_Date__c == null) {
				row.Resolved_Date__c = Datetime.now();
			}
		} else if (old != null && row.Status__c != 'Cancelled') {
			row.Resolved_Date__c = null;
		}
	}

	private static Boolean isUser(Id ownerId) {
		return ownerId != null && ownerId.getSObjectType() == User.SObjectType;
	}

	private static Boolean isOthersUser(Id ownerId) {
		return isUser(ownerId) && ownerId != UserInfo.getUserId();
	}

	/** The request number and subject, the two values every notice and email names. */
	private static List<Object> named(Project_Request__c row) {
		return new List<Object>{ row.Name == null ? '' : row.Name, row.Subject__c };
	}

	/**
	 * One bell notice per request, to its owner (a queue's members when a queue owns it), never
	 * to the person saving, up to the cap.
	 */
	private static void notifyOwners(Map<Id, String> titles, List<Project_Request__c> rows) {
		Set<Id> queueIds = new Set<Id>();
		for (Project_Request__c row : rows) {
			if (titles.containsKey(row.Id) && row.OwnerId != null && !isUser(row.OwnerId)) {
				queueIds.add(row.OwnerId);
			}
		}
		Map<Id, Set<String>> members = queueIds.isEmpty()
			? new Map<Id, Set<String>>()
			: new Elevated().queueMembers(queueIds);
		Integer count = 0;
		for (Project_Request__c row : rows) {
			String title = titles.get(row.Id);
			Set<String> recipients = isUser(row.OwnerId)
				? new Set<String>{ row.OwnerId }
				: members.get(row.OwnerId);
			if (recipients != null) {
				recipients.remove(UserInfo.getUserId());
			}
			if (
				title == null ||
				recipients == null ||
				recipients.isEmpty() ||
				count >= NOTICE_CAP
			) {
				continue;
			}
			count++;
			sent.add(title);
			JobNotifier.ownType(
				NOTICE_TYPE,
				recipients,
				title,
				row.Subject__c == null ? title : row.Subject__c,
				row.Id,
				CONTEXT + '.notifyOwners'
			);
		}
	}

	private static void emailSharedComments(List<Project_Request_Comment__c> comments) {
		Map<Id, String> bodies = new Map<Id, String>();
		for (Project_Request_Comment__c comment : comments) {
			if (comment.Shared__c && !comment.From_Requester__c) {
				bodies.put(comment.Request__c, comment.Body__c);
			}
		}
		if (!bodies.isEmpty()) {
			emailRequesters(bodies.keySet(), bodies);
		}
	}

	/**
	 * Emails each request's requester: a shared comment when `comments` names one, otherwise the
	 * resolution. A requester with no email address gets none.
	 */
	private static void emailRequesters(Set<Id> requestIds, Map<Id, String> comments) {
		List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
		for (Project_Request__c request : new Elevated().withRequesters(requestIds)) {
			String subject = comments == null
				? BarnHelp.text(
						'Projects',
						'Projects_Requests_Email_ResolvedSubject',
						named(request)
				  )
				: BarnHelp.text(
						'Projects',
						'Projects_Requests_Email_CommentSubject',
						named(request)
				  );
			String body = comments == null ? request.Resolution__c : comments.get(request.Id);
			Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
			email.setTargetObjectId(request.Requester__c);
			email.setSaveAsActivity(false);
			email.setSubject(subject);
			email.setPlainTextBody(body == null ? subject : body);
			emails.add(email);
			sent.add(subject);
		}
		if (emails.isEmpty() || Limits.getEmailInvocations() >= Limits.getLimitEmailInvocations()) {
			return;
		}
		try {
			Messaging.sendEmail(emails, false);
		} catch (Exception refused) {
			// An org with email turned off, or out of its daily allowance: the save still stands.
			ErrorLogger.log(refused, CONTEXT + '.emailRequesters');
		}
	}

	/**
	 * The reads and writes a portal save needs: the portal's integration user has no access to
	 * Contact or comments of its own (ADR-0185 decision 8), so these run in system mode, only for
	 * the requests being saved.
	 */
	private without sharing class Elevated {
		void fillAccounts(List<Project_Request__c> rows) {
			Set<Id> contactIds = new Set<Id>();
			for (Project_Request__c row : rows) {
				contactIds.add(row.Requester__c);
			}
			Map<Id, Contact> contacts = new Map<Id, Contact>(
				[SELECT Id, AccountId FROM Contact WHERE Id IN :contactIds WITH SYSTEM_MODE]
			);
			for (Project_Request__c row : rows) {
				Contact requester = contacts.get(row.Requester__c);
				if (requester != null) {
					row.Account__c = requester.AccountId;
				}
			}
		}

		/** The shipped Requests queue, or null where an admin removed it. */
		Id requestsQueue() {
			List<Group> queues = [
				SELECT Id
				FROM Group
				WHERE DeveloperName = 'Project_Requests' AND Type = 'Queue'
				WITH SYSTEM_MODE
				LIMIT 1
			];
			return queues.isEmpty() ? null : queues[0].Id;
		}

		/** The users in each queue, directly named (not through roles or groups). */
		Map<Id, Set<String>> queueMembers(Set<Id> queueIds) {
			Map<Id, Set<String>> members = new Map<Id, Set<String>>();
			for (GroupMember member : [
				SELECT GroupId, UserOrGroupId
				FROM GroupMember
				WHERE GroupId IN :queueIds
				WITH SYSTEM_MODE
				LIMIT 500
			]) {
				if (isUser(member.UserOrGroupId)) {
					if (!members.containsKey(member.GroupId)) {
						members.put(member.GroupId, new Set<String>());
					}
					members.get(member.GroupId).add(member.UserOrGroupId);
				}
			}
			return members;
		}

		void insertComments(List<Project_Request_Comment__c> comments) {
			insert as system comments;
		}

		List<Project_Request__c> withRequesters(Set<Id> requestIds) {
			return [
				SELECT Id, Name, Subject__c, Resolution__c, Requester__c
				FROM Project_Request__c
				WHERE Id IN :requestIds AND Requester__c != NULL AND Requester__r.Email != NULL
				WITH SYSTEM_MODE
			];
		}
	}
}
