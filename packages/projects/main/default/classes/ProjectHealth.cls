/**
 * Project health (canonical model R-PM2; ADR-NEXT `NEXT-project-management-module.md` decision
 * 5): On Track, At Risk or Off Track for each Active project that is not a template, with one
 * line of Health Reasons per reason, and none for any other project.
 *
 * The 6:40 AM step of BarnCRM's nightly run checks every project as whoever scheduled the run,
 * in system mode (ADR-0021), and writes only Health and Health Reasons. Refresh Health on the
 * project page checks one project as the person, in user mode.
 */
public with sharing class ProjectHealth implements Schedulable {
	public static final String JOB_NAME = 'BarnCRM Projects Health';
	public static final String ON_TRACK = 'On Track';
	public static final String AT_RISK = 'At Risk';
	public static final String OFF_TRACK = 'Off Track';
	private static final Integer MAX_ROWS = 2000;
	private static final Integer MAX_LISTED = 5;

	/** The step as BarnCRM's nightly run lists it, with a switch that ships on. */
	public static NightlyStep step() {
		return new NightlyStep(
				JOB_NAME,
				BarnHelp.text('Projects', 'Projects_Nightly_StepName'),
				6,
				40,
				new ProjectHealth()
			)
			.withSwitch(true);
	}

	public void execute(SchedulableContext jobContext) {
		try {
			List<Project__c> records = [
				SELECT
					Id,
					Status__c,
					Is_Template__c,
					Target_Date__c,
					Budget_Hours__c,
					Actual_Hours__c,
					Health__c,
					Health_Reasons__c
				FROM Project__c
				WHERE (Status__c = :Projects.ACTIVE AND Is_Template__c = FALSE) OR Health__c != NULL
				WITH SYSTEM_MODE
				ORDER BY Target_Date__c NULLS LAST
				LIMIT :MAX_ROWS
			];
			update as system assess(records, AccessLevel.SYSTEM_MODE);
		} catch (Exception e) {
			ErrorLogger.log(e, 'ProjectHealth');
		}
	}

	/** Refresh Health: one project, read and written as the person. */
	public static void refresh(Id projectId) {
		List<Project__c> records = [
			SELECT
				Id,
				Status__c,
				Is_Template__c,
				Target_Date__c,
				Budget_Hours__c,
				Actual_Hours__c,
				Health__c,
				Health_Reasons__c
			FROM Project__c
			WHERE Id = :projectId
			WITH USER_MODE
		];
		update as user assess(records, AccessLevel.USER_MODE);
	}

	/** Works out R-PM2 for each project; returns those whose Health or reasons changed. */
	@TestVisible
	private static List<Project__c> assess(List<Project__c> records, AccessLevel mode) {
		Date today = Date.today();
		Map<Id, List<String>> late = lateWork(records, today, mode);
		Integer warning = ProjectsSettings.budgetWarningPercent();
		List<Project__c> changed = new List<Project__c>();
		for (Project__c project : records) {
			String health = null;
			List<String> reasons = new List<String>();
			if (project.Status__c == Projects.ACTIVE && !project.Is_Template__c) {
				Boolean offTrack = false;
				if (project.Target_Date__c != null && project.Target_Date__c < today) {
					reasons.add(
						BarnHelp.text(
							'Projects',
							'Projects_Health_TargetPassed',
							new List<Object>{ project.Target_Date__c.format() }
						)
					);
					offTrack = true;
				}
				Decimal budget = project.Budget_Hours__c;
				Decimal used = project.Actual_Hours__c == null ? 0 : project.Actual_Hours__c;
				if (budget != null && budget > 0) {
					Decimal percent = (used * 100 / budget).setScale(0);
					if (used > budget) {
						reasons.add(
							BarnHelp.text(
								'Projects',
								'Projects_Health_OverBudget',
								new List<Object>{ used, budget }
							)
						);
						offTrack = true;
					} else if (percent >= warning) {
						reasons.add(
							BarnHelp.text(
								'Projects',
								'Projects_Health_NearBudget',
								new List<Object>{ used, budget, percent }
							)
						);
					}
				}
				List<String> lateLines = late.get(project.Id);
				if (lateLines != null) {
					reasons.addAll(lateLines);
				}
				health = offTrack ? OFF_TRACK : reasons.isEmpty() ? ON_TRACK : AT_RISK;
			}
			String joined = reasons.isEmpty() ? null : String.join(reasons, '\n');
			if (health != project.Health__c || joined != project.Health_Reasons__c) {
				changed.add(
					new Project__c(Id = project.Id, Health__c = health, Health_Reasons__c = joined)
				);
			}
		}
		return changed;
	}

	/**
	 * The lines for late work by project: a milestone past its due date, or a task past it by
	 * At Risk Days or more. At most five are named; the rest are counted.
	 */
	private static Map<Id, List<String>> lateWork(
		List<Project__c> records,
		Date today,
		AccessLevel mode
	) {
		Map<Id, List<String>> lines = new Map<Id, List<String>>();
		Map<Id, Integer> more = new Map<Id, Integer>();
		Set<Id> active = new Set<Id>();
		for (Project__c project : records) {
			if (project.Status__c == Projects.ACTIVE && !project.Is_Template__c) {
				active.add(project.Id);
			}
		}
		if (active.isEmpty()) {
			return lines;
		}
		// Access mode: the caller's, passed as `mode` (system for the nightly run, user for Refresh Health).
		List<Project_Task__c> tasks = Database.queryWithBinds(
			'SELECT Project__c, Name, Due_Date__c, Milestone__c FROM Project_Task__c ' +
				'WHERE Project__c IN :active AND Status__c NOT IN :closed AND Due_Date__c != NULL ' +
				'AND ((Milestone__c = TRUE AND Due_Date__c < :today) OR Due_Date__c <= :lateBy) ' +
				'ORDER BY Due_Date__c LIMIT 10000',
			new Map<String, Object>{
				'active' => active,
				'closed' => new List<String>{ Projects.DONE, Projects.CANCELLED },
				'today' => today,
				'lateBy' => today.addDays(-ProjectsSettings.atRiskDays())
			},
			mode
		);
		for (Project_Task__c task : tasks) {
			List<String> forProject = lines.get(task.Project__c);
			if (forProject == null) {
				forProject = new List<String>();
				lines.put(task.Project__c, forProject);
			}
			if (forProject.size() < MAX_LISTED) {
				List<Object> args = new List<Object>{ task.Name, task.Due_Date__c.format() };
				forProject.add(
					task.Milestone__c
						? BarnHelp.text('Projects', 'Projects_Health_LateMilestone', args)
						: BarnHelp.text('Projects', 'Projects_Health_LateTask', args)
				);
			} else {
				more.put(
					task.Project__c,
					(more.containsKey(task.Project__c) ? more.get(task.Project__c) : 0) + 1
				);
			}
		}
		for (Id projectId : more.keySet()) {
			lines.get(projectId)
				.add(
					BarnHelp.text(
						'Projects',
						'Projects_Health_MoreLate',
						new List<Object>{ more.get(projectId) }
					)
				);
		}
		return lines;
	}
}
