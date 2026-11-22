/**
 * A module's step after a settings save lands (ADR-NEXT settings as custom metadata): Core hands
 * every module that registers this seam in its catalog row's `Extensions__c`
 * (`SettingsSavedExtension: <Class>`) the settings group and keys a save changed, so a module
 * keeps records that show a setting in line at once (Fundraising's Is Default flag on funds).
 * Core names no module class; `SettingsService.afterSaved` finds them through `ModuleExtensions`.
 * A failure is logged and the saved setting stands.
 */
@NamespaceAccessible
public interface SettingsSavedExtension {
	/**
	 * Called once per settings group a save changed, after the values are stored.
	 *
	 * @param settingsObject the group's legacy settings object name, such as `Giving_Settings__c`
	 * @param changedKeys the changed keys, as the legacy field names
	 */
	void afterSettingsSaved(String settingsObject, Set<String> changedKeys);
}
