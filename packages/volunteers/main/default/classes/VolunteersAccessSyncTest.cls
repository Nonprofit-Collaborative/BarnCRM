/**
 * BarnCRM's roles get the Volunteers sets (ADR-0127 decision 3): the Coordinator role gets
 * Volunteers Coordinator and the Team Member role Volunteers Staff, though both hold the same
 * Core set, the Read Only role Volunteers Read Only and BarnCRM Admin holders Volunteers Admin,
 * at install, at Turn on and with the nightly access check.
 */
@IsTest(testFor='ApexClass:VolunteersAccessSync')
private class VolunteersAccessSyncTest {
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
            WHERE AssigneeId = :userId AND PermissionSet.Name LIKE 'Volunteers_%'
            WITH SYSTEM_MODE
        ]) {
            names.add(row.PermissionSet.Name);
        }
        return names;
    }

    @IsTest
    static void givesEachRoleItsOwnVolunteersSet() {
        System.runAs(TestUsers.admin()) {
            Map<String, Id> ids = people();

            Test.startTest();
            Boolean more = VolunteersAccessSync.syncOnce();
            Boolean again = VolunteersAccessSync.syncOnce();
            Test.stopTest();

            Assert.isFalse(more, 'A small org is done in one pass');
            Assert.isFalse(again, 'And a second pass finds nothing to give');
            Map<String, String> expected = new Map<String, String>{
                'Coordinator' => 'Volunteers_Coordinator',
                'Member' => 'Volunteers_Staff',
                'Reader' => 'Volunteers_Read_Only',
                'Boss' => VolunteersAccessSync.ADMIN_SET
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
            VolunteersAccessSync.rowsPerSet = 0;

            Test.startTest();
            Boolean more = VolunteersAccessSync.syncOnce();
            Test.stopTest();

            Assert.isTrue(more, 'Nobody fits in a slice of nothing, so more is left');
        }
    }

    @IsTest
    static void givesNothingWhileTheModuleIsOff() {
        System.runAs(TestUsers.admin()) {
            Map<String, Id> ids = people();
            ModuleManagerService.turnOff(VolunteersAccessSync.MODULE_NAME);

            Test.startTest();
            Boolean more = VolunteersAccessSync.syncOnce();
            Test.stopTest();

            Assert.isFalse(more, 'Nothing to do');
            Assert.isTrue(setsOf(ids.get('Member')).isEmpty(), 'Nothing was given');
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
            ModuleManagerService.turnOff(VolunteersAccessSync.MODULE_NAME);

            Test.startTest();
            ModuleManagerService.turnOn(VolunteersAccessSync.MODULE_NAME);
            Test.stopTest();

            Assert.isTrue(
                setsOf(ids.get('Coordinator')).contains('Volunteers_Coordinator'),
                'Someone given a role while it was off gets the set once it is on'
            );
        }
    }

    @IsTest
    static void theNightlyAccessCheckQueuesTheSync() {
        System.runAs(TestUsers.admin()) {
            Map<String, Id> ids = people();

            Test.startTest();
            // What Core's nightly access check (TabAccessScheduler) asks of every module.
            ModuleAccessSyncs.requestAll();
            Test.stopTest();

            Assert.isTrue(
                setsOf(ids.get('Member')).contains('Volunteers_Staff'),
                'Someone given a role since the install gets the set overnight'
            );
        }
    }
}
