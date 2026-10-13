/**
 * One console Save that changes a Core setting and a Giving setting together (ADMIN-13 b),
 * made by an administrator holding only the shipped permission sets, not a set built for the
 * test (ADMIN-13 e). The console groups the keys by the settings object each row names and
 * saves each object in turn, so this is the path a module's row takes in a real org.
 */
@IsTest
private class ConsoleSaveAcrossModulesTest {
    private static final String CORE_KEY = 'Household_Name_Pattern__c';
    private static final String GIVING_KEY = 'Organization_EIN__c';

    @IsTest
    static void oneSaveChangesACoreAndAGivingSettingWithTheShippedAdminSets() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Assert.isTrue(
                FeatureManagement.checkPermission('Manage_BarnCRM_Settings'),
                'The shipped BarnCRM Admin set carries Manage BarnCRM Settings'
            );

            Test.startTest();
            SettingsController.ConsoleModel model = SettingsController.saveSettings(
                new Map<String, Object>{
                    CORE_KEY => 'The {LastName} Household',
                    GIVING_KEY => '12-3456789'
                }
            );
            Test.stopTest();

            Assert.isTrue(model.canEdit, 'The page comes back editable');
            Assert.areEqual(
                'The {LastName} Household',
                SettingsService.getValue(CORE_KEY),
                'The Core setting is saved on BarnCRM Settings'
            );
            Assert.areEqual(
                '12-3456789',
                Giving_Settings__c.getOrgDefaults().Organization_EIN__c,
                'and the Giving setting on Giving Settings, in the same Save'
            );
            Set<String> audited = new Set<String>();
            for (SettingsController.ChangeModel change : SettingsController.getRecentChanges(10)) {
                audited.add(change.settingName);
            }
            Assert.areEqual(2, audited.size(), 'Both changes are in the history: ' + audited);
        }
    }
}
