/**
 * The one way Mirror saves a run record on its protected org-level settings in system mode:
 * the Opportunity mirror's last completed run and its summary (R-OM8, ADR-0038 point 4), read by
 * the Opportunity mirror page and by Health Check.
 *
 * A run executes as the administrator who started or scheduled it, and Mirror Settings is a
 * protected setting nobody edits outside the BarnCRM Settings console, so the run cannot save
 * it in user mode. Only the two run keys are written: when a record exists it is locked and only
 * they are updated, so a direction or start date saved meanwhile is never undone; when none
 * exists one is created from the field defaults. The caller carries the authorization (a run it
 * started); this class adds no permission of its own.
 */
public without sharing class MirrorSettingsWriter {
    public static void recordOpportunityMirrorRun(Datetime ranAt, String summary) {
        Mirror_Settings__c keys = new Mirror_Settings__c(
            Opportunity_Mirror_Last_Run__c = ranAt,
            Opportunity_Mirror_Last_Summary__c = summary == null ? null : summary.left(255)
        );
        Id stored = lockStored();
        if (stored == null) {
            Mirror_Settings__c created = (Mirror_Settings__c) Mirror_Settings__c.SObjectType.newSObject(
                null,
                true
            );
            created.SetupOwnerId = UserInfo.getOrganizationId();
            created.Opportunity_Mirror_Last_Run__c = keys.Opportunity_Mirror_Last_Run__c;
            created.Opportunity_Mirror_Last_Summary__c = keys.Opportunity_Mirror_Last_Summary__c;
            try {
                Database.insert(created, AccessLevel.SYSTEM_MODE);
                return;
            } catch (DmlException collided) {
                if (collided.getDmlType(0) != StatusCode.DUPLICATE_VALUE) {
                    throw collided;
                }
                // Someone saved the settings for the first time in the meantime: update theirs.
                stored = lockStored();
            }
        }
        keys.Id = stored;
        Database.update(keys, AccessLevel.SYSTEM_MODE);
    }

    /** The org-level record's Id, locked until the transaction ends, or null when none exists. */
    private static Id lockStored() {
        Id org = UserInfo.getOrganizationId();
        List<Mirror_Settings__c> stored = [
            SELECT Id
            FROM Mirror_Settings__c
            WHERE SetupOwnerId = :org
            WITH SYSTEM_MODE
            LIMIT 1
            FOR UPDATE
        ];
        return stored.isEmpty() ? null : stored[0].Id;
    }
}
