/**
 * The one write that moves an hours entry's Status, Approved By, Approved Date and Rejection
 * Reason, and nothing else.
 *
 * DOCUMENTED EXCEPTION to the "user mode DML" rule (plan Section 4.13), under ADR-0021.
 *
 * Approved By and Approved Date are read only in every packaged permission set: an approval a
 * person can type is an approval nobody gave (R-VG5). Nobody edits the fields, so the package
 * writes them, and a user mode write would be refused for the coordinator.
 *
 * The four ADR-0021 conditions:
 *
 * 1. **Permission enforced before this class is reached.** `VolunteerHoursService` checks
 *    `Manage_Volunteers` before every call and is the only caller.
 * 2. **Inputs validated by the caller.** The values written are a status the service chose, the
 *    running user's Id, the current time, and a rejection reason the service checked is present.
 * 3. **Only package owned fields.** Four fields on one object, in records built by the service
 *    with nothing else set. The hours rules and the Approved Hours Are Locked validation rule
 *    still run on the save.
 * 4. **Reads that reach a user stay in user mode.** There are no reads here, and the entries
 *    were read in user mode by the service, so an entry the user cannot see is never moved.
 *
 * `with sharing`: the elevation needed is field level security on two fields, not visibility of
 * records the running user cannot see.
 */
public with sharing class VolunteerHoursWriter {
    /**
     * Saves each entry on its own (all or none off), so one the user can see but not edit, or
     * one a rule refuses, comes back as a failed result for the service to report and never
     * stops the others.
     */
    public static List<Database.SaveResult> save(List<Volunteer_Hours__c> entries) {
        if (entries == null || entries.isEmpty()) {
            return new List<Database.SaveResult>();
        }
        return Database.update(entries, false, AccessLevel.SYSTEM_MODE);
    }
}
