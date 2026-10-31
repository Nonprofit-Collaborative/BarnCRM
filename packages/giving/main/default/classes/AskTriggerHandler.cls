/**
 * Runs the ask rules (canonical model R-SO2 to R-SO4) on every save, through the dispatcher
 * (registry row `Ask_Stage_And_Dates`, always running).
 */
@NamespaceAccessible
public with sharing class AskTriggerHandler extends TriggerHandler {
    @NamespaceAccessible
    public AskTriggerHandler() {
        return;
    }

    public override void beforeInsert() {
        AskRules.beforeSave(newRecords(), null);
    }

    public override void beforeUpdate() {
        AskRules.beforeSave(newRecords(), oldRecordsById());
    }
}
