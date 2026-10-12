/**
 * Tests for PermissionSetGroupSelector: the packaged roles are found by DeveloperName,
 * and nothing is queried when there is nothing to look for.
 */
@IsTest
private class PermissionSetGroupSelectorTest {
    @IsTest
    static void selectByDeveloperNamesFindsThePackagedRoles() {
        PermissionSetGroupSelector selector = new PermissionSetGroupSelector();

        Test.startTest();
        List<PermissionSetGroup> groups = selector.selectByDeveloperNames(
            new Set<String>(AccessService.ROLE_DEVELOPER_NAMES)
        );
        Test.stopTest();

        Set<String> names = new Set<String>();
        for (PermissionSetGroup groupRecord : groups) {
            names.add(groupRecord.DeveloperName);
        }
        Assert.isTrue(
            names.contains(AccessService.ADMIN_ROLE),
            'The Nonprofit Admin group ships with Open Impact Core and should be found.'
        );
        Assert.isTrue(
            names.contains('Read_Only'),
            'The Read Only group ships with Open Impact Core.'
        );
    }

    @IsTest
    static void selectByDeveloperNamesReturnsNothingForAnEmptySet() {
        PermissionSetGroupSelector selector = new PermissionSetGroupSelector();

        Test.startTest();
        List<PermissionSetGroup> groups = selector.selectByDeveloperNames(new Set<String>());
        Test.stopTest();

        Assert.areEqual(0, groups.size(), 'Asking for no groups should not query the org.');
    }

    @IsTest
    static void selectByDeveloperNameReturnsOneGroup() {
        PermissionSetGroupSelector selector = new PermissionSetGroupSelector();

        Test.startTest();
        PermissionSetGroup groupRecord = selector.selectByDeveloperName('Program_Staff');
        Test.stopTest();

        Assert.isNotNull(groupRecord, 'The Program Staff group ships with Open Impact Core.');
        Assert.areEqual('Program_Staff', groupRecord.DeveloperName, 'The wrong group came back.');
    }

    @IsTest
    static void selectByDeveloperNameReturnsNullForAGroupThatIsNotThere() {
        PermissionSetGroupSelector selector = new PermissionSetGroupSelector();

        Test.startTest();
        PermissionSetGroup missing = selector.selectByDeveloperName('No_Such_Group_Here');
        PermissionSetGroup blank = selector.selectByDeveloperName('  ');
        Test.stopTest();

        Assert.isNull(missing, 'A group that does not exist should come back as nothing.');
        Assert.isNull(blank, 'A blank name should come back as nothing without querying.');
    }
}
