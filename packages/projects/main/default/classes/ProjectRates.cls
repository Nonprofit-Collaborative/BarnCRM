/**
 * PM-06 rate resolution (canonical model R-PM9; ADR-0219 `0219-projects-psa.md` section 2).
 * For each time entry, its Bill Rate and Cost Rate come from the person's own rate, else the
 * rate for their role on the project, else (Bill Rate only) the project's Hourly Rate, each of
 * the two resolved separately. Reads the rate cards in system mode because Staff cannot read
 * cost rates yet every entry keeps its cost; nothing here is returned to a user.
 */
public with sharing class ProjectRates {
	/** One call of Apply Rates stays inside the DML row limit with room for the trigger. */
	@TestVisible
	private static final Integer APPLY_LIMIT = 5000;

	/**
	 * Writes Bill Rate and Cost Rate on each entry (insert and update triggers, before save, or
	 * Apply Rates): the caller decides which entries to stamp. Bulk: one query per source.
	 */
	public static void stamp(List<SObject> rows) {
		List<Time_Entry__c> entries = new List<Time_Entry__c>();
		Set<Id> users = new Set<Id>();
		Set<Id> projects = new Set<Id>();
		Date earliest;
		Date latest;
		for (SObject row : rows) {
			Time_Entry__c entry = (Time_Entry__c) row;
			entries.add(entry);
			users.add(entry.User__c);
			projects.add(entry.Project__c);
			Date day = entry.Date__c;
			earliest = earliest == null || (day != null && day < earliest) ? day : earliest;
			latest = latest == null || (day != null && day > latest) ? day : latest;
		}
		Map<Id, Decimal> hourly = new Map<Id, Decimal>();
		for (Project__c project : [
			SELECT Hourly_Rate__c
			FROM Project__c
			WHERE Id IN :projects
			WITH SYSTEM_MODE
		]) {
			hourly.put(project.Id, project.Hourly_Rate__c);
		}
		// Roles by person and project: their assignments, then their resource's default role.
		List<Project_Assignment__c> assignments = [
			SELECT Resource__c, Project__c, Role__c, Start_Date__c, End_Date__c
			FROM Project_Assignment__c
			WHERE Resource__c IN :users AND Project__c IN :projects AND Role__c != NULL
			WITH SYSTEM_MODE
		];
		Map<Id, String> defaults = new Map<Id, String>();
		for (
			Project_Resource__c resource : ProjectResources.byUser(
					[
						SELECT User__c, Default_Role__c
						FROM Project_Resource__c
						WHERE User__c IN :users AND Default_Role__c != NULL
						WITH SYSTEM_MODE
						ORDER BY CreatedDate
					]
				)
				.values()
		) {
			defaults.put(resource.User__c, resource.Default_Role__c);
		}
		Set<String> roles = new Set<String>(defaults.values());
		for (Project_Assignment__c assignment : assignments) {
			roles.add(assignment.Role__c);
		}
		List<Project_Rate__c> rates = new List<Project_Rate__c>();
		if (earliest != null) {
			rates = [
				SELECT
					User__c,
					Role__c,
					Bill_Rate__c,
					Cost_Rate__c,
					Effective_From__c,
					Effective_To__c
				FROM Project_Rate__c
				WHERE
					(User__c IN :users
					OR Role__c IN :roles)
					AND Effective_From__c <= :latest
					AND (Effective_To__c = NULL
					OR Effective_To__c >= :earliest)
				WITH SYSTEM_MODE
				LIMIT 5000
			];
		}
		for (Time_Entry__c entry : entries) {
			Project_Rate__c person = pick(rates, entry.User__c, null, entry.Date__c);
			String role = roleOf(assignments, defaults, entry);
			Project_Rate__c byRole = role == null ? null : pick(rates, null, role, entry.Date__c);
			entry.Bill_Rate__c = first(
				person?.Bill_Rate__c,
				byRole?.Bill_Rate__c,
				hourly.get(entry.Project__c)
			);
			entry.Cost_Rate__c = first(person?.Cost_Rate__c, byRole?.Cost_Rate__c, null);
		}
	}

	/**
	 * Apply Rates (Manage Projects): stamps entries logged before rates were turned on, those
	 * with a blank Bill Rate that are not invoiced; returns how many it filled, at most
	 * `APPLY_LIMIT`, so a larger backlog is cleared by running it again.
	 */
	public static Integer applyRates() {
		Projects.requireManage();
		if (!ProjectsSettings.ratesEnabled()) {
			throw Projects.refuse(BarnHelp.text('Projects', 'Projects_Rates_Off'));
		}
		List<Time_Entry__c> entries = [
			SELECT User__c, Project__c, Date__c
			FROM Time_Entry__c
			WHERE Bill_Rate__c = NULL AND Invoice_Line__c = NULL
			WITH USER_MODE
			ORDER BY Date__c DESC
			LIMIT :APPLY_LIMIT
		];
		stamp(entries);
		// Only the rates are saved: the other fields read here are not the user's to write.
		List<Time_Entry__c> filled = new List<Time_Entry__c>();
		for (Time_Entry__c entry : entries) {
			if (entry.Bill_Rate__c != null) {
				filled.add(
					new Time_Entry__c(
						Id = entry.Id,
						Bill_Rate__c = entry.Bill_Rate__c,
						Cost_Rate__c = entry.Cost_Rate__c
					)
				);
			}
		}
		update as user filled;
		return filled.size();
	}

	/** The rate of a person or role in force on a day: the latest Effective From wins. */
	private static Project_Rate__c pick(
		List<Project_Rate__c> rates,
		Id userId,
		String role,
		Date day
	) {
		Project_Rate__c best;
		for (Project_Rate__c rate : rates) {
			Boolean matches = userId != null
				? rate.User__c == userId
				: rate.User__c == null &&
				  rate.Role__c != null &&
				  rate.Role__c.equalsIgnoreCase(role);
			if (
				matches &&
				rate.Effective_From__c <= day &&
				(best == null ||
				rate.Effective_From__c > best.Effective_From__c) &&
				covers(rate, day)
			) {
				best = rate;
			}
		}
		return best;
	}

	private static Boolean covers(Project_Rate__c rate, Date day) {
		return rate.Effective_To__c == null || rate.Effective_To__c >= day;
	}

	/** The person's role on the project: the assignment covering the day, else any, else default. */
	private static String roleOf(
		List<Project_Assignment__c> assignments,
		Map<Id, String> defaults,
		Time_Entry__c entry
	) {
		String fallback;
		for (Project_Assignment__c assignment : assignments) {
			if (
				assignment.Resource__c == entry.User__c &&
				assignment.Project__c == entry.Project__c
			) {
				fallback = fallback == null ? assignment.Role__c : fallback;
				if (
					(assignment.Start_Date__c == null ||
					assignment.Start_Date__c <= entry.Date__c) &&
					(assignment.End_Date__c == null ||
					assignment.End_Date__c >= entry.Date__c)
				) {
					return assignment.Role__c;
				}
			}
		}
		return fallback == null ? defaults.get(entry.User__c) : fallback;
	}

	private static Decimal first(Decimal a, Decimal b, Decimal c) {
		return a != null ? a : (b != null ? b : c);
	}
}
