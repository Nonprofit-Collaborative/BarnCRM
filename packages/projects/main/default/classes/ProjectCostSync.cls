/**
 * Puts every project's stored Actual Cost right (`ProjectCostHandler.cost`), in system mode as
 * the module's own bookkeeping (ADR-0021): at install, so a project saved before the field
 * existed gets one, and from the nightly health step once Use rate cards differs from the
 * value the last pass applied (the run-state row `Projects.Cost_Rates_Applied__c`), since a
 * settings save cannot reach every project's save. Writes only projects whose cost differs.
 */
public with sharing class ProjectCostSync implements Database.Batchable<SObject> {
	private static final String LOG_CONTEXT = 'ProjectCostSync';
	@TestVisible
	private static final String APPLIED_KEY = SettingsState.moduleKey('Projects', 'Cost_Rates_Applied__c');

	private final Boolean rates;

	public ProjectCostSync() {
		this.rates = ProjectsSettings.ratesSetting();
	}

	/** Starts a pass, logging rather than throwing when the platform has no room for it. */
	public static void startPass() {
		try {
			AsyncStarter.batch(new ProjectCostSync(), 2000, LOG_CONTEXT);
		} catch (Exception notStarted) {
			ErrorLogger.log(notStarted, LOG_CONTEXT);
		}
	}

	/** Starts a pass when Use rate cards changed since the last one, or none ever ran. */
	public static void startIfRatesChanged() {
		Object applied = SettingsState.get(APPLIED_KEY);
		if (applied == null || (applied == true) != ProjectsSettings.ratesSetting()) {
			startPass();
		}
	}

	public Database.QueryLocator start(Database.BatchableContext context) {
		return Database.getQueryLocator(
			[
				SELECT Id, Time_Amount__c, Actual_Hours__c, Hourly_Rate__c, Actual_Cost_Amount__c
				FROM Project__c
				WITH SYSTEM_MODE
			]
		);
	}

	public void execute(Database.BatchableContext context, List<Project__c> projects) {
		List<Project__c> changed = new List<Project__c>();
		for (Project__c project : projects) {
			Decimal cost = ProjectCostHandler.cost(project, rates);
			if (cost != project.Actual_Cost_Amount__c) {
				changed.add(new Project__c(Id = project.Id, Actual_Cost_Amount__c = cost));
			}
		}
		Integer failed = 0;
		String firstFailure;
		for (Database.SaveResult result : Database.update(changed, false, AccessLevel.SYSTEM_MODE)) {
			if (!result.isSuccess()) {
				failed++;
				firstFailure = firstFailure == null ? result.getErrors()[0].getMessage() : firstFailure;
			}
		}
		if (failed > 0) {
			ErrorLogger.logMessage(
				failed + ' projects kept an old Actual Cost: ' + firstFailure,
				LOG_CONTEXT,
				ErrorLogger.SEVERITY_ERROR
			);
		}
	}

	public void finish(Database.BatchableContext context) {
		try {
			SettingsState.put(new Map<String, Object>{ APPLIED_KEY => rates });
		} catch (Exception notNoted) {
			ErrorLogger.log(notNoted, LOG_CONTEXT);
		}
	}
}
