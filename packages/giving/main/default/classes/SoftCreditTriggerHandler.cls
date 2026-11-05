/**
 * The rules a soft credit is saved by (feature G-08).
 *
 * One credited party, a role that says why, and one number entered rather than two that disagree.
 * The amount and the percent are two ways of saying the same thing, so whichever one is missing
 * is worked out from the gift, and a pair that contradicts each other is refused rather than
 * quietly corrected: staff who typed both meant both.
 *
 * "Exactly one credited party" is also a validation rule on the object, so it holds for an import
 * or an integration that never reaches this handler. It is repeated here so that the message a
 * person sees is the same one in both places.
 */
@NamespaceAccessible
public with sharing class SoftCreditTriggerHandler extends TriggerHandler {
	private static final Decimal ROUNDING_TOLERANCE = 0.01;

	@NamespaceAccessible
	public SoftCreditTriggerHandler() {
		return;
	}

	public override void beforeInsert() {
		apply(asCredits(newRecords()));
	}

	public override void beforeUpdate() {
		apply(asCredits(newRecords()));
	}

	private static void apply(List<Soft_Credit__c> credits) {
		if (credits == null || credits.isEmpty()) {
			return;
		}
		Set<Id> giftIds = new Set<Id>();
		for (Soft_Credit__c credit : credits) {
			if (credit.Gift__c != null) {
				giftIds.add(credit.Gift__c);
			}
		}
		Map<Id, Gift__c> giftById = new Map<Id, Gift__c>(
			GiftLookupSelector.selectForRecognition(giftIds)
		);

		for (Soft_Credit__c credit : credits) {
			if (credit.Gift__c == null) {
				credit.addError(Label.Giving_SoftCredit_GiftRequired);
				continue;
			}
			if (!hasExactlyOneCreditedParty(credit)) {
				credit.addError(Label.Giving_SoftCredit_OneCreditedParty);
				continue;
			}
			if ('Other'.equals(credit.Role__c) && String.isBlank(credit.Custom_Role__c)) {
				credit.addError(Label.Giving_SoftCredit_CustomRoleRequired);
				continue;
			}
			Gift__c gift = giftById.get(credit.Gift__c);
			Decimal giftAmount = gift == null ? null : gift.Amount__c;
			if (!settleAmountAndPercent(credit, giftAmount)) {
				credit.addError(Label.Giving_SoftCredit_AmountOrPercent);
			}
		}
	}

	/**
	 * Fills in whichever of amount and percent was left out, and answers false when the two the
	 * staff member typed disagree by more than rounding.
	 */
	private static Boolean settleAmountAndPercent(Soft_Credit__c credit, Decimal giftAmount) {
		if (credit.Amount__c == null && credit.Percent__c == null) {
			// The validation rule on the object says this in the same words.
			return false;
		}
		if (credit.Amount__c == null) {
			credit.Amount__c = SoftCreditService.amountOf(credit.Percent__c, giftAmount);
			return true;
		}
		Decimal impliedPercent = SoftCreditService.percentOf(credit.Amount__c, giftAmount);
		if (credit.Percent__c == null) {
			credit.Percent__c = impliedPercent;
			return true;
		}
		if (impliedPercent == null) {
			return true;
		}
		return Math.abs(impliedPercent - credit.Percent__c) <= ROUNDING_TOLERANCE;
	}

	private static Boolean hasExactlyOneCreditedParty(Soft_Credit__c credit) {
		Boolean hasContact = credit.Contact__c != null;
		Boolean hasAccount = credit.Account__c != null;
		return hasContact != hasAccount;
	}

	private static List<Soft_Credit__c> asCredits(List<SObject> records) {
		List<Soft_Credit__c> credits = new List<Soft_Credit__c>();
		if (records == null) {
			return credits;
		}
		for (SObject record : records) {
			credits.add((Soft_Credit__c) record);
		}
		return credits;
	}
}
