/**
 * Fills a new membership term's dues and dates before it is saved (canonical model R-MEM1),
 * run by the Core trigger dispatcher through the registry row `Membership_Term_Dates`, which
 * always runs: a term with no end date would never lapse.
 */
@NamespaceAccessible
public with sharing class MembershipTermHandler extends TriggerHandler {
	@NamespaceAccessible
	public MembershipTermHandler() {
		return;
	}

	public override String getName() {
		return 'MembershipTermHandler';
	}

	public override void beforeInsert() {
		MembershipService.fill((List<Membership_Term__c>) newRecords());
	}
}
