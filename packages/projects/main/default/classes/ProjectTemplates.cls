/**
 * Project templates (PM-03, canonical model R-PM3; ADR-0208 `0208-project-management-module.md`
 * decision 4): the shipped templates in the `Projects_Templates` static resource, placed by day
 * offsets from a start date, and any project marked Is Template, copied with its dates moved to
 * the new start. Both become one plan of offsets, which `create` builds in user mode.
 */
public with sharing class ProjectTemplates {
	public static final String RESOURCE = 'Projects_Templates';

	/** The shipped templates' JSON, set by tests instead of reading the static resource. */
	@TestVisible
	private static String bodyForTest;

	/** A template as New Project From Template lists it. */
	public class Template {
		@AuraEnabled
		public String key;
		@AuraEnabled
		public String name;
		@AuraEnabled
		public String type;
		@AuraEnabled
		public Boolean shipped = false;
	}

	/** A template as offsets from its start, whichever kind it is. */
	private class Plan {
		String name;
		String type;
		Integer days;
		Decimal budgetHours;
		Decimal rate;
		String description;
		List<Step> phases = new List<Step>();
		List<Step> loose = new List<Step>();
		/** Assignment roles: name is the role, hours the planned hours. */
		List<Step> roles = new List<Step>();
	}

	/** A phase (with its tasks) or a task, by offsets in days. */
	private class Step {
		String name;
		Integer start;
		Integer due;
		Decimal hours;
		Boolean milestone = false;
		Decimal sortOrder;
		String description;
		List<Step> tasks = new List<Step>();
	}

	/** The shipped templates, then the org's template projects the person can read. */
	public static List<Template> available() {
		List<Template> out = new List<Template>();
		for (Object raw : shipped()) {
			Map<String, Object> row = (Map<String, Object>) raw;
			out.add(
				template(
					(String) row.get('key'),
					(String) row.get('name'),
					(String) row.get('type'),
					true
				)
			);
		}
		for (Project__c project : [
			SELECT Id, Name, Type__c
			FROM Project__c
			WHERE Is_Template__c = TRUE
			WITH USER_MODE
			ORDER BY Name
			LIMIT 200
		]) {
			out.add(template(project.Id, project.Name, project.Type__c, false));
		}
		return out;
	}

	/**
	 * Builds a new Planned project from a template (a shipped key or a template project's Id)
	 * starting on `startDate`, with its phases, tasks and assignment roles. Returns its Id.
	 */
	public static Id create(String key, String name, Date startDate, Id accountId, Id contactId) {
		if (String.isBlank(key) || startDate == null) {
			throw Projects.refuse(BarnHelp.text('Projects', 'Projects_Template_Needed'));
		}
		Id templateId = idOrNull(key);
		Plan plan = templateId == null ? fromShipped(key) : fromProject(templateId);
		Project__c project = new Project__c(
			Name = String.isBlank(name) ? plan.name : name.trim().abbreviate(80),
			Type__c = plan.type,
			Status__c = 'Planned',
			Start_Date__c = startDate,
			Target_Date__c = plan.days == null ? null : startDate.addDays(plan.days),
			Account__c = accountId,
			Contact__c = contactId,
			Template_Key__c = key,
			Budget_Hours__c = plan.budgetHours,
			Hourly_Rate__c = plan.rate,
			Description__c = plan.description
		);
		insert as user project;
		List<Project_Phase__c> phases = new List<Project_Phase__c>();
		Integer order = 0;
		for (Step step : plan.phases) {
			order += 10;
			phases.add(
				new Project_Phase__c(
					Project__c = project.Id,
					Name = step.name,
					Sort_Order__c = order,
					Start_Date__c = at(startDate, step.start),
					End_Date__c = at(startDate, step.due)
				)
			);
		}
		insert as user phases;
		List<Project_Task__c> tasks = new List<Project_Task__c>();
		for (Integer i = 0; i < plan.phases.size(); i++) {
			addTasks(tasks, plan.phases[i].tasks, project.Id, phases[i].Id, startDate);
		}
		addTasks(tasks, plan.loose, project.Id, null, startDate);
		insert as user tasks;
		List<Project_Assignment__c> roles = new List<Project_Assignment__c>();
		for (Step role : plan.roles) {
			roles.add(
				new Project_Assignment__c(
					Project__c = project.Id,
					Role__c = role.name,
					Planned_Hours__c = role.hours,
					Start_Date__c = at(startDate, role.start),
					End_Date__c = at(startDate, role.due)
				)
			);
		}
		insert as user roles;
		return project.Id;
	}

	private static void addTasks(
		List<Project_Task__c> out,
		List<Step> steps,
		Id projectId,
		Id phaseId,
		Date startDate
	) {
		Integer order = 0;
		for (Step step : steps) {
			order += 10;
			out.add(
				new Project_Task__c(
					Project__c = projectId,
					Phase__c = phaseId,
					Name = step.name,
					Status__c = 'Not Started',
					Milestone__c = step.milestone,
					Start_Date__c = at(startDate, step.start),
					Due_Date__c = at(startDate, step.due),
					Estimated_Hours__c = step.hours,
					Sort_Order__c = step.sortOrder == null ? order : step.sortOrder,
					Description__c = step.description
				)
			);
		}
	}

	private static Date at(Date startDate, Integer offset) {
		return offset == null ? null : startDate.addDays(offset);
	}

	private static Template template(String key, String name, String type, Boolean shipped) {
		Template row = new Template();
		row.key = key;
		row.name = name;
		row.type = type;
		row.shipped = shipped;
		return row;
	}

	/** The shipped templates as parsed JSON: a list of maps. */
	private static List<Object> shipped() {
		String body = bodyForTest;
		if (body == null) {
			body = SetupObjectSelector.staticResourceBody(RESOURCE);
			body = body == null ? '{}' : body;
		}
		Object templates = ((Map<String, Object>) JSON.deserializeUntyped(body)).get('templates');
		return templates == null ? new List<Object>() : (List<Object>) templates;
	}

	private static Plan fromShipped(String key) {
		for (Object raw : shipped()) {
			Map<String, Object> row = (Map<String, Object>) raw;
			if (row.get('key') == key) {
				Plan plan = new Plan();
				plan.name = (String) row.get('name');
				plan.type = (String) row.get('type');
				plan.days = toInteger(row.get('days'));
				for (Object phaseRaw : (List<Object>) row.get('phases')) {
					Map<String, Object> phaseRow = (Map<String, Object>) phaseRaw;
					Step phase = step(
						(String) phaseRow.get('name'),
						phaseRow.get('start'),
						phaseRow.get('end')
					);
					for (Object taskRaw : (List<Object>) phaseRow.get('tasks')) {
						Map<String, Object> taskRow = (Map<String, Object>) taskRaw;
						Step task = step(
							(String) taskRow.get('name'),
							taskRow.get('start'),
							taskRow.get('due')
						);
						task.hours = taskRow.get('hours') == null
							? null
							: Decimal.valueOf(String.valueOf(taskRow.get('hours')));
						task.milestone = taskRow.get('milestone') == true;
						phase.tasks.add(task);
					}
					plan.phases.add(phase);
				}
				return plan;
			}
		}
		throw Projects.refuse(BarnHelp.text('Projects', 'Projects_Template_Missing'));
	}

	/** A template project as offsets from its Start Date, or else its earliest phase or task date. */
	private static Plan fromProject(Id projectId) {
		List<Project__c> found = [
			SELECT
				Name,
				Type__c,
				Is_Template__c,
				Start_Date__c,
				Target_Date__c,
				Budget_Hours__c,
				Hourly_Rate__c,
				Description__c,
				(
					SELECT Id, Name, Start_Date__c, End_Date__c
					FROM Phases__r
					ORDER BY Sort_Order__c NULLS LAST, Start_Date__c
				),
				(
					SELECT
						Name,
						Phase__c,
						Start_Date__c,
						Due_Date__c,
						Estimated_Hours__c,
						Milestone__c,
						Sort_Order__c,
						Description__c
					FROM Tasks__r
					WHERE Status__c != :Projects.CANCELLED
					ORDER BY Sort_Order__c NULLS LAST, Due_Date__c
				),
				(SELECT Role__c, Planned_Hours__c, Start_Date__c, End_Date__c FROM Assignments__r)
			FROM Project__c
			WHERE Id = :projectId
			WITH USER_MODE
		];
		if (found.isEmpty() || !found[0].Is_Template__c) {
			throw Projects.refuse(BarnHelp.text('Projects', 'Projects_Template_Missing'));
		}
		Project__c source = found[0];
		Date base = source.Start_Date__c;
		for (Project_Phase__c phase : source.Phases__r) {
			base = earliest(base, phase.Start_Date__c);
		}
		for (Project_Task__c task : source.Tasks__r) {
			base = earliest(earliest(base, task.Start_Date__c), task.Due_Date__c);
		}
		base = base == null ? Date.today() : base;
		Plan plan = new Plan();
		plan.name = source.Name;
		plan.type = source.Type__c;
		plan.days = offset(base, source.Target_Date__c);
		plan.budgetHours = source.Budget_Hours__c;
		plan.rate = source.Hourly_Rate__c;
		plan.description = source.Description__c;
		Map<Id, Step> byPhase = new Map<Id, Step>();
		for (Project_Phase__c phase : source.Phases__r) {
			Step step = step(
				phase.Name,
				offset(base, phase.Start_Date__c),
				offset(base, phase.End_Date__c)
			);
			byPhase.put(phase.Id, step);
			plan.phases.add(step);
		}
		for (Project_Task__c task : source.Tasks__r) {
			Step step = step(
				task.Name,
				offset(base, task.Start_Date__c),
				offset(base, task.Due_Date__c)
			);
			step.hours = task.Estimated_Hours__c;
			step.milestone = task.Milestone__c;
			step.sortOrder = task.Sort_Order__c;
			step.description = task.Description__c;
			if (byPhase.containsKey(task.Phase__c)) {
				byPhase.get(task.Phase__c).tasks.add(step);
			} else {
				plan.loose.add(step);
			}
		}
		for (Project_Assignment__c role : source.Assignments__r) {
			Step step = step(
				role.Role__c,
				offset(base, role.Start_Date__c),
				offset(base, role.End_Date__c)
			);
			step.hours = role.Planned_Hours__c;
			plan.roles.add(step);
		}
		return plan;
	}

	private static Step step(String name, Object start, Object due) {
		Step step = new Step();
		step.name = name;
		step.start = toInteger(start);
		step.due = toInteger(due);
		return step;
	}

	private static Id idOrNull(String key) {
		try {
			return Id.valueOf(key);
		} catch (StringException notAnId) {
			return null;
		}
	}

	private static Integer toInteger(Object value) {
		return value == null ? null : Integer.valueOf(String.valueOf(value));
	}

	private static Integer offset(Date base, Date value) {
		return value == null ? null : base.daysBetween(value);
	}

	private static Date earliest(Date a, Date b) {
		return a == null ? b : b == null || a <= b ? a : b;
	}
}
