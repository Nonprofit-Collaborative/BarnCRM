/**
 * Maria installs the Programs module and can open it straight away: she holds Programs Admin,
 * BarnCRM's roles hold their Programs sets, the module's automations have their switch rows, and
 * nothing in the install can fail it.
 */
@IsTest(testFor='ApexClass:ProgramsPostInstall')
private class ProgramsPostInstallTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static Integer adminSetsHeldBy(Id userId) {
        return [
            SELECT COUNT()
            FROM PermissionSetAssignment
            WHERE AssigneeId = :userId AND PermissionSet.Name = :ProgramsAccessSync.ADMIN_SET
            WITH SYSTEM_MODE
        ];
    }

    @IsTest
    static void theInstallerGetsProgramsAdminOnceAndTheRolesTheirSets() {
        System.runAs(TestUsers.admin()) {
            Id fresh = TestDataFactory.createUser('Installer', new List<String>()).Id;
            Id alreadyHolding = TestDataFactory.createUser(
                    'Holder',
                    new List<String>{ ProgramsAccessSync.ADMIN_SET }
                )
                .Id;
            User member = TestUsers.standardUser('Member');
            insert new PermissionSetAssignment(
                AssigneeId = member.Id,
                PermissionSetGroupId = TestDataFactory.prepareRoleGroup('Program_Staff').Id
            );

            Test.startTest();
            Test.testInstall(new ProgramsPostInstall(), null);
            System.enqueueJob(new ProgramsPostInstall.InstallerAccess(fresh));
            System.enqueueJob(new ProgramsPostInstall.InstallerAccess(alreadyHolding));
            Test.stopTest();

            Assert.areEqual(1, adminSetsHeldBy(fresh), 'The installer holds Programs Admin');
            Assert.areEqual(1, adminSetsHeldBy(alreadyHolding), 'Never given twice');
            Assert.areEqual(
                1,
                [
                    SELECT COUNT()
                    FROM PermissionSetAssignment
                    WHERE AssigneeId = :member.Id AND PermissionSet.Name = 'Programs_Staff'
                    WITH SYSTEM_MODE
                ],
                'The Team Member role holds Programs Staff after the install'
            );
            Assert.areEqual(
                0,
                [
                    SELECT COUNT()
                    FROM Error_Log__c
                    WHERE Context__c = :ProgramsPostInstall.ACCESS_CONTEXT
                    WITH SYSTEM_MODE
                ],
                'Nothing failed'
            );
            Assert.areEqual(
                2,
                [
                    SELECT COUNT()
                    FROM Automation_Setting__c
                    WHERE Handler_Class__c IN ('EnrollmentRulesHandler', 'EnrollmentDatesHandler')
                    WITH SYSTEM_MODE
                ],
                'Both enrollment automations have their switch rows'
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
            new ProgramsPostInstall().onInstall(null);
            System.enqueueJob(new ProgramsPostInstall.InstallerAccess(notAUser));
            Test.stopTest();

            Assert.areEqual(
                1,
                [
                    SELECT COUNT()
                    FROM Error_Log__c
                    WHERE Context__c = :ProgramsPostInstall.ACCESS_CONTEXT
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
            new ProgramsPostInstall().runSetup(null);
            Test.stopTest();

            Assert.areEqual(
                1,
                [
                    SELECT COUNT()
                    FROM PermissionSetAssignment
                    WHERE AssigneeId = :reader.Id AND PermissionSet.Name = 'Programs_Read_Only'
                    WITH SYSTEM_MODE
                ],
                'The Read Only role holds Programs Read Only'
            );
        }
    }
}
