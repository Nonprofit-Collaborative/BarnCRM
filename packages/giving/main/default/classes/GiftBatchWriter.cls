/**
 * The two writes only posting makes: a line's Gift, and the batch's Status (G-17, R-GB4).
 *
 * DOCUMENTED EXCEPTION to the "user mode DML" rule (plan Section 4.13), under ADR-0021.
 *
 * Both fields are read only in every packaged permission set, because a person who could set
 * Status to Posted could close a batch without creating its gifts, and one who could set a line's
 * Gift could point the record of a deposit at a gift it never produced. Nobody edits them, so the
 * package writes them, and a user mode write would be refused for the person posting.
 *
 * The four ADR-0021 conditions:
 *
 * 1. **Permission enforced before this class is reached.** `GiftBatchService.post` is the only
 *    caller. It has read the batch in user mode with a row lock, and it calls here only after the
 *    gifts were inserted in user mode, so the platform has already authorized the person's own
 *    write of every gift these fields point at.
 * 2. **Inputs validated by the caller.** The values are the identifiers of the gifts just
 *    inserted and the constant Posted. No typed text reaches this class.
 * 3. **Only package owned fields.** `Gift_Batch_Row__c.Gift__c` and `Gift_Batch__c.Status__c`,
 *    on records built here with nothing else set.
 * 4. **Reads that reach a user stay in user mode.** There are no reads here.
 *
 * `with sharing`: the elevation needed is field level security, not visibility. A person who
 * cannot edit the batch record still cannot post it.
 */
public with sharing class GiftBatchWriter {
	public static final String STATUS_POSTED = 'Posted';

	/** Points each line at the gift it produced. */
	public static void linkGifts(Map<Id, Id> giftIdByRowId) {
		List<Gift_Batch_Row__c> rows = new List<Gift_Batch_Row__c>();
		for (Id rowId : giftIdByRowId.keySet()) {
			rows.add(new Gift_Batch_Row__c(Id = rowId, Gift__c = giftIdByRowId.get(rowId)));
		}
		Database.update(rows, true, AccessLevel.SYSTEM_MODE);
	}

	/** Closes the batch. The validation rule `Posted_Batch_Is_Final` keeps it closed. */
	public static void markPosted(Id batchId) {
		Database.update(
			new Gift_Batch__c(Id = batchId, Status__c = STATUS_POSTED),
			true,
			AccessLevel.SYSTEM_MODE
		);
	}
}
