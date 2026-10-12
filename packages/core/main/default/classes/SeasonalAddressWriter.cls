/**
 * The two writes the nightly seasonal address swap makes (C-18).
 *
 * DOCUMENTED EXCEPTION to the user-mode DML rule (plan Section 7.2), recorded in ADR-0027 as a
 * fifth kind of write under ADR-0021: scheduled reconciliation of package owned data. The swap
 * runs as whoever scheduled it, weeks or years earlier, so there is no user-mode write that can
 * be relied on and no permission to check at the moment of writing. The permission gate sits at
 * the only two ways the job starts instead: `SeasonalAddressController` requires
 * `Manage_BarnCRM_Settings` before scheduling the job or running it now.
 *
 * The conditions of ADR-0021 that still apply are met here:
 *
 * - Only package owned fields are written: `Is_Default__c` and `Replaced_By_Seasonal__c` on
 *   `Address__c`, and the two run keys on the protected settings object.
 * - The values are computed by `SeasonalAddressService` from the seasonal dates on the records.
 *   No user-typed text reaches a query or a dynamic field name; this class builds no SOQL.
 * - Nothing else in the transaction is elevated. The copy of the new default into the standard
 *   address fields is the address automation's work and stays in the user mode it already used,
 *   so a sharing failure there is a real, logged failure rather than an elevated write of
 *   standard fields the package does not own.
 */
public without sharing class SeasonalAddressWriter {
    /**
     * Saves one owner's swap, all of it or none of it.
     *
     * All of it or none of it, and therefore one DML statement per owner rather than one for
     * the whole chunk: a swap is a pair of writes, one address giving up the default flag and
     * another taking it, and a partial save would leave a household with no default address at
     * all and so with no address in its standard address fields. The caller catches the
     * exception, writes it to the Error Log against that owner, and carries on with the rest of
     * the chunk (R-AD8).
     */
    public static void save(List<Address__c> updates) {
        if (updates == null || updates.isEmpty()) {
            return;
        }
        Database.update(updates, true, AccessLevel.SYSTEM_MODE);
    }

    /**
     * Records when the run finished and what it did, on the org-level settings record.
     *
     * No permission is checked, unlike `SettingsWriter`: nobody asked for this write and no
     * value in it came from a person. Both values are produced by the job about itself, and
     * they are the whole of C-18's "visible last run" (R-AD8).
     */
    public static void recordRun(Datetime finishedAt, String summary) {
        OrgSettingsSystemWriter.save(
            new Map<Schema.SObjectField, Object>{
                BarnCRM_Settings__c.Seasonal_Address_Last_Run__c => finishedAt,
                BarnCRM_Settings__c.Seasonal_Address_Last_Run_Summary__c => summary
            }
        );
    }
}
