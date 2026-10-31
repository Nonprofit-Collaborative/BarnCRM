/**
 * LWC-facing entry points for the sampleDataManager component (C-10). Loading and
 * removing check the Manage_BarnCRM_Settings custom permission before doing anything;
 * getStatus() is readable by anyone so the card can show read-only counts.
 *
 * This is the one place a synchronous sample data failure is written to the Error Log:
 * SampleDataLoader throws without logging, so one failure produces one Error Log row.
 */
public with sharing class SampleDataController {
    /**
     * Injected by the tests so the permitted path can be asserted in an org where the
     * Manage_BarnCRM_Settings custom permission (owned by another feature) is not
     * assigned to the running user. Null in production, where the real check runs.
     */
    @TestVisible
    private static Boolean permissionOverride;

    @AuraEnabled
    public static void loadSampleData() {
        try {
            enforcePermission();
            SampleDataLoader.load();
        } catch (Exception e) {
            throw UserErrors.wrap(e, 'SampleDataController.loadSampleData', true);
        }
    }

    @AuraEnabled
    public static SampleDataLoader.Counts removeSampleData() {
        try {
            enforcePermission();
            return SampleDataLoader.remove();
        } catch (Exception e) {
            throw UserErrors.wrap(e, 'SampleDataController.removeSampleData', true);
        }
    }

    @AuraEnabled
    public static SampleDataLoader.Counts getStatus() {
        try {
            return SampleDataLoader.status();
        } catch (Exception e) {
            throw UserErrors.wrap(e, 'SampleDataController.getStatus', true);
        }
    }

    @AuraEnabled
    public static Boolean canManageSampleData() {
        return hasManagePermission();
    }

    private static void enforcePermission() {
        if (!hasManagePermission()) {
            throw new SampleDataException(Label.Core_SampleData_NoPermission);
        }
    }

    private static Boolean hasManagePermission() {
        if (permissionOverride != null) {
            return permissionOverride;
        }
        return BarnCRMPermissions.canManageSettings();
    }
}
