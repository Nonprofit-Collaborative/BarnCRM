/**
 * Keeps a gift's automatic soft credits right (feature G-08).
 *
 * Registered on Gift with execution order 30, so it runs after the gift's own rules have settled
 * the donor, the amount, and the status it is going to save with.
 *
 * It runs after insert, after update when the donor, the amount, or the status changed, and
 * before delete. Nothing else moves an automatic credit, and nothing here ever touches a credit a
 * person entered (R-SC6).
 */
@NamespaceAccessible
public with sharing class GiftSoftCreditHandler extends TriggerHandler {
	@NamespaceAccessible
	public GiftSoftCreditHandler() {
		return;
	}

	public override void afterInsert() {
		SoftCreditService.createHouseholdMemberCredits(asGifts(newRecords()));
	}

	public override void afterUpdate() {
		Map<Id, SObject> priorById = oldRecordsById();
		if (newRecords() == null || priorById == null) {
			return;
		}
		List<Gift__c> changed = new List<Gift__c>();
		for (Gift__c gift : asGifts(newRecords())) {
			Gift__c prior = (Gift__c) priorById.get(gift.Id);
			if (prior == null || recognitionChanged(gift, prior)) {
				changed.add(gift);
			}
		}
		SoftCreditService.createHouseholdMemberCredits(changed);
	}

	public override void beforeDelete() {
		Map<Id, SObject> priorById = oldRecordsById();
		if (priorById == null || priorById.isEmpty()) {
			return;
		}
		SoftCreditService.removeAutomaticCredits(priorById.keySet());
	}

	private static Boolean recognitionChanged(Gift__c gift, Gift__c prior) {
		return gift.Donor_Contact__c != prior.Donor_Contact__c ||
			gift.Donor_Account__c != prior.Donor_Account__c ||
			gift.Amount__c != prior.Amount__c ||
			gift.Status__c != prior.Status__c;
	}

	private static List<Gift__c> asGifts(List<SObject> records) {
		List<Gift__c> gifts = new List<Gift__c>();
		if (records == null) {
			return gifts;
		}
		for (SObject record : records) {
			gifts.add((Gift__c) record);
		}
		return gifts;
	}
}
