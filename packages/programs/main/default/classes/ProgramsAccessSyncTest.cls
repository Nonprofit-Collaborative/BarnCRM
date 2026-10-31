/**
 * BarnCRM's roles get the Programs sets (ADR-NEXT decision 7): BarnCRM Admin holders Programs
 * Admin, the Team Member and Coordinator roles Programs Staff and the Read Only role Programs Read
 * Only, at install, at Turn on and with the hourly access check.
 */
@IsTest(testFor='ApexClass:ProgramsAccessSync')
private class ProgramsAccessSyncTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    /** The people, by last name: one per role, and one with none. */
    private static Map<String, Id> people() {
        Map<String, Id> ids = new Map<String, Id>{
            'Outsider' => TestUsers.standardUser('Outsider').Id
        };
        Map<String, String> groupByName = new Map<String, String>{
            'Coordinator' => 'Volunteer_Coordinator',
            'Member' => 'Program_Staff',
            'Reader' => 'Read_Only',
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
            WHERE AssigneeId = :userId AND PermissionSet.Name LIKE 'Programs_%'
            WITH SYSTEM_MODE
        ]) {
            names.add(row.PermissionSet.Name);
        }
        return names;
    }

    @IsTest
    static void givesEachRoleItsProgramsSet() {
        System.runAs(TestUsers.admin()) {
            Map<String, Id> ids = people();

            Test.startTest();
            Boolean more = ProgramsAccessSync.syncOnce();
            Boolean again = ProgramsAccessSync.syncOnce();
            Test.stopTest();

            Assert.isFalse(more, 'A small org is done in one pass');
            Assert.isFalse(again, 'And a second pass finds nothing to give');
            Map<String, String> expected = new Map<String, String>{
                'Coordinator' => 'Programs_Staff',
                'Member' => 'Programs_Staff',
                'Reader' => 'Programs_Read_Only',
                'Boss' => ProgramsAccessSync.ADMIN_SET
            };
            for (String name : expected.keySet()) {
                Assert.areEqual(
                    new Set<String>{ expected.get(name) },
                    setsOf(ids.get(name)),
                    name + ' gets their role\'s set and no other'
                );
            }
            Assert.isTrue(setsOf(ids.get('Outsider')).isEmpty(), 'No role, no set');
        }
    }

    @IsTest
    static void aLargeOrgIsDoneASliceAtATime() {
        System.runAs(TestUsers.admin()) {
            people();
            ProgramsAccessSync.rowsPerSet = 0;

            Test.startTest();
            Boolean more = ProgramsAccessSync.syncOnce();
            Test.stopTest();

            Assert.isTrue(more, 'Nobody fits in a slice of nothing, so more is left');
        }
    }

    @IsTest
    static void givesNothingWhileTheModuleIsOff() {
        System.runAs(TestUsers.admin()) {
            Map<String, Id> ids = people();
            ModuleManagerService.turnOff(ProgramsAccessSync.MODULE_NAME);

            Test.startTest();
            Boolean more = ProgramsAccessSync.syncOnce();
            Test.stopTest();

            Assert.isFalse(more, 'Nothing to do');
            Assert.isTrue(setsOf(ids.get('Member')).isEmpty(), 'Nothing was given');
        }
    }

    @IsTest
    static void theHourlyAccessCheckQueuesTheSync() {
        System.runAs(TestUsers.admin()) {
            Map<String, Id> ids = people();

            Test.startTest();
            // What Core's hourly access check (TabAccessScheduler) asks of every module.
            ModuleAccessSyncs.requestAll();
            Test.stopTest();

            Assert.isTrue(
                setsOf(ids.get('Member')).contains('Programs_Staff'),
                'Someone given a role since the install gets the set within the hour'
            );
        }
    }
}
