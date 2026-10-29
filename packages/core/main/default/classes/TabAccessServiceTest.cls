/**
 * The feature tabs follow their feature (ADR-0124): once it is on, the BarnCRM Tab sets go to
 * the people who held those tabs before; while it is off, nobody holds them.
 */
@IsTest(testFor='ApexClass:TabAccessService')
private class TabAccessServiceTest {
    private static final String PRIYA = 'Nair';
    private static final String SAM = 'Okafor';
    private static final String TEAM_MEMBER = 'Mensah';

    @TestSetup
    static void createTestUsers() {
        System.runAs(TestUsers.admin()) {
            TestUsers.standardUserWith(PRIYA, new List<String>{ 'BarnCRM_Find_And_Export' });
            TestUsers.standardUserWith(SAM, new List<String>{ 'BarnCRM_Tab_Import' });
            TestUsers.standardUserWith(TEAM_MEMBER, new List<String>{ 'BarnCRM_Staff' });
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
            Assert.isTrue(held.contains(TabAccessService.DATA_HYGIENE_TAB), 'And Org Optimizer');
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
    static void givesTheHouseholdsTabToTheRolesWhileHouseholdUpkeepIsOn() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            TabAccessService.syncNow();
            Test.stopTest();

            Assert.isTrue(
                holdsHouseholds(userId(TEAM_MEMBER)),
                'A Staff holder gets the Households tab set'
            );
            Assert.isTrue(holdsHouseholds(UserInfo.getUserId()), 'So does the admin');
            Assert.isFalse(
                holdsHouseholds(userId(PRIYA)),
                'Find and Export alone is not a BarnCRM role'
            );
        }
    }

    @IsTest
    static void aNewInstallHasNoHouseholdsTabUntilHouseholdUpkeepIsOn() {
        System.runAs(TestUsers.admin()) {
            TestSettings.newInstall();
        }
        System.runAs(TestUsers.admin()) {
            TabAccessService.syncNow();
            Assert.isFalse(holdsHouseholds(userId(TEAM_MEMBER)), 'Household Upkeep is off');
        }
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            FeatureSwitchService.turnOn(FeatureSwitchService.HOUSEHOLD_UPKEEP);
            Test.stopTest();

            Assert.isTrue(
                holdsHouseholds(userId(TEAM_MEMBER)),
                'Turning Household Upkeep on queues the sync that gives the tab'
            );
            Assert.isTrue(
                tabSetsOf(userId(TEAM_MEMBER)).isEmpty(),
                'And no tool tab comes with it'
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
                'Turning Org Optimizer on gives the Org Optimizer tab, and Data Manager stays hidden'
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
    static void aJobStillOnTheOldNightlyCronIsReplacedNotDoubled() {
        System.runAs(TestUsers.admin()) {
            // What an earlier version left behind: the same job name on the nightly cron.
            Id old = System.schedule(
                TabAccessScheduler.JOB_NAME,
                '0 0 1 * * ?',
                new TabAccessScheduler()
            );
            ScheduledJobSelector.forget();

            Id moved = TabAccessScheduler.start();
            Id again = TabAccessScheduler.start();

            Assert.areNotEqual(old, moved, 'The nightly job is replaced');
            Assert.areEqual(moved, again, 'Starting it again finds the hourly job');
            List<CronTrigger> jobs = [
                SELECT Id, CronExpression
                FROM CronTrigger
                WHERE CronJobDetail.Name = :TabAccessScheduler.JOB_NAME
            ];
            Assert.areEqual(1, jobs.size(), 'There is one job, not two');
            Assert.areEqual('0 0 * * * ?', jobs[0].CronExpression, 'It runs every hour');
        }
    }

    @IsTest
    static void theHourlyCheckIsScheduledOnceAndQueuesASync() {
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

    @IsTest
    static void everyRoleSeesBothStylesAndOnlyAdminsSeeTheAdminApps() {
        System.runAs(TestUsers.admin()) {
            Id staff = userId(TEAM_MEMBER);

            Test.startTest();
            TabAccessService.syncNow();
            Test.stopTest();

            Assert.areEqual(
                new Set<String>{ TabAccessService.STANDARD_APP, TabAccessService.CONSOLE_APP },
                appSetsOf(staff),
                'Both is the default, so staff see BarnCRM and BarnCRM Console and no admin app'
            );
            Assert.areEqual(
                new Set<String>{
                    TabAccessService.STANDARD_APP,
                    TabAccessService.CONSOLE_APP,
                    TabAccessService.ADMIN_STANDARD_APP,
                    TabAccessService.ADMIN_CONSOLE_APP
                },
                appSetsOf(UserInfo.getUserId()),
                'An admin sees all four apps'
            );
            Assert.isTrue(
                appSetsOf(userId(PRIYA)).isEmpty(),
                'An extra permission alone is not a BarnCRM role, so it shows no app'
            );
        }
    }

    @IsTest
    static void savingOneStyleHidesTheOtherAppsForEveryone() {
        Id staff = userId(TEAM_MEMBER);
        System.runAs(TestUsers.admin()) {
            TabAccessService.syncNow();
            Assert.areEqual(2, appSetsOf(staff).size(), 'Both styles before the change');
        }
        // A separate block: the platform does not mix the assignments with a settings write.
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            SettingsService.saveValues(
                new Map<String, Object>{
                    'App_Navigation_Style__c' => TabAccessService.STYLE_CONSOLE
                }
            );
            Test.stopTest();

            Assert.areEqual(
                new Set<String>{ TabAccessService.CONSOLE_APP },
                appSetsOf(staff),
                'The save queued the sync, which took the standard app away'
            );
            Assert.areEqual(
                new Set<String>{ TabAccessService.CONSOLE_APP, TabAccessService.ADMIN_CONSOLE_APP },
                appSetsOf(UserInfo.getUserId()),
                'And the admin keeps the two console apps'
            );
        }
    }

    @IsTest
    static void eachStyleTurnsOnItsOwnTwoApps() {
        System.runAs(TestUsers.admin()) {
            SettingsService.saveValues(
                new Map<String, Object>{
                    'App_Navigation_Style__c' => TabAccessService.STYLE_STANDARD
                }
            );
            Assert.areEqual(
                new Set<String>{
                    TabAccessService.STANDARD_APP,
                    TabAccessService.ADMIN_STANDARD_APP
                },
                TabAccessService.appSetsOn(),
                'Standard'
            );
            SettingsService.saveValues(
                new Map<String, Object>{ 'App_Navigation_Style__c' => TabAccessService.STYLE_BOTH }
            );
            Assert.areEqual(4, TabAccessService.appSetsOn().size(), 'Both');
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
        return setsOf(userId, 'BarnCRM_Tab_%');
    }

    private static Boolean holdsHouseholds(Id userId) {
        return setsOf(userId, TabAccessService.HOUSEHOLDS_SET)
            .contains(TabAccessService.HOUSEHOLDS_SET);
    }

    private static Set<String> appSetsOf(Id userId) {
        return setsOf(userId, 'BarnCRM_App_%');
    }

    private static Set<String> setsOf(Id userId, String pattern) {
        Set<String> names = new Set<String>();
        for (PermissionSetAssignment row : [
            SELECT PermissionSet.Name
            FROM PermissionSetAssignment
            WHERE AssigneeId = :userId AND PermissionSet.Name LIKE :pattern
            WITH SYSTEM_MODE
        ]) {
            names.add(row.PermissionSet.Name);
        }
        return names;
    }
}
