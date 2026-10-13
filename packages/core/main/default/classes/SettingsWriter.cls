/**
 * Writes the org-level record of a protected hierarchy custom setting.
 *
 * DOCUMENTED EXCEPTION to the user-mode DML rule (plan Section 7.2, and the reason is recorded
 * in ADR-0006 decision 1 and ADR-0017). Settings objects are protected components of a managed
 * package. Protected components are not visible in a subscriber org, so a packaged permission
 * set cannot grant a subscriber user object or field access on them, and a user-mode write is
 * refused for every user who is not an administrator. That contradicts plan Section 2.3, which
 * says any user with the `Manage BarnCRM Settings` custom permission may change settings.
 *
 * So the write runs in system mode, and the permission is the gate instead of the object
 * permission. Three things hold at every call:
 *
 * 1. `FeatureManagement.checkPermission` is re-checked here, not only in the controller, so no
 *    caller can reach the write without the permission.
 * 2. Only fields that exist on the settings object and are named by a shipped Setting Definition
 *    row are written, only the ones whose value changed, and their values have already been
 *    coerced and range checked by `SettingsService`. The write itself goes through
 *    `OrgSettingsSystemWriter`, which updates just those keys on the locked stored record, so
 *    a key another person saved in the meantime is not written back from a stale copy.
 * 3. Nothing else is written in system mode. The `Setting_Change__c` audit records are a normal
 *    custom object and stay in user mode, so an org that has locked audit records down keeps
 *    that control.
 *
 * Reads are unaffected and stay as they were.
 */
public with sharing class SettingsWriter {
    /** Raised when a caller reaches the write without the Manage BarnCRM Settings permission. */
    public class PermissionException extends Exception {
    }

    /**
     * Saves the changed keys on the org-level record of a settings object. The caller has
     * already validated every value, and read `stored` through
     * `OrgSettingsSystemWriter.lockStored(type)` in this transaction (null when the org has no
     * record yet).
     */
    public static void saveOrgDefault(
        Schema.SObjectType type,
        SObject stored,
        Map<Schema.SObjectField, Object> changed
    ) {
        if (changed == null || changed.isEmpty()) {
            return;
        }
        if (!BarnCRMPermissions.canManageSettings()) {
            throw new PermissionException(System.Label.Core_Settings_PermissionRequiredError);
        }
        OrgSettingsSystemWriter.saveOver(type, stored, changed);
    }
}
