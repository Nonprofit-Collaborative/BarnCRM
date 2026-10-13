/**
 * The two Affiliation__c handlers, each on its own, and the case the split exists for: an
 * administrator who switches the primary affiliation upkeep off before a bulk import still gets
 * every check on the records the import saves.
 *
 * NOT EXECUTED. No Salesforce org exists in the environment these were written in, so every
 * assertion here is unverified. They are written to the same standard as if they had run, and
 * the first person with a scratch org should run them before trusting the feature.
 */
@IsTest
private class AffiliationHandlerTest {
    private static final String MAINTENANCE = 'Affiliation_Primary';
    private static final String VALIDATION = 'Affiliation_Validation';

    // ------------------------------------------------------ the validation handler on its own

    @IsTest
    static void validationHandlerSettlesTheStatusAndTakesThePrimaryFlagOff() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            List<Contact> people = RelationshipTestDataFactory.contacts(1, 'Garcia');
            List<Account> orgs = RelationshipTestDataFactory.organizations(1, 'Union Foundation');
            Affiliation__c ended = RelationshipTestDataFactory.affiliation(
                people[0],
                orgs[0],
                'Program Officer'
            );
            ended.Is_Primary__c = true;
            ended.End_Date__c = Date.today().addDays(-1);

            Test.startTest();
            driveBeforeInsert(new AffiliationValidationHandler(), new List<SObject>{ ended });
            Test.stopTest();

            Assert.areEqual('Former', ended.Status__c, 'An affiliation with an end date has ended');
            Assert.isFalse(
                ended.Is_Primary__c,
                'And a former affiliation is never the primary one'
            );
        }
    }

    @IsTest
    static void validationHandlerDoesNoMaintenance() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            AutomationControl.bypass(MAINTENANCE);
            AutomationControl.bypass(VALIDATION);
            List<Contact> people = RelationshipTestDataFactory.contacts(1, 'Garcia');
            List<Account> orgs = RelationshipTestDataFactory.organizations(1, 'Union Foundation');
            Affiliation__c work = RelationshipTestDataFactory.affiliation(
                people[0],
                orgs[0],
                'Program Officer'
            );
            work.Is_Primary__c = true;
            insert work;
            AutomationControl.clearBypass(MAINTENANCE);
            AutomationControl.clearBypass(VALIDATION);

            Test.startTest();
            driveAfterInsert(new AffiliationValidationHandler(), new List<SObject>{ work });
            clearOverrides();
            Test.stopTest();

            Contact reloaded = [
                SELECT Primary_Affiliation__c
                FROM Contact
                WHERE Id = :people[0].Id
            ];
            Assert.isNull(
                reloaded.Primary_Affiliation__c,
                'The validation handler never writes the person'
            );
        }
    }

    // ----------------------------------------------------- the maintenance handler on its own

    @IsTest
    static void maintenanceHandlerCopiesTheOrganizationToThePerson() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            AutomationControl.bypass(MAINTENANCE);
            AutomationControl.bypass(VALIDATION);
            List<Contact> people = RelationshipTestDataFactory.contacts(1, 'Garcia');
            List<Account> orgs = RelationshipTestDataFactory.organizations(1, 'Union Foundation');
            Affiliation__c work = RelationshipTestDataFactory.affiliation(
                people[0],
                orgs[0],
                'Program Officer'
            );
            work.Is_Primary__c = true;
            insert work;
            AutomationControl.clearBypass(MAINTENANCE);
            AutomationControl.clearBypass(VALIDATION);

            Test.startTest();
            driveAfterInsert(new AffiliationMaintenanceHandler(), new List<SObject>{ work });
            clearOverrides();
            Test.stopTest();

            Contact reloaded = [
                SELECT Primary_Affiliation__c
                FROM Contact
                WHERE Id = :people[0].Id
            ];
            Assert.areEqual(
                orgs[0].Id,
                reloaded.Primary_Affiliation__c,
                'The maintenance handler is what carries the organization to the person'
            );
        }
    }

    @IsTest
    static void maintenanceHandlerDoesNoValidation() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            List<Contact> people = RelationshipTestDataFactory.contacts(1, 'Garcia');
            Affiliation__c noOrganization = new Affiliation__c(
                Contact__c = people[0].Id,
                Role__c = 'Officer'
            );

            Test.startTest();
            driveBeforeInsert(
                new AffiliationMaintenanceHandler(),
                new List<SObject>{ noOrganization }
            );
            Test.stopTest();

            Assert.isFalse(
                noOrganization.hasErrors(),
                'The maintenance handler holds no rules: the checks are the other automation'
            );
        }
    }

    // -------------------------------------- the point of the split: rules outlive the upkeep

    @IsTest
    static void refusesAnAffiliationWithNoOrganizationWhenMaintenanceIsSwitchedOff() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            switchMaintenanceOff();
            List<Contact> people = RelationshipTestDataFactory.contacts(1, 'Garcia');

            Test.startTest();
            Database.SaveResult result = Database.insert(
                new Affiliation__c(Contact__c = people[0].Id, Role__c = 'Officer'),
                false
            );
            Test.stopTest();

            Assert.isFalse(
                result.isSuccess(),
                'Switching the primary upkeep off does not switch the rules off'
            );
        }
    }

    @IsTest
    static void refusesAnOverlappingAffiliationWhenMaintenanceIsSwitchedOff() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            switchMaintenanceOff();
            List<Contact> people = RelationshipTestDataFactory.contacts(1, 'Garcia');
            List<Account> orgs = RelationshipTestDataFactory.organizations(1, 'Union Foundation');
            insert RelationshipTestDataFactory.affiliation(people[0], orgs[0], 'Program Officer');

            Test.startTest();
            Database.SaveResult result = Database.insert(
                RelationshipTestDataFactory.affiliation(people[0], orgs[0], 'Program Officer'),
                false
            );
            Test.stopTest();

            Assert.isFalse(
                result.isSuccess(),
                'The overlap check is exactly what an import needs and it is still there'
            );
            Assert.areEqual(
                1,
                RelationshipTestDataFactory.allAffiliations().size(),
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

    private static void clearOverrides() {
        TriggerHandler.testNew = null;
        TriggerHandler.testNewMap = null;
        TriggerHandler.testOld = null;
        TriggerHandler.testOldMap = null;
    }
}
