/**
 * Keeps the two halves of a matching gift pair in step (feature G-10).
 *
 * Registered on Gift with execution order 40, after the soft credit handler, because linking a
 * gift creates a soft credit of its own and the two must not race.
 *
 * David links a match by setting Matched Gift on the employer's gift, so the rules have to live
 * where that edit lands. The handler validates the pair, writes the other side of the link, and
 * maintains the matched donor credit. A link the rules refuse is reported on the record being
 * saved, in the same words the service uses.
 *
 * It also carries the refund of a linked gift to the credit (ADR-0031). A refund is a negative
 * gift naming the gift it reverses, so it arrives here as an insert like any other, and the
 * matched donor credit it has to reverse belongs to the gift it names rather than to itself.
 */
@NamespaceAccessible
public with sharing class GiftMatchingGiftHandler extends TriggerHandler {
	@NamespaceAccessible
	public GiftMatchingGiftHandler() {
		return;
	}

	public override void afterInsert() {
		List<Gift__c> gifts = asGifts(newRecords());
		MatchingGiftService.applyLinkChanges(gifts, new Map<Id, Gift__c>());
		MatchingGiftService.syncReversalCredits(reversedGiftIds(gifts, null));
	}

	public override void afterUpdate() {
		List<Gift__c> gifts = asGifts(newRecords());
		Map<Id, Gift__c> prior = priorById(oldRecordsById());
		MatchingGiftService.applyLinkChanges(gifts, prior);
		// An edited refund amount changes what the reversal took back, so the negative credit
		// that mirrors it changes too. Nothing else about a reversal moves the credit.
		MatchingGiftService.syncReversalCredits(reversedGiftIds(gifts, prior));
	}

	public override void beforeDelete() {
		List<Gift__c> cleared = new List<Gift__c>();
		for (Gift__c gift : asGifts(oldRecords())) {
			if (gift.Matched_Gift__c != null) {
				cleared.add(new Gift__c(Id = gift.Id, Matched_Gift__c = null));
			}
		}
		MatchingGiftService.applyLinkChanges(cleared, priorById(oldRecordsById()));
	}

	/**
	 * The gifts these records reverse, which are the gifts whose matched donor credits have to be
	 * mirrored negatively. On an update only an amount that moved matters: `prior` null means an
	 * insert, where every reversal counts.
	 */
	private static Set<Id> reversedGiftIds(List<Gift__c> gifts, Map<Id, Gift__c> prior) {
		Set<Id> reversed = new Set<Id>();
		for (Gift__c gift : gifts) {
			if (gift.Original_Gift__c == null) {
				continue;
			}
			Gift__c before = prior == null ? null : prior.get(gift.Id);
			if (prior != null && before != null && before.Amount__c == gift.Amount__c) {
				continue;
			}
			reversed.add(gift.Original_Gift__c);
		}
		return reversed;
	}

	private static Map<Id, Gift__c> priorById(Map<Id, SObject> oldRecordsById) {
		Map<Id, Gift__c> prior = new Map<Id, Gift__c>();
		if (oldRecordsById == null) {
			return prior;
		}
		for (Id recordId : oldRecordsById.keySet()) {
			prior.put(recordId, (Gift__c) oldRecordsById.get(recordId));
		}
		return prior;
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
