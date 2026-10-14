/**
 * Tests for UserSelector: the search box behind "Find a person" on the Access page.
 */
@IsTest(testFor='ApexClass:UserSelector')
private class UserSelectorTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

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

    @IsTest
    static void searchActiveFindsAPersonByTheStartOfTheirName() {
        System.runAs(TestUsers.admin()) {
            User david = insertUser('Davidselector', 'Okafor');
            UserSelector selector = new UserSelector();

            Test.startTest();
            List<User> found = selector.searchActive('Davidselector', 20);
            Test.stopTest();

            Set<Id> foundIds = new Set<Id>();
            for (User person : found) {
                foundIds.add(person.Id);
            }
            Assert.isTrue(
                foundIds.contains(david.Id),
                'Typing the start of a name should find the person.'
            );
        }
    }

    @IsTest
    static void searchActiveIgnoresBlankTermsAndSillyLimits() {
        System.runAs(TestUsers.admin()) {
            UserSelector selector = new UserSelector();

            Test.startTest();
            List<User> blank = selector.searchActive('   ', 20);
            List<User> noLimit = selector.searchActive('Maria', 0);
            Test.stopTest();

            Assert.areEqual(0, blank.size(), 'A blank search should not list the whole org.');
            Assert.areEqual(0, noLimit.size(), 'A limit of zero should return nothing.');
        }
    }

    @IsTest
    static void searchActiveTreatsWildcardCharactersAsText() {
        System.runAs(TestUsers.admin()) {
            insertUser('Priyawild', 'Nair');
            UserSelector selector = new UserSelector();

            Test.startTest();
            List<User> found = selector.searchActive('%', 20);
            Test.stopTest();

            Assert.areEqual(
                0,
                found.size(),
                'A percent sign is a character to search for, not a wildcard.'
            );
        }
    }

    @IsTest
    static void searchActiveRespectsTheLimit() {
        System.runAs(TestUsers.admin()) {
            List<User> staff = new List<User>();
            for (Integer i = 0; i < 3; i++) {
                staff.add(insertUser('Limitcheck' + i, 'Bulk'));
            }
            UserSelector selector = new UserSelector();

            Test.startTest();
            List<User> found = selector.searchActive('Limitcheck', 2);
            Test.stopTest();

            Assert.areEqual(
                2,
                found.size(),
                'The search should return no more than it was asked for.'
            );
            Assert.areEqual(3, staff.size(), 'Three people were created for this check.');
        }
    }

    @IsTest
    static void selectActiveByIdsReturnsOnlyActivePeople() {
        System.runAs(TestUsers.admin()) {
            User david = insertUser('David', 'Okafor');
            UserSelector selector = new UserSelector();

            Test.startTest();
            List<User> found = selector.selectActiveByIds(new Set<Id>{ david.Id });
            List<User> none = selector.selectActiveByIds(new Set<Id>());
            Test.stopTest();

            Assert.areEqual(1, found.size(), 'An active person should be returned.');
            Assert.areEqual(david.Id, found[0].Id, 'The wrong person came back.');
            Assert.areEqual(0, none.size(), 'Asking about nobody should return nothing.');
        }
    }

    @IsTest
    static void runningUserPermissionAccessReflectsEffectivePermissions() {
        System.runAs(TestUsers.admin()) {
            User priya = insertUser('Priya', 'Nair');
            UserSelector selector = new UserSelector();
            UserPermissionAccess adminAccess;
            UserPermissionAccess priyaAccess;

            Test.startTest();
            adminAccess = selector.selectRunningUserPermissionAccess();
            System.runAs(priya) {
                priyaAccess = selector.selectRunningUserPermissionAccess();
            }
            Test.stopTest();

            Assert.isTrue(
                adminAccess.PermissionsAssignPermissionSets,
                'A System Administrator can assign permission sets.'
            );
            Assert.isFalse(
                priyaAccess.PermissionsAssignPermissionSets || priyaAccess.PermissionsManageUsers,
                'A standard user can neither assign permission sets nor manage users.'
            );
        }
    }
}
