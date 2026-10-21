/**
 * Tests for AccessService: Maria giving David a role, giving it twice, taking it away,
 * finding people, a person who is not allowed to change roles, and several at once.
 */
@IsTest(testFor='ApexClass:AccessService')
private class AccessServiceTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

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
        return new User(
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
        System.runAs(TestUsers.admin()) {
            TestDataFactory.prepareRoleGroup(PROGRAM_ROLE);
            User david = insertUser('David', 'Okafor');

            Test.startTest();
            AccessService.assignRole(david.Id, PROGRAM_ROLE);
            Test.stopTest();

            Assert.areEqual(
                1,
                countAssignments(david.Id, PROGRAM_ROLE),
                'David should hold the Team Member role once Maria has given it to him.'
            );
        }
    }

    @IsTest
    static void assignRoleTwiceChangesNothingTheSecondTime() {
        System.runAs(TestUsers.admin()) {
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
    }

    @IsTest
    static void removeRoleTakesTheRoleAway() {
        System.runAs(TestUsers.admin()) {
            TestDataFactory.prepareRoleGroup(PROGRAM_ROLE);
            User david = insertUser('David', 'Okafor');
            AccessService.assignRole(david.Id, PROGRAM_ROLE);

            Test.startTest();
            AccessService.removeRole(david.Id, PROGRAM_ROLE);
            Test.stopTest();

            Assert.areEqual(
                0,
                countAssignments(david.Id, PROGRAM_ROLE),
                'David should not hold the Team Member role after Maria removes it.'
            );
        }
    }

    @IsTest
    static void removeRoleThePersonDoesNotHoldIsNotAnError() {
        System.runAs(TestUsers.admin()) {
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
    }

    @IsTest
    static void searchUsersFindsAPersonByName() {
        System.runAs(TestUsers.admin()) {
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
    }

    @IsTest
    static void searchUsersReturnsNothingForABlankTerm() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            List<AccessService.UserSummary> found = AccessService.searchUsers('   ');
            Test.stopTest();

            Assert.areEqual(0, found.size(), 'An empty search box should not list the whole org.');
        }
    }

    @IsTest
    static void assignRoleRejectsARoleThatIsNotOurs() {
        System.runAs(TestUsers.admin()) {
            User david = insertUser('David', 'Okafor');
            String message;

            Test.startTest();
            try {
                AccessService.assignRole(david.Id, 'Some_Other_Group');
                Assert.fail('A role that BarnCRM does not ship should be refused.');
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
    }

    @IsTest
    static void assignRoleRefusesSomebodyWhoCanNoLongerSignIn() {
        System.runAs(TestUsers.admin()) {
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
    }

    @IsTest
    static void removeRoleRefusesToRemoveTheLastBarnCrmAdmin() {
        System.runAs(TestUsers.admin()) {
            PermissionSetGroup adminGroup = TestDataFactory.prepareRoleGroup(
                AccessService.ADMIN_ROLE
            );
            User maria = insertUser('Maria', 'Alvarez');
            // A real org already has other holders of the role (assignments are visible to
            // tests), so Maria is the last one only once the others are cleared. The delete
            // rolls back with the test.
            delete as system [
                SELECT Id
                FROM PermissionSetAssignment
                WHERE PermissionSetGroupId = :adminGroup.Id
            ];
            AccessService.assignRole(maria.Id, AccessService.ADMIN_ROLE);
            String message;

            Test.startTest();
            try {
                AccessService.removeRole(maria.Id, AccessService.ADMIN_ROLE);
                Assert.fail('Removing the only BarnCRM Admin should be refused.');
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
                'Maria should still hold the BarnCRM Admin role.'
            );
        }
    }

    @IsTest
    static void getRolesReturnsThePackagedRoles() {
        System.runAs(TestUsers.admin()) {
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
                'The BarnCRM Admin role should be one of the packaged roles.'
            );
            Assert.isTrue(names.contains(PROGRAM_ROLE), 'The Team Member role should be packaged.');
        }
    }

    @IsTest
    static void getAssignmentsListsThePeopleInEachRole() {
        System.runAs(TestUsers.admin()) {
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
            Assert.isTrue(
                davidIsListed,
                'David should appear under Team Member on the Access page.'
            );
        }
    }

    @IsTest
    static void aPersonWithoutThePermissionCannotChangeRoles() {
        System.runAs(TestUsers.admin()) {
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
                priyaProfile.PermissionsModifyAllData ||
                priyaProfile.PermissionsAssignPermissionSets,
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
                'A person without the Manage BarnCRM Settings permission should be refused.'
            );
            Assert.areEqual(
                0,
                countAssignments(david.Id, PROGRAM_ROLE),
                'A refused attempt should leave no assignment behind.'
            );
        }
    }

    @IsTest
    static void severalPeopleAreGivenARoleInOneOperation() {
        System.runAs(TestUsers.admin()) {
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
                    buildUser(
                        'Staff' + i,
                        'Bulk',
                        String.valueOf(Math.abs(Crypto.getRandomLong())) + i
                    )
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
            Assert.areEqual(
                1,
                dmlUsed,
                'Five assignments should cost one DML statement, not five.'
            );
        }
    }

    @IsTest
    static void theAssignmentListIsBuiltInOneCollectionAtTwoHundred() {
        System.runAs(TestUsers.admin()) {
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
                Assert.areEqual(
                    groupId,
                    row.PermissionSetGroupId,
                    'Every row is for the chosen role.'
                );
            }
            Assert.areEqual(199, assignees.size(), 'Every row is for a different person.');
        }
    }

    @IsTest
    static void severalPeopleHaveARoleTakenAwayInOneOperation() {
        System.runAs(TestUsers.admin()) {
            // Five for the same license reason as the assignment test above.
            TestDataFactory.prepareRoleGroup(PROGRAM_ROLE);
            List<User> staff = new List<User>();
            for (Integer i = 0; i < 5; i++) {
                staff.add(
                    buildUser(
                        'Staff' + i,
                        'Bulk',
                        String.valueOf(Math.abs(Crypto.getRandomLong())) + i
                    )
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
    }

    private static final String BULK_UPDATE = 'BarnCRM_Bulk_Update';

    /**
     * Counts how many direct rows link a person to a permission set.
     *
     * @param userId the person
     * @param permissionSetName the permission set's API name
     * @return the number of assignment rows
     */
    private static Integer countAddOn(Id userId, String permissionSetName) {
        return [
            SELECT COUNT()
            FROM PermissionSetAssignment
            WHERE AssigneeId = :userId AND PermissionSet.Name = :permissionSetName
        ];
    }

    /**
     * Builds an in-memory Access Add-On row. Custom metadata records cannot be created in a
     * test, and NamespacePrefix cannot be set by a constructor, so the row is deserialized.
     *
     * @param namespace the row's namespace, or null for the package's own
     * @param permissionSetName the permission set the row lists
     * @param labelName the label holding the row's sentence
     * @return the row
     */
    private static Access_Add_On__mdt addOnRow(
        String namespace,
        String permissionSetName,
        String labelName
    ) {
        String own = NamespaceUtil.prefix().removeEnd('__');
        Map<String, Object> fields = new Map<String, Object>{
            'DeveloperName' => permissionSetName,
            'NamespacePrefix' => namespace != null ? namespace : (String.isBlank(own) ? null : own),
            'Permission_Set__c' => permissionSetName,
            'Description_Label__c' => labelName
        };
        return (Access_Add_On__mdt) JSON.deserialize(
            JSON.serialize(fields),
            Access_Add_On__mdt.class
        );
    }

    /** A Core set no role card or Core add-on lists, standing in for a module's set. */
    private static final String MODULE_SET = 'BarnCRM_Read_Only';

    @IsTest
    static void aModuleAddOnIsListedAfterCoreAndCanBeGivenAndRemoved() {
        AccessService.stubbedModuleAddOns = new List<Access_Add_On__mdt>{
            addOnRow(null, MODULE_SET, 'Core_Access_AddOnBulkUpdate')
        };
        System.runAs(TestUsers.admin()) {
            User david = insertUser('David', 'Okafor');

            Test.startTest();
            List<AccessService.AddOn> addOns = AccessService.getAddOns();
            List<String> failures = AccessService.assignAddOn(new Set<Id>{ david.Id }, MODULE_SET);
            Boolean listed = false;
            for (AccessService.AddOnAssignments entry : AccessService.getAddOnAssignments()) {
                if (entry.permissionSetName == MODULE_SET) {
                    for (AccessService.UserSummary person : entry.users) {
                        listed = listed || person.userId == david.Id;
                    }
                }
            }
            Integer heldAfterAssign = countAddOn(david.Id, MODULE_SET);
            List<String> removeFailures = AccessService.removeAddOn(
                new Set<Id>{ david.Id },
                MODULE_SET
            );
            Test.stopTest();

            Assert.areEqual(
                AccessService.ADD_ON_PERMISSION_SETS.size() + 1,
                addOns.size(),
                'The module add-on should be listed beside the Core ones.'
            );
            AccessService.AddOn moduleAddOn = addOns[addOns.size() - 1];
            Assert.areEqual(MODULE_SET, moduleAddOn.developerName, 'It should come after Core.');
            Assert.areEqual(
                Label.Core_Access_AddOnBulkUpdate,
                moduleAddOn.description,
                'Its sentence should be the label its row names.'
            );
            Assert.isFalse(
                moduleAddOn.isDestructive,
                'A module add-on is not marked as removing data.'
            );
            Assert.isNull(moduleAddOn.warning, 'So it carries no warning.');
            Assert.isTrue(
                failures.isEmpty(),
                'Giving David the module add-on should not be refused.'
            );
            Assert.areEqual(1, heldAfterAssign, 'David should hold it once.');
            Assert.isTrue(listed, 'David should be listed on its card.');
            Assert.isTrue(removeFailures.isEmpty(), 'Removing it should not be refused.');
            Assert.areEqual(0, countAddOn(david.Id, MODULE_SET), 'David should no longer hold it.');
        }
    }

    @IsTest
    static void aModuleRowFromAnotherNamespaceOrRepeatingCoreIsIgnored() {
        AccessService.stubbedModuleAddOns = new List<Access_Add_On__mdt>{
            addOnRow('someoneelse', 'BarnCRM_Staff', 'Core_Access_AddOnBulkUpdate'),
            addOnRow(null, BULK_UPDATE, 'Core_Access_AddOnErasePeople'),
            addOnRow(null, MODULE_SET, 'No_Such_Label_For_This_Test')
        };
        System.runAs(TestUsers.admin()) {
            User david = insertUser('David', 'Okafor');
            String refusal;

            Test.startTest();
            List<AccessService.AddOn> addOns = AccessService.getAddOns();
            try {
                AccessService.assignAddOn(new Set<Id>{ david.Id }, 'BarnCRM_Staff');
            } catch (AccessService.AccessException e) {
                refusal = e.getMessage();
            }
            Test.stopTest();

            Map<String, AccessService.AddOn> byName = new Map<String, AccessService.AddOn>();
            for (AccessService.AddOn addOn : addOns) {
                byName.put(addOn.developerName, addOn);
            }
            Assert.areEqual(
                AccessService.ADD_ON_PERMISSION_SETS.size() + 1,
                addOns.size(),
                'Only the row in the package namespace that names a new set should be added.'
            );
            Assert.isFalse(
                byName.containsKey('BarnCRM_Staff'),
                'A row from another namespace should never be listed.'
            );
            Assert.areEqual(
                Label.Core_Access_AddOnBulkUpdate,
                byName.get(BULK_UPDATE).description,
                'A row repeating a Core add-on should not change it.'
            );
            Assert.isNull(
                byName.get(MODULE_SET).description,
                'A row whose label cannot be read is listed without a sentence.'
            );
            Assert.areEqual(
                Label.Core_Access_ErrorAddOnNotFound,
                refusal,
                'A set named only by a row from another namespace should never be given.'
            );
            Assert.areEqual(0, countAddOn(david.Id, 'BarnCRM_Staff'), 'David should not hold it.');
        }
    }

    @IsTest
    static void everyShippedModuleAddOnIsListedWithItsSentence() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            List<AccessService.AddOn> addOns = AccessService.getAddOns();
            Test.stopTest();

            Map<String, AccessService.AddOn> byName = new Map<String, AccessService.AddOn>();
            for (AccessService.AddOn addOn : addOns) {
                byName.put(addOn.developerName, addOn);
            }
            // Whatever modules this org has: none in a Core-only org, Giving's and Mirror's here.
            String own = NamespaceUtil.prefix().removeEnd('__');
            for (Access_Add_On__mdt row : Access_Add_On__mdt.getAll().values()) {
                if ((String.isBlank(row.NamespacePrefix) ? '' : row.NamespacePrefix) != own) {
                    continue;
                }
                AccessService.AddOn addOn = byName.get(row.Permission_Set__c);
                Assert.isNotNull(
                    addOn,
                    row.Permission_Set__c + ' should be listed: its row names a set this org has.'
                );
                Assert.isTrue(
                    String.isNotBlank(addOn.description),
                    row.Permission_Set__c + ' should say what it grants: its row names a label.'
                );
            }
        }
    }

    @IsTest
    static void getAddOnsListsTheSixCoreAddOnsAndWarnsOnTheDestructiveOnes() {
        AccessService.stubbedModuleAddOns = new List<Access_Add_On__mdt>();
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            List<AccessService.AddOn> addOns = AccessService.getAddOns();
            Test.stopTest();

            Assert.areEqual(
                AccessService.ADD_ON_PERMISSION_SETS.size(),
                addOns.size(),
                'Every Core add-on the package ships should be listed, and nothing else.'
            );
            for (Integer i = 0; i < addOns.size(); i++) {
                AccessService.AddOn addOn = addOns[i];
                Assert.areEqual(
                    AccessService.ADD_ON_PERMISSION_SETS[i],
                    addOn.developerName,
                    'Add-ons should come back in the page order.'
                );
                Assert.isTrue(
                    String.isNotBlank(addOn.description),
                    addOn.developerName + ' should say in one sentence what it grants.'
                );
                Boolean destructive =
                    addOn.developerName == 'BarnCRM_Bulk_Delete' ||
                    addOn.developerName == 'BarnCRM_Erase_People';
                Assert.areEqual(
                    destructive,
                    addOn.isDestructive,
                    'Only Bulk Delete and Erase People should be marked as removing data.'
                );
                Assert.areEqual(
                    destructive,
                    String.isNotBlank(addOn.warning),
                    'Only the add-ons that remove data should carry a warning.'
                );
            }
        }
    }

    @IsTest
    static void assignAndRemoveAnAddOn() {
        System.runAs(TestUsers.admin()) {
            User david = insertUser('David', 'Okafor');

            Test.startTest();
            List<String> failures = AccessService.assignAddOn(new Set<Id>{ david.Id }, BULK_UPDATE);
            List<String> again = AccessService.assignAddOn(new Set<Id>{ david.Id }, BULK_UPDATE);
            Boolean listed = false;
            for (AccessService.AddOnAssignments entry : AccessService.getAddOnAssignments()) {
                if (entry.permissionSetName == BULK_UPDATE) {
                    for (AccessService.UserSummary person : entry.users) {
                        listed = listed || person.userId == david.Id;
                    }
                }
            }
            Integer heldAfterAssign = countAddOn(david.Id, BULK_UPDATE);
            AccessService.removeAddOn(new Set<Id>{ david.Id }, BULK_UPDATE);
            AccessService.removeAddOn(new Set<Id>{ david.Id }, BULK_UPDATE);
            Test.stopTest();

            Assert.isTrue(failures.isEmpty(), 'Giving David Bulk Update should not be refused.');
            Assert.isTrue(again.isEmpty(), 'Giving it twice should not be an error.');
            Assert.areEqual(1, heldAfterAssign, 'David should hold Bulk Update exactly once.');
            Assert.isTrue(listed, 'David should be listed on the Bulk Update card.');
            Assert.areEqual(
                0,
                countAddOn(david.Id, BULK_UPDATE),
                'David should not hold Bulk Update after it is removed, and removing it twice ' +
                'should not be an error.'
            );
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Error_Log__c],
                'Nothing should be logged when giving and removing work.'
            );
        }
    }

    @IsTest
    static void severalPeopleAreGivenAnAddOnInOneOperation() {
        System.runAs(TestUsers.admin()) {
            List<User> staff = new List<User>();
            for (Integer i = 0; i < 5; i++) {
                staff.add(
                    buildUser(
                        'Staff' + i,
                        'AddOn',
                        String.valueOf(Math.abs(Crypto.getRandomLong())) + i
                    )
                );
            }
            insert staff;
            Set<Id> staffIds = new Map<Id, User>(staff).keySet();

            Test.startTest();
            AccessService.assignAddOn(staffIds, BULK_UPDATE);
            Integer dmlUsed = Limits.getDmlStatements();
            Test.stopTest();

            Assert.areEqual(
                5,
                [
                    SELECT COUNT()
                    FROM PermissionSetAssignment
                    WHERE AssigneeId IN :staffIds AND PermissionSet.Name = :BULK_UPDATE
                ],
                'All five people should have been given Bulk Update.'
            );
            Assert.areEqual(1, dmlUsed, 'Five assignments should cost one DML statement.');
        }
    }

    @IsTest
    static void onlyTheCoreAddOnsCanBeGiven() {
        System.runAs(TestUsers.admin()) {
            User david = insertUser('David', 'Okafor');
            List<String> refusedNames = new List<String>();

            Test.startTest();
            for (String name : new List<String>{ 'BarnCRM_Admin', 'BarnCRM_Staff', '', null }) {
                try {
                    AccessService.assignAddOn(new Set<Id>{ david.Id }, name);
                } catch (AccessService.AccessException e) {
                    Assert.areEqual(
                        Label.Core_Access_ErrorAddOnNotFound,
                        e.getMessage(),
                        'The refusal should say the permission is not one the page can give.'
                    );
                    refusedNames.add(String.valueOf(name));
                }
            }
            Boolean removeRefused = false;
            try {
                AccessService.removeAddOn(new Set<Id>{ david.Id }, 'BarnCRM_Admin');
            } catch (AccessService.AccessException e) {
                removeRefused = true;
            }
            Test.stopTest();

            Assert.areEqual(
                4,
                refusedNames.size(),
                'A permission set off the allowlist should never be given: ' + refusedNames
            );
            Assert.isTrue(removeRefused, 'Nor removed.');
            Assert.areEqual(
                0,
                countAddOn(david.Id, 'BarnCRM_Admin'),
                'David should not have been given BarnCRM Admin.'
            );
        }
    }

    @IsTest
    static void aPersonWhoCannotAssignPermissionSetsIsRefused() {
        System.runAs(TestUsers.admin()) {
            User david = insertUser('David', 'Okafor');
            User priya = insertUser('Priya', 'Nair');
            String assignMessage;
            String removeMessage;
            Boolean priyaCanAssign;

            Test.startTest();
            System.runAs(priya) {
                priyaCanAssign = AccessService.canAssignPermissionSets();
                try {
                    AccessService.assignAddOn(new Set<Id>{ david.Id }, BULK_UPDATE);
                } catch (AccessService.AccessException e) {
                    assignMessage = e.getMessage();
                }
                try {
                    AccessService.removeAddOn(new Set<Id>{ david.Id }, BULK_UPDATE);
                } catch (AccessService.AccessException e) {
                    removeMessage = e.getMessage();
                }
            }
            Test.stopTest();

            Assert.isFalse(priyaCanAssign, 'A standard user cannot assign permission sets.');
            Assert.areEqual(
                Label.Core_Access_ErrorNoPermission,
                assignMessage,
                'Priya, without Manage BarnCRM Settings, should be refused by the service itself.'
            );
            Assert.areEqual(Label.Core_Access_ErrorNoPermission, removeMessage, 'Nor remove.');
            Assert.areEqual(0, countAddOn(david.Id, BULK_UPDATE), 'Nothing should be assigned.');
        }
    }

    @IsTest
    static void manageSettingsWithoutAssignPermissionSetsIsRefused() {
        // No packaged set carries Manage BarnCRM Settings without Assign Permission Sets, but
        // an org's own can, so the Setup check is made to answer no.
        System.runAs(TestUsers.admin()) {
            User david = insertUser('David', 'Okafor');
            String assignMessage;
            String removeMessage;

            Test.startTest();
            AccessService.assignPermissionSetsOverride = false;
            try {
                AccessService.assignAddOn(new Set<Id>{ david.Id }, BULK_UPDATE);
            } catch (AccessService.AccessException e) {
                assignMessage = e.getMessage();
            }
            try {
                AccessService.removeAddOn(new Set<Id>{ david.Id }, BULK_UPDATE);
            } catch (AccessService.AccessException e) {
                removeMessage = e.getMessage();
            }
            Test.stopTest();

            Assert.areEqual(
                Label.Core_Access_ErrorNeedsAccessManager,
                assignMessage,
                'The person should be told what Setup permission is missing.'
            );
            Assert.areEqual(
                Label.Core_Access_ErrorNeedsAccessManager,
                removeMessage,
                'Nor remove them.'
            );
            Assert.areEqual(0, countAddOn(david.Id, BULK_UPDATE), 'Nothing should be assigned.');
        }
    }

    @IsTest
    static void aRefusedRemovalIsNamedWithTheReason() {
        System.runAs(TestUsers.admin()) {
            User david = [
                SELECT Id, Name
                FROM User
                WHERE Id = :insertUser('David', 'Okafor').Id
            ];
            List<PermissionSetAssignment> rows = new List<PermissionSetAssignment>{
                new PermissionSetAssignment(AssigneeId = david.Id)
            };
            List<Database.DeleteResult> results = (List<Database.DeleteResult>) JSON.deserialize(
                '[{"success":false,"errors":[{"message":"Not allowed","statusCode":' +
                '"INSUFFICIENT_ACCESS_OR_READONLY","fields":[]}]}]',
                List<Database.DeleteResult>.class
            );

            Test.startTest();
            List<String> failures = AccessService.reportFailures(
                rows,
                AccessService.errorsOf(results),
                new Map<Id, User>{ david.Id => david },
                Label.Core_Access_ErrorAddOnRemoveRefused,
                'BarnCRM Bulk Update'
            );
            Test.stopTest();

            Assert.areEqual(1, failures.size(), 'The refused person should be reported.');
            Assert.isTrue(
                failures[0]
                    .startsWith('BarnCRM Bulk Update could not be removed from David Okafor.'),
                'The message should name the permission and the person: ' + failures[0]
            );
        }
    }

    @IsTest
    static void aPersonSalesforceRefusesIsNamedWithTheReason() {
        // A real refusal needs a user whose license does not allow what the add-on grants,
        // which a test org cannot be relied on to have. The per-row handling is proven on
        // results shaped exactly as Database.insert returns them.
        System.runAs(TestUsers.admin()) {
            Map<Id, User> people = new Map<Id, User>(
                [
                    SELECT Id, Name
                    FROM User
                    WHERE
                        Id IN :new List<Id>{
                            insertUser('David', 'Okafor').Id,
                            insertUser('Priya', 'Nair').Id
                        }
                ]
            );
            User david;
            User priya;
            for (User person : people.values()) {
                if (person.Name == 'David Okafor') {
                    david = person;
                } else {
                    priya = person;
                }
            }
            List<PermissionSetAssignment> rows = new List<PermissionSetAssignment>{
                new PermissionSetAssignment(AssigneeId = david.Id),
                new PermissionSetAssignment(AssigneeId = priya.Id)
            };
            List<Database.SaveResult> results = (List<Database.SaveResult>) JSON.deserialize(
                '[{"success":true,"errors":[]},' +
                    '{"success":false,"errors":[{"message":"The user license doesn\'t allow ' +
                    'the permission: Read DuplicateRecordSet","statusCode":' +
                    '"FIELD_INTEGRITY_EXCEPTION","fields":[]}]}]',
                List<Database.SaveResult>.class
            );

            Test.startTest();
            List<String> failures = AccessService.reportFailures(
                rows,
                AccessService.errorsOf(results),
                people,
                Label.Core_Access_ErrorAddOnRefused,
                'BarnCRM Duplicate Review'
            );
            Test.stopTest();

            Assert.areEqual(1, failures.size(), 'Only the refused person should be reported.');
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Error_Log__c],
                'The refusal should be written to the Error Log once.'
            );
            Assert.isTrue(
                failures[0].startsWith('Priya Nair could not be given BarnCRM Duplicate Review.'),
                'The message should name the person and the permission: ' + failures[0]
            );
            Assert.isTrue(
                failures[0].contains('Read DuplicateRecordSet'),
                'The message should carry Salesforce\'s own reason.'
            );
        }
    }
}
