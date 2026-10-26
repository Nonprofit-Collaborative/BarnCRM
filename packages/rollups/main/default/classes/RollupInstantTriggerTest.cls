/**
 * The entry point a generated rollup trigger calls (ADR-0138). No generated trigger ships, so
 * the trigger context is handed to `handle` directly, as `run` hands it inside a trigger, with
 * organizations counting their child organizations (`ParentId`) as `RollupTriggerHandlerTest`
 * does: Account has no packaged rollup trigger.
 */
@IsTest(testFor='ApexClass:RollupInstantTrigger')
private class RollupInstantTriggerTest {
    /** Totals read right after each save: recalculated in the save (RollupTestSupport). */
    @TestSetup
    static void recalculateInTheSave() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            RollupTestSupport.recalculateInTheSave();
        }
    }

    private static Account organization(String name, Id parentId) {
        return new Account(
            Name = name,
            ParentId = parentId,
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
                .get('Organization')
                .getRecordTypeId()
        );
    }

    /** A child organization saved under a parent counted by a new Instantly rollup. */
    private static Account savedChild() {
        insert new Rollup_Definition__c(
            Name = 'Child organization count',
            Definition_Key__c = 'Custom_Instant_Child_Count',
            Source_Object__c = 'Account',
            Target_Object__c = 'Account',
            Relationship_Path__c = 'ParentId',
            Aggregate__c = 'COUNT',
            Target_Field__c = 'NumberOfEmployees',
            Mode__c = RollupService.MODE_REAL_TIME,
            Fiscal_Year_Aware__c = false,
            Active__c = true
        );
        Account parent = organization('Parent', null);
        insert parent;
        Account child = organization('Child', parent.Id);
        insert child;
        TriggerHandler.clearRunClaims();
        TriggerHandler.setTestRecords(new List<SObject>{ child }, null);
        return child;
    }

    private static Integer countOn(Id parentId) {
        return [SELECT NumberOfEmployees FROM Account WHERE Id = :parentId].NumberOfEmployees;
    }

    @IsTest
    static void aSaveReachesTheRollupEngine() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            Account child = savedChild();

            Test.startTest();
            RollupInstantTrigger.handle(
                System.TriggerOperation.AFTER_INSERT,
                new List<SObject>{ child },
                new Map<Id, SObject>{ child.Id => child },
                null,
                null
            );
            Test.stopTest();

            System.Assert.areEqual(
                1,
                countOn(child.ParentId),
                'The generated trigger hands the save to the same handler a packaged one does.'
            );
        }
    }

    @IsTest
    static void aSwitchedOffObjectIsLeftAlone() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            TestDataFactory.insertAutomationSettings(
                new Map<String, Boolean>{ RollupInstantTrigger.triggerNameFor('Account') => false }
            );
            Account child = savedChild();

            Test.startTest();
            RollupInstantTrigger.handle(
                System.TriggerOperation.AFTER_INSERT,
                new List<SObject>{ child },
                new Map<Id, SObject>{ child.Id => child },
                null,
                null
            );
            RollupInstantTrigger.handle(
                System.TriggerOperation.AFTER_INSERT,
                new List<SObject>(),
                null,
                null,
                null
            );
            Test.stopTest();

            System.Assert.areNotEqual(
                1,
                countOn(child.ParentId),
                'With its switch off the trigger does nothing: the nightly run covers Both.'
            );
        }
    }

    // runs-as: deploying user (namesAreTheSameInEveryOrg: pure string logic, no DML or SOQL)
    @IsTest
    static void namesAreTheSameInEveryOrg() {
        System.Assert.areEqual(
            'BarnRollup_Account',
            RollupInstantTrigger.triggerNameFor('Account'),
            'A standard object keeps its name.'
        );
        System.Assert.areEqual(
            'BarnRollup_Shift_c_Test',
            RollupInstantTrigger.testClassNameFor('Shift__c'),
            'Underscores run together become one, and the test adds _Test.'
        );
        String longOne = RollupInstantTrigger.triggerNameFor('Volunteer_Shift_Signup_Record__c');
        String longTwo = RollupInstantTrigger.triggerNameFor('Volunteer_Shift_Signup_Records__c');
        System.Assert.isTrue(
            (longOne + '_Test').length() <= 40,
            'A long name is cut so its test class fits 40 characters: ' + longOne
        );
        System.Assert.isTrue(
            longOne.startsWith(RollupInstantTrigger.namePrefix()),
            'Every generated name starts the same way.'
        );
        System.Assert.areNotEqual(longOne, longTwo, 'Two long names that start alike differ.');
        System.Assert.areEqual(
            longOne,
            RollupInstantTrigger.triggerNameFor('Volunteer_Shift_Signup_Record__c'),
            'And the same name always gives the same result.'
        );
    }

    @IsTest
    static void hasRunSaysWhetherATriggerCalledRun() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            System.Assert.isFalse(RollupInstantTrigger.hasRun(), 'Nothing has called it yet.');
            RollupInstantTrigger.run();
            System.Assert.isTrue(
                RollupInstantTrigger.hasRun(),
                'The generated test asserts this after its insert.'
            );
        }
    }
}
