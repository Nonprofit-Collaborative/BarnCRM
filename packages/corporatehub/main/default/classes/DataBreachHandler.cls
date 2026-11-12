/**
 * The breach bell when a breach is logged (CH-22, D-196; canonical model R-DB1), run by the Core
 * trigger dispatcher through the registry row `Data_Breach_Bell`. The bell, its recipient and its
 * once-per-date stamp are `HubReminders.bellLogged`, the same code the nightly run uses; this
 * handler only applies the module's reminder switch.
 */
@NamespaceAccessible
public with sharing class DataBreachHandler extends TriggerHandler {
	@NamespaceAccessible
	public DataBreachHandler() {
		return;
	}

	public override String getName() {
		return 'DataBreachHandler';
	}

	public override void afterInsert() {
		if (CorporateHubSettings.remindersEnabled()) {
			HubReminders.bellLogged((List<Data_Breach__c>) newRecords());
		}
	}
}
