/**
 * Record-level rules for Fund__c: at most one fund is the default, and marking a new one
 * clears the old one rather than asking an administrator to remember (R-F1). The Default Fund
 * setting is the source (R-F4): while it names a fund, each fund's Is Default follows it on every
 * save and a different tick is refused; the trigger never saves the setting.
 */
@NamespaceAccessible
public with sharing class FundTriggerHandler extends TriggerHandler {
	@NamespaceAccessible
	public FundTriggerHandler() {
		return;
	}

	public override String getName() {
		return 'FundTriggerHandler';
	}

	public override void beforeInsert() {
		rejectSeveralDefaults((List<Fund__c>) newRecords());
		followTheSetting((List<Fund__c>) newRecords(), null);
	}

	public override void beforeUpdate() {
		rejectSeveralDefaults((List<Fund__c>) newRecords());
		followTheSetting((List<Fund__c>) newRecords(), (Map<Id, Fund__c>) oldRecordsById());
	}

	public override void afterInsert() {
		clearOtherDefaults((List<Fund__c>) newRecords(), null);
	}

	public override void afterUpdate() {
		clearOtherDefaults((List<Fund__c>) newRecords(), (Map<Id, Fund__c>) oldRecordsById());
	}

	/**
	 * R-F2: a fund that has received gifts is deactivated, not deleted, so historical
	 * allocations keep their meaning. The message says which fund and what to do instead,
	 * rather than leaving the platform to report a foreign key.
	 */
	public override void beforeDelete() {
		List<Fund__c> funds = (List<Fund__c>) oldRecords();
		Map<Id, Fund__c> byId = new Map<Id, Fund__c>(funds);
		Map<Id, Integer> allocationCounts = GiftAllocationSelector.countByFundIds(byId.keySet());
		for (Fund__c fund : funds) {
			Integer used = allocationCounts.get(fund.Id);
			if (used != null && used > 0) {
				fund.addError(BarnHelp.text('Giving', 'Giving_Fund_InUseNotDeletable'));
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
					fund.addError(BarnHelp.text('Giving', 'Giving_Fund_OneDefaultAtATime'));
				}
			}
		}
	}

	/**
	 * R-F4: while the Default Fund setting names a fund, Is Default is that setting shown on the
	 * fund. A save that sets the flag the other way is refused with where to change it; any other
	 * save brings the flag into line. While the setting is blank, the flag itself is the default
	 * (the fund made at install, or one an administrator ticked).
	 */
	private void followTheSetting(List<Fund__c> funds, Map<Id, Fund__c> oldFunds) {
		Id chosen = settingFundId();
		if (chosen == null) {
			return;
		}
		for (Fund__c fund : funds) {
			Boolean shouldBe = fund.Id != null && fund.Id == chosen;
			Fund__c previous = oldFunds == null ? null : oldFunds.get(fund.Id);
			Boolean flagged = fund.Is_Default__c == true;
			Boolean ticked = previous == null ? flagged : flagged != (previous.Is_Default__c == true);
			if (ticked && flagged != shouldBe) {
				fund.addError(BarnHelp.text('Giving', 'Giving_Fund_DefaultFromSettings'));
			} else {
				fund.Is_Default__c = shouldBe;
			}
		}
	}

	/** The fund the Default Fund setting names, or null when it is blank or not an identifier. */
	private static Id settingFundId() {
		String stored = ModuleSettings.text('Giving_Default_Fund');
		try {
			return stored == null ? null : Id.valueOf(stored);
		} catch (StringException notAnId) {
			return null;
		}
	}

	/** R-F1: a fund that just became the default takes the flag from every other fund. */
	private void clearOtherDefaults(List<Fund__c> funds, Map<Id, Fund__c> oldFunds) {
		Set<Id> newDefaults = new Set<Id>();
		for (Fund__c fund : funds) {
			Fund__c previous = oldFunds == null ? null : oldFunds.get(fund.Id);
			if (fund.Is_Default__c == true && (previous == null || previous.Is_Default__c != true)) {
				newDefaults.add(fund.Id);
			}
		}
		if (newDefaults.isEmpty()) {
			return;
		}
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
			for (Fund__c fund : funds) {
				fund.addError(BarnHelp.text('Giving', 'Giving_Fund_DefaultNotSaved'));
			}
		}
	}
}
