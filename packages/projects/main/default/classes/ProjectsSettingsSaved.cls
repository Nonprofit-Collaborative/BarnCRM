/**
 * Projects' step after a settings save (Core seam `SettingsSavedExtension`): a save of Projects
 * settings starts `ProjectCostSync` when Use rate cards changed since the last pass, so every
 * project's stored Actual Cost follows at once instead of at the next nightly run.
 */
public inherited sharing class ProjectsSettingsSaved implements SettingsSavedExtension {
	public void afterSettingsSaved(String settingsObject, Set<String> changedKeys) {
		if (settingsObject != null && settingsObject.endsWithIgnoreCase('Projects_Settings__c')) {
			ProjectCostSync.startIfRatesChanged();
		}
	}
}
