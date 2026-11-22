/**
 * Fundraising's step after a settings save (Core seam `SettingsSavedExtension`): when Default
 * Fund changes, each fund's Is Default follows at once (R-F4). The funds that hold the flag and
 * the newly chosen fund are saved unchanged; the Fund trigger sets each flag from the setting,
 * so the rule lives in one place.
 */
public inherited sharing class GivingSettingsSaved implements SettingsSavedExtension {
	private static final String SETTINGS_OBJECT = 'Giving_Settings__c';
	private static final String DEFAULT_FUND_KEY = 'Default_Fund__c';

	public void afterSettingsSaved(String settingsObject, Set<String> changedKeys) {
		if (settingsObject == null || !settingsObject.endsWithIgnoreCase(SETTINGS_OBJECT) || changedKeys == null) {
			return;
		}
		for (String key : changedKeys) {
			if (key != null && key.endsWithIgnoreCase(DEFAULT_FUND_KEY)) {
				syncDefaultFlags();
				return;
			}
		}
	}

	/** Brings every fund's Is Default into line with the Default Fund setting, when it names one. */
	public static void syncDefaultFlags() {
		Id chosen;
		try {
			String stored = ModuleSettings.text('Giving_Default_Fund');
			chosen = String.isBlank(stored) ? null : Id.valueOf(stored);
		} catch (StringException notAnId) {
			return;
		}
		if (chosen == null) {
			return;
		}
		List<Fund__c> funds = [
			SELECT Id
			FROM Fund__c
			WHERE Is_Default__c = TRUE OR Id = :chosen
			WITH SYSTEM_MODE
		];
		if (!funds.isEmpty()) {
			Database.update(funds, AccessLevel.SYSTEM_MODE);
		}
	}
}
