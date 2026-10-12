/**
 * Tests for UserSelector: the search box behind "Find a person" on the Access page.
 */
@IsTest
private class UserSelectorTest {
    /**
     * Inserts one active user.
     *
     * @param firstName the person's first name
     * @param lastName the person's last name
     * @return the inserted user
     */
    private static User insertUser(String firstName, String lastName) {
        Profile standardProfile = leastPrivilegedStandardProfile();
        String suffix = String.valueOf(Math.abs(Crypto.getRandomLong()));
        User person = new User(
            FirstName = firstName,
            LastName = lastName,
            Alias = 'oi' + suffix.right(6),
            Email = firstName.toLowerCase() + '.' + suffix + '@example.invalid',
            Username = firstName.toLowerCase() + '.' + suffix + '@barncrm.test.invalid',
            ProfileId = standardProfile.Id,
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

    @IsTest
    static void searchActiveIgnoresBlankTermsAndSillyLimits() {
        UserSelector selector = new UserSelector();

        Test.startTest();
        List<User> blank = selector.searchActive('   ', 20);
        List<User> noLimit = selector.searchActive('Maria', 0);
        Test.stopTest();

        Assert.areEqual(0, blank.size(), 'A blank search should not list the whole org.');
        Assert.areEqual(0, noLimit.size(), 'A limit of zero should return nothing.');
    }

    @IsTest
    static void searchActiveTreatsWildcardCharactersAsText() {
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

    @IsTest
    static void searchActiveRespectsTheLimit() {
        List<User> staff = new List<User>();
        for (Integer i = 0; i < 3; i++) {
            staff.add(insertUser('Limitcheck' + i, 'Bulk'));
        }
        UserSelector selector = new UserSelector();

        Test.startTest();
        List<User> found = selector.searchActive('Limitcheck', 2);
        Test.stopTest();

        Assert.areEqual(2, found.size(), 'The search should return no more than it was asked for.');
        Assert.areEqual(3, staff.size(), 'Three people were created for this check.');
    }

    @IsTest
    static void selectActiveByIdsReturnsOnlyActivePeople() {
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

    /**
     * Finds a profile that grants no more than an ordinary staff member needs, so that a
     * test user built from it genuinely lacks the permissions the Access page checks.
     * Standard User is named first because "any profile whose UserType is Standard" also
     * matches System Administrator, which would silently disarm the denied-user tests.
     *
     * @return the profile every test user in this class is built from
     */
    private static Profile leastPrivilegedStandardProfile() {
        // Profile.Name is the translated label, so this first lookup misses in an org that
        // is not in English. That is what the fallback below is for.
        List<Profile> named = [SELECT Id, Name FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        if (!named.isEmpty()) {
            return named[0];
        }
        List<Profile> fallback = [
            SELECT Id, Name
            FROM Profile
            WHERE UserType = 'Standard' AND Name != 'System Administrator'
            ORDER BY Name
            LIMIT 1
        ];
        Assert.isFalse(
            fallback.isEmpty(),
            'This org has no standard profile other than System Administrator, so the tests ' +
            'cannot build a user who lacks the Access page permissions.'
        );
        return fallback[0];
    }
}
