/**
 * Tests for AccessController: what the Access page gets back when Maria uses it, and
 * what David gets back when he opens it without the Manage BarnCRM Settings permission.
 */
@IsTest(testFor='ApexClass:AccessController')
private class AccessControllerTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static final String PROGRAM_ROLE = 'Program_Staff';

    /**
     * Inserts one active user.
     *
     * @param firstName the person's first name
     * @param lastName the person's last name
     * @return the inserted user
     */
    private static User insertUser(String firstName, String lastName) {
        String suffix = String.valueOf(Math.abs(Crypto.getRandomLong()));
        User person = new User(
            FirstName = firstName,
            LastName = lastName,
            Alias = 'oi' + suffix.right(6),
            Email = firstName.toLowerCase() + '.' + suffix + '@example.invalid',
            Username = firstName.toLowerCase() + '.' + suffix + '@barncrm.test.invalid',
            ProfileId = TestUsers.standardProfileId(),
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            IsActive = true
        );
        insert person;
        return person;
    }

    /**
     * Creates Maria: a person who holds the BarnCRM Admin role, and therefore the
     * Manage BarnCRM Settings custom permission that the Access page requires, and BarnCRM
     * Access Manager, which carries the Salesforce permissions to give roles (ADR-0121).
     *
     * @return the inserted user, already in the BarnCRM Admin role
     */
    private static User insertAdminUser() {
        User maria = insertAdminRoleOnly();
        insert new PermissionSetAssignment(
            AssigneeId = maria.Id,
            PermissionSetId = [SELECT Id FROM PermissionSet WHERE Name = 'BarnCRM_Access_Manager']
            .Id
        );
        return maria;
    }

    /**
     * Creates Maria with the BarnCRM Admin role alone, as a Salesforce Platform user holds it:
     * she may manage BarnCRM settings but has no Salesforce permission to give roles.
     *
     * @return the inserted user, in the BarnCRM Admin role only
     */
    private static User insertAdminRoleOnly() {
        PermissionSetGroup adminGroup = TestDataFactory.prepareRoleGroup(AccessService.ADMIN_ROLE);
        User maria = insertUser('Maria', 'Alvarez');
        insert new PermissionSetAssignment(
            AssigneeId = maria.Id,
            PermissionSetGroupId = adminGroup.Id
        );
        return maria;
    }

    @IsTest
    static void theAdminRoleAloneCannotGiveRolesAndSaysSo() {
        System.runAs(TestUsers.admin()) {
            User maria = insertAdminRoleOnly();
            User david = insertUser('David', 'Okafor');
            TestDataFactory.prepareRoleGroup(PROGRAM_ROLE);
            AccessController.AccessResult overview;
            AccessController.AccessResult assigned;
            AccessController.AccessResult removed;

            Test.startTest();
            System.runAs(maria) {
                overview = AccessController.getAccessOverview();
                assigned = AccessController.assignRole(david.Id, PROGRAM_ROLE);
                removed = AccessController.removeRole(maria.Id, AccessService.ADMIN_ROLE);
            }
            Test.stopTest();

            Assert.isTrue(overview.canManage, 'Maria may manage BarnCRM settings.');
            Assert.isFalse(
                overview.canChangeAccess,
                'BarnCRM Admin does not carry Assign Permission Sets, so the page disables changes.'
            );
            for (
                AccessController.AccessResult refused : new List<AccessController.AccessResult>{
                    assigned,
                    removed
                }
            ) {
                Assert.isFalse(refused.success, 'Refused up front.');
                Assert.areEqual(
                    AccessController.ERROR_NO_PERMISSION,
                    refused.errorCode,
                    'A permission refusal, not a failure.'
                );
                Assert.areEqual(
                    Label.Core_Access_ErrorNeedsAccessManager,
                    refused.message,
                    'The reason names BarnCRM Access Manager and the license limit.'
                );
            }
            Assert.areEqual(
                0,
                [
                    SELECT COUNT()
                    FROM PermissionSetAssignment
                    WHERE
                        AssigneeId = :david.Id
                        AND PermissionSetGroup.DeveloperName = :PROGRAM_ROLE
                ],
                'David gets no role.'
            );
        }
    }

    @IsTest
    static void getAccessOverviewTellsThePageWhoMayChangeRoles() {
        System.runAs(TestUsers.admin()) {
            User david = insertUser('David', 'Okafor');
            AccessController.AccessResult result;

            Test.startTest();
            System.runAs(david) {
                result = AccessController.getAccessOverview();
            }
            Test.stopTest();

            Assert.isFalse(
                result.canManage,
                'David has no Manage BarnCRM Settings permission, so the page opens read only for him.'
            );
            // Read only means read, not blank. Either David can see the roles, or the page
            // tells him why he cannot. What it must never do is come back empty and silent.
            Assert.isTrue(
                result.success || String.isNotBlank(result.message),
                'A read only page must either show the roles or say why it cannot.'
            );
            Assert.isNotNull(result.roles, 'The page always gets a list, even an empty one.');
        }
    }

    @IsTest
    static void getAccessOverviewReturnsTheRolesAndTheirMembers() {
        System.runAs(TestUsers.admin()) {
            User maria = insertAdminUser();
            AccessController.AccessResult result;

            Test.startTest();
            System.runAs(maria) {
                result = AccessController.getAccessOverview();
            }
            Test.stopTest();

            Assert.isTrue(result.success, 'Maria should be able to open the Access page.');
            Assert.isTrue(
                result.canManage,
                'Maria holds the BarnCRM Admin role, so she may change roles.'
            );
            Assert.isNotNull(result.roles, 'The page needs the list of roles.');
            Assert.isNotNull(result.assignments, 'The page needs to know who holds each role.');
            // The result was built inside System.runAs(maria), so it carries Maria's id, not
            // the id of the user running the test.
            Assert.areEqual(
                maria.Id,
                result.currentUserId,
                'The page needs to know who is looking at it.'
            );
        }
    }

    @IsTest
    static void assignRoleIsRefusedWithoutThePermission() {
        System.runAs(TestUsers.admin()) {
            User david = insertUser('David', 'Okafor');
            AccessController.AccessResult result;

            Test.startTest();
            System.runAs(david) {
                result = AccessController.assignRole(david.Id, PROGRAM_ROLE);
            }
            Test.stopTest();

            Assert.isFalse(result.success, 'David may not give himself a role.');
            Assert.areEqual(
                AccessController.ERROR_NO_PERMISSION,
                result.errorCode,
                'The page needs a code it can branch on, not only a message.'
            );
            Assert.areEqual(
                Label.Core_Access_ErrorNoPermission,
                result.message,
                'The message should name the permission that is missing.'
            );
        }
    }

    @IsTest
    static void assignRoleRejectsSomethingThatIsNotAUserId() {
        System.runAs(TestUsers.admin()) {
            User maria = insertAdminUser();
            AccessController.AccessResult result;

            Test.startTest();
            System.runAs(maria) {
                result = AccessController.assignRole('not an id', PROGRAM_ROLE);
            }
            Test.stopTest();

            Assert.isFalse(result.success, 'A value that is not a person should be refused.');
            Assert.areEqual(
                AccessController.ERROR_INVALID_INPUT,
                result.errorCode,
                'The refusal should say why.'
            );
        }
    }

    @IsTest
    static void assignRoleRejectsAMissingRole() {
        System.runAs(TestUsers.admin()) {
            User maria = insertAdminUser();
            AccessController.AccessResult result;

            Test.startTest();
            System.runAs(maria) {
                result = AccessController.assignRole(maria.Id, '');
            }
            Test.stopTest();

            Assert.isFalse(result.success, 'Choosing nobody and no role should be refused.');
            Assert.areEqual(
                AccessController.ERROR_INVALID_INPUT,
                result.errorCode,
                'The refusal should say why.'
            );
        }
    }

    @IsTest
    static void assignRoleAndRemoveRoleWorkForMaria() {
        System.runAs(TestUsers.admin()) {
            User maria = insertAdminUser();
            User david = insertUser('David', 'Okafor');
            TestDataFactory.prepareRoleGroup(PROGRAM_ROLE);
            AccessController.AccessResult assigned;
            AccessController.AccessResult removed;

            Test.startTest();
            System.runAs(maria) {
                assigned = AccessController.assignRole(david.Id, PROGRAM_ROLE);
                removed = AccessController.removeRole(david.Id, PROGRAM_ROLE);
            }
            Test.stopTest();

            Assert.isTrue(
                assigned.success,
                'Maria should be able to give David the Team Member role.'
            );
            Assert.isTrue(removed.success, 'Maria should be able to take the role away again.');
            Assert.areEqual(
                0,
                [
                    SELECT COUNT()
                    FROM PermissionSetAssignment
                    WHERE
                        AssigneeId = :david.Id
                        AND PermissionSetGroup.DeveloperName = :PROGRAM_ROLE
                ],
                'David should not hold the role after Maria removes it.'
            );
        }
    }

    @IsTest
    static void assignRoleReportsARoleThatIsNotPackaged() {
        System.runAs(TestUsers.admin()) {
            User maria = insertAdminUser();
            AccessController.AccessResult result;

            Test.startTest();
            System.runAs(maria) {
                result = AccessController.assignRole(maria.Id, 'Some_Other_Group');
            }
            Test.stopTest();

            Assert.isFalse(result.success, 'A role BarnCRM does not ship should be refused.');
            Assert.areEqual(
                AccessController.ERROR_FAILED,
                result.errorCode,
                'The page needs a code it can branch on.'
            );
            Assert.areEqual(
                Label.Core_Access_ErrorRoleNotFound,
                result.message,
                'The message should match the one in the admin guide.'
            );
        }
    }

    @IsTest
    static void searchUsersReturnsMatchingPeople() {
        System.runAs(TestUsers.admin()) {
            User maria = insertAdminUser();
            User david = insertUser('Davidcontroller', 'Okafor');
            AccessController.AccessResult result;

            Test.startTest();
            System.runAs(maria) {
                result = AccessController.searchUsers('Davidcontroller');
            }
            Test.stopTest();

            Assert.isTrue(result.success, 'Searching should not fail.');
            Set<Id> foundIds = new Set<Id>();
            for (AccessService.UserSummary summary : result.users) {
                foundIds.add(summary.userId);
            }
            Assert.isTrue(
                foundIds.contains(david.Id),
                'Maria should find David in the search box.'
            );
        }
    }

    @IsTest
    static void searchUsersIsRefusedWithoutThePermission() {
        System.runAs(TestUsers.admin()) {
            User david = insertUser('David', 'Okafor');
            insertUser('Davidcontroller', 'Okafor');
            AccessController.AccessResult result;

            Test.startTest();
            System.runAs(david) {
                result = AccessController.searchUsers('Davidcontroller');
            }
            Test.stopTest();

            Assert.isFalse(result.success, 'David may not look colleagues up.');
            Assert.areEqual(
                AccessController.ERROR_NO_PERMISSION,
                result.errorCode,
                'The page needs a code it can branch on.'
            );
            Assert.areEqual(0, result.users.size(), 'No names or email addresses come back.');
        }
    }

    @IsTest
    static void searchUsersReturnsNothingForABlankTerm() {
        System.runAs(TestUsers.admin()) {
            AccessController.AccessResult result;

            Test.startTest();
            result = AccessController.searchUsers(null);
            Test.stopTest();

            Assert.isTrue(result.success, 'An empty search box is not an error.');
            Assert.areEqual(
                0,
                result.users.size(),
                'An empty search box should not list the whole org.'
            );
        }
    }

    private static final String ERASE_PEOPLE = 'BarnCRM_Erase_People';

    @IsTest
    static void getAccessOverviewListsTheAddOnsAndWhoMayGiveThem() {
        // Core's add-ons only: a module's rows are counted in AccessServiceTest.
        AccessService.stubbedModuleAddOns = new List<Access_Add_On__mdt>();
        System.runAs(TestUsers.admin()) {
            User maria = insertAdminUser();
            User david = insertUser('David', 'Okafor');
            AccessController.AccessResult forMaria;
            AccessController.AccessResult forDavid;

            Test.startTest();
            System.runAs(maria) {
                forMaria = AccessController.getAccessOverview();
            }
            System.runAs(david) {
                forDavid = AccessController.getAccessOverview();
            }
            Test.stopTest();

            Assert.isTrue(
                forMaria.canChangeAccess,
                'The BarnCRM Admin role carries Assign Permission Sets, so Maria may give add-ons.'
            );
            Assert.areEqual(
                AccessService.ADD_ON_PERMISSION_SETS.size(),
                forMaria.addOns.size(),
                'Maria should see every Core add-on.'
            );
            Assert.areEqual(
                forMaria.addOns.size(),
                forMaria.addOnAssignments.size(),
                'Each add-on should have its list of people.'
            );
            Assert.isFalse(forDavid.canChangeAccess, 'David may not give add-ons.');
            Assert.isNotNull(forDavid.addOns, 'The page always gets a list, even an empty one.');
        }
    }

    @IsTest
    static void assignAddOnIsRefusedWithoutThePermission() {
        System.runAs(TestUsers.admin()) {
            User david = insertUser('David', 'Okafor');
            AccessController.AccessResult result;

            Test.startTest();
            System.runAs(david) {
                result = AccessController.assignAddOn(david.Id, ERASE_PEOPLE);
            }
            Test.stopTest();

            Assert.isFalse(result.success, 'David may not give himself Erase People.');
            Assert.areEqual(
                AccessController.ERROR_NO_PERMISSION,
                result.errorCode,
                'The page needs a code it can branch on.'
            );
            Assert.areEqual(
                0,
                [
                    SELECT COUNT()
                    FROM PermissionSetAssignment
                    WHERE AssigneeId = :david.Id AND PermissionSet.Name = :ERASE_PEOPLE
                ],
                'A refused attempt should leave no assignment behind.'
            );
        }
    }

    @IsTest
    static void assignAddOnIsRefusedWithoutAssignPermissionSets() {
        System.runAs(TestUsers.admin()) {
            // Manage BarnCRM Settings alone is not enough: giving a permission set also needs
            // what Setup itself would need. No packaged set carries the one without the other,
            // but an org's own permission set can, so the check is made to answer no.
            User maria = insertAdminUser();
            User david = insertUser('David', 'Okafor');
            AccessController.AccessResult result;
            AccessController.AccessResult overview;

            Test.startTest();
            System.runAs(maria) {
                AccessService.assignPermissionSetsOverride = false;
                result = AccessController.assignAddOn(david.Id, ERASE_PEOPLE);
                overview = AccessController.getAccessOverview();
            }
            Test.stopTest();

            Assert.isTrue(overview.canManage, 'Maria still manages BarnCRM Settings.');
            Assert.isFalse(overview.canChangeAccess, 'But she may not give add-ons.');
            Assert.isFalse(result.success, 'Her attempt should be refused.');
            Assert.areEqual(
                AccessController.ERROR_NO_PERMISSION,
                result.errorCode,
                'The page needs a code it can branch on.'
            );
            Assert.areEqual(
                Label.Core_Access_ErrorNeedsAccessManager,
                result.message,
                'The message should name the Setup permission that is missing.'
            );
        }
    }

    @IsTest
    static void assignAddOnRejectsSomethingThatIsNotAUserId() {
        System.runAs(TestUsers.admin()) {
            User maria = insertAdminUser();
            AccessController.AccessResult result;
            AccessController.AccessResult blank;

            Test.startTest();
            System.runAs(maria) {
                result = AccessController.assignAddOn('not an id', ERASE_PEOPLE);
                blank = AccessController.removeAddOn('', ERASE_PEOPLE);
            }
            Test.stopTest();

            Assert.areEqual(
                AccessController.ERROR_INVALID_INPUT,
                result.errorCode,
                'A value that is not a person should be refused as invalid.'
            );
            Assert.areEqual(
                AccessController.ERROR_INVALID_INPUT,
                blank.errorCode,
                'Choosing nobody should be refused as invalid.'
            );
        }
    }

    @IsTest
    static void assignAddOnRefusesAPermissionSetOffTheAllowlist() {
        System.runAs(TestUsers.admin()) {
            User maria = insertAdminUser();
            User david = insertUser('David', 'Okafor');
            AccessController.AccessResult result;

            Test.startTest();
            System.runAs(maria) {
                result = AccessController.assignAddOn(david.Id, 'BarnCRM_Admin');
            }
            Test.stopTest();

            Assert.isFalse(result.success, 'Only the Core add-ons may be given here.');
            Assert.areEqual(
                Label.Core_Access_ErrorAddOnNotFound,
                result.message,
                'The refusal should say the permission is not one the page can give.'
            );
        }
    }

    @IsTest
    static void assignAddOnAndRemoveAddOnWorkForMaria() {
        System.runAs(TestUsers.admin()) {
            User maria = insertAdminUser();
            User david = insertUser('David', 'Okafor');
            AccessController.AccessResult assigned;
            AccessController.AccessResult removed;
            Integer held;

            Test.startTest();
            System.runAs(maria) {
                assigned = AccessController.assignAddOn(david.Id, ERASE_PEOPLE);
                held = [
                    SELECT COUNT()
                    FROM PermissionSetAssignment
                    WHERE AssigneeId = :david.Id AND PermissionSet.Name = :ERASE_PEOPLE
                ];
                removed = AccessController.removeAddOn(david.Id, ERASE_PEOPLE);
            }
            Test.stopTest();

            Assert.isTrue(assigned.success, 'Maria should be able to give David Erase People.');
            Assert.areEqual(1, held, 'David should hold Erase People once given it.');
            Assert.isTrue(removed.success, 'Maria should be able to take it away again.');
            Assert.areEqual(
                0,
                [
                    SELECT COUNT()
                    FROM PermissionSetAssignment
                    WHERE AssigneeId = :david.Id AND PermissionSet.Name = :ERASE_PEOPLE
                ],
                'David should not hold Erase People after Maria removes it.'
            );
        }
    }
}
