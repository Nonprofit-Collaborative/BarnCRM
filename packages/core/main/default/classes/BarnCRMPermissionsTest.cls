/**
 * Tests for BarnCRMPermissions: the settings permission is held by BarnCRM Admin and not by
 * staff, so every page that asks it gets the same answer.
 */
@IsTest(testFor='ApexClass:BarnCRMPermissions')
private class BarnCRMPermissionsTest {
    @IsTest
    static void anAdministratorMayManageSettings() {
        System.runAs(TestUsers.admin()) {
            Assert.isTrue(
                BarnCRMPermissions.canManageSettings(),
                'BarnCRM Admin carries the Manage BarnCRM Settings permission'
            );
        }
    }

    @IsTest
    static void staffMayNotManageSettings() {
        System.runAs(TestUsers.withPermissionSets(new List<String>{ 'BarnCRM_Staff' })) {
            Assert.isFalse(
                BarnCRMPermissions.canManageSettings(),
                'BarnCRM Staff works with records but does not configure the app'
            );
        }
    }
}
