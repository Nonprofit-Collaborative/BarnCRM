/**
 * BarnCRM's roles get the Rollup Builder sets (ADR-NEXT `NEXT-rollup-builder-module.md`, D2):
 * Staff and Read Only holders get Rollup Builder User, Admin holders Rollup Builder Admin,
 * whether they hold the set directly or through a role, at install and with the nightly run.
 */
@IsTest(testFor='ApexClass:RollupAccessSync')
private class RollupAccessSyncTest {
    private static final String ADMIN_SET = RollupsPostInstall.ADMIN_PERMISSION_SET;

    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    /** The people, by last name: one per way of holding a role, and one with none. */
    private static Map<String, Id> people() {
        Map<String, Id> ids = new Map<String, Id>{
            'Staffer' => TestUsers.standardUserWith('Staffer', new List<String>{ 'BarnCRM_Staff' })
                .Id,
            'Outsider' => TestUsers.standardUser('Outsider').Id
        };
        Map<String, String> groupByName = new Map<String, String>{
            'Reader' => 'Read_Only',
            'Coordinator' => 'Volunteer_Coordinator',
            'Boss' => 'BarnCRM_Admin_Group'
        };
        List<PermissionSetAssignment> roles = new List<PermissionSetAssignment>();
        for (String name : groupByName.keySet()) {
            Id userId = TestUsers.standardUser(name).Id;
            ids.put(name, userId);
            roles.add(
                new PermissionSetAssignment(
                    AssigneeId = userId,
                    PermissionSetGroupId = TestDataFactory.prepareRoleGroup(groupByName.get(name))
                        .Id
                )
            );
        }
        insert roles;
        return ids;
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
