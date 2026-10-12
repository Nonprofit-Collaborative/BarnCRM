/**
 * The one write that sets Books Closed Through, and nothing else.
 *
 * DOCUMENTED EXCEPTION to the "user mode DML" rule (plan Section 4.13), under ADR-0021 and for
 * the reason `SettingsWriter` gives (ADR-0006, ADR-0017): `Giving_Settings__c` is a protected
 * custom setting, so no packaged permission set can grant a subscriber user access to it and a
 * user mode write is refused for everyone who is not a system administrator.
 *
 * The four ADR-0021 conditions:
 *
 * 1. **Permission enforced before this class is reached.** `AccountingPeriodController` checks
 *    Manage Nonprofit Settings, and Override Posting Lock for a date that reopens a period,
 *    before its call to save.
 * 2. **Inputs validated by the caller.** The date is typed as a Date and checked to be before
 *    today; no text reaches this class.
 * 3. **Only package owned fields.** One field on the Giving settings org default.
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
        Giving_Settings__c stored = (Giving_Settings__c) OrgSettingsSystemWriter.lockStored(
            Giving_Settings__c.SObjectType
        );
        return stored?.Books_Closed_Through__c;
    }

    /**
     * Saves the close date and nothing else. A first save keeps the checkboxes that ship on
     * (OrgSettingsSystemWriter).
     */
    public static void saveClosedThrough(Date closeDate) {
        OrgSettingsSystemWriter.save(
            Giving_Settings__c.SObjectType,
            new Map<Schema.SObjectField, Object>{
                Giving_Settings__c.Books_Closed_Through__c => closeDate
            }
        );
    }
}
