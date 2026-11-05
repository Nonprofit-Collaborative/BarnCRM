/**
 * The one write that sets or clears a gift's posting fields, and nothing else.
 *
 * DOCUMENTED EXCEPTION to the "user mode DML" rule (plan Section 4.13), under ADR-0021.
 *
 * ADR-0053 makes `Gift__c.Accounting_Posted_At__c` and `Accounting_Posted_By__c` read only in
 * every packaged permission set: a posting mark a person can type is a mark nobody recorded, and
 * it would lock or unlock a gift without the unpost reason being logged. Nobody edits the fields,
 * so the package has to write them, and a user mode write would be refused for the bookkeeper.
 *
 * The four ADR-0021 conditions:
 *
 * 1. **Permission enforced before this class is reached.** `GiftPostingService` checks
 *    `Post_Gifts` before every call and is the only caller.
 * 2. **Inputs validated by the caller.** The values written are the current time and the running
 *    user's Id, or null when a gift is unposted. No user typed text reaches this class.
 * 3. **Only package owned fields.** Two fields on one object, in records built by
 *    `GiftPostingService` with nothing else set. The posting and receipt locks still run on the
 *    save, so a caller could not carry an amount or a date through.
 * 4. **Reads that reach a user stay in user mode.** There are no reads here, and the gifts were
 *    read in user mode by the service, so a gift the user cannot see is never marked.
 *
 * `with sharing`: the elevation needed is field level security on two fields, not visibility of
 * records the running user cannot see.
 */
public with sharing class GiftPostingWriter {
	public static void save(List<Gift__c> gifts) {
		if (gifts == null || gifts.isEmpty()) {
			return;
		}
		Database.update(gifts, true, AccessLevel.SYSTEM_MODE);
	}
}
