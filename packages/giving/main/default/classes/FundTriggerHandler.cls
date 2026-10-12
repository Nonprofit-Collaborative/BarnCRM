/**
 * Record-level rules for Fund__c: at most one fund is the default, and marking a new one
 * clears the old one rather than asking an administrator to remember (R-F1).
 */
public with sharing class FundTriggerHandler extends TriggerHandler {
    public override String getName() {
        return 'FundTriggerHandler';
    }

    public override void beforeInsert() {
        rejectSeveralDefaults((List<Fund__c>) Trigger.new);
    }

    public override void beforeUpdate() {
        rejectSeveralDefaults((List<Fund__c>) Trigger.new);
    }

    public override void afterInsert() {
        recordTheDefault((List<Fund__c>) Trigger.new, null);
    }

    public override void afterUpdate() {
        recordTheDefault((List<Fund__c>) Trigger.new, (Map<Id, Fund__c>) Trigger.oldMap);
    }

    /**
     * R-F2: a fund that has received gifts is deactivated, not deleted, so historical
     * allocations keep their meaning. The message says which fund and what to do instead,
     * rather than leaving the platform to report a foreign key.
     */
    public override void beforeDelete() {
        List<Fund__c> funds = (List<Fund__c>) Trigger.old;
        Map<Id, Fund__c> byId = new Map<Id, Fund__c>(funds);
        Map<Id, Integer> allocationCounts = GiftAllocationSelector.countByFundIds(byId.keySet());
        for (Fund__c fund : funds) {
            Integer used = allocationCounts.get(fund.Id);
            if (used != null && used > 0) {
                fund.addError(Label.Giving_Fund_InUseNotDeletable);
            }
        }
    }

    /**
     * One save that marks two funds as the default has no defensible answer, so it is refused
     * rather than guessed at.
     */
    private void rejectSeveralDefaults(List<Fund__c> funds) {
        Integer defaults = 0;
        for (Fund__c fund : funds) {
            if (fund.Is_Default__c == true) {
                defaults++;
            }
        }
        if (defaults > 1) {
            for (Fund__c fund : funds) {
                if (fund.Is_Default__c == true) {
                    fund.addError(Label.Giving_Fund_OneDefaultAtATime);
                }
            }
        }
    }

    /**
     * R-F1 and R-F4: the flag on the fund and the Default Fund key in Giving settings are two
     * faces of one decision, so marking a fund writes both. Otherwise the key silently wins and
     * ticking the box does nothing, which is what the funds guide promises it will not do.
     */
    private void recordTheDefault(List<Fund__c> funds, Map<Id, Fund__c> oldFunds) {
        Set<Id> newDefaults = new Set<Id>();
        Set<Id> droppedDefaults = new Set<Id>();
        for (Fund__c fund : funds) {
            Fund__c previous = oldFunds == null ? null : oldFunds.get(fund.Id);
            Boolean wasDefault = previous != null && previous.Is_Default__c == true;
            if (fund.Is_Default__c == true && !wasDefault) {
                newDefaults.add(fund.Id);
            } else if (wasDefault && fund.Is_Default__c != true) {
                droppedDefaults.add(fund.Id);
            }
        }
        if (newDefaults.isEmpty() && droppedDefaults.isEmpty()) {
            return;
        }

        if (!newDefaults.isEmpty()) {
            clearOtherDefaults(newDefaults);
            writeSettingsKey(new List<Id>(newDefaults)[0]);
        } else if (stillTheStoredDefault(droppedDefaults)) {
            writeSettingsKey(null);
        }
    }

    private void clearOtherDefaults(Set<Id> newDefaults) {
        List<Fund__c> toClear = FundSelector.selectOtherDefaults(newDefaults);
        if (toClear.isEmpty()) {
            return;
        }
        for (Fund__c fund : toClear) {
            fund.Is_Default__c = false;
        }
        try {
            Database.update(toClear, AccessLevel.USER_MODE);
        } catch (Exception clearError) {
            ErrorLogger.log(clearError, 'FundTriggerHandler.clearOtherDefaults');
            reportFailure();
        }
    }

    /**
     * True when the key still names one of the funds that just lost the flag, which is the only
     * case where dropping the flag should empty the key.
     */
    private Boolean stillTheStoredDefault(Set<Id> droppedDefaults) {
        String stored = Giving_Settings__c.getOrgDefaults().Default_Fund__c;
        return String.isNotBlank(stored) && droppedDefaults.contains((Id) stored);
    }

    private void writeSettingsKey(Id fundId) {
        try {
            SettingsService.saveValues(
                'Giving_Settings__c',
                new Map<String, Object>{
                    'Default_Fund__c' => fundId == null ? null : String.valueOf(fundId)
                }
            );
        } catch (Exception settingsError) {
            ErrorLogger.log(settingsError, 'FundTriggerHandler.writeSettingsKey');
            reportFailure();
        }
    }

    private void reportFailure() {
        for (Fund__c fund : (List<Fund__c>) Trigger.new) {
            fund.addError(Label.Giving_Fund_DefaultNotSaved);
        }
    }
}
