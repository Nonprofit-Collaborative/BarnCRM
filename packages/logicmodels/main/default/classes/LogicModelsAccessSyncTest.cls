/**
 * BarnCRM's roles get the Logic Models sets (ADR-0154 decision 7): BarnCRM Admin holders Logic
 * Models Admin, the Team Member and Coordinator roles Logic Models Staff and the Read Only role Logic Models
 * Read Only, at install, at Turn on and with the hourly access check.
 */
@IsTest(testFor='ApexClass:LogicModelsAccessSync')
private class LogicModelsAccessSyncTest {
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
            WHERE AssigneeId = :userId AND PermissionSet.Name LIKE 'Logic_Models_%'
            WITH SYSTEM_MODE
        ]) {
            names.add(row.PermissionSet.Name);
        }
        return names;
    }

    @IsTest
    static void givesEachRoleItsLogicModelsSet() {
        System.runAs(TestUsers.admin()) {
            Map<String, Id> ids = people();

            Test.startTest();
            Boolean more = LogicModelsAccessSync.syncOnce();
            Boolean again = LogicModelsAccessSync.syncOnce();
            Test.stopTest();

            Assert.isFalse(more, 'A small org is done in one pass');
            Assert.isFalse(again, 'And a second pass finds nothing to give');
            Map<String, String> expected = new Map<String, String>{
                'Coordinator' => 'Logic_Models_Staff',
                'Member' => 'Logic_Models_Staff',
                'Reader' => 'Logic_Models_Read_Only',
                'Boss' => LogicModelsAccessSync.ADMIN_SET
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
            LogicModelsAccessSync.rowsPerSet = 0;

            Test.startTest();
            Boolean more = LogicModelsAccessSync.syncOnce();
            Test.stopTest();

            Assert.isTrue(more, 'Nobody fits in a slice of nothing, so more is left');
        }
    }

    @IsTest
    static void givesNothingWhileTheModuleIsOff() {
        System.runAs(TestUsers.admin()) {
            Map<String, Id> ids = people();
            ModuleManagerService.turnOff(LogicModelsAccessSync.MODULE_NAME);

            Test.startTest();
            Boolean more = LogicModelsAccessSync.syncOnce();
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
                setsOf(ids.get('Member')).contains('Logic_Models_Staff'),
                'Someone given a role since the install gets the set within the hour'
            );
        }
    }
}
