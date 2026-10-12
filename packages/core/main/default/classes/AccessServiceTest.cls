/**
 * Tests for AccessService: Maria giving David a role, giving it twice, taking it away,
 * finding people, a person who is not allowed to change roles, and several at once.
 */
@IsTest
private class AccessServiceTest {
    private static final String PROGRAM_ROLE = 'Program_Staff';

    /**
     * Builds an unassigned active user without inserting it.
     *
     * @param firstName the person's first name
     * @param lastName the person's last name
     * @param suffix a value that makes the username unique in the org
     * @return the user, ready to insert
     */
    private static User buildUser(String firstName, String lastName, String suffix) {
        Profile standardProfile = leastPrivilegedStandardProfile();
        return new User(
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
    }

    /**
     * Inserts one active user.
     *
     * @param firstName the person's first name
     * @param lastName the person's last name
     * @return the inserted user
     */
    private static User insertUser(String firstName, String lastName) {
        User person = buildUser(
            firstName,
            lastName,
            String.valueOf(Math.abs(Crypto.getRandomLong()))
        );
        insert person;
        return person;
    }

    /**
     * Counts how many rows link a person to a role.
     *
     * @param userId the person
     * @param roleDeveloperName the role's DeveloperName
     * @return the number of assignment rows
     */
    private static Integer countAssignments(Id userId, String roleDeveloperName) {
        return [
            SELECT COUNT()
            FROM PermissionSetAssignment
            WHERE AssigneeId = :userId AND PermissionSetGroup.DeveloperName = :roleDeveloperName
        ];
    }

    @IsTest
    static void assignRoleGivesThePersonTheRole() {
        TestDataFactory.prepareRoleGroup(PROGRAM_ROLE);
        User david = insertUser('David', 'Okafor');

        Test.startTest();
        AccessService.assignRole(david.Id, PROGRAM_ROLE);
        Test.stopTest();

        Assert.areEqual(
            1,
            countAssignments(david.Id, PROGRAM_ROLE),
            'David should hold the Program Staff role once Maria has given it to him.'
        );
    }

    @IsTest
    static void assignRoleTwiceChangesNothingTheSecondTime() {
        TestDataFactory.prepareRoleGroup(PROGRAM_ROLE);
        User david = insertUser('David', 'Okafor');
        AccessService.assignRole(david.Id, PROGRAM_ROLE);

        Test.startTest();
        AccessService.assignRole(david.Id, PROGRAM_ROLE);
        Test.stopTest();

        Assert.areEqual(
            1,
            countAssignments(david.Id, PROGRAM_ROLE),
            'Giving David a role he already holds should leave exactly one assignment.'
        );
    }

    @IsTest
    static void removeRoleTakesTheRoleAway() {
        TestDataFactory.prepareRoleGroup(PROGRAM_ROLE);
        User david = insertUser('David', 'Okafor');
        AccessService.assignRole(david.Id, PROGRAM_ROLE);

        Test.startTest();
        AccessService.removeRole(david.Id, PROGRAM_ROLE);
        Test.stopTest();

        Assert.areEqual(
            0,
            countAssignments(david.Id, PROGRAM_ROLE),
            'David should not hold the Program Staff role after Maria removes it.'
        );
    }

    @IsTest
    static void removeRoleThePersonDoesNotHoldIsNotAnError() {
        TestDataFactory.prepareRoleGroup(PROGRAM_ROLE);
        User david = insertUser('David', 'Okafor');

        Test.startTest();
        AccessService.removeRole(david.Id, PROGRAM_ROLE);
        Test.stopTest();

        Assert.areEqual(
            0,
            countAssignments(david.Id, PROGRAM_ROLE),
            'Removing a role nobody holds should leave the org unchanged.'
        );
    }

    @IsTest
    static void searchUsersFindsAPersonByName() {
        User david = insertUser('Davidsearch', 'Okafor');

        Test.startTest();
        List<AccessService.UserSummary> found = AccessService.searchUsers('Davidsearch');
        Test.stopTest();

        Set<Id> foundIds = new Set<Id>();
        for (AccessService.UserSummary summary : found) {
            foundIds.add(summary.userId);
        }
        Assert.isTrue(
            foundIds.contains(david.Id),
            'Maria should find David by typing the start of his name.'
        );
    }

    @IsTest
    static void searchUsersReturnsNothingForABlankTerm() {
        Test.startTest();
        List<AccessService.UserSummary> found = AccessService.searchUsers('   ');
        Test.stopTest();

        Assert.areEqual(0, found.size(), 'An empty search box should not list the whole org.');
    }

    @IsTest
    static void assignRoleRejectsARoleThatIsNotOurs() {
        User david = insertUser('David', 'Okafor');
        String message;

        Test.startTest();
        try {
            AccessService.assignRole(david.Id, 'Some_Other_Group');
            Assert.fail('A role that Open Impact does not ship should be refused.');
        } catch (AccessService.AccessException e) {
            message = e.getMessage();
        }
        Test.stopTest();

        Assert.areEqual(
            Label.Core_Access_ErrorRoleNotFound,
            message,
            'An unknown role should be reported in the words the admin guide uses.'
        );
    }

    @IsTest
    static void assignRoleRefusesSomebodyWhoCanNoLongerSignIn() {
        TestDataFactory.prepareRoleGroup(PROGRAM_ROLE);
        User david = insertUser('David', 'Okafor');
        david.IsActive = false;
        update david;
        String message;

        Test.startTest();
        try {
            AccessService.assignRole(david.Id, PROGRAM_ROLE);
            Assert.fail('A deactivated person should not be given a role.');
        } catch (AccessService.AccessException e) {
            message = e.getMessage();
        }
        Test.stopTest();

        Assert.areEqual(
            Label.Core_Access_ErrorUserNotFound,
            message,
            'Maria should be told the person is not there or is no longer active.'
        );
        Assert.areEqual(
            0,
            countAssignments(david.Id, PROGRAM_ROLE),
            'A deactivated person should hold no role.'
        );
    }

    @IsTest
    static void removeRoleRefusesToRemoveTheLastNonprofitAdmin() {
        TestDataFactory.prepareRoleGroup(AccessService.ADMIN_ROLE);
        User maria = insertUser('Maria', 'Alvarez');
        AccessService.assignRole(maria.Id, AccessService.ADMIN_ROLE);
        String message;

        Test.startTest();
        try {
            AccessService.removeRole(maria.Id, AccessService.ADMIN_ROLE);
            Assert.fail('Removing the only Nonprofit Admin should be refused.');
        } catch (AccessService.AccessException e) {
            message = e.getMessage();
        }
        Test.stopTest();

        Assert.areEqual(
            Label.Core_Access_ErrorLastAdmin,
            message,
            'Maria should be told to give the role to someone else first.'
        );
        Assert.areEqual(
            1,
            countAssignments(maria.Id, AccessService.ADMIN_ROLE),
            'Maria should still hold the Nonprofit Admin role.'
        );
    }

    @IsTest
    static void getRolesReturnsThePackagedRoles() {
        Test.startTest();
        List<AccessService.Role> roles = AccessService.getRoles();
        Test.stopTest();

        Set<String> names = new Set<String>();
        for (AccessService.Role role : roles) {
            names.add(role.developerName);
            Assert.isNotNull(role.label, 'Every role needs a label the page can show.');
        }
        Assert.isTrue(
            names.contains(AccessService.ADMIN_ROLE),
            'The Nonprofit Admin role should be one of the packaged roles.'
        );
        Assert.isTrue(names.contains(PROGRAM_ROLE), 'The Program Staff role should be packaged.');
    }

    @IsTest
    static void getAssignmentsListsThePeopleInEachRole() {
        TestDataFactory.prepareRoleGroup(PROGRAM_ROLE);
        User david = insertUser('David', 'Okafor');
        AccessService.assignRole(david.Id, PROGRAM_ROLE);

        Test.startTest();
        List<AccessService.RoleAssignments> assignments = AccessService.getAssignments();
        Test.stopTest();

        Boolean davidIsListed = false;
        for (AccessService.RoleAssignments entry : assignments) {
            if (PROGRAM_ROLE.equals(entry.roleDeveloperName)) {
                for (AccessService.UserSummary summary : entry.users) {
                    davidIsListed = davidIsListed || summary.userId == david.Id;
                }
            }
        }
        Assert.isTrue(davidIsListed, 'David should appear under Program Staff on the Access page.');
    }

    @IsTest
    static void aPersonWithoutThePermissionCannotChangeRoles() {
        TestDataFactory.prepareRoleGroup(PROGRAM_ROLE);
        User david = insertUser('David', 'Okafor');
        User priya = insertUser('Priya', 'Nair');
        Boolean refused = false;

        // The test only means anything if Priya really is an ordinary staff member, so
        // check the profile she was built from before relying on it.
        Profile priyaProfile = [
            SELECT Id, Name, PermissionsModifyAllData, PermissionsAssignPermissionSets
            FROM Profile
            WHERE Id = :priya.ProfileId
        ];
        Assert.isFalse(
            priyaProfile.PermissionsModifyAllData || priyaProfile.PermissionsAssignPermissionSets,
            'Priya must be built from a profile that cannot assign permission sets, or this ' +
                'test proves nothing. Profile used: ' +
                priyaProfile.Name
        );

        Test.startTest();
        System.runAs(priya) {
            try {
                AccessService.assignRole(david.Id, PROGRAM_ROLE);
            } catch (AccessService.AccessException e) {
                refused = true;
            }
        }
        Test.stopTest();

        Assert.isTrue(
            refused,
            'A person without the Manage Nonprofit Settings permission should be refused.'
        );
        Assert.areEqual(
            0,
            countAssignments(david.Id, PROGRAM_ROLE),
            'A refused attempt should leave no assignment behind.'
        );
    }

    @IsTest
    static void severalPeopleAreGivenARoleInOneOperation() {
        // Five, not two hundred. Every user inserted here consumes a real user license,
        // and a Developer edition scratch org (the base of all four org shapes) allocates
        // only a handful of Salesforce seats, so a larger number fails on
        // LICENSE_LIMIT_EXCEEDED rather than on anything this feature does. The
        // collection handling at 200 is proven without DML in
        // theAssignmentListIsBuiltInOneCollectionAtTwoHundred below.
        TestDataFactory.prepareRoleGroup(PROGRAM_ROLE);
        List<User> staff = new List<User>();
        for (Integer i = 0; i < 5; i++) {
            staff.add(
                buildUser('Staff' + i, 'Bulk', String.valueOf(Math.abs(Crypto.getRandomLong())) + i)
            );
        }
        insert staff;
        Set<Id> staffIds = new Map<Id, User>(staff).keySet();

        // Test.startTest resets the governor counters, so the count read inside the window
        // is already the count this call alone spent.
        Test.startTest();
        AccessService.assignRole(staffIds, PROGRAM_ROLE);
        Integer dmlUsed = Limits.getDmlStatements();
        Test.stopTest();

        Integer assigned = [
            SELECT COUNT()
            FROM PermissionSetAssignment
            WHERE AssigneeId IN :staffIds AND PermissionSetGroup.DeveloperName = :PROGRAM_ROLE
        ];
        Assert.areEqual(5, assigned, 'All five people should have been given the role.');
        Assert.areEqual(1, dmlUsed, 'Five assignments should cost one DML statement, not five.');
    }

    @IsTest
    static void theAssignmentListIsBuiltInOneCollectionAtTwoHundred() {
        // The bulk safety the plan asks for (200 records per DML context) proven on the
        // collection logic itself. No users are inserted, so no licenses are consumed and
        // the assertion holds on every org shape.
        // The prefixes come from the describe rather than being typed out, so nothing here
        // is a hard-coded Id and the test still works if a prefix ever changes.
        String userPrefix = Schema.User.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
            .getKeyPrefix();
        String groupPrefix = Schema.PermissionSetGroup.SObjectType.getDescribe(
                SObjectDescribeOptions.DEFERRED
            )
            .getKeyPrefix();
        Set<Id> people = new Set<Id>();
        for (Integer i = 0; i < 200; i++) {
            people.add(Id.valueOf(userPrefix + '00000000' + String.valueOf(1000 + i)));
        }
        Id groupId = Id.valueOf(groupPrefix + '000000000001');
        Set<Id> alreadyAssigned = new Set<Id>{ Id.valueOf(userPrefix + '000000001000') };

        Test.startTest();
        List<PermissionSetAssignment> rows = AccessService.buildAssignments(
            people,
            alreadyAssigned,
            groupId
        );
        Test.stopTest();

        Assert.areEqual(
            199,
            rows.size(),
            'Two hundred people, one of whom already holds the role, is 199 rows to insert.'
        );
        Set<Id> assignees = new Set<Id>();
        for (PermissionSetAssignment row : rows) {
            assignees.add(row.AssigneeId);
            Assert.areEqual(groupId, row.PermissionSetGroupId, 'Every row is for the chosen role.');
        }
        Assert.areEqual(199, assignees.size(), 'Every row is for a different person.');
    }

    @IsTest
    static void severalPeopleHaveARoleTakenAwayInOneOperation() {
        // Five for the same license reason as the assignment test above.
        TestDataFactory.prepareRoleGroup(PROGRAM_ROLE);
        List<User> staff = new List<User>();
        for (Integer i = 0; i < 5; i++) {
            staff.add(
                buildUser('Staff' + i, 'Bulk', String.valueOf(Math.abs(Crypto.getRandomLong())) + i)
            );
        }
        insert staff;
        Set<Id> staffIds = new Map<Id, User>(staff).keySet();
        AccessService.assignRole(staffIds, PROGRAM_ROLE);

        // Test.startTest resets the governor counters, so the count read inside the window
        // is already the count this call alone spent.
        Test.startTest();
        AccessService.removeRole(staffIds, PROGRAM_ROLE);
        Integer dmlUsed = Limits.getDmlStatements();
        Test.stopTest();

        Integer assigned = [
            SELECT COUNT()
            FROM PermissionSetAssignment
            WHERE AssigneeId IN :staffIds AND PermissionSetGroup.DeveloperName = :PROGRAM_ROLE
        ];
        Assert.areEqual(0, assigned, 'All five assignments should have been removed.');
        Assert.areEqual(1, dmlUsed, 'Five removals should cost one DML statement, not five.');
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
