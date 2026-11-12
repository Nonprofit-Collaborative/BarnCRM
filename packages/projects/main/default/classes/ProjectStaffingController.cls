/**
 * The Staffing page and the allocation view (PM-09; ADR-NEXT `NEXT-projects-psa.md` decision 5,
 * R-PM14, R-PM15). Thin by design (plan Section 9.9): it returns the records the browser needs
 * and `c/projectsAllocationModel` works out allocation and ranks candidates. User mode
 * throughout; with Manage resources off it returns nothing and changes nothing.
 */
public with sharing class ProjectStaffingController {
	private static final String CONTEXT = 'ProjectStaffingController';
	private static final Integer MAX_RANGE_DAYS = 182;
	private static final List<String> NOT_COUNTED = new List<String>{
		'Open',
		'Submitted',
		'Rejected'
	};

	public class Staffing {
		@AuraEnabled
		public Boolean enabled = false;
		@AuraEnabled
		public Integer defaultCapacity;
		@AuraEnabled
		public List<Project_Resource__c> resources = new List<Project_Resource__c>();
		@AuraEnabled
		public List<Resource_Request__c> requests = new List<Resource_Request__c>();
		@AuraEnabled
		public List<String> skills = new List<String>();
	}

	public class Allocation {
		@AuraEnabled
		public Integer defaultCapacity;
		@AuraEnabled
		public List<Project_Resource__c> resources;
		@AuraEnabled
		public List<Project_Assignment__c> assignments = new List<Project_Assignment__c>();
		@AuraEnabled
		public List<Resource_Request__c> requests = new List<Resource_Request__c>();
		@AuraEnabled
		public List<Map<String, Object>> logged = new List<Map<String, Object>>();
	}

	/** People who can be staffed, the open requests and the skill list; empty when off. */
	@AuraEnabled
	public static Staffing getStaffing() {
		try {
			Staffing staffing = new Staffing();
			staffing.enabled = ProjectsSettings.resourcesEnabled();
			staffing.defaultCapacity = ProjectsSettings.weeklyCapacity();
			if (!staffing.enabled) {
				return staffing;
			}
			staffing.resources = resources();
			staffing.requests = requests(null, null);
			for (
				Schema.PicklistEntry entry : Project_Resource__c.Skills__c.getDescribe()
					.getPicklistValues()
			) {
				staffing.skills.add(entry.getValue());
			}
			return staffing;
		} catch (Exception e) {
			throw failure(e);
		}
	}

	/**
	 * What the browser needs for the weeks from `fromDate` to `toDate` (a Monday to a Sunday,
	 * at most 26 weeks): active people, their planned assignments, counted logged hours by
	 * day and the open requests (R-PM14). The same call ranks candidates for a request.
	 */
	@AuraEnabled
	public static Allocation getAllocation(Date fromDate, Date toDate) {
		try {
			if (
				fromDate == null ||
				toDate == null ||
				toDate < fromDate ||
				fromDate.daysBetween(toDate) >= MAX_RANGE_DAYS
			) {
				throw Projects.refuse(BarnHelp.text('Projects', 'Projects_Allocation_Range'));
			}
			Allocation view = new Allocation();
			view.defaultCapacity = ProjectsSettings.weeklyCapacity();
			view.resources = new List<Project_Resource__c>();
			if (!ProjectsSettings.resourcesEnabled()) {
				return view;
			}
			for (Project_Resource__c resource : resources()) {
				if (resource.Active__c) {
					view.resources.add(resource);
				}
			}
			view.requests = requests(fromDate, toDate);
			view.assignments = [
				SELECT Resource__c, Planned_Hours__c, Start_Date__c, End_Date__c
				FROM Project_Assignment__c
				WHERE
					Resource__c != NULL
					AND Planned_Hours__c > 0
					AND (Start_Date__c = NULL
					OR Start_Date__c <= :toDate)
					AND (End_Date__c = NULL
					OR End_Date__c >= :fromDate)
					AND Project__r.Status__c IN ('Planned', 'Active')
					AND Project__r.Is_Template__c = FALSE
				WITH USER_MODE
				LIMIT 5000
			];
			for (AggregateResult row : [
				SELECT User__c userId, Date__c day, SUM(Hours__c) hours
				FROM Time_Entry__c
				WHERE
					User__c != NULL
					AND Date__c >= :fromDate
					AND Date__c <= :toDate
					AND Status__c NOT IN :NOT_COUNTED
				WITH USER_MODE
				GROUP BY User__c, Date__c
				LIMIT 10000
			]) {
				view.logged.add(
					new Map<String, Object>{
						'userId' => row.get('userId'),
						'date' => row.get('day'),
						'hours' => row.get('hours')
					}
				);
			}
			return view;
		} catch (Exception e) {
			throw failure(e);
		}
	}

	/**
	 * Fills an open request with a person (R-PM15): a Project Assignment with the request's
	 * role, hours and dates, linked to the request, which becomes Filled. Returns the assignment.
	 */
	@AuraEnabled
	public static Id fill(Id requestId, Id userId) {
		try {
			requireOn();
			Resource_Request__c request = [
				SELECT Project__c, Role__c, Hours__c, Start_Date__c, End_Date__c, Status__c
				FROM Resource_Request__c
				WHERE Id = :requestId
				WITH USER_MODE
				FOR UPDATE
			];
			if (request.Status__c != 'Open') {
				throw Projects.refuse(BarnHelp.text('Projects', 'Projects_Staffing_NotOpen'));
			}
			if (
				[
					SELECT COUNT()
					FROM Project_Resource__c
					WHERE User__c = :userId AND Active__c = TRUE
					WITH USER_MODE
				] == 0
			) {
				throw Projects.refuse(BarnHelp.text('Projects', 'Projects_Staffing_NotResource'));
			}
			Project_Assignment__c assignment = new Project_Assignment__c(
				Project__c = request.Project__c,
				Resource__c = userId,
				Role__c = request.Role__c,
				Planned_Hours__c = request.Hours__c,
				Start_Date__c = request.Start_Date__c,
				End_Date__c = request.End_Date__c
			);
			insert as user assignment;
			update as user new Resource_Request__c(
				Id = requestId,
				Assignment__c = assignment.Id,
				Status__c = 'Filled'
			);
			return assignment.Id;
		} catch (Exception e) {
			throw failure(e);
		}
	}

	/** Saves a person's skills, capacity, default role and active flag: one row per person. */
	@AuraEnabled
	public static Id saveResource(
		Id userId,
		String skills,
		Decimal weeklyCapacity,
		String defaultRole,
		Boolean active
	) {
		try {
			requireOn();
			List<Project_Resource__c> found = [
				SELECT Id
				FROM Project_Resource__c
				WHERE User__c = :userId
				WITH USER_MODE
				ORDER BY CreatedDate
				LIMIT 1
			];
			Project_Resource__c resource = new Project_Resource__c(
				Id = found.isEmpty() ? null : found[0].Id,
				Skills__c = String.isBlank(skills) ? null : skills,
				Weekly_Capacity_Hours__c = weeklyCapacity,
				Default_Role__c = String.isBlank(defaultRole) ? null : defaultRole.trim(),
				Active__c = active != false
			);
			if (found.isEmpty()) {
				resource.User__c = userId;
			}
			upsert as user resource;
			return resource.Id;
		} catch (Exception e) {
			throw failure(e);
		}
	}

	/** One row per person: if a second was made by hand, the oldest wins. */
	private static List<Project_Resource__c> resources() {
		Map<Id, Project_Resource__c> byUser = new Map<Id, Project_Resource__c>();
		for (Project_Resource__c resource : [
			SELECT
				User__c,
				User__r.Name,
				Skills__c,
				Weekly_Capacity_Hours__c,
				Default_Role__c,
				Active__c
			FROM Project_Resource__c
			WITH USER_MODE
			ORDER BY CreatedDate
			LIMIT 2000
		]) {
			if (!byUser.containsKey(resource.User__c)) {
				byUser.put(resource.User__c, resource);
			}
		}
		return byUser.values();
	}

	/** Open requests, all of them or those overlapping a date range. */
	private static List<Resource_Request__c> requests(Date fromDate, Date toDate) {
		Date starts = fromDate == null ? Date.newInstance(1900, 1, 1) : fromDate;
		Date ends = toDate == null ? Date.newInstance(4000, 12, 31) : toDate;
		return [
			SELECT
				Project__c,
				Project__r.Name,
				Role__c,
				Skills__c,
				Hours__c,
				Start_Date__c,
				End_Date__c
			FROM Resource_Request__c
			WHERE
				Status__c = 'Open'
				AND Start_Date__c <= :ends
				AND End_Date__c >= :starts
				AND Project__r.Is_Template__c = FALSE
			WITH USER_MODE
			ORDER BY Start_Date__c
			LIMIT 500
		];
	}

	private static void requireOn() {
		if (!ProjectsSettings.resourcesEnabled()) {
			throw Projects.refuse(BarnHelp.text('Projects', 'Projects_Staffing_Off'));
		}
	}

	private static AuraHandledException failure(Exception e) {
		if (!(e instanceof Projects.ProjectsException) && !(e instanceof DmlException)) {
			ErrorLogger.log(e, CONTEXT);
		}
		return UserErrors.wrapShowingDml(e, BarnHelp.text('Projects', 'Projects_Error_Generic'));
	}
}
