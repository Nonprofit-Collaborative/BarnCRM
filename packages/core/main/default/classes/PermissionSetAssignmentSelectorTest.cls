/**
 * Tests for PermissionSetAssignmentSelector: who holds a role, and how many people do.
 */
@IsTest
private class PermissionSetAssignmentSelectorTest {
    private static final String PROGRAM_ROLE = 'Program_Staff';

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
            Username = firstName.toLowerCase() + '.' + suffix + '@openimpact.test.invalid',
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
    static void selectByGroupIdsListsThePeopleInTheRole() {
        PermissionSetGroup groupRecord = TestDataFactory.prepareRoleGroup(PROGRAM_ROLE);
        User david = insertUser('David', 'Okafor');
        insert new PermissionSetAssignment(
            AssigneeId = david.Id,
            PermissionSetGroupId = groupRecord.Id
        );
        PermissionSetAssignmentSelector selector = new PermissionSetAssignmentSelector();

        Test.startTest();
        List<PermissionSetAssignment> assignments = selector.selectByGroupIds(
            new Set<Id>{ groupRecord.Id }
        );
        Test.stopTest();

        Set<Id> assignees = new Set<Id>();
        for (PermissionSetAssignment assignment : assignments) {
            assignees.add(assignment.AssigneeId);
        }
        Assert.isTrue(
            assignees.contains(david.Id),
            'David should be listed under the role he holds.'
        );
    }

    @IsTest
    static void selectByGroupIdsAndUserIdsFindsAnExistingAssignment() {
        PermissionSetGroup groupRecord = TestDataFactory.prepareRoleGroup(PROGRAM_ROLE);
        User david = insertUser('David', 'Okafor');
        insert new PermissionSetAssignment(
            AssigneeId = david.Id,
            PermissionSetGroupId = groupRecord.Id
        );
        PermissionSetAssignmentSelector selector = new PermissionSetAssignmentSelector();

        Test.startTest();
        List<PermissionSetAssignment> found = selector.selectByGroupIdsAndUserIds(
            new Set<Id>{ groupRecord.Id },
            new Set<Id>{ david.Id }
        );
        Integer count = selector.countActiveAssignees(groupRecord.Id);
        Test.stopTest();

        Assert.areEqual(
            1,
            found.size(),
            'The one assignment linking David to the role should be found.'
        );
        Assert.areEqual(1, count, 'One active person holds the role.');
    }

    @IsTest
    static void emptyInputQueriesNothing() {
        PermissionSetAssignmentSelector selector = new PermissionSetAssignmentSelector();

        Test.startTest();
        List<PermissionSetAssignment> byGroup = selector.selectByGroupIds(new Set<Id>());
        List<PermissionSetAssignment> byBoth = selector.selectByGroupIdsAndUserIds(
            new Set<Id>(),
            new Set<Id>()
        );
        Integer count = selector.countActiveAssignees(null);
        Test.stopTest();

        Assert.areEqual(0, byGroup.size(), 'Asking about no groups should return nothing.');
        Assert.areEqual(
            0,
            byBoth.size(),
            'Asking about no groups and no people should return nothing.'
        );
        Assert.areEqual(0, count, 'Counting nobody should return zero without querying.');
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
