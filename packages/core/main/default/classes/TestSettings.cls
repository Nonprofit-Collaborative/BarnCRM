/**
 * The org-wide BarnCRM settings a test starts from. Hierarchy custom settings saved in the org
 * are visible to tests, so an org that already finished first-run setup (an edition, a feature
 * list, checklist progress) would change the result of any test that assumes a new install.
 * These helpers put those fields back to a never-set-up org inside the test; the change rolls
 * back with the test. Call them inside `System.runAs(TestUsers.admin())`.
 */
@IsTest
public class TestSettings {
    /** An org that never saved an edition, a feature list or checklist progress. */
    public static void neverSetUp() {
        SettingsService.saveSystemValue('Features_Turned_On__c', null);
        SettingsService.saveSystemValue('Suite__c', null);
        SettingsService.saveBookkeeping(
            new Map<String, Object>{ 'Setup_Steps_Completed__c' => '' }
        );
    }

    /** A new install: never set up, with the feature list marked as awaiting first-run setup. */
    public static void newInstall() {
        neverSetUp();
        FeatureSwitchService.markNewInstall();
    }
}
