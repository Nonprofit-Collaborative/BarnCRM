/**
 * The gift page's Gift Allocations card (people-giving-16): the funds a gift is split across,
 * and Edit Funds, which saves a new split in one transaction.
 *
 * The rules stay the triggers': the posting and closed period lock (R-GA5) refuses a change to
 * a gift in the books with its own message, and the allocations must total the gift (R-GA1).
 * This class only orders the statements. Rows that keep their fund are updated, a fund that is
 * new takes over a row whose fund left the split before a row is inserted, and only rows left
 * over are deleted; the total is checked once, on the finished split, and anything refused rolls
 * the whole save back.
 */
public with sharing class GiftAllocationController {
	private static final String CONTEXT = 'Gift Allocations card';
	private static final UserErrors.Screen ERRORS = new UserErrors.Screen(
			CONTEXT,
			'Giving',
			'Giving_Gift_UnexpectedError'
		)
		.showingDml();

	/** One allocation as the card shows it. */
	public class AllocationRow {
		@AuraEnabled
		public Id id;
		@AuraEnabled
		public Id fundId;
		@AuraEnabled
		public String fundName;
		@AuraEnabled
		public Decimal amount;
		@AuraEnabled
		public Decimal percent;
	}

	/** The card, in one round trip. */
	public class AllocationState {
		@AuraEnabled
		public Decimal giftAmount;
		@AuraEnabled
		public List<AllocationRow> rows;
		/** Whether Edit Funds is offered: the person may change allocations and the gift is open. */
		@AuraEnabled
		public Boolean canEdit;
		/** Why the funds cannot change, when the gift is in the books. */
		@AuraEnabled
		public String lockedMessage;
	}

	/** One row of the new split, as the editor sends it. */
	public class AllocationInput {
		@AuraEnabled
		public Id fundId { get; set; }
		@AuraEnabled
		public Decimal amount { get; set; }
	}

	@AuraEnabled
	public static AllocationState getState(Id giftId) {
		try {
			return stateOf(giftId);
		} catch (Exception caught) {
			throw ERRORS.wrap(caught, CONTEXT, giftId);
		}
	}

	/**
	 * Replaces the gift's allocations with `allocations` and returns the card as saved. Nothing
	 * is changed unless the whole split saves.
	 */
	@AuraEnabled
	public static AllocationState save(Id giftId, List<AllocationInput> allocations) {
		Savepoint before = Database.setSavepoint();
		Boolean wasDeferred = GiftService.deferAllocationTotalCheck;
		try {
			Gift__c gift = giftOf(giftId);
			requireComplete(allocations);
			GiftService.deferAllocationTotalCheck = true;
			replace(gift.Id, allocations);
			GiftService.deferAllocationTotalCheck = wasDeferred;
			String problem = GiftService.validateAllocations(new Set<Id>{ gift.Id }).get(gift.Id);
			if (problem != null) {
				throw new GiftService.GiftServiceException(problem);
			}
			return stateOf(gift.Id);
		} catch (Exception caught) {
			Database.rollback(before);
			throw ERRORS.wrap(caught, CONTEXT, giftId);
		} finally {
			GiftService.deferAllocationTotalCheck = wasDeferred;
		}
	}

	private static AllocationState stateOf(Id giftId) {
		Gift__c gift = giftOf(giftId);
		AllocationState state = new AllocationState();
		state.giftAmount = gift.Amount__c;
		state.rows = new List<AllocationRow>();
		for (Gift_Allocation__c allocation : GiftAllocationSelector.selectWithFundNames(gift.Id)) {
			AllocationRow row = new AllocationRow();
			row.id = allocation.Id;
			row.fundId = allocation.Fund__c;
			row.fundName = allocation.Fund__r?.Name;
			row.amount = allocation.Amount__c;
			row.percent = allocation.Percent__c;
			state.rows.add(row);
		}
		Boolean locked = isLocked(gift.Id) && !GiftPostingLock.canOverride();
		state.lockedMessage = locked
			? BarnHelp.text('Giving', 'Giving_Posting_AllocationLocked')
			: null;
		state.canEdit =
			!locked &&
			gift.Amount__c != null &&
			gift.Amount__c != 0 &&
			Schema.SObjectType.Gift_Allocation__c.isCreateable() &&
			Schema.SObjectType.Gift_Allocation__c.isUpdateable();
		return state;
	}

	private static Gift__c giftOf(Id giftId) {
		List<Gift__c> found = giftId == null
			? new List<Gift__c>()
			: GiftSelector.selectWithAllocations(new Set<Id>{ giftId });
		if (found.isEmpty()) {
			throw new GiftService.GiftServiceException(
				BarnHelp.text('Giving', 'Giving_Gift_OriginalNotFound')
			);
		}
		return found[0];
	}

	private static Boolean isLocked(Id giftId) {
		Date closed = GiftPostingLock.closedThrough();
		for (Gift__c gift : GiftPostingSelector.selectLockStateByIds(new Set<Id>{ giftId })) {
			if (GiftPostingLock.isLocked(gift, closed)) {
				return true;
			}
		}
		return false;
	}

	/** Every row needs its own fund and an amount; the editor checks the same before saving. */
	private static void requireComplete(List<AllocationInput> allocations) {
		if (allocations == null || allocations.isEmpty()) {
			throw new GiftService.GiftServiceException(
				BarnHelp.text('Giving', 'Giving_FundSplit_NeedsFund')
			);
		}
		Set<Id> funds = new Set<Id>();
		for (AllocationInput input : allocations) {
			if (input == null || input.fundId == null) {
				throw new GiftService.GiftServiceException(
					BarnHelp.text('Giving', 'Giving_FundSplit_NeedsFund')
				);
			}
			if (input.amount == null || input.amount == 0) {
				throw new GiftService.GiftServiceException(
					BarnHelp.text('Giving', 'Giving_FundSplit_NeedsAmount')
				);
			}
			if (!funds.add(input.fundId)) {
				throw new GiftService.GiftServiceException(
					BarnHelp.text('Giving', 'Giving_FundSplit_DuplicateFund')
				);
			}
		}
	}

	/**
	 * Saves the new split with as few changes as it can: a fund already on the gift keeps its
	 * row, a new fund takes over a row whose fund left, and only what is left over is inserted
	 * or deleted. People who may not delete allocations can still move money between funds.
	 */
	private static void replace(Id giftId, List<AllocationInput> allocations) {
		List<Gift_Allocation__c> existing = GiftAllocationSelector.selectByGiftIds(
			new Set<Id>{ giftId }
		);
		Map<Id, Gift_Allocation__c> byFund = new Map<Id, Gift_Allocation__c>();
		for (Gift_Allocation__c allocation : existing) {
			if (allocation.Fund__c != null && !byFund.containsKey(allocation.Fund__c)) {
				byFund.put(allocation.Fund__c, allocation);
			}
		}

		Set<Id> kept = new Set<Id>();
		List<AllocationInput> unmatched = new List<AllocationInput>();
		List<Gift_Allocation__c> toUpdate = new List<Gift_Allocation__c>();
		for (AllocationInput input : allocations) {
			Gift_Allocation__c same = byFund.get(input.fundId);
			if (same == null) {
				unmatched.add(input);
				continue;
			}
			kept.add(same.Id);
			Decimal amount = input.amount.setScale(2, System.RoundingMode.HALF_UP);
			if (same.Amount__c != amount) {
				toUpdate.add(new Gift_Allocation__c(Id = same.Id, Amount__c = amount));
			}
		}

		List<Gift_Allocation__c> spare = new List<Gift_Allocation__c>();
		for (Gift_Allocation__c allocation : existing) {
			if (!kept.contains(allocation.Id)) {
				spare.add(allocation);
			}
		}

		List<Gift_Allocation__c> toInsert = new List<Gift_Allocation__c>();
		for (AllocationInput input : unmatched) {
			Decimal amount = input.amount.setScale(2, System.RoundingMode.HALF_UP);
			if (!spare.isEmpty()) {
				Gift_Allocation__c reused = spare.remove(0);
				toUpdate.add(
					new Gift_Allocation__c(
						Id = reused.Id,
						Fund__c = input.fundId,
						Amount__c = amount
					)
				);
			} else {
				toInsert.add(
					new Gift_Allocation__c(
						Gift__c = giftId,
						Fund__c = input.fundId,
						Amount__c = amount
					)
				);
			}
		}

		if (!toUpdate.isEmpty()) {
			Database.update(toUpdate, AccessLevel.USER_MODE);
		}
		if (!toInsert.isEmpty()) {
			Database.insert(toInsert, AccessLevel.USER_MODE);
		}
		if (!spare.isEmpty()) {
			if (!Schema.SObjectType.Gift_Allocation__c.isDeletable()) {
				throw new GiftService.GiftServiceException(
					BarnHelp.text('Giving', 'Giving_GiftAllocations_NoDelete')
				);
			}
			Database.delete(spare, AccessLevel.USER_MODE);
		}
	}
}
