/**
 * Who may change a Rollup Definition outside the Builder, and what it may read and write
 * (2026-10-28 security review, R-H1): holding Create and Edit on the object through the Rollup
 * Builder set is not enough without Manage BarnCRM Settings, a total never goes to the user
 * record or setup objects, and the author must be able to write the target and read the source.
 */
@IsTest(
    testFor='ApexClass:RollupDefinitionGuard, ApexTrigger:RollupDefinitionTrigger, ApexClass:RollupWriter'
)
private class RollupDefinitionGuardTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.adminWith('Rollup_Builder_Admin');
    }

    private static Rollup_Definition__c definition(String key) {
        return new Rollup_Definition__c(
            Name = key,
            Definition_Key__c = key,
            Source_Object__c = 'Contact',
            Relationship_Path__c = 'AccountId',
            Aggregate__c = 'COUNT',
            Target_Object__c = 'Account',
            Target_Field__c = 'NumberOfEmployees',
            Mode__c = RollupService.MODE_BOTH,
            Fiscal_Year_Aware__c = false,
            Active__c = false
        );
    }

    /** Holds the Rollup Builder set, with Create and Edit on the object, but not the settings permission. */
    private static User builderOnly() {
        User builder;
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            builder = TestUsers.standardUserWith(
                'Builderonly',
                new List<String>{ 'Rollup_Builder_Admin' }
            );
        }
        return builder;
    }

    private static String firstError(Database.SaveResult saved) {
        return saved.getErrors().isEmpty() ? null : saved.getErrors()[0].getMessage();
    }

    @IsTest
    static void aBuilderWithoutTheSettingsPermissionCannotCreateOne() {
        User builder = builderOnly();
        Database.SaveResult saved;

        Test.startTest();
        System.runAs(builder) {
            saved = Database.insert(
                definition('Test_Guard_Create'),
                false,
                AccessLevel.SYSTEM_MODE
            );
        }
        Test.stopTest();

        Assert.isFalse(
            saved.isSuccess(),
            'A save from outside the Builder still needs the permission'
        );
        Assert.areEqual(System.Label.Core_Rollups_ErrorNoPermission, firstError(saved), 'Says why');
    }

    @IsTest
    static void aBuilderWithoutTheSettingsPermissionCannotRetargetOne() {
        Rollup_Definition__c saved = definition('Test_Guard_Retarget');
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            insert as user saved;
        }
        User builder = builderOnly();
        Database.SaveResult result;

        Test.startTest();
        System.runAs(builder) {
            result = Database.update(
                new Rollup_Definition__c(Id = saved.Id, Target_Field__c = 'AnnualRevenue'),
                false,
                AccessLevel.SYSTEM_MODE
            );
        }
        Test.stopTest();

        Assert.isFalse(result.isSuccess(), 'Retargeting needs the permission');
        Assert.areEqual(
            'NumberOfEmployees',
            [SELECT Target_Field__c FROM Rollup_Definition__c WHERE Id = :saved.Id WITH SYSTEM_MODE]
            .Target_Field__c,
            'The target is unchanged'
        );
    }

    @IsTest
    static void anAdministratorCannotSendATotalToTheUserRecord() {
        Rollup_Definition__c onUsers = definition('Test_Guard_User');
        onUsers.Source_Object__c = 'Contact';
        onUsers.Relationship_Path__c = 'OwnerId';
        onUsers.Target_Object__c = 'User';
        onUsers.Target_Field__c = 'Title';
        onUsers.Aggregate__c = 'LAST';
        onUsers.Source_Field__c = 'Title';
        onUsers.Order_By_Field__c = 'CreatedDate';
        Database.SaveResult saved;

        Test.startTest();
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            saved = Database.insert(onUsers, false, AccessLevel.SYSTEM_MODE);
        }
        Test.stopTest();

        Assert.isFalse(saved.isSuccess(), 'No total goes to the user record');
        Set<String> messages = new Set<String>();
        for (Database.Error error : saved.getErrors()) {
            messages.add(error.getMessage());
        }
        Assert.isTrue(
            messages.contains(System.Label.Core_Rollups_ErrorTargetNotAllowed),
            'Says the object cannot hold a total: ' + messages
        );
    }

    @IsTest
    static void onlyObjectsATotalMayGoToAreAllowed() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            Assert.isTrue(RollupDefinitionGuard.isAllowedTarget('Account'), 'Account holds totals');
            Assert.isTrue(
                RollupDefinitionGuard.isAllowedTarget('Gift__c'),
                'An org object holds totals'
            );
            Assert.isFalse(RollupDefinitionGuard.isAllowedTarget('User'), 'Never the user record');
            Assert.isFalse(RollupDefinitionGuard.isAllowedTarget('PermissionSet'), 'Never setup');
            Assert.isFalse(
                RollupDefinitionGuard.isAllowedTarget('Rollup_Queue__c'),
                'Never BarnCRM bookkeeping'
            );
            Assert.isFalse(RollupDefinitionGuard.isAllowedTarget(' '), 'Never a blank');
        }
    }

    @IsTest
    static void aTargetTheAuthorCannotWriteIsRefused() {
        Rollup_Definition__c onCreatedDate = definition('Test_Guard_Read_Only');
        onCreatedDate.Target_Field__c = 'CreatedDate';
        String problem;

        Test.startTest();
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            problem = RollupDefinitionGuard.accessProblem(onCreatedDate);
        }
        Test.stopTest();

        Assert.areEqual(System.Label.Core_Rollups_ErrorTargetNotWritable, problem, 'Says why');
    }

    @IsTest
    static void aSourceTheAuthorCannotReadIsRefused() {
        User reader = TestUsers.standardUser('Noqueue');
        Rollup_Definition__c fromQueue = definition('Test_Guard_Unreadable');
        fromQueue.Source_Object__c = 'Rollup_Queue__c';
        fromQueue.Relationship_Path__c = 'Name';
        String problem;

        Test.startTest();
        System.runAs(reader) {
            problem = RollupDefinitionGuard.accessProblem(fromQueue);
        }
        Test.stopTest();

        Assert.areEqual(System.Label.Core_Rollups_ErrorFieldNotReadable, problem, 'Says why');
    }

    @IsTest
    static void aDefinitionTheAuthorMayReadAndWritePasses() {
        String problem;

        Test.startTest();
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            problem = RollupDefinitionGuard.accessProblem(definition('Test_Guard_Fine'));
        }
        Test.stopTest();

        Assert.isNull(problem, 'A count of contacts into employees is allowed');
    }

    @IsTest
    static void theShippedDefaultsAndTheEngineStampNeedNoPermission() {
        User builder = builderOnly();
        Rollup_Definition__c shipped = definition('Test_Guard_Shipped');

        Test.startTest();
        System.runAs(builder) {
            RollupWriter.insertDefinitions(new List<Rollup_Definition__c>{ shipped });
            RollupWriter.stampDefinitions(new Map<Id, Datetime>{ shipped.Id => Datetime.now() });
        }
        Test.stopTest();

        Rollup_Definition__c stored = [
            SELECT Last_Calculated__c
            FROM Rollup_Definition__c
            WHERE Id = :shipped.Id
            WITH SYSTEM_MODE
        ];
        Assert.isNotNull(stored.Last_Calculated__c, 'The package wrote and stamped its own row');
        Assert.isFalse(
            RollupDefinitionGuard.shippedDefaultsSaving,
            'The trust ends with the shipped save'
        );
    }
}
