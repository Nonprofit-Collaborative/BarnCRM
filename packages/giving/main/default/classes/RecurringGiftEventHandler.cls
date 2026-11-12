/**
 * Runs the recurring gift event rules (canonical model R-RH1, R-RH2) on every save, through the
 * dispatcher (registry row `Recurring_Gift_Event_Health`). The work is in `RecurringGiftUpkeep`.
 */
@NamespaceAccessible
public with sharing class RecurringGiftEventHandler extends TriggerHandler {
	@NamespaceAccessible
	public RecurringGiftEventHandler() {
		return;
	}

	public override void beforeInsert() {
		RecurringGiftUpkeep.match((List<Recurring_Gift_Event__c>) newRecords());
	}

	public override void beforeUpdate() {
		RecurringGiftUpkeep.match((List<Recurring_Gift_Event__c>) newRecords());
	}

	public override void afterInsert() {
		RecurringGiftUpkeep.apply((List<Recurring_Gift_Event__c>) newRecords(), null);
	}

	public override void afterUpdate() {
		RecurringGiftUpkeep.apply((List<Recurring_Gift_Event__c>) newRecords(), oldRecordsById());
	}
}
