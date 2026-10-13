/**
 * The relationship card's server side.
 *
 * NOT EXECUTED. No Salesforce org exists in the environment these were written in, so every
 * assertion here is unverified.
 */
@IsTest
private class RelationshipControllerTest {
    @IsTest
    static void readsARelationshipFromThePersonsOwnSide() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            List<Contact> people = RelationshipTestDataFactory.contacts(2, 'Garcia');
            insert RelationshipTestDataFactory.between(people[0], people[1], 'Parent');

            Test.startTest();
            List<RelationshipController.RelationshipView> theirs = RelationshipController.getRelationships(
                people[0].Id
            );
            List<RelationshipController.RelationshipView> others = RelationshipController.getRelationships(
                people[1].Id
            );
            Test.stopTest();

            Assert.areEqual(1, theirs.size(), 'One relationship on this person');
            Assert.areEqual('Parent', theirs[0].relationshipType, 'Read from their side');
            Assert.areEqual(people[1].Id, theirs[0].relatedPersonId, 'Naming the other person');
            Assert.areEqual(1, others.size(), 'And one on the other person');
            Assert.areEqual(
                'Child',
                others[0].relationshipType,
                'The same fact, read the other way'
            );
        }
    }

    @IsTest
    static void readsRelationshipsForAPersonHeldAsAnAccount() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            List<Account> people = RelationshipTestDataFactory.peopleAsAccounts(2, 'Okafor');
            insert RelationshipTestDataFactory.between(people[0], people[1], 'Sibling');

            Test.startTest();
            List<RelationshipController.RelationshipView> theirs = RelationshipController.getRelationships(
                people[0].Id
            );
            Test.stopTest();

            Assert.areEqual(1, theirs.size(), 'The card does not care which object holds a person');
            Assert.areEqual(people[1].Id, theirs[0].relatedPersonId, 'And names the other one');
        }
    }

    @IsTest
    static void removingARelationshipRemovesBothSides() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            List<Contact> people = RelationshipTestDataFactory.contacts(2, 'Garcia');
            Relationship__c saved = RelationshipTestDataFactory.between(
                people[0],
                people[1],
                'Spouse'
            );
            insert saved;

            Test.startTest();
            List<RelationshipController.RelationshipView> left = RelationshipController.removeRelationship(
                saved.Id,
                people[0].Id
            );
            Test.stopTest();

            Assert.areEqual(0, left.size(), 'Nothing left on this person');
            Assert.areEqual(
                0,
                RelationshipTestDataFactory.allRelationships().size(),
                'And nothing left on the other one either'
            );
        }
    }

    @IsTest
    static void refusesToReadWithoutAPerson() {
        System.runAs(TestUsers.admin()) {
            Boolean refused = false;

            Test.startTest();
            try {
                RelationshipController.getRelationships(null);
            } catch (AuraHandledException expected) {
                refused = true;
            }
            Test.stopTest();

            Assert.isTrue(refused, 'A card with no record behind it asks for nothing');
        }
    }

    @IsTest
    static void refusesToRemoveWithoutARelationship() {
        System.runAs(TestUsers.admin()) {
            Boolean refused = false;

            Test.startTest();
            try {
                RelationshipController.removeRelationship(null, null);
            } catch (AuraHandledException expected) {
                refused = true;
            }
            Test.stopTest();

            Assert.isTrue(refused, 'Nothing is deleted without being named');
        }
    }
}
