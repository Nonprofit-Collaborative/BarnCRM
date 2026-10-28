/**
 * BarnCRM's roles get the Rollup Builder sets (ADR-0125 `0125-rollup-builder-module.md`, D2):
 * Staff and Read Only holders get Rollup Builder User, Admin holders Rollup Builder Admin,
 * whether they hold the set directly or through a role, at install and with the nightly run.
 */
@IsTest(testFor='ApexClass:RollupAccessSync')
private class RollupAccessSyncTest {
    private static final String ADMIN_SET = RollupsPostInstall.ADMIN_PERMISSION_SET;

    /** The role each person holds through a permission set group, by last name. */
    private static final Map<String, String> GROUP_BY_NAME = new Map<String, String>{
        'Reader' => 'Read_Only',
        'Coordinator' => 'Volunteer_Coordinator',
        'Boss' => 'BarnCRM_Admin_Group'
    };

    /** The test user and the people, created once for every method. */
    @TestSetup
    static void createTestUsers() {
        System.runAs(TestUsers.admin()) {
            createPeople();
        }
    }

    /** The people, by last name: one per way of holding a role, and one with none. */
    private static Map<String, Id> people() {
        Map<String, Id> ids = new Map<String, Id>();
        for (User person : [
            SELECT Id, LastName
            FROM User
            WHERE
                Username LIKE 'barn-test.%'
                AND LastName IN ('Staffer', 'Outsider', 'Reader', 'Coordinator', 'Boss')
            WITH SYSTEM_MODE
        ]) {
            ids.put(person.LastName, person.Id);
        }
        for (String developerName : GROUP_BY_NAME.values()) {
            TestDataFactory.prepareRoleGroup(developerName);
        }
        return ids;
    }

    private static void createPeople() {
        TestUsers.standardUserWith('Staffer', new List<String>{ 'BarnCRM_Staff' });
        TestUsers.standardUser('Outsider');
        List<PermissionSetAssignment> roles = new List<PermissionSetAssignment>();
        for (String name : GROUP_BY_NAME.keySet()) {
            roles.add(
                new PermissionSetAssignment(
                    AssigneeId = TestUsers.standardUser(name).Id,
                    PermissionSetGroupId = TestDataFactory.prepareRoleGroup(GROUP_BY_NAME.get(name))
                        .Id
                )
            );
        }
        insert roles;
    }

    private static Set<String> setsOf(Id userId) {
        Set<String> names = new Set<String>();
        for (PermissionSetAssignment row : [
            SELECT PermissionSet.Name
            FROM PermissionSetAssignment
            WHERE AssigneeId = :userId AND PermissionSet.Name LIKE 'Rollup_Builder_%'
            WITH SYSTEM_MODE
        ]) {
            names.add(row.PermissionSet.Name);
        }
        return names;
    }

    @IsTest
    static void givesEachRoleItsRollupBuilderSet() {
        System.runAs(TestUsers.admin()) {
            Map<String, Id> ids = people();

            Test.startTest();
            Boolean more = RollupAccessSync.syncOnce();
            Boolean again = RollupAccessSync.syncOnce();
            Test.stopTest();

            Assert.isFalse(more, 'A small org is done in one pass');
            Assert.isFalse(again, 'And a second pass finds nothing to give');
            for (String name : new List<String>{ 'Staffer', 'Reader', 'Coordinator' }) {
                Assert.areEqual(
                    new Set<String>{ RollupAccessSync.USER_SET },
                    setsOf(ids.get(name)),
                    name + ' gets the read-only Builder, directly or through a role'
                );
            }
            Assert.isTrue(
                setsOf(ids.get('Boss')).contains(ADMIN_SET),
                'The BarnCRM Admin role gets Rollup Builder Admin'
            );
            Assert.isTrue(setsOf(ids.get('Outsider')).isEmpty(), 'No role, no set');
        }
    }

    @IsTest
    static void aLargeOrgIsDoneASliceAtATime() {
        System.runAs(TestUsers.admin()) {
            people();
            RollupAccessSync.rowsPerSet = 1;

            Test.startTest();
            Boolean more = RollupAccessSync.syncOnce();
            Test.stopTest();

            Assert.isTrue(more, 'Three Builder users do not fit in a slice of one');
        }
    }

    @IsTest
    static void givesNothingWhileTheModuleIsOff() {
        System.runAs(TestUsers.admin()) {
            Map<String, Id> ids = people();
            ModuleManagerService.turnOff(RollupService.MODULE_NAME);

            Test.startTest();
            Boolean more = RollupAccessSync.syncOnce();
            Test.stopTest();

            Assert.isFalse(more, 'Nothing to do');
            Assert.isTrue(setsOf(ids.get('Staffer')).isEmpty(), 'Nothing was given');
        }
    }

    @IsTest
    static void turningTheModuleOnQueuesTheSync() {
        Map<String, Id> ids;
        // Its own block: Turn on also writes switch rows, which may not follow setup writes.
        System.runAs(TestUsers.admin()) {
            ids = people();
        }
        System.runAs(TestUsers.admin()) {
            ModuleManagerService.turnOff(RollupService.MODULE_NAME);

            Test.startTest();
            ModuleManagerService.turnOn(RollupService.MODULE_NAME);
            Test.stopTest();

            Assert.isTrue(
                setsOf(ids.get('Staffer')).contains(RollupAccessSync.USER_SET),
                'Someone given a role while it was off gets the set once it is on'
            );
        }
    }

    @IsTest
    static void skipsInactivePeopleAndThoseHoldingItThroughAGroup() {
        System.runAs(TestUsers.admin()) {
            List<String> staff = new List<String>{ 'BarnCRM_Staff' };
            User gone = TestUsers.standardUserWith('Gone', staff);
            gone.IsActive = false;
            update gone;
            // A role of the org's own that already includes Rollup Builder User.
            PermissionSetGroup role = new PermissionSetGroup(
                DeveloperName = 'Test_Rollup_Role',
                MasterLabel = 'Test Rollup Role'
            );
            insert role;
            insert new PermissionSetGroupComponent(
                PermissionSetGroupId = role.Id,
                PermissionSetId = [
                    SELECT Id
                    FROM PermissionSet
                    WHERE Name = :RollupAccessSync.USER_SET
                    LIMIT 1
                ]
                .Id
            );
            Test.calculatePermissionSetGroup(role.Id);
            User grouped = TestUsers.standardUserWith('Grouped', staff);
            insert new PermissionSetAssignment(
                AssigneeId = grouped.Id,
                PermissionSetGroupId = role.Id
            );

            Test.startTest();
            Boolean more = RollupAccessSync.syncOnce();
            Test.stopTest();

            Assert.isFalse(more, 'Nothing is left');
            Assert.isTrue(setsOf(gone.Id).isEmpty(), 'An inactive Staff holder is given nothing');
            Assert.isTrue(
                setsOf(grouped.Id).isEmpty(),
                'Someone holding it through a group is not given it again directly'
            );
        }
    }

    @IsTest
    static void theInstallerIsGivenRollupBuilderAdminOnce() {
        System.runAs(TestUsers.admin()) {
            Map<String, Id> ids = people();
            Id installer = ids.get('Boss');

            Test.startTest();
            System.enqueueJob(new RollupsPostInstall.InstallerAccess(installer));
            Test.stopTest();

            Assert.areEqual(
                1,
                [
                    SELECT COUNT()
                    FROM PermissionSetAssignment
                    WHERE AssigneeId = :installer AND PermissionSet.Name = :ADMIN_SET
                ],
                'The installer, a BarnCRM Admin, holds Rollup Builder Admin once'
            );
            Assert.isTrue(
                setsOf(ids.get('Reader')).contains(RollupAccessSync.USER_SET),
                'The roles sync ran after the installer\'s grant'
            );
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Error_Log__c WHERE Severity__c != :ErrorLogger.SEVERITY_INFO],
                'Nothing was refused'
            );
        }
    }

    @IsTest
    static void theInstallQueuesTheSync() {
        System.runAs(TestUsers.admin()) {
            Map<String, Id> ids = people();

            Test.startTest();
            Test.testInstall(new RollupsPostInstall(), null);
            Test.stopTest();

            Assert.isTrue(
                setsOf(ids.get('Reader')).contains(RollupAccessSync.USER_SET),
                'The queued sync gave the Read Only role the read-only Builder'
            );
        }
    }

    @IsTest
    static void theNightlyRunQueuesTheSync() {
        System.runAs(TestUsers.admin()) {
            Map<String, Id> ids = people();

            Test.startTest();
            new RollupScheduler().execute(null);
            Test.stopTest();

            Assert.isTrue(
                setsOf(ids.get('Staffer')).contains(RollupAccessSync.USER_SET),
                'Someone given a role since the install gets the set overnight'
            );
        }
    }
}
