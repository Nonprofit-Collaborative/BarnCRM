/**
 * The two Relationship__c handlers, each on its own, and the case the split exists for: an
 * administrator who switches the reciprocal maintenance off before a bulk import still gets
 * every check on the records the import saves.
 *
 * NOT EXECUTED. No Salesforce org exists in the environment these were written in, so every
 * assertion here is unverified. They are written to the same standard as if they had run, and
 * the first person with a scratch org should run them before trusting the feature.
 */
@IsTest
private class RelationshipHandlerTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static final String MAINTENANCE = 'Relationship_Reciprocal';
    private static final String VALIDATION = 'Relationship_Validation';

    // ------------------------------------------------------ the validation handler on its own

    @IsTest
    static void validationHandlerFillsInTheReciprocalTypeAndSettlesTheStatus() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            List<Contact> people = RelationshipTestDataFactory.contacts(2, 'Garcia');
            Relationship__c parent = RelationshipTestDataFactory.between(
                people[0],
                people[1],
                'Parent'
            );
            parent.End_Date__c = Date.today().addDays(-1);

            Test.startTest();
            driveBeforeInsert(new RelationshipValidationHandler(), new List<SObject>{ parent });
            Test.stopTest();

            Assert.areEqual('Child', parent.Reciprocal_Type__c, 'The reciprocal type is filled in');
            Assert.areEqual(
                'Former',
                parent.Status__c,
                'And a relationship with an end date is not current'
            );
        }
    }

    @IsTest
    static void validationHandlerDoesNoMaintenance() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            AutomationControl.bypass(MAINTENANCE);
            AutomationControl.bypass(VALIDATION);
            List<Contact> people = RelationshipTestDataFactory.contacts(2, 'Garcia');
            Relationship__c saved = RelationshipTestDataFactory.between(
                people[0],
                people[1],
                'Spouse'
            );
            insert saved;
            AutomationControl.clearBypass(MAINTENANCE);
            AutomationControl.clearBypass(VALIDATION);

            Test.startTest();
            TriggerHandler handler = new RelationshipValidationHandler();
            driveAfterInsert(handler, new List<SObject>{ saved });
            driveAfterUndelete(handler, new List<SObject>{ saved });
            clearOverrides();
            Test.stopTest();

            Assert.areEqual(
                1,
                RelationshipTestDataFactory.allRelationships().size(),
                'The validation handler never writes the other side'
            );
        }
    }

    // ----------------------------------------------------- the maintenance handler on its own

    @IsTest
    static void maintenanceHandlerWritesTheOtherSide() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            AutomationControl.bypass(MAINTENANCE);
            AutomationControl.bypass(VALIDATION);
            List<Contact> people = RelationshipTestDataFactory.contacts(2, 'Garcia');
            Relationship__c saved = RelationshipTestDataFactory.between(
                people[0],
                people[1],
                'Parent'
            );
            saved.Reciprocal_Type__c = 'Child';
            insert saved;
            AutomationControl.clearBypass(MAINTENANCE);
            AutomationControl.clearBypass(VALIDATION);
            Assert.areEqual(
                1,
                RelationshipTestDataFactory.allRelationships().size(),
                'Nothing has run yet'
            );

            Test.startTest();
            driveAfterInsert(new RelationshipMaintenanceHandler(), new List<SObject>{ saved });
            clearOverrides();
            Test.stopTest();

            List<Relationship__c> all = RelationshipTestDataFactory.allRelationships();
            Assert.areEqual(
                2,
                all.size(),
                'The maintenance handler gives the relationship its side'
            );
            Relationship__c other = all[0].Id == saved.Id ? all[1] : all[0];
            Assert.areEqual(people[1].Id, other.Contact__c, 'Described from the other person');
            Assert.areEqual(
                'Child',
                other.Type__c,
                'The parent of someone is that person\'s child'
            );
        }
    }

    @IsTest
    static void maintenanceHandlerDoesNoValidation() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            List<Contact> people = RelationshipTestDataFactory.contacts(1, 'Garcia');
            Relationship__c toSelf = RelationshipTestDataFactory.between(
                people[0],
                people[0],
                'Friend'
            );

            Test.startTest();
            driveBeforeInsert(new RelationshipMaintenanceHandler(), new List<SObject>{ toSelf });
            Test.stopTest();

            Assert.isFalse(
                toSelf.hasErrors(),
                'The maintenance handler holds no rules: the checks are the other automation'
            );
        }
    }

    // -------------------------------------- the point of the split: rules outlive the upkeep

    @IsTest
    static void refusesARelationshipToTheSamePersonWhenMaintenanceIsSwitchedOff() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            switchMaintenanceOff();
            List<Contact> people = RelationshipTestDataFactory.contacts(1, 'Garcia');

            Test.startTest();
            Database.SaveResult result = Database.insert(
                RelationshipTestDataFactory.between(people[0], people[0], 'Friend'),
                false
            );
            Test.stopTest();

            Assert.isFalse(
                result.isSuccess(),
                'Switching the reciprocal upkeep off does not switch the rules off'
            );
            Assert.isTrue(
                result.getErrors()[0].getMessage().contains('two different people'),
                'And the message still says why'
            );
        }
    }

    @IsTest
    static void refusesADuplicateRelationshipWhenMaintenanceIsSwitchedOff() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            switchMaintenanceOff();
            List<Contact> people = RelationshipTestDataFactory.contacts(2, 'Garcia');
            insert RelationshipTestDataFactory.between(people[0], people[1], 'Spouse');
            Assert.areEqual(
                1,
                RelationshipTestDataFactory.allRelationships().size(),
                'With the upkeep off the relationship stays one sided'
            );

            Test.startTest();
            Database.SaveResult result = Database.insert(
                RelationshipTestDataFactory.between(people[0], people[1], 'Spouse'),
                false
            );
            Test.stopTest();

            Assert.isFalse(
                result.isSuccess(),
                'The duplicate check is exactly what an import needs and it is still there'
            );
            Assert.areEqual(
                1,
                RelationshipTestDataFactory.allRelationships().size(),
                'And nothing was written'
            );
        }
    }

    // ------------------------------------------------------------------------------- helpers

    /** Switches the maintenance automation off the way the Automation page does, and only it. */
    private static void switchMaintenanceOff() {
        TestDataFactory.insertAutomationSettings(
            new Map<String, Boolean>{ MAINTENANCE => false, VALIDATION => true }
        );
        Assert.isFalse(AutomationControl.isEnabled(MAINTENANCE), 'The upkeep is off');
        Assert.isTrue(AutomationControl.isEnabled(VALIDATION), 'The checks are on');
    }

    /**
     * Drives one handler context outside a trigger. `TriggerHandler` reads the records through
     * accessors that return these overrides when they are set, which is how a unit test reaches
     * a single handler without a DML operation that would run every automation on the object.
     */
    private static void driveBeforeInsert(TriggerHandler handler, List<SObject> records) {
        TriggerHandler.testNew = records;
        try {
            handler.beforeInsert();
        } finally {
            clearOverrides();
        }
    }

    private static void driveAfterInsert(TriggerHandler handler, List<SObject> records) {
        TriggerHandler.testNew = records;
        TriggerHandler.testNewMap = new Map<Id, SObject>(records);
        handler.afterInsert();
    }

    private static void driveAfterUndelete(TriggerHandler handler, List<SObject> records) {
        TriggerHandler.testNew = records;
        TriggerHandler.testNewMap = new Map<Id, SObject>(records);
        handler.afterUndelete();
    }

    private static void clearOverrides() {
        TriggerHandler.testNew = null;
        TriggerHandler.testNewMap = null;
        TriggerHandler.testOld = null;
        TriggerHandler.testOldMap = null;
    }
}
