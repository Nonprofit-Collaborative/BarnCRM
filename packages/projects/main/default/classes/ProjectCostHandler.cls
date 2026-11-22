/**
 * A project's Actual Cost (`Actual_Cost_Amount__c`, canonical model 29PM1), kept on
 * every project save (registry row `Project_Actual_Cost`, Always Runs). With Use rate cards on,
 * the cost is Time Amount (each counted time entry's amount); off, Actual Hours times the Hourly
 * Rate, blank with no rate. A counted time entry's save changes the project's roll-up summaries,
 * which saves the project through this handler, so the cost follows every entry. Stored, not a
 * formula, because a packaged formula cannot read the settings store (ADR-NEXT settings as
 * custom metadata); `ProjectCostSync` puts every project right after the setting changes.
 */
@NamespaceAccessible
public with sharing class ProjectCostHandler extends TriggerHandler {
	@NamespaceAccessible
	public ProjectCostHandler() {
		return;
	}

	public override void beforeInsert() {
		fill((List<Project__c>) newRecords());
	}

	public override void beforeUpdate() {
		beforeInsert();
	}

	private static void fill(List<Project__c> projects) {
		Boolean rates = ProjectsSettings.ratesSetting();
		for (Project__c project : projects) {
			project.Actual_Cost_Amount__c = cost(project, rates);
		}
	}

	/**
	 * The cost as the project's figures give it: Time Amount with rate cards on (blank counts as
	 * zero), else blank without an Hourly Rate, else Actual Hours (blank counts as zero) times it.
	 */
	public static Decimal cost(Project__c project, Boolean rates) {
		if (rates) {
			return project.Time_Amount__c == null ? 0 : project.Time_Amount__c;
		}
		if (project.Hourly_Rate__c == null) {
			return null;
		}
		Decimal hours = project.Actual_Hours__c == null ? 0 : project.Actual_Hours__c;
		return (hours * project.Hourly_Rate__c).setScale(2);
	}
}
