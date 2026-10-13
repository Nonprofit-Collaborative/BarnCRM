/**
 * The save and delete paths of the account address, affiliation and relationship handlers that
 * the focused handler tests leave out: every context a real save fires, a person with no right to
 * read the records the handlers have to check, and a save of 200 records.
 *
 * A failure inside a handler must refuse the save with the handler's own message rather than
 * let an unexplained error through, so each failure path is driven as a user who holds no
 * BarnCRM access, which makes the handler's user mode reads throw.
 */
@IsTest(
    testFor='ApexClass:AccountAddressHandler, ApexClass:AffiliationMaintenanceHandler, ApexClass:AffiliationValidationHandler, ApexClass:RelationshipMaintenanceHandler, ApexClass:RelationshipValidationHandler'
)
private class CoreHandlerCoverageTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static final Integer TWO_HUNDRED = 200;

    private static User nobody() {
        return TestDataFactory.createUser('NoAccess', new List<String>());
    }

    private static void clearOverrides() {
        TriggerHandler.testNew = null;
        TriggerHandler.testNewMap = null;
        TriggerHandler.testOld = null;
        TriggerHandler.testOldMap = null;
    }

    private static Relationship__c fakeRelationship(Boolean paired) {
        return new Relationship__c(
            Id = FakeIds.of(Relationship__c.SObjectType, 1),
            Contact__c = FakeIds.of(Contact.SObjectType, 1),
            Related_Contact__c = FakeIds.of(Contact.SObjectType, 2),
            Type__c = 'Parent',
            Reciprocal_Type__c = 'Child',
            Status__c = 'Current',
            Is_Reciprocal_Managed__c = true,
            Reciprocal_Relationship__c = paired ? FakeIds.of(Relationship__c.SObjectType, 2) : null
        );
    }

    private static Affiliation__c fakeAffiliation() {
        return new Affiliation__c(
            Id = FakeIds.of(Affiliation__c.SObjectType, 1),
            Contact__c = FakeIds.of(Contact.SObjectType, 1),
            Organization__c = FakeIds.of(Account.SObjectType, 1),
            Role__c = 'Officer',
            Status__c = 'Current'
        );
    }

    private static String onlyMessage(SObject record) {
        List<Database.Error> errors = record.getErrors();
        return errors.size() == 1 ? errors[0].getMessage() : null;
    }

    // ------------------------------------------------------------------- account address

    @IsTest
    static void anAddressThatCannotBeKeptRefusesTheAccountWithTheAddressMessage() {
        System.runAs(TestUsers.admin()) {
            Account unsaved = new Account(
                Name = 'The Garcia Family',
                RecordTypeId = HouseholdService.householdRecordTypeId(),
                BillingStreet = '1 Winter Road',
                BillingCity = 'Springfield'
            );
            TriggerHandler.testNew = new List<SObject>{ unsaved };

            Test.startTest();
            try {
                new AccountAddressHandler().afterInsert();
            } finally {
                clearOverrides();
            }
            Test.stopTest();

            Assert.isTrue(
                unsaved.hasErrors(),
                'An address with no account to belong to is refused'
            );
            Assert.areEqual(
                Label.Core_Address_PropagationFailed,
                onlyMessage(unsaved),
                'With the message that says the address could not be kept'
            );
            Assert.areEqual(0, [SELECT COUNT() FROM Address__c], 'And no address was written');
        }
    }

    @IsTest
    static void aHandlerGivenNothingInATriggerlessCallDoesNothing() {
        System.runAs(TestUsers.admin()) {
            TriggerHandler.testNew = null;
            Test.startTest();
            new AccountAddressHandler().afterInsert();
            Test.stopTest();
            Assert.areEqual(0, [SELECT COUNT() FROM Address__c], 'Nothing to keep, nothing kept');
        }
    }

    @IsTest
    static void twoHundredHouseholdsCreatedWithAnAddressEachKeepOne() {
        System.runAs(TestUsers.admin()) {
            List<Account> households = new List<Account>();
            for (Integer i = 0; i < TWO_HUNDRED; i++) {
                households.add(
                    new Account(
                        Name = 'The Bulk Family ' + i,
                        RecordTypeId = HouseholdService.householdRecordTypeId(),
                        BillingStreet = i + ' Winter Road',
                        BillingCity = 'Springfield'
                    )
                );
            }

            Test.startTest();
            insert households;
            Test.stopTest();

            Assert.areEqual(
                TWO_HUNDRED,
                [
                    SELECT COUNT()
                    FROM Address__c
                    WHERE Account__c IN :households AND Is_Default__c = TRUE
                ],
                'Each household keeps the address it started with, marked default'
            );
        }
    }

    // ------------------------------------------------------------------------ affiliations

    @IsTest
    static void aPrimaryAffiliationFollowsItsPersonThroughSaveDeleteAndUndelete() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            List<Contact> people = RelationshipTestDataFactory.contacts(1, 'Garcia');
            List<Account> orgs = RelationshipTestDataFactory.organizations(1, 'Union Foundation');
            Affiliation__c work = RelationshipTestDataFactory.affiliation(
                people[0],
                orgs[0],
                'Program Officer'
            );
            work.Is_Primary__c = true;
            insert work;
            Assert.areEqual(
                orgs[0].Id,
                [SELECT Primary_Affiliation__c FROM Contact WHERE Id = :people[0].Id]
                .Primary_Affiliation__c,
                'Saving the affiliation makes its organization the primary one'
            );

            delete work;
            Assert.isNull(
                [SELECT Primary_Affiliation__c FROM Contact WHERE Id = :people[0].Id]
                .Primary_Affiliation__c,
                'Deleting the only affiliation leaves the person with no primary one'
            );

            undelete work;
            Assert.areEqual(
                orgs[0].Id,
                [SELECT Primary_Affiliation__c FROM Contact WHERE Id = :people[0].Id]
                .Primary_Affiliation__c,
                'Restoring it gives the person their primary organization back'
            );

            work.End_Date__c = Date.today().addDays(-1);
            update work;
            Affiliation__c ended = [
                SELECT Status__c, Is_Primary__c
                FROM Affiliation__c
                WHERE Id = :work.Id
            ];
            Assert.areEqual('Former', ended.Status__c, 'An affiliation with an end date has ended');
            Assert.isFalse(ended.Is_Primary__c, 'A former affiliation is never the primary one');
            Assert.isNull(
                [SELECT Primary_Affiliation__c FROM Contact WHERE Id = :people[0].Id]
                .Primary_Affiliation__c,
                'So the person has no primary organization any more'
            );
        }
    }

    @IsTest
    static void twoHundredPeopleEachGetAndLoseAPrimaryAffiliationInOneSave() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            List<Contact> people = RelationshipTestDataFactory.contacts(TWO_HUNDRED, 'Crowd');
            List<Account> orgs = RelationshipTestDataFactory.organizations(1, 'Union Foundation');
            List<Affiliation__c> all = new List<Affiliation__c>();
            for (Contact person : people) {
                Affiliation__c work = RelationshipTestDataFactory.affiliation(
                    person,
                    orgs[0],
                    'Member'
                );
                work.Is_Primary__c = true;
                all.add(work);
            }

            Test.startTest();
            insert all;
            Test.stopTest();

            Assert.areEqual(
                TWO_HUNDRED,
                [SELECT COUNT() FROM Contact WHERE Primary_Affiliation__c = :orgs[0].Id],
                'Every one of the 200 people has the organization as primary'
            );

            for (Affiliation__c work : all) {
                work.End_Date__c = Date.today().addDays(-1);
            }
            update all;

            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Contact WHERE Primary_Affiliation__c = :orgs[0].Id],
                'Ending all 200 clears the primary organization of all 200'
            );
            delete all;
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Affiliation__c],
                'And the delete of 200 goes through'
            );
        }
    }

    @IsTest
    static void anAffiliationUpdateIsCheckedAgainstWhatWasThereBefore() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            List<Contact> people = RelationshipTestDataFactory.contacts(1, 'Garcia');
            List<Account> orgs = RelationshipTestDataFactory.organizations(1, 'Union Foundation');
            Affiliation__c ended = RelationshipTestDataFactory.affiliation(
                people[0],
                orgs[0],
                'Chair'
            );
            ended.End_Date__c = Date.today().addDays(-5);
            insert ended;
            Assert.areEqual(
                'Former',
                [SELECT Status__c FROM Affiliation__c WHERE Id = :ended.Id].Status__c,
                'An affiliation saved with an end date is former'
            );

            ended.End_Date__c = null;
            update ended;

            Assert.areEqual(
                'Current',
                [SELECT Status__c FROM Affiliation__c WHERE Id = :ended.Id].Status__c,
                'Taking the end date off makes it current again'
            );
        }
    }

    @IsTest
    static void affiliationHandlersGivenNothingDoNothing() {
        System.runAs(TestUsers.admin()) {
            TriggerHandler.testNew = null;
            TriggerHandler.testOld = null;
            Test.startTest();
            try {
                AffiliationMaintenanceHandler upkeep = new AffiliationMaintenanceHandler();
                upkeep.afterInsert();
                upkeep.afterUpdate();
                upkeep.afterDelete();
                upkeep.afterUndelete();
                AffiliationValidationHandler checks = new AffiliationValidationHandler();
                checks.beforeInsert();
                checks.beforeUpdate();
            } finally {
                clearOverrides();
            }
            Test.stopTest();
            Assert.areEqual(0, [SELECT COUNT() FROM Affiliation__c], 'No records, no writes');
        }
    }

    @IsTest
    static void aPersonWhoCannotReadAffiliationsIsToldTheUpkeepFailedInEveryContext() {
        System.runAs(TestUsers.admin()) {
            User outsider = nobody();
            Affiliation__c inserted = fakeAffiliation();
            Affiliation__c updated = fakeAffiliation();
            Affiliation__c deleted = fakeAffiliation();
            Affiliation__c restored = fakeAffiliation();

            System.runAs(outsider) {
                AffiliationMaintenanceHandler upkeep = new AffiliationMaintenanceHandler();
                TriggerHandler.testNew = new List<SObject>{ inserted };
                upkeep.afterInsert();
                TriggerHandler.testNew = new List<SObject>{ updated };
                TriggerHandler.testOld = new List<SObject>{ updated.clone(true) };
                upkeep.afterUpdate();
                TriggerHandler.testNew = null;
                TriggerHandler.testOld = new List<SObject>{ deleted };
                upkeep.afterDelete();
                TriggerHandler.testOld = null;
                TriggerHandler.testNew = new List<SObject>{ restored };
                upkeep.afterUndelete();
                clearOverrides();
            }

            for (
                Affiliation__c record : new List<Affiliation__c>{
                    inserted,
                    updated,
                    deleted,
                    restored
                }
            ) {
                Assert.areEqual(
                    Label.Core_Affiliation_PrimaryFailed,
                    onlyMessage(record),
                    'The person sees the affiliation message, once'
                );
            }
        }
    }

    @IsTest
    static void aPersonWhoCannotReadAffiliationsIsToldTheCheckFailedOnInsertAndUpdate() {
        System.runAs(TestUsers.admin()) {
            User outsider = nobody();
            Affiliation__c inserted = fakeAffiliation();
            Affiliation__c updated = fakeAffiliation();

            System.runAs(outsider) {
                AffiliationValidationHandler checks = new AffiliationValidationHandler();
                TriggerHandler.testNew = new List<SObject>{ inserted };
                checks.beforeInsert();
                TriggerHandler.testNew = new List<SObject>{ updated };
                TriggerHandler.testOldMap = new Map<Id, SObject>{
                    updated.Id => updated.clone(true)
                };
                checks.beforeUpdate();
                clearOverrides();
            }

            Assert.areEqual(
                Label.Core_Affiliation_PrimaryFailed,
                onlyMessage(inserted),
                'On insert'
            );
            Assert.areEqual(
                Label.Core_Affiliation_PrimaryFailed,
                onlyMessage(updated),
                'On update'
            );
        }
    }

    @IsTest
    static void aMessageAlreadyOnAnAffiliationIsNotReplacedByTheGeneralOne() {
        System.runAs(TestUsers.admin()) {
            User outsider = nobody();
            Affiliation__c refused = fakeAffiliation();
            refused.addError('Choose an organization first.');

            System.runAs(outsider) {
                TriggerHandler.testNew = new List<SObject>{ refused };
                new AffiliationMaintenanceHandler().afterInsert();
                clearOverrides();
            }

            Assert.areEqual(
                'Choose an organization first.',
                onlyMessage(refused),
                'A message that already says what to change stays the only one'
            );
        }
    }

    // ---------------------------------------------------------------------- relationships

    @IsTest
    static void aRelationshipFollowsItsOtherSideThroughSaveEditAndDelete() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            List<Contact> people = RelationshipTestDataFactory.contacts(2, 'Garcia');
            Relationship__c parent = RelationshipTestDataFactory.between(
                people[0],
                people[1],
                'Parent'
            );
            insert parent;
            Assert.areEqual(
                2,
                RelationshipTestDataFactory.allRelationships().size(),
                'Saving a relationship writes the other side'
            );

            parent.Description__c = 'Since birth';
            update parent;
            Integer sharing = 0;
            for (Relationship__c each : RelationshipTestDataFactory.allRelationships()) {
                if (each.Description__c == 'Since birth') {
                    sharing++;
                }
            }
            Assert.areEqual(2, sharing, 'An edit reaches the other side');

            delete parent;
            Assert.areEqual(
                0,
                RelationshipTestDataFactory.allRelationships().size(),
                'Deleting one side deletes the other'
            );
        }
    }

    @IsTest
    static void twoHundredRelationshipsGetTheirOtherSideInOneSave() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            List<Contact> parents = RelationshipTestDataFactory.contacts(TWO_HUNDRED, 'Parent');
            List<Contact> children = RelationshipTestDataFactory.contacts(TWO_HUNDRED, 'Child');
            List<Relationship__c> saved = new List<Relationship__c>();
            for (Integer i = 0; i < TWO_HUNDRED; i++) {
                saved.add(RelationshipTestDataFactory.between(parents[i], children[i], 'Parent'));
            }

            Test.startTest();
            insert saved;
            Test.stopTest();

            Assert.areEqual(
                TWO_HUNDRED * 2,
                [SELECT COUNT() FROM Relationship__c],
                'Two hundred relationships and two hundred other sides'
            );
            Assert.areEqual(
                TWO_HUNDRED,
                [SELECT COUNT() FROM Relationship__c WHERE Type__c = 'Child'],
                'Every other side is the child of the person'
            );
            delete saved;
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Relationship__c],
                'Deleting two hundred removes their other sides with them'
            );
        }
    }

    @IsTest
    static void relationshipHandlersGivenNothingDoNothing() {
        System.runAs(TestUsers.admin()) {
            TriggerHandler.testNew = null;
            TriggerHandler.testOld = null;
            Test.startTest();
            try {
                RelationshipMaintenanceHandler upkeep = new RelationshipMaintenanceHandler();
                upkeep.afterInsert();
                upkeep.afterUpdate();
                upkeep.afterDelete();
                upkeep.afterUndelete();
                RelationshipValidationHandler checks = new RelationshipValidationHandler();
                checks.beforeInsert();
                checks.beforeUpdate();
            } finally {
                clearOverrides();
            }
            Test.stopTest();
            Assert.areEqual(0, [SELECT COUNT() FROM Relationship__c], 'No records, no writes');
        }
    }

    @IsTest
    static void aPersonWhoCannotReadRelationshipsIsToldTheUpkeepFailedInEveryContext() {
        System.runAs(TestUsers.admin()) {
            User outsider = nobody();
            Relationship__c inserted = fakeRelationship(false);
            Relationship__c updated = fakeRelationship(true);
            Relationship__c deleted = fakeRelationship(true);
            Relationship__c restored = fakeRelationship(false);

            System.runAs(outsider) {
                RelationshipMaintenanceHandler upkeep = new RelationshipMaintenanceHandler();
                TriggerHandler.testNew = new List<SObject>{ inserted };
                upkeep.afterInsert();
                TriggerHandler.testNew = new List<SObject>{ updated };
                TriggerHandler.testOldMap = new Map<Id, SObject>{ updated.Id => null };
                upkeep.afterUpdate();
                TriggerHandler.testNew = null;
                TriggerHandler.testOld = new List<SObject>{ deleted };
                upkeep.afterDelete();
                TriggerHandler.testOld = null;
                TriggerHandler.testNew = new List<SObject>{ restored };
                upkeep.afterUndelete();
                clearOverrides();
            }

            for (
                Relationship__c record : new List<Relationship__c>{
                    inserted,
                    updated,
                    deleted,
                    restored
                }
            ) {
                Assert.areEqual(
                    Label.Core_Relationship_SyncFailed,
                    onlyMessage(record),
                    'The person sees the relationship message, once'
                );
            }
        }
    }

    @IsTest
    static void aPersonWhoCannotReadRelationshipsIsToldTheCheckFailedOnInsertAndUpdate() {
        System.runAs(TestUsers.admin()) {
            User outsider = nobody();
            Relationship__c inserted = fakeRelationship(false);
            Relationship__c updated = fakeRelationship(false);

            System.runAs(outsider) {
                RelationshipValidationHandler checks = new RelationshipValidationHandler();
                TriggerHandler.testNew = new List<SObject>{ inserted };
                checks.beforeInsert();
                TriggerHandler.testNew = new List<SObject>{ updated };
                TriggerHandler.testOldMap = new Map<Id, SObject>{
                    updated.Id => updated.clone(true)
                };
                checks.beforeUpdate();
                clearOverrides();
            }

            Assert.areEqual(Label.Core_Relationship_SyncFailed, onlyMessage(inserted), 'On insert');
            Assert.areEqual(Label.Core_Relationship_SyncFailed, onlyMessage(updated), 'On update');
        }
    }

    @IsTest
    static void aMessageAlreadyOnARelationshipIsNotReplacedByTheGeneralOne() {
        System.runAs(TestUsers.admin()) {
            User outsider = nobody();
            Relationship__c refused = fakeRelationship(false);
            refused.addError('Choose two different people.');

            System.runAs(outsider) {
                TriggerHandler.testNew = new List<SObject>{ refused };
                new RelationshipMaintenanceHandler().afterInsert();
                clearOverrides();
            }

            Assert.areEqual(
                'Choose two different people.',
                onlyMessage(refused),
                'A message that already says what to change stays the only one'
            );
        }
    }
}
