/**
 * The feature tabs follow their feature (ADR-NEXT): once it is on, the BarnCRM Tab sets go to
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
            Assert.areEqual(
                5,
                tabSetsOf(UserInfo.getUserId()).size(),
                'An upgraded org has every feature on, so the admin keeps all five tabs'
            );
        }
    }

    @IsTest
    static void aNewInstallShowsNoFeatureTabUntilTheFeatureIsOn() {
        System.runAs(TestUsers.admin()) {
            FeatureSwitchService.markNewInstall();
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
                5,
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
