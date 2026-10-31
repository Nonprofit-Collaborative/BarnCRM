/**
 * Every write the pledge reminder feature makes to package owned data (G-30).
 *
 * DOCUMENTED EXCEPTION to the "user mode DML" rule (plan Section 4.13), under ADR-0021, on the
 * same four conditions as `AcknowledgmentWriter`:
 *
 * 1. **Permission enforced before this class is reached.** `PledgeReminderController` and
 *    `PledgeReminderService` check Send Acknowledgments, and that the feature is turned on,
 *    before anything here runs.
 * 2. **Inputs validated by the caller.** Every field written is computed by package code from
 *    records the running user was already allowed to read. The only free text stored is a failure
 *    reason the platform produced, never used in a query or a dynamic field name.
 * 3. **Only package owned fields.** The reminder log and its own file link are the only things
 *    written. Nothing on the installment, the pledge or the donor is touched.
 * 4. **Reads that reach a user stay in user mode.** `PledgeReminderSelector` runs
 *    `WITH USER_MODE`.
 *
 * `without sharing` rather than `with sharing`: a nightly run reminds donors the scheduling user
 * may not personally be able to see, and a reminder that quietly did not go out is worse than one
 * sent on behalf of somebody who cannot open the pledge.
 */
public without sharing class PledgeReminderWriter {
    /**
     * Inserts rows one at a time, keeping the ones that went in and reporting the ones that did
     * not. The unique key on each row is the claim: a row whose installment and step already have
     * a standing reminder fails, and that failure is the answer "already reminded".
     */
    public static List<Database.SaveResult> claim(List<Pledge_Reminder__c> rows) {
        if (rows == null || rows.isEmpty()) {
            return new List<Database.SaveResult>();
        }
        return Database.insert(rows, false, AccessLevel.SYSTEM_MODE);
    }

    public static void updateReminders(List<Pledge_Reminder__c> rows) {
        if (rows == null || rows.isEmpty()) {
            return;
        }
        Database.update(rows, true, AccessLevel.SYSTEM_MODE);
    }
}
