/**
 * The one write that puts a receipt number on a gift, and nothing else.
 *
 * DOCUMENTED EXCEPTION to the "user mode DML" rule (plan Section 4.13), under ADR-0021.
 *
 * ADR-0033 makes `Gift__c.Receipt_Number__c` read only in every packaged permission set, because
 * a receipt number that a person can type is a number that never came from the sequence: it locks
 * the gift irreversibly, it can collide with a number the sequence issues later, and it leaves the
 * gift permanently unreceiptable. Nobody edits the field, so the package has to write it, and a
 * user mode write would be refused for the very user issuing the receipt.
 *
 * The four ADR-0021 conditions:
 *
 * 1. **Permission enforced before this class is reached.** `ReceiptService` checks `Issue_Receipts`
 *    before every call, and `GiftService.recordReceiptNumbers` is the only caller here.
 * 2. **Inputs validated by the caller.** The only value written is a number `ReceiptNumberSequence`
 *    allocated, or null when a receipt is voided. No user typed text reaches this class.
 * 3. **Only package owned fields.** One field on one object, named in the record built by
 *    `recordReceiptNumbers`. The gift's amount, date and donor are not touched here, and the
 *    receipt lock still runs on the save, so a caller could not smuggle them through.
 * 4. **Reads that reach a user stay in user mode.** There are no reads here.
 *
 * `with sharing`, unlike `ReceiptWriter`: the elevation this class needs is field level security
 * on one field, not visibility of records the running user cannot see. A per gift receipt is
 * issued from a gift the user opened, so their sharing already reaches it.
 */
public with sharing class GiftReceiptNumberWriter {
	public static void save(List<Gift__c> gifts) {
		if (gifts == null || gifts.isEmpty()) {
			return;
		}
		Database.update(gifts, true, AccessLevel.SYSTEM_MODE);
	}
}
