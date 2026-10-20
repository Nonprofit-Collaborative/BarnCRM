/**
 * Tests for CustomPermissionSelector (feature C-11, ADR-0024).
 *
 * A custom permission cannot be created with DML, so the selector is exercised two ways:
 * against a name no package ships, which is exactly the shape of a Platform-only org, and
 * against a permission Core does ship, granted to a user the test creates, which is the only
 * way to prove the four queries actually find a holder and name them.
 */
@IsTest(testFor='ApexClass:CustomPermissionSelector')
private class CustomPermissionSelectorTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    /** A developer name deliberately belonging to no package in this repository. */
    private static final String ABSENT_PERMISSION = 'No_Package_Ships_This_Permission';

    @IsTest
    static void aPermissionNoPackageShipsIsHeldByNobody() {
        System.runAs(TestUsers.admin()) {
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
    }

    @IsTest
    static void aPersonHoldingAPermissionIsFoundAndNamed() {
        System.runAs(TestUsers.admin()) {
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
    }

    @IsTest
    static void aBlankPermissionNameAsksNothing() {
        System.runAs(TestUsers.admin()) {
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

    @IsTest
    static void aStatedAnswerIsReturnedAsGiven() {
        System.runAs(TestUsers.admin()) {
            CustomPermissionSelector.Holders stated = new CustomPermissionSelector.Holders();
            stated.total = 7;
            CustomPermissionSelector.holdersOverride = stated;

            System.assertEquals(
                7,
                CustomPermissionSelector.holders(HealthCheckService.MANAGE_SETTINGS).total,
                'A caller that already has the answer is not asked to look it up again.'
            );
        }
    }

    @IsTest
    static void holderIdsListsTheActiveHoldersAndNobodyForAnAbsentPermission() {
        System.runAs(TestUsers.admin()) {
            User maria = HealthCheckTestHelper.mariaWithManageSettings();

            Test.startTest();
            List<Id> holders = CustomPermissionSelector.holderIds(
                HealthCheckService.MANAGE_SETTINGS
            );
            List<Id> nobody = CustomPermissionSelector.holderIds(ABSENT_PERMISSION);
            List<Id> blank = CustomPermissionSelector.holderIds(' ');
            Test.stopTest();

            System.assert(new Set<Id>(holders).contains(maria.Id), 'Maria is a holder.');
            System.assertEquals(0, nobody.size(), 'Nobody holds a permission that does not exist.');
            System.assertEquals(0, blank.size(), 'A blank name is not a question.');
        }
    }

    @IsTest
    static void aReaderWhoCannotSeeSetupIsToldTheAnswerIsUnknown() {
        List<Profile> minimum = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Minimum Access - Salesforce'
            LIMIT 1
        ];
        if (minimum.isEmpty()) {
            return; // An org without the profile has no reader who lacks View Setup to test.
        }
        User setupless = new User(
            Alias = 'nosetup',
            Email = 'nosetup@barncrm.example.invalid',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Setupless',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = minimum[0].Id,
            TimeZoneSidKey = 'GMT',
            Username = 'nosetup.' + System.now().getTime() + '@barncrm.example.invalid'
        );
        insert setupless;
        System.runAs(setupless) {
            Test.startTest();
            CustomPermissionSelector.Holders holders = CustomPermissionSelector.holders(
                HealthCheckService.MANAGE_SETTINGS
            );
            List<Id> ids = CustomPermissionSelector.holderIds(HealthCheckService.MANAGE_SETTINGS);
            Test.stopTest();

            System.assertEquals(
                false,
                holders.readable,
                'A person who cannot read the setup objects must not be told that nobody holds ' +
                'the permission: the answer is unknown, not none.'
            );
            System.assertEquals(0, holders.total, 'No count is claimed.');
            System.assertEquals(0, holders.names.size(), 'No names are claimed.');
            System.assertEquals(0, ids.size(), 'The id list is empty, not partial.');
        }
    }

    @IsTest
    static void aProfileThatGrantsThePermissionMakesItsActiveUsersHolders() {
        User plain = TestUsers.standardUser('ProfileHolder');
        User admin = TestUsers.admin();
        System.runAs(admin) {
            CustomPermission permission = [
                SELECT Id
                FROM CustomPermission
                WHERE DeveloperName = :HealthCheckService.MANAGE_SETTINGS
                LIMIT 1
            ];
            PermissionSet profileOwned = [
                SELECT Id
                FROM PermissionSet
                WHERE IsOwnedByProfile = TRUE AND ProfileId = :TestUsers.standardProfileId()
                LIMIT 1
            ];
            insert as system new SetupEntityAccess(
                ParentId = profileOwned.Id,
                SetupEntityId = permission.Id
            );

            Test.startTest();
            CustomPermissionSelector.Holders holders = CustomPermissionSelector.holders(
                HealthCheckService.MANAGE_SETTINGS
            );
            Test.stopTest();

            System.assertEquals(true, holders.readable, 'The admin can read the setup objects.');
            System.assert(
                new Set<Id>(CustomPermissionSelector.holderIds(HealthCheckService.MANAGE_SETTINGS))
                    .contains(plain.Id),
                'A user holds the permission through the profile that owns the permission set.'
            );
            System.assert(holders.total >= 1, 'The profile holder is counted.');
        }
    }
}
