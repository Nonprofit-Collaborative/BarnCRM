/**
 * Tests for CustomPermissionSelector (feature C-11, ADR-0024).
 *
 * A custom permission cannot be created with DML, so the selector is exercised two ways:
 * against a name no package ships, which is exactly the shape of a Platform-only org, and
 * against a permission Core does ship, granted to a user the test creates, which is the only
 * way to prove the four queries actually find a holder and name them.
 */
@IsTest
private class CustomPermissionSelectorTest {
    /** A developer name deliberately belonging to no package in this repository. */
    private static final String ABSENT_PERMISSION = 'No_Package_Ships_This_Permission';

    @IsTest
    static void aPermissionNoPackageShipsIsHeldByNobody() {
        Test.startTest();
        CustomPermissionSelector.Holders holders = CustomPermissionSelector.holders(
            ABSENT_PERMISSION
        );
        Test.stopTest();

        System.assertEquals(
            true,
            holders.readable,
            'The setup objects were readable, so the answer stands: this is a real "nobody", ' +
            'not a question that could not be asked.'
        );
        System.assertEquals(
            0,
            holders.total,
            'A custom permission that is not in the org is held by nobody. This is the ' +
                'Platform-only org shape: Giving is not installed, the permission does not ' +
                'exist, and Core answers rather than failing.'
        );
        System.assertEquals(
            0,
            holders.names.size(),
            'With no holders there are no names to print.'
        );
    }

    @IsTest
    static void aPersonHoldingAPermissionIsFoundAndNamed() {
        User maria = HealthCheckTestHelper.mariaWithManageSettings();
        String mariaName = [SELECT Name FROM User WHERE Id = :maria.Id].Name;

        Test.startTest();
        CustomPermissionSelector.Holders holders = CustomPermissionSelector.holders(
            HealthCheckService.MANAGE_SETTINGS
        );
        Test.stopTest();

        System.assert(
            holders.total >= 1,
            'Maria was given the permission through a permission set, so the selector has to ' +
            'find at least one holder.'
        );
        System.assert(
            new Set<String>(holders.names).contains(mariaName),
            'The finding names people, so the selector has to return the holder by name, not ' +
                'just count one. Expected ' +
                mariaName +
                ' among ' +
                String.join(holders.names, ', ')
        );
    }

    @IsTest
    static void aBlankPermissionNameAsksNothing() {
        CustomPermissionSelector.Holders holders = CustomPermissionSelector.holders(null);

        System.assertEquals(
            0,
            holders.total,
            'A missing name is not a question, so it does not become a finding.'
        );
        System.assertEquals(
            true,
            holders.readable,
            'Nothing failed: there was simply nothing to ask.'
        );
    }
}
