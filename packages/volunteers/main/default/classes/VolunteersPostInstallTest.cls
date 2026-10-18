/**
 * Maria installs the Volunteers module and can open it straight away: she holds Volunteers
 * Admin, BarnCRM's roles hold their Volunteers sets, and nothing in the install can fail it.
 */
@IsTest(testFor='ApexClass:VolunteersPostInstall')
private class VolunteersPostInstallTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static Integer adminSetsHeldBy(Id userId) {
        return [
            SELECT COUNT()
            FROM PermissionSetAssignment
            WHERE AssigneeId = :userId AND PermissionSet.Name = :VolunteersAccessSync.ADMIN_SET
            WITH SYSTEM_MODE
        ];
    }

    private static Integer accessFailures() {
        return [
            SELECT COUNT()
            FROM Error_Log__c
            WHERE Context__c = :VolunteersPostInstall.ACCESS_CONTEXT
            WITH SYSTEM_MODE
        ];
    }

    @IsTest
    static void theInstallerGetsVolunteersAdminOnceAndTheRolesTheirSets() {
        System.runAs(TestUsers.admin()) {
            Id fresh = TestDataFactory.createUser('Installer', new List<String>()).Id;
            Id alreadyHolding = TestDataFactory.createUser(
                    'Holder',
                    new List<String>{ VolunteersAccessSync.ADMIN_SET }
                )
                .Id;
            User member = TestUsers.standardUser('Member');
            insert new PermissionSetAssignment(
                AssigneeId = member.Id,
                PermissionSetGroupId = TestDataFactory.prepareRoleGroup('Program_Staff').Id
            );

            Test.startTest();
            Test.testInstall(new VolunteersPostInstall(), null);
            System.enqueueJob(new VolunteersPostInstall.InstallerAccess(fresh));
            System.enqueueJob(new VolunteersPostInstall.InstallerAccess(alreadyHolding));
            Test.stopTest();

            Assert.areEqual(1, adminSetsHeldBy(fresh), 'The installer holds Volunteers Admin');
            Assert.areEqual(1, adminSetsHeldBy(alreadyHolding), 'Never given twice');
            Assert.areEqual(
                1,
                [
                    SELECT COUNT()
                    FROM PermissionSetAssignment
                    WHERE AssigneeId = :member.Id AND PermissionSet.Name = 'Volunteers_Staff'
                    WITH SYSTEM_MODE
                ],
                'The Team Member role holds Volunteers Staff after the install'
            );
            Assert.areEqual(0, accessFailures(), 'Nothing failed');
        }
    }

    @IsTest
    static void aMissingContextChangesNothing() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            new VolunteersPostInstall().onInstall(null);
            Test.stopTest();

            Assert.areEqual(
                0,
                [SELECT COUNT() FROM AsyncApexJob WHERE JobType = 'Queueable' WITH SYSTEM_MODE],
                'Nothing is queued without an install to answer'
            );
        }
    }

    @IsTest
    static void aGrantThePlatformRefusesIsLoggedAsAWarning() {
        System.runAs(TestUsers.admin()) {
            // An Id that is no user, so the insert is refused for a reason other than a duplicate.
            Account notAUser = new Account(Name = 'Not a user');
            insert notAUser;

            Test.startTest();
            System.enqueueJob(new VolunteersPostInstall.InstallerAccess(notAUser.Id));
            Test.stopTest();

            List<Error_Log__c> logged = [
                SELECT Severity__c
                FROM Error_Log__c
                WHERE Context__c = :VolunteersPostInstall.ACCESS_CONTEXT
                WITH SYSTEM_MODE
            ];
            Assert.areEqual(1, logged.size(), 'The refusal is in the Error Log');
            Assert.areEqual(
                ErrorLogger.SEVERITY_WARNING,
                logged[0].Severity__c,
                'It is a warning: the install is not aborted by it'
            );
        }
    }
}
