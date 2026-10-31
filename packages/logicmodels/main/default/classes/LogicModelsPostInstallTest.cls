/**
 * Maria installs the Logic Models module and can open it straight away: she holds Logic Models Admin,
 * BarnCRM's roles hold their Logic Models sets, the module's automations have their switch rows, and
 * nothing in the install can fail it.
 */
@IsTest(testFor='ApexClass:LogicModelsPostInstall')
private class LogicModelsPostInstallTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static Integer adminSetsHeldBy(Id userId) {
        return [
            SELECT COUNT()
            FROM PermissionSetAssignment
            WHERE AssigneeId = :userId AND PermissionSet.Name = :LogicModelsAccessSync.ADMIN_SET
            WITH SYSTEM_MODE
        ];
    }

    @IsTest
    static void theInstallerGetsLogicModelsAdminOnceAndTheRolesTheirSets() {
        System.runAs(TestUsers.admin()) {
            Id fresh = TestDataFactory.createUser('Installer', new List<String>()).Id;
            Id alreadyHolding = TestDataFactory.createUser(
                    'Holder',
                    new List<String>{ LogicModelsAccessSync.ADMIN_SET }
                )
                .Id;
            User member = TestUsers.standardUser('Member');
            insert new PermissionSetAssignment(
                AssigneeId = member.Id,
                PermissionSetGroupId = TestDataFactory.prepareRoleGroup('Program_Staff').Id
            );

            Test.startTest();
            Test.testInstall(new LogicModelsPostInstall(), null);
            System.enqueueJob(new LogicModelsPostInstall.InstallerAccess(fresh));
            System.enqueueJob(new LogicModelsPostInstall.InstallerAccess(alreadyHolding));
            Test.stopTest();

            Assert.areEqual(1, adminSetsHeldBy(fresh), 'The installer holds Logic Models Admin');
            Assert.areEqual(1, adminSetsHeldBy(alreadyHolding), 'Never given twice');
            Assert.areEqual(
                1,
                [
                    SELECT COUNT()
                    FROM PermissionSetAssignment
                    WHERE AssigneeId = :member.Id AND PermissionSet.Name = 'Logic_Models_Staff'
                    WITH SYSTEM_MODE
                ],
                'The Team Member role holds Logic Models Staff after the install'
            );
            Assert.areEqual(
                0,
                [
                    SELECT COUNT()
                    FROM Error_Log__c
                    WHERE Context__c = :LogicModelsPostInstall.ACCESS_CONTEXT
                    WITH SYSTEM_MODE
                ],
                'Nothing failed'
            );
            Assert.areEqual(
                1,
                [
                    SELECT COUNT()
                    FROM Automation_Setting__c
                    WHERE Handler_Class__c = 'LogicModelScopeHandler'
                    WITH SYSTEM_MODE
                ],
                'The scope automation has its switch row'
            );
        }
    }

    /** A grant the platform refuses is logged, never thrown, and a missing context is a no-op. */
    @IsTest
    static void aRefusedGrantIsLoggedAndNeverFailsTheInstall() {
        System.runAs(TestUsers.admin()) {
            // An Id that is not a user: the assignment is refused for a reason other than a duplicate.
            Id notAUser = TestUsers.admin().ProfileId;

            Test.startTest();
            new LogicModelsPostInstall().onInstall(null);
            System.enqueueJob(new LogicModelsPostInstall.InstallerAccess(notAUser));
            Test.stopTest();

            Assert.areEqual(
                1,
                [
                    SELECT COUNT()
                    FROM Error_Log__c
                    WHERE Context__c = :LogicModelsPostInstall.ACCESS_CONTEXT
                    WITH SYSTEM_MODE
                ],
                'The refusal is in the Error Log'
            );
        }
    }

    @IsTest
    static void anInstallWithNoInstallerStillSyncsTheRoles() {
        System.runAs(TestUsers.admin()) {
            User reader = TestUsers.standardUser('Reader');
            insert new PermissionSetAssignment(
                AssigneeId = reader.Id,
                PermissionSetGroupId = TestDataFactory.prepareRoleGroup('Read_Only').Id
            );

            Test.startTest();
            new LogicModelsPostInstall().runSetup(null);
            Test.stopTest();

            Assert.areEqual(
                1,
                [
                    SELECT COUNT()
                    FROM PermissionSetAssignment
                    WHERE AssigneeId = :reader.Id AND PermissionSet.Name = 'Logic_Models_Read_Only'
                    WITH SYSTEM_MODE
                ],
                'The Read Only role holds Logic Models Read Only'
            );
        }
    }
}
