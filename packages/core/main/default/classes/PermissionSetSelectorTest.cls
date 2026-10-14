/**
 * Tests for PermissionSetSelector: the packaged permission set the post-install script
 * hands to the person who installed BarnCRM.
 */
@IsTest(testFor='ApexClass:PermissionSetSelector')
private class PermissionSetSelectorTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    @IsTest
    static void selectByNameFindsThePackagedAdminPermissionSet() {
        System.runAs(TestUsers.admin()) {
            PermissionSetSelector selector = new PermissionSetSelector();

            Test.startTest();
            PermissionSet found = selector.selectByNameInSystemMode(
                AccessService.ADMIN_PERMISSION_SET
            );
            Test.stopTest();

            Assert.isNotNull(found, 'The BarnCRM Admin permission set ships with BarnCRM Core.');
            Assert.areEqual(
                AccessService.ADMIN_PERMISSION_SET,
                found.Name,
                'The wrong permission set came back.'
            );
        }
    }

    @IsTest
    static void selectByNameReturnsNullForSomethingThatIsNotThere() {
        System.runAs(TestUsers.admin()) {
            PermissionSetSelector selector = new PermissionSetSelector();

            Test.startTest();
            PermissionSet missing = selector.selectByNameInSystemMode(
                'No_Such_Permission_Set_Here'
            );
            PermissionSet blank = selector.selectByNameInSystemMode('  ');
            Test.stopTest();

            Assert.isNull(
                missing,
                'A permission set that does not exist should come back as nothing.'
            );
            Assert.isNull(blank, 'A blank name should come back as nothing without querying.');
        }
    }

    @IsTest
    static void selectPackagedByNamesFindsOnlyTheNamedPackagedSets() {
        System.runAs(TestUsers.admin()) {
            PermissionSetSelector selector = new PermissionSetSelector();
            String namespacePrefix = NamespaceUtil.prefix().removeEnd('__');

            Test.startTest();
            List<PermissionSet> found = selector.selectPackagedByNames(
                new Set<String>{ 'BarnCRM_Bulk_Update', 'No_Such_Permission_Set_Here' },
                namespacePrefix
            );
            List<PermissionSet> none = selector.selectPackagedByNames(
                new Set<String>(),
                namespacePrefix
            );
            Test.stopTest();

            Assert.areEqual(1, found.size(), 'Only the packaged set that exists should be found.');
            Assert.areEqual('BarnCRM_Bulk_Update', found[0].Name, 'It should be the named set.');
            Assert.areEqual(0, none.size(), 'Asking for no names should return nothing.');
        }
    }
}
