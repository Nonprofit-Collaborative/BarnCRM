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
            Assert.areEqual(
                2,
                [
                    SELECT COUNT()
                    FROM Volunteer_Letter_Template__c
                    WHERE Active__c = TRUE AND Template_Key__c != NULL
                    WITH SYSTEM_MODE
                ],
                'The shipped letter templates arrive, one active per type'
            );
        }
    }

    /** The Rollup Definitions Volunteers ships, by key, from its own metadata. */
    private static Set<String> shippedKeys() {
        Set<String> keys = new Set<String>();
        for (Rollup_Definition_Default__mdt shipped : [
            SELECT Definition_Key__c
            FROM Rollup_Definition_Default__mdt
            WHERE Package__c = 'Volunteers'
        ]) {
            keys.add(shipped.Definition_Key__c);
        }
        return keys;
    }

    private static Map<String, Rollup_Definition__c> volunteerDefinitions() {
        Map<String, Rollup_Definition__c> byKey = new Map<String, Rollup_Definition__c>();
        for (Rollup_Definition__c definition : [
            SELECT Id, Definition_Key__c, Mode__c, Active__c, Is_Package_Default__c
            FROM Rollup_Definition__c
            WHERE Definition_Key__c IN :shippedKeys()
            WITH SYSTEM_MODE
        ]) {
            byKey.put(definition.Definition_Key__c, definition);
        }
        return byKey;
    }

    /**
     * The install creates the 19 volunteer totals (canonical model Section 29O), each active, in
     * mode Both and marked as shipped; an upgrade creates no second copy and keeps one the admin
     * switched off (ADR-0029, R-R6).
     */
    @IsTest
    static void theInstallCreatesTheVolunteerTotalsOnce() {
        System.runAs(TestUsers.admin()) {
            Assert.areEqual(19, shippedKeys().size(), 'Volunteers ships 19 rollups');

            Test.startTest();
            Test.testInstall(new VolunteersPostInstall(), null);
            Map<String, Rollup_Definition__c> installed = volunteerDefinitions();
            Rollup_Definition__c total = installed.get('Contact_Volunteer_Hours_Total');
            update as system new Rollup_Definition__c(Id = total.Id, Active__c = false);
            Test.testInstall(new VolunteersPostInstall(), new Version(0, 1), true);
            Test.stopTest();

            Assert.areEqual(19, installed.size(), 'Every shipped volunteer total is created');
            for (Rollup_Definition__c definition : installed.values()) {
                Assert.areEqual('Both', definition.Mode__c, definition.Definition_Key__c);
                Assert.isTrue(definition.Active__c, definition.Definition_Key__c);
                Assert.isTrue(definition.Is_Package_Default__c, definition.Definition_Key__c);
            }
            Map<String, Rollup_Definition__c> upgraded = volunteerDefinitions();
            Assert.areEqual(
                19,
                [
                    SELECT COUNT()
                    FROM Rollup_Definition__c
                    WHERE Definition_Key__c IN :shippedKeys()
                    WITH SYSTEM_MODE
                ],
                'An upgrade creates no second copy'
            );
            Assert.isFalse(
                upgraded.get('Contact_Volunteer_Hours_Total').Active__c,
                'A total the admin switched off stays off across an upgrade'
            );
            Assert.areEqual(
                0,
                [
                    SELECT COUNT()
                    FROM Error_Log__c
                    WHERE Context__c = :VolunteersPostInstall.ROLLUP_CONTEXT
                    WITH SYSTEM_MODE
                ],
                'Nothing failed'
            );
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
