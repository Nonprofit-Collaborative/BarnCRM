/**
 * The Requests tab and the request panel (D-201; ADR-NEXT `NEXT-projects-requests-and-issues.md`
 * decision 3): requests by view, one request with its comments, triage changes, comments, and a
 * task or change request made from a request. Thin by design (plan Section 9.9): plain DTOs,
 * user mode throughout, the rules in `ProjectRequestHandler` and the validation rules; views
 * and display rules in `c/projectsRequestsModel`.
 */
public with sharing class ProjectRequestsController {
	private static final String CONTEXT = 'ProjectRequestsController';
	private static final String OPEN = ' Status__c NOT IN (\'Resolved\', \'Closed\', \'Cancelled\')';
	private static final Map<String, String> VIEWS = new Map<String, String>{
		'mine' => 'OwnerId = :me AND' + OPEN,
		'open' => OPEN,
		'unassigned' => 'Owner.Type = \'Queue\' AND' + OPEN,
		'overdue' => 'Overdue__c = TRUE',
		'closed' => ' Status__c IN (\'Resolved\', \'Closed\', \'Cancelled\')'
	};
	private static final String FIELDS =
		'SELECT Id, Name, Subject__c, Status__c, Priority__c, Type__c, Category__c, ' +
		'Requester__r.Name, Owner.Name, Owner.Type, OwnerId, Due_Date__c, Overdue__c, ' +
		'Project__c, Project__r.Name, CreatedDate';
	/** What triage may change from the panel; anything else in a save is ignored. */
	private static final Set<String> EDITABLE = new Set<String>{
		'Status__c',
		'Priority__c',
		'OwnerId',
		'Due_Date__c',
		'Resolution__c',
		'Project__c'
	};

	public class RequestList {
		@AuraEnabled
		public Boolean enabled = false;
		@AuraEnabled
		public List<Row> rows = new List<Row>();
	}

	public virtual class Row {
		@AuraEnabled
		public Id id;
		@AuraEnabled
		public String name;
		@AuraEnabled
		public String subject;
		@AuraEnabled
		public String status;
		@AuraEnabled
		public String priority;
		@AuraEnabled
		public String type;
		@AuraEnabled
		public String category;
		@AuraEnabled
		public String requester;
		@AuraEnabled
		public Id ownerId;
		@AuraEnabled
		public String owner;
		@AuraEnabled
		public Boolean ownerIsQueue;
		@AuraEnabled
		public Date dueDate;
		@AuraEnabled
		public Boolean overdue;
		@AuraEnabled
		public Id projectId;
		@AuraEnabled
		public String project;
		@AuraEnabled
		public Datetime created;
	}

	public class Detail extends Row {
		@AuraEnabled
		public String description;
		@AuraEnabled
		public String resolution;
		@AuraEnabled
		public String channel;
		@AuraEnabled
		public String satisfaction;
		@AuraEnabled
		public Id taskId;
		@AuraEnabled
		public String task;
		@AuraEnabled
		public Id changeRequestId;
		@AuraEnabled
		public String changeRequest;
		@AuraEnabled
		public Boolean changeRequestsEnabled;
		@AuraEnabled
		public List<Comment> comments = new List<Comment>();
	}

	public class Comment {
		@AuraEnabled
		public Id id;
		@AuraEnabled
		public String body;
		@AuraEnabled
		public Boolean shared;
		@AuraEnabled
		public Boolean fromRequester;
		@AuraEnabled
		public String author;
		@AuraEnabled
		public Datetime created;
	}

	/** The requests of one view: mine, open, unassigned, overdue or closed (500 at most). */
	@AuraEnabled
	public static RequestList getRequests(String view) {
		try {
			RequestList page = new RequestList();
			page.enabled = ProjectsSettings.requestsEnabled();
			String filter = VIEWS.get(view);
			if (!page.enabled || filter == null) {
				return page;
			}
			String order = view == 'closed'
				? ' ORDER BY LastModifiedDate DESC'
				: ' ORDER BY Due_Date__c ASC NULLS LAST, CreatedDate ASC';
			for (
				Project_Request__c request : (List<Project_Request__c>) Database.queryWithBinds(
					FIELDS + ' FROM Project_Request__c WHERE ' + filter + order + ' LIMIT 500',
					new Map<String, Object>{ 'me' => UserInfo.getUserId() },
					AccessLevel.USER_MODE
				)
			) {
				page.rows.add(fill(new Row(), request));
			}
			return page;
		} catch (Exception e) {
			throw failure(e);
		}
	}

	/** One request with its comments, oldest first. */
	@AuraEnabled
	public static Detail getRequest(Id requestId) {
		try {
			Project_Request__c request = [
				SELECT
					Id,
					Name,
					Subject__c,
					Status__c,
					Priority__c,
					Type__c,
					Category__c,
					Requester__r.Name,
					Owner.Name,
					Owner.Type,
					OwnerId,
					Due_Date__c,
					Overdue__c,
					Project__c,
					Project__r.Name,
					CreatedDate,
					Description__c,
					Resolution__c,
					Channel__c,
					Satisfaction__c,
					Project_Task__c,
					Project_Task__r.Name,
					Change_Request__c,
					Change_Request__r.Name,
					(
						SELECT
							Id,
							Body__c,
							Shared__c,
							From_Requester__c,
							CreatedBy.Name,
							CreatedDate
						FROM Comments__r
						ORDER BY CreatedDate ASC
						LIMIT 500
					)
				FROM Project_Request__c
				WHERE Id = :requestId
				WITH USER_MODE
			];
			Detail detail = (Detail) fill(new Detail(), request);
			detail.description = request.Description__c;
			detail.resolution = request.Resolution__c;
			detail.channel = request.Channel__c;
			detail.satisfaction = request.Satisfaction__c;
			detail.taskId = request.Project_Task__c;
			detail.task = request.Project_Task__r?.Name;
			detail.changeRequestId = request.Change_Request__c;
			detail.changeRequest = request.Change_Request__r?.Name;
			detail.changeRequestsEnabled = ProjectsSettings.changeRequestsEnabled();
			for (Project_Request_Comment__c row : request.Comments__r) {
				Comment comment = new Comment();
				comment.id = row.Id;
				comment.body = row.Body__c;
				comment.shared = row.Shared__c;
				comment.fromRequester = row.From_Requester__c;
				comment.author = row.CreatedBy.Name;
				comment.created = row.CreatedDate;
				detail.comments.add(comment);
			}
			return detail;
		} catch (Exception e) {
			throw failure(e);
		}
	}

	/** Saves triage changes (status, priority, owner, due date, resolution, project). */
	@AuraEnabled
	public static void saveRequest(Id requestId, Map<String, Object> changes) {
		try {
			Project_Request__c request = new Project_Request__c(Id = requestId);
			for (String field : changes == null ? new Set<String>() : changes.keySet()) {
				if (!EDITABLE.contains(field)) {
					continue;
				}
				Object value = changes.get(field);
				if (field == 'Due_Date__c' && value != null) {
					value = Date.valueOf(String.valueOf(value));
				}
				request.put(field, value == '' ? null : value);
			}
			update as user request;
		} catch (Exception e) {
			throw failure(e);
		}
	}

	/** Adds a comment, internal unless shared. */
	@AuraEnabled
	public static void addComment(Id requestId, String body, Boolean shared) {
		try {
			insert as user new Project_Request_Comment__c(
				Request__c = requestId,
				Body__c = body,
				Shared__c = shared == true
			);
		} catch (Exception e) {
			throw failure(e);
		}
	}

	/** Adds a task to the request's project, named from the subject, and links it. */
	@AuraEnabled
	public static Id createTask(Id requestId) {
		try {
			Project_Request__c request = linked(requestId);
			Project_Task__c task = new Project_Task__c(
				Project__c = request.Project__c,
				Name = request.Subject__c.abbreviate(80),
				Description__c = describe(request),
				Status__c = 'Not Started',
				Due_Date__c = request.Due_Date__c
			);
			insert as user task;
			Project_Request__c link = new Project_Request__c(
				Id = requestId,
				Project_Task__c = task.Id
			);
			if (request.Status__c == 'New') {
				link.Status__c = ProjectRequestHandler.IN_PROGRESS;
			}
			update as user link;
			return task.Id;
		} catch (Exception e) {
			throw failure(e);
		}
	}

	/** Adds a Draft change request to the request's project and links it. */
	@AuraEnabled
	public static Id createChangeRequest(Id requestId) {
		try {
			Project_Request__c request = linked(requestId);
			Project_Change_Request__c change = new Project_Change_Request__c(
				Project__c = request.Project__c,
				Name = request.Subject__c.abbreviate(80),
				Description__c = describe(request),
				Status__c = 'Draft'
			);
			insert as user change;
			update as user new Project_Request__c(Id = requestId, Change_Request__c = change.Id);
			return change.Id;
		} catch (Exception e) {
			throw failure(e);
		}
	}

	/** The request, refused in words when it has no project yet. */
	private static Project_Request__c linked(Id requestId) {
		Project_Request__c request = [
			SELECT Id, Name, Subject__c, Description__c, Status__c, Due_Date__c, Project__c
			FROM Project_Request__c
			WHERE Id = :requestId
			WITH USER_MODE
		];
		if (request.Project__c == null) {
			throw Projects.refuse(BarnHelp.text('Projects', 'Projects_Requests_NeedProject'));
		}
		return request;
	}

	/** The request number, then its description, for the task or change it becomes. */
	private static String describe(Project_Request__c request) {
		return String.isBlank(request.Description__c)
			? request.Name
			: request.Name + ': ' + request.Description__c;
	}

	private static Row fill(Row row, Project_Request__c request) {
		row.id = request.Id;
		row.name = request.Name;
		row.subject = request.Subject__c;
		row.status = request.Status__c;
		row.priority = request.Priority__c;
		row.type = request.Type__c;
		row.category = request.Category__c;
		row.requester = request.Requester__r?.Name;
		row.ownerId = request.OwnerId;
		row.owner = request.Owner?.Name;
		row.ownerIsQueue = request.Owner?.Type == 'Queue';
		row.dueDate = request.Due_Date__c;
		row.overdue = request.Overdue__c;
		row.projectId = request.Project__c;
		row.project = request.Project__r?.Name;
		row.created = request.CreatedDate;
		return row;
	}

	private static AuraHandledException failure(Exception e) {
		if (!(e instanceof Projects.ProjectsException) && !(e instanceof DmlException)) {
			ErrorLogger.log(e, CONTEXT);
		}
		return UserErrors.wrapShowingDml(e, BarnHelp.text('Projects', 'Projects_Error_Generic'));
	}
}
