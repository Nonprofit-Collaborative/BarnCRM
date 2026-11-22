/**
 * The one write that sets Books Closed Through, and nothing else. It is run state, not a setting
 * (ADR-0238 settings as custom metadata, decision 6): one `GivingState` row, written
 * synchronously in system mode (ADR-0021).
 *
 * The four ADR-0021 conditions:
 *
 * 1. **Permission enforced before this class is reached.** `AccountingPeriodController` checks
 *    Manage BarnCRM Settings, and Override Posting Lock for a date that reopens a period,
 *    before its call to save.
 * 2. **Inputs validated by the caller.** The date is typed as a Date and checked to be before
 *    today; no text reaches this class.
 * 3. **Only package owned state.** One Fundraising state row.
 * 4. **Reads that reach a user stay in user mode.** The one read here is the stored close date,
 *    locked so the controller decides from the value it is about to replace; the page itself
 *    reads the date through `GiftPostingLock`, as before.
 */
public with sharing class AccountingPeriodWriter {
	/**
	 * The stored close date, read under a lock that holds until the transaction ends, so two
	 * people closing or reopening at once take turns instead of both deciding from the same
	 * value. Null when no period is closed.
	 */
	public static Date lockedClosedThrough() {
		GivingState.lock(GivingState.BOOKS_CLOSED_THROUGH);
		return GivingState.dateValue(GivingState.BOOKS_CLOSED_THROUGH);
	}

	/** Saves the close date and nothing else. */
	public static void saveClosedThrough(Date closeDate) {
		GivingState.put(new Map<String, Object>{ GivingState.BOOKS_CLOSED_THROUGH => closeDate });
	}
}
