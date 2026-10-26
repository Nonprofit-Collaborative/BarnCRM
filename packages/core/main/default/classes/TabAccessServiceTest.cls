/**
 * The feature tabs follow their feature (ADR-0124): once it is on, the BarnCRM Tab sets go to
 * the people who held those tabs before; while it is off, nobody holds them.
 */
@IsTest(testFor='ApexClass:TabAccessService')
private class TabAccessServiceTest {
    private static final String PRIYA = 'Nair';
    private static final String SAM = 'Okafor';

    @TestSetup
    static void createTestUsers() {
        System.runAs(TestUsers.admin()) {
            TestUsers.standardUserWith(PRIYA, new List<String>{ 'BarnCRM_Find_And_Export' });
            TestUsers.standardUserWith(SAM, new List<String>{ 'BarnCRM_Tab_Import' });
        }
    }

    @IsTest
    static void givesPriyaTheTabsHerExtraPermissionUsedToShow() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            Boolean more = TabAccessService.syncNow();
            Test.stopTest();

            Set<String> held = tabSetsOf(userId(PRIYA));
            Assert.isFalse(more, 'A small org is done in one pass');
            Assert.isTrue(held.contains(TabAccessService.FIND_TAB), 'Find and Export sees Find');
            Assert.isTrue(
                held.contains(TabAccessService.DATA_MANAGER_TAB),
                'And the Data Manager hub'
            );
            Assert.isTrue(held.contains(TabAccessService.DATA_HYGIENE_TAB), 'And Data Hygiene');
            Assert.isFalse(held.contains(TabAccessService.IMPORT_TAB), 'But not Import');
            Assert.isFalse(held.contains(TabAccessService.BULK_UPDATE_TAB), 'Nor Bulk Update');
            Assert.isFalse(
                held.contains(TabAccessService.DUPLICATE_MATCHING_TAB),
                'Nor Duplicate Matching'
            );
            Assert.areEqual(
                6,
                tabSetsOf(UserInfo.getUserId()).size(),
                'An upgraded org has every feature on, so the admin keeps all six tabs'
            );
        }
    }

    @IsTest
    static void givesADuplicateReviewerAndAMetadataAdminDuplicateMatchingOnly() {
        System.runAs(TestUsers.admin()) {
            User reviewer = TestUsers.standardUserWith(
                'Reviewer',
                new List<String>{ 'BarnCRM_Duplicate_Review' }
            );
            User editor = TestUsers.standardUserWith(
                'Editor',
                new List<String>{ 'BarnCRM_Metadata_Admin' }
            );

            Test.startTest();
            TabAccessService.syncNow();
            Test.stopTest();

            Set<String> expected = new Set<String>{ TabAccessService.DUPLICATE_MATCHING_TAB };
            Assert.areEqual(
                expected,
                tabSetsOf(reviewer.Id),
                'Duplicate Review shows Duplicate Matching, where the review list is, and nothing else'
            );
            Assert.areEqual(
                expected,
                tabSetsOf(editor.Id),
                'Metadata Admin shows Duplicate Matching, where the matching logic is changed'
            );
        }
    }

    @IsTest
    static void aNewInstallShowsNoFeatureTabUntilTheFeatureIsOn() {
        System.runAs(TestUsers.admin()) {
            TestSettings.newInstall();
        }
        System.runAs(TestUsers.admin()) {
            TabAccessService.syncNow();
            Assert.isTrue(tabSetsOf(userId(PRIYA)).isEmpty(), 'No feature is on, so no tab');
        }
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            FeatureSwitchService.turnOn(FeatureSwitchService.ORG_OPTIMIZER);
            Test.stopTest();

            Assert.areEqual(
                new Set<String>{ TabAccessService.DATA_HYGIENE_TAB },
                tabSetsOf(userId(PRIYA)),
                'Turning Org Optimizer on gives Data Hygiene, and Data Manager stays hidden'
            );
        }
    }

    @IsTest
    static void takesATabSetGivenByHandFromSomeoneOutsideItsAudience() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            TabAccessService.syncNow();
            Test.stopTest();

            Assert.isTrue(tabSetsOf(userId(SAM)).isEmpty(), 'Sam has no set that shows Import');
        }
    }

    @IsTest
    static void aLargeOrgIsDoneASliceAtATime() {
        System.runAs(TestUsers.admin()) {
            TabAccessService.rowsPerRun = 2;

            Test.startTest();
            Boolean more = TabAccessService.syncNow();
            Test.stopTest();

            Assert.isTrue(more, 'More than two assignments do not fit in a slice of two');
            Assert.isTrue(
                tabSetsOf(UserInfo.getUserId()).size() <= 2,
                'No more than the slice is given now'
            );
        }
    }

    @IsTest
    static void givesAModuleSetToARolesHoldersAndTakesNothing() {
        System.runAs(TestUsers.admin()) {
            User reader = TestUsers.standardUser('Reader');
            insert new PermissionSetAssignment(
                AssigneeId = reader.Id,
                PermissionSetGroupId = TestDataFactory.prepareRoleGroup('Read_Only').Id
            );
            List<String> audience = new List<String>{ 'BarnCRM_Read_Only' };
            // Core's tests can name no module set, so a tab set stands in for one.
            TabAccessService.coreSetPrefix = 'Not_Core_';

            Test.startTest();
            Boolean noRoom = TabAccessService.giveToHolders(
                TabAccessService.IMPORT_TAB,
                audience,
                0,
                'Test'
            );
            Boolean more = TabAccessService.giveToHolders(
                TabAccessService.IMPORT_TAB,
                audience,
                100,
                'Test'
            );
            Boolean missing = TabAccessService.giveToHolders('No_Such_Set', audience, 100, 'Test');
            Test.stopTest();

            Assert.isTrue(noRoom, 'A budget of nothing leaves the role holder for later');
            Assert.isFalse(more, 'Then everyone is done in one pass');
            Assert.isFalse(missing, 'A set this org lacks is skipped');
            Assert.isTrue(
                tabSetsOf(reader.Id).contains(TabAccessService.IMPORT_TAB),
                'The Read Only role holder, through the group, gets the set'
            );
            Assert.isFalse(
                tabSetsOf(userId(PRIYA)).contains(TabAccessService.IMPORT_TAB),
                'Someone outside the audience does not'
            );
            Assert.isTrue(
                tabSetsOf(userId(SAM)).contains(TabAccessService.IMPORT_TAB),
                'And a set given by hand is never taken away'
            );
        }
    }

    @IsTest
    static void givesAModuleSetToOneRoleNotAnotherHoldingTheSameSets() {
        System.runAs(TestUsers.admin()) {
            User coordinator = TestUsers.standardUser('Coordinator');
            User member = TestUsers.standardUser('Member');
            insert new List<PermissionSetAssignment>{
                new PermissionSetAssignment(
                    AssigneeId = coordinator.Id,
                    PermissionSetGroupId = TestDataFactory.prepareRoleGroup('Volunteer_Coordinator')
                        .Id
                ),
                new PermissionSetAssignment(
                    AssigneeId = member.Id,
                    PermissionSetGroupId = TestDataFactory.prepareRoleGroup('Program_Staff').Id
                )
            };
            List<String> roles = new List<String>{ 'Volunteer_Coordinator' };
            // Core's tests can name no module set, so a tab set stands in for one.
            TabAccessService.coreSetPrefix = 'Not_Core_';

            Test.startTest();
            Boolean noRoom = TabAccessService.giveToGroupHolders(
                TabAccessService.IMPORT_TAB,
                roles,
                0,
                'Test'
            );
            Boolean more = TabAccessService.giveToGroupHolders(
                TabAccessService.IMPORT_TAB,
                roles,
                100,
                'Test'
            );
            Boolean again = TabAccessService.giveToGroupHolders(
                TabAccessService.IMPORT_TAB,
                roles,
                100,
                'Test'
            );
            Boolean missing = TabAccessService.giveToGroupHolders('No_Such_Set', roles, 100, 'T');
            Boolean noRoles = TabAccessService.giveToGroupHolders('Module_Set', null, 100, 'T');
            Test.stopTest();

            Assert.isTrue(noRoom, 'A budget of nothing leaves the role holder for later');
            Assert.isFalse(more, 'Then everyone is done in one pass');
            Assert.isFalse(again, 'And a second pass finds nobody left');
            Assert.isFalse(missing, 'A set this org lacks is skipped');
            Assert.isFalse(noRoles, 'No roles gives nothing');
            Assert.isTrue(
                tabSetsOf(coordinator.Id).contains(TabAccessService.IMPORT_TAB),
                'The Coordinator role holder gets the set'
            );
            Assert.isFalse(
                tabSetsOf(member.Id).contains(TabAccessService.IMPORT_TAB),
                'The Team Member, holding the same Core set, does not'
            );
        }
    }

    @IsTest
    static void byRoleSkipsInactivePeopleAndThoseHoldingTheSetThroughAGroup() {
        System.runAs(TestUsers.admin()) {
            Id coordinatorRole = TestDataFactory.prepareRoleGroup('Volunteer_Coordinator').Id;
            User gone = TestUsers.standardUser('Gone');
            User grouped = TestUsers.standardUser('Grouped');
            // A role of the org's own that already includes the stand-in module set.
            PermissionSetGroup ownRole = new PermissionSetGroup(
                DeveloperName = 'Test_Module_Role',
                MasterLabel = 'Test Module Role'
            );
            insert ownRole;
            insert new PermissionSetGroupComponent(
                PermissionSetGroupId = ownRole.Id,
                PermissionSetId = [
                    SELECT Id
                    FROM PermissionSet
                    WHERE Name = :TabAccessService.IMPORT_TAB
                    LIMIT 1
                ]
                .Id
            );
            Test.calculatePermissionSetGroup(ownRole.Id);
            insert new List<PermissionSetAssignment>{
                new PermissionSetAssignment(
                    AssigneeId = gone.Id,
                    PermissionSetGroupId = coordinatorRole
                ),
                new PermissionSetAssignment(
                    AssigneeId = grouped.Id,
                    PermissionSetGroupId = coordinatorRole
                ),
                new PermissionSetAssignment(
                    AssigneeId = grouped.Id,
                    PermissionSetGroupId = ownRole.Id
                )
            };
            gone.IsActive = false;
            update gone;
            TabAccessService.coreSetPrefix = 'Not_Core_';

            Test.startTest();
            Boolean more = TabAccessService.giveToGroupHolders(
                TabAccessService.IMPORT_TAB,
                new List<String>{ 'Volunteer_Coordinator' },
                100,
                'Test'
            );
            Test.stopTest();

            Assert.isFalse(more, 'Nothing is left');
            Assert.isTrue(tabSetsOf(gone.Id).isEmpty(), 'An inactive role holder is given nothing');
            Assert.isTrue(
                tabSetsOf(grouped.Id).isEmpty(),
                'Someone holding it through a group is not given it again directly'
            );
        }
    }

    @IsTest
    static void givesNoneOfCoresOwnSetsAndNothingWithoutAnAudience() {
        System.runAs(TestUsers.admin()) {
            List<String> refused = new List<String>();

            Test.startTest();
            for (
                String coreSet : new List<String>{
                    'BarnCRM_Staff',
                    'BarnCRM_Admin',
                    'BarnCRM_Metadata_Admin',
                    TabAccessService.IMPORT_TAB
                }
            ) {
                try {
                    TabAccessService.giveToHolders(
                        coreSet,
                        new List<String>{ 'BarnCRM_Read_Only' },
                        100,
                        'Test'
                    );
                } catch (IllegalArgumentException expected) {
                    refused.add(coreSet);
                }
            }
            try {
                TabAccessService.giveToGroupHolders(
                    'BarnCRM_Staff',
                    new List<String>{ 'Read_Only' },
                    100,
                    'Test'
                );
            } catch (IllegalArgumentException expected) {
                refused.add('BarnCRM_Staff by role');
            }
            Boolean noAudience = TabAccessService.giveToHolders('Module_Set', null, 100, 'Test');
            Test.stopTest();

            Assert.areEqual(5, refused.size(), 'Each of Core\'s sets is refused: ' + refused);
            Assert.isFalse(noAudience, 'No audience gives nothing and leaves nothing for later');
        }
    }

    @IsTest
    static void theNightlyCheckIsScheduledOnceAndQueuesASync() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            Id first = TabAccessScheduler.start();
            Id second = TabAccessScheduler.start();
            new TabAccessScheduler().execute(null);
            Test.stopTest();

            Assert.areEqual(first, second, 'Starting it again finds the same job');
            Assert.isTrue(TabAccessScheduler.isScheduled(), 'It is scheduled');
            Assert.areEqual(
                6,
                tabSetsOf(UserInfo.getUserId()).size(),
                'The queued sync ran and gave the admin the tabs'
            );
        }
    }

    private static Id userId(String lastName) {
        return [
            SELECT Id
            FROM User
            WHERE LastName = :lastName
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ]
        .Id;
    }

    private static Set<String> tabSetsOf(Id userId) {
        Set<String> names = new Set<String>();
        for (PermissionSetAssignment row : [
            SELECT PermissionSet.Name
            FROM PermissionSetAssignment
            WHERE AssigneeId = :userId AND PermissionSet.Name LIKE 'BarnCRM_Tab_%'
            WITH SYSTEM_MODE
        ]) {
            names.add(row.PermissionSet.Name);
        }
        return names;
    }
}
