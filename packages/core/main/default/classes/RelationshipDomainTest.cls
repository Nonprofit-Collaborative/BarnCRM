/**
 * The rules a relationship has to pass before it is saved, and the two values BarnCRM
 * fills in.
 *
 * NOT EXECUTED. No Salesforce org exists in the environment these were written in, so every
 * assertion here is unverified.
 */
@IsTest(testFor='ApexClass:RelationshipDomain')
private class RelationshipDomainTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    @IsTest
    static void refusesARelationshipBetweenSomeoneAndThemselves() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            List<Contact> people = RelationshipTestDataFactory.contacts(1, 'Garcia');

            Test.startTest();
            Database.SaveResult result = Database.insert(
                RelationshipTestDataFactory.between(people[0], people[0], 'Friend'),
                false
            );
            Test.stopTest();

            Assert.isFalse(result.isSuccess(), 'A person is not related to themselves');
            Assert.isTrue(
                result.getErrors()[0].getMessage().contains('two different people'),
                'And the message says why'
            );
        }
    }

    @IsTest
    static void refusesARelationshipWithOnlyOnePerson() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            List<Contact> people = RelationshipTestDataFactory.contacts(1, 'Garcia');

            Test.startTest();
            Database.SaveResult result = Database.insert(
                new Relationship__c(Contact__c = people[0].Id, Type__c = 'Friend'),
                false
            );
            Test.stopTest();

            Assert.isFalse(result.isSuccess(), 'A relationship needs both people');
        }
    }

    @IsTest
    static void refusesAPersonHeldTwoWaysAtOnce() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            List<Contact> people = RelationshipTestDataFactory.contacts(2, 'Garcia');
            List<Account> asAccount = RelationshipTestDataFactory.peopleAsAccounts(1, 'Okafor');

            Test.startTest();
            Database.SaveResult result = Database.insert(
                new Relationship__c(
                    Contact__c = people[0].Id,
                    Person_Account__c = asAccount[0].Id,
                    Related_Contact__c = people[1].Id,
                    Type__c = 'Friend'
                ),
                false
            );
            Test.stopTest();

            Assert.isFalse(result.isSuccess(), 'One person is one record, not two');
        }
    }

    @IsTest
    static void refusesTheSameRelationshipTwiceAndNamesTheRecordOnFile() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            List<Contact> people = RelationshipTestDataFactory.contacts(2, 'Garcia');
            insert RelationshipTestDataFactory.between(people[0], people[1], 'Spouse');

            Test.startTest();
            Database.SaveResult result = Database.insert(
                RelationshipTestDataFactory.between(people[0], people[1], 'Spouse'),
                false
            );
            Test.stopTest();

            Assert.isFalse(result.isSuccess(), 'The same relationship is not entered twice');
            Assert.isTrue(
                result.getErrors()[0].getMessage().contains('RL-'),
                'And the message names the record to open'
            );
        }
    }

    @IsTest
    static void refusesEnteringTheOtherSideByHandBecauseItIsAlreadyThere() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            List<Contact> people = RelationshipTestDataFactory.contacts(2, 'Garcia');
            // BarnCRM writes the other side, so entering it by hand is a duplicate of that.
            insert RelationshipTestDataFactory.between(people[0], people[1], 'Spouse');

            Test.startTest();
            Database.SaveResult result = Database.insert(
                RelationshipTestDataFactory.between(people[1], people[0], 'Spouse'),
                false
            );
            Test.stopTest();

            Assert.isFalse(
                result.isSuccess(),
                'The other side already exists, so this is a duplicate'
            );
        }
    }

    @IsTest
    static void allowsTheSameTwoPeopleWithDifferentTypes() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            List<Contact> people = RelationshipTestDataFactory.contacts(2, 'Garcia');
            insert RelationshipTestDataFactory.between(people[0], people[1], 'Colleague');

            Test.startTest();
            Database.SaveResult result = Database.insert(
                RelationshipTestDataFactory.between(people[0], people[1], 'Friend'),
                false
            );
            Test.stopTest();

            Assert.isTrue(result.isSuccess(), 'Two people can be connected in more than one way');
        }
    }

    @IsTest
    static void fillsInTheReciprocalTypeOnTheRecordItself() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            List<Contact> people = RelationshipTestDataFactory.contacts(2, 'Garcia');
            Relationship__c saved = RelationshipTestDataFactory.between(
                people[0],
                people[1],
                'Parent'
            );

            Test.startTest();
            insert saved;
            Test.stopTest();

            Relationship__c reloaded = [
                SELECT Reciprocal_Type__c
                FROM Relationship__c
                WHERE Id = :saved.Id
            ];
            Assert.areEqual(
                'Child',
                reloaded.Reciprocal_Type__c,
                'The reciprocal type is filled in'
            );
        }
    }

    @IsTest
    static void clearingTheEndDateMakesARelationshipCurrentAgain() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            List<Contact> people = RelationshipTestDataFactory.contacts(2, 'Garcia');
            Relationship__c saved = RelationshipTestDataFactory.between(
                people[0],
                people[1],
                'Spouse'
            );
            saved.End_Date__c = Date.today().addDays(-1);
            insert saved;

            Test.startTest();
            update new Relationship__c(Id = saved.Id, End_Date__c = null);
            Test.stopTest();

            for (Relationship__c record : RelationshipTestDataFactory.allRelationships()) {
                Assert.areEqual(
                    'Current',
                    record.Status__c,
                    'Clearing the end date returns both sides to current'
                );
            }
        }
    }

    @IsTest
    static void anEndDateMakesARelationshipFormerOnSave() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            List<Contact> people = RelationshipTestDataFactory.contacts(2, 'Garcia');
            Relationship__c saved = RelationshipTestDataFactory.between(
                people[0],
                people[1],
                'Spouse'
            );
            saved.End_Date__c = Date.today();

            Test.startTest();
            insert saved;
            Test.stopTest();

            for (Relationship__c record : RelationshipTestDataFactory.allRelationships()) {
                Assert.areEqual('Former', record.Status__c, 'Both sides read former');
            }
        }
    }

    /**
     * PEOPLE-23. Private sharing cannot be set from a test, so the row on file is treated as
     * invisible through the test seam. The existence check comes from
     * RelationshipUpkeepSelector, which returns it regardless of the user, and the message must
     * carry nothing of it.
     */
    @IsTest
    static void aDuplicateTheSaverCannotSeeIsStillRefusedWithAGenericMessage() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            List<Contact> people = RelationshipTestDataFactory.contacts(2, 'Garcia');
            Relationship__c onFile = RelationshipTestDataFactory.between(
                people[0],
                people[1],
                'Spouse'
            );
            insert onFile;
            Assert.isFalse(
                RelationshipUpkeepSelector.selectByFromPersonIds(new Set<Id>{ people[0].Id })
                    .isEmpty(),
                'The system mode selector finds the row'
            );
            RelationshipDomain.hiddenForTest = new Set<Id>{ onFile.Id };

            Test.startTest();
            Database.SaveResult result = Database.insert(
                RelationshipTestDataFactory.between(people[0], people[1], 'Spouse'),
                false
            );
            Test.stopTest();

            Assert.isFalse(result.isSuccess(), 'A hidden duplicate is still refused');
            String message = result.getErrors()[0].getMessage();
            Assert.areEqual(Label.Core_Relationship_DuplicateHidden, message, 'Generic message');
            Assert.isFalse(message.contains('RL-'), 'No record number');
            Assert.isFalse(message.contains('Garcia'), 'No name');
        }
    }

    @IsTest
    static void twoHundredDuplicatesOfRowsTheSaverCannotSeeAreAllRefused() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            List<Contact> people = RelationshipTestDataFactory.contacts(201, 'Garcia');
            List<Relationship__c> onFile = new List<Relationship__c>();
            List<Relationship__c> incoming = new List<Relationship__c>();
            for (Integer i = 0; i < 200; i++) {
                onFile.add(RelationshipTestDataFactory.between(people[i], people[200], 'Friend'));
                incoming.add(RelationshipTestDataFactory.between(people[i], people[200], 'Friend'));
            }
            insert onFile;
            Set<Id> hiddenIds = new Set<Id>();
            for (Relationship__c row : onFile) {
                hiddenIds.add(row.Id);
            }
            RelationshipDomain.hiddenForTest = hiddenIds;

            Test.startTest();
            List<Database.SaveResult> results = Database.insert(incoming, false);
            Test.stopTest();

            for (Database.SaveResult result : results) {
                Assert.isFalse(result.isSuccess(), 'Every hidden duplicate is refused');
                Assert.areEqual(
                    Label.Core_Relationship_DuplicateHidden,
                    result.getErrors()[0].getMessage(),
                    'With the generic message'
                );
            }
        }
    }
}
