/**
 * Tests for PermissionSetSelector: the packaged permission set the post-install script
 * hands to the person who installed BarnCRM.
 */
@IsTest
private class PermissionSetSelectorTest {
    @IsTest
    static void selectByNameFindsThePackagedAdminPermissionSet() {
        PermissionSetSelector selector = new PermissionSetSelector();

        Test.startTest();
        PermissionSet found = selector.selectByNameInSystemMode(AccessService.ADMIN_PERMISSION_SET);
        Test.stopTest();

        Assert.isNotNull(found, 'The Nonprofit Admin permission set ships with BarnCRM Core.');
        Assert.areEqual(
            AccessService.ADMIN_PERMISSION_SET,
            found.Name,
            'The wrong permission set came back.'
        );
    }

    @IsTest
    static void selectByNameReturnsNullForSomethingThatIsNotThere() {
        PermissionSetSelector selector = new PermissionSetSelector();

        Test.startTest();
        PermissionSet missing = selector.selectByNameInSystemMode('No_Such_Permission_Set_Here');
        PermissionSet blank = selector.selectByNameInSystemMode('  ');
        Test.stopTest();

        Assert.isNull(missing, 'A permission set that does not exist should come back as nothing.');
        Assert.isNull(blank, 'A blank name should come back as nothing without querying.');
    }
}
