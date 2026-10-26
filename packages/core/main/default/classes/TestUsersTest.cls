/**
 * The person every BarnCRM test runs as: created once per transaction, found again after
 * `@TestSetup`, and given exactly the packaged permission sets asked for.
 */
// runs-as: deploying user (it tests TestUsers itself, which creates the test user as the deploying user)
@IsTest
private class TestUsersTest {
    private static final String USERNAME_START = 'barn-test.%';

    @TestSetup
    static void makeTheAdmin() {
        TestUsers.admin();
    }

    @IsTest
    static void theAdminHoldsBarnCrmAdminAndItsCustomPermissions() {
        User admin = TestUsers.admin();

        Integer held = [
            SELECT COUNT()
            FROM PermissionSetAssignment
            WHERE AssigneeId = :admin.Id AND PermissionSet.Name = :TestUsers.CORE_ADMIN
            WITH SYSTEM_MODE
        ];
        Assert.areEqual(1, held, 'The test user holds the packaged BarnCRM Admin set.');
        Assert.areNotEqual(
            UserInfo.getUserId(),
            admin.Id,
            'The test user is never the person running the tests.'
        );
        System.runAs(admin) {
            Assert.isTrue(
                FeatureManagement.checkPermission('Manage_BarnCRM_Settings'),
                'BarnCRM Admin carries the Manage BarnCRM Settings permission.'
            );
            Assert.isTrue(
                Schema.SObjectType.Error_Log__c.fields.Message__c.isAccessible(),
                'BarnCRM Admin can read the Error Log.'
            );
        }
    }

    @IsTest
    static void aUserMadeInTestSetupIsFoundAgainNotMadeTwice() {
        List<User> fromSetup = [
            SELECT Id
            FROM User
            WHERE Username LIKE :USERNAME_START
            WITH SYSTEM_MODE
        ];
        Assert.areEqual(1, fromSetup.size(), 'Test setup made one test user.');

        Assert.areEqual(fromSetup[0].Id, TestUsers.admin().Id, 'The same user comes back.');
        Assert.areEqual(
            TestUsers.admin().Id,
            TestUsers.withPermissionSets(
                    new List<String>{ TestUsers.CORE_ADMIN, TestUsers.CORE_ADMIN }
                )
                .Id,
            'The same set of permission sets, named twice, is the same user.'
        );
        Assert.areEqual(
            1,
            [SELECT COUNT() FROM User WHERE Username LIKE :USERNAME_START WITH SYSTEM_MODE],
            'Asking again made nobody new.'
        );
    }

    @IsTest
    static void otherPermissionSetsMakeAnotherUserHoldingOnlyThose() {
        User reader = TestUsers.withPermissionSets(new List<String>{ 'BarnCRM_Read_Only' });

        Assert.areNotEqual(TestUsers.admin().Id, reader.Id, 'Other sets, other user.');
        Assert.areEqual(
            reader.Id,
            TestUsers.withPermissionSets(new List<String>{ 'BarnCRM_Read_Only' }).Id,
            'Asked again in the same test, the same user comes back.'
        );
        Assert.areEqual(
            0,
            [
                SELECT COUNT()
                FROM PermissionSetAssignment
                WHERE AssigneeId = :reader.Id AND PermissionSet.Name = :TestUsers.CORE_ADMIN
                WITH SYSTEM_MODE
            ],
            'The reader was not given BarnCRM Admin.'
        );
    }

    /** Whether the profile's own permissions give this access on accounts or contacts. */
    private static Boolean profileGrants(Id profileId, Boolean editOnly) {
        for (ObjectPermissions grant : [
            SELECT PermissionsRead, PermissionsEdit
            FROM ObjectPermissions
            WHERE
                Parent.IsOwnedByProfile = TRUE
                AND Parent.ProfileId = :profileId
                AND SobjectType IN ('Account', 'Contact')
            WITH SYSTEM_MODE
        ]) {
            if (grant.PermissionsEdit || (!editOnly && grant.PermissionsRead)) {
                return true;
            }
        }
        return false;
    }

    @IsTest
    static void restrictedProfilesAreFoundByWhatTheyGrantNotOnlyByName() {
        Id byPermissions = TestUsers.firstProfileWithout(true);
        Id readOnlyByPermissions = TestUsers.firstProfileWithout(false);

        Assert.isNotNull(byPermissions, 'Every org has a profile with no account access');
        Assert.isFalse(profileGrants(byPermissions, false), 'It reads no account or contact');
        Assert.isFalse(profileGrants(readOnlyByPermissions, true), 'The read only one edits none');
        Assert.isFalse(
            profileGrants(TestUsers.minimumAccessProfileId(), false),
            'Minimum access, by name or not, reads nothing'
        );
        Assert.isFalse(
            profileGrants(TestUsers.readOnlyProfileId(), true),
            'Read only, by name or not, edits nothing'
        );
    }
}
