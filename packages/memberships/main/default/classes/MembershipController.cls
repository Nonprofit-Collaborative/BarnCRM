/**
 * The membership panel's controller (`membershipActions`; ADR-NEXT `NEXT-memberships-module.md`,
 * decision 11): what a term can do, renewing it, and emailing a payment link. Thin: plain shapes,
 * user mode, the rules in `MembershipService` and `MembershipPayments`.
 */
public with sharing class MembershipController {
	/** The panel's state for one term. */
	public class Panel {
		@AuraEnabled
		public String status;
		@AuraEnabled
		public Id levelId;
		@AuraEnabled
		public Boolean canRenew = false;
		@AuraEnabled
		public Boolean paymentsReady = false;
		@AuraEnabled
		public Boolean hasEmail = false;
		@AuraEnabled
		public List<Map<String, Object>> levels = new List<Map<String, Object>>();
	}

	@AuraEnabled
	public static Panel panel(Id termId) {
		try {
			Membership_Term__c term = [
				SELECT Id, Status__c, Level__c, Contact__r.Email
				FROM Membership_Term__c
				WHERE Id = :termId
				WITH USER_MODE
			];
			Panel result = new Panel();
			result.status = term.Status__c;
			result.levelId = term.Level__c;
			result.canRenew =
				Schema.SObjectType.Membership_Term__c.isCreateable() &&
				new Set<String>{
						MembershipService.CURRENT,
						MembershipService.GRACE,
						MembershipService.LAPSED
					}
					.contains(term.Status__c);
			result.hasEmail = term.Contact__r?.Email != null;
			result.paymentsReady = MembershipPayments.ready();
			for (Membership_Level__c level : [
				SELECT Id, Name, Dues__c
				FROM Membership_Level__c
				WHERE Active__c = TRUE OR Id = :term.Level__c
				WITH USER_MODE
				ORDER BY Type__c NULLS LAST, Tier__c NULLS LAST, Name
				LIMIT 200
			]) {
				result.levels.add(
					new Map<String, Object>{
						'value' => level.Id,
						'label' => level.Name,
						'dues' => level.Dues__c
					}
				);
			}
			return result;
		} catch (Exception e) {
			throw UserErrors.wrap(e, 'MembershipController.panel', true);
		}
	}

	/** Renews the term at the level chosen; returns the new term's id. */
	@AuraEnabled
	public static Id renew(Id termId, Id levelId) {
		try {
			MembershipService.Renewal renewal = new MembershipService.Renewal(termId);
			renewal.levelId = levelId;
			return MembershipService.renew(new List<MembershipService.Renewal>{ renewal }, false)[0]
				.Id;
		} catch (Exception e) {
			throw UserErrors.wrap(e, 'MembershipController.renew', true);
		}
	}

	/** Queues the payment link email for a term the person may edit. */
	@AuraEnabled
	public static void emailPaymentLink(Id termId) {
		try {
			if (
				[
					SELECT RecordId, HasEditAccess
					FROM UserRecordAccess
					WHERE UserId = :UserInfo.getUserId() AND RecordId = :termId
					WITH SYSTEM_MODE
				]
				?.HasEditAccess != true
			) {
				throw new MembershipService.MembershipException(
					BarnHelp.text('Memberships', 'Memberships_Error_NotFound')
				);
			}
			MembershipPayments.request(termId);
		} catch (Exception e) {
			throw UserErrors.wrap(e, 'MembershipController.emailPaymentLink', true);
		}
	}
}
