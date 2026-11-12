/**
 * R-SG11 for Award_Payment__c, run by the Core trigger dispatcher through the registry row
 * `Award_Payment_Rules`, which always runs since it enforces a rule (ADR-0017; ADR-NEXT
 * `NEXT-scholarships-outbound-grants-module.md` decision 10): a disbursement becomes Paid only for
 * a holder of Manage Scholarships and only while no open condition of its award holds it back;
 * an empty Paid Date is filled with today.
 */
@NamespaceAccessible
public with sharing class AwardPaymentRulesHandler extends TriggerHandler {
	@NamespaceAccessible
	public AwardPaymentRulesHandler() {
		return;
	}

	public override String getName() {
		return 'AwardPaymentRulesHandler';
	}

	public override void beforeInsert() {
		check((List<Award_Payment__c>) newRecords(), null);
	}

	public override void beforeUpdate() {
		check((List<Award_Payment__c>) newRecords(), (Map<Id, Award_Payment__c>) oldRecordsById());
	}

	@TestVisible
	private static void check(List<Award_Payment__c> rows, Map<Id, Award_Payment__c> before) {
		List<Award_Payment__c> becomingPaid = new List<Award_Payment__c>();
		Set<Id> awardIds = new Set<Id>();
		for (Award_Payment__c row : rows) {
			Award_Payment__c old = before == null ? null : before.get(row.Id);
			if (
				row.Status__c == ScholarshipAwards.PAID &&
				(old == null ||
				old.Status__c != ScholarshipAwards.PAID)
			) {
				becomingPaid.add(row);
				awardIds.add(row.Award__c);
			}
		}
		if (becomingPaid.isEmpty()) {
			return;
		}
		Boolean manager = Scholarships.canManage();
		Map<Id, Set<Id>> held = ScholarshipAwards.held(awardIds);
		for (Award_Payment__c row : becomingPaid) {
			if (!manager) {
				row.addError(BarnHelp.text('Scholarships', 'Scholarships_Error_NoPermission'));
			} else if (ScholarshipAwards.isHeld(held, row.Award__c, row.Id)) {
				row.addError(BarnHelp.text('Scholarships', 'Scholarships_Paid_Held'));
			} else if (row.Paid_Date__c == null) {
				row.Paid_Date__c = Date.today();
			}
		}
	}
}
