/**
 * R-GN4 and R-GN8 for Grant__c, run by the Core trigger dispatcher through the registry row
 * `Grant_Rules`, which always runs (ADR-0024): a grant's program and Giving fund are record
 * identifiers of a program and a fund, stored in their 18-character form.
 */
@NamespaceAccessible
public with sharing class GrantRulesHandler extends TriggerHandler {
	@NamespaceAccessible
	public GrantRulesHandler() {
		return;
	}

	public override String getName() {
		return 'GrantRulesHandler';
	}

	public override void beforeInsert() {
		GrantService.checkPrograms((List<Grant__c>) newRecords());
		GrantFundService.checkFunds((List<Grant__c>) newRecords());
	}

	public override void beforeUpdate() {
		List<Grant__c> programChanged = new List<Grant__c>();
		List<Grant__c> fundChanged = new List<Grant__c>();
		Map<Id, Grant__c> oldById = (Map<Id, Grant__c>) oldRecordsById();
		for (Grant__c grant : (List<Grant__c>) newRecords()) {
			Grant__c old = oldById.get(grant.Id);
			if (grant.Program_Id__c != old.Program_Id__c) {
				programChanged.add(grant);
			}
			if (grant.Fund_Id__c != old.Fund_Id__c) {
				fundChanged.add(grant);
			}
		}
		GrantService.checkPrograms(programChanged);
		GrantFundService.checkFunds(fundChanged);
	}
}
