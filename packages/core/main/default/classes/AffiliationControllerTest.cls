/**
 * The affiliation card's server side, read from both ends of the connection.
 *
 * NOT EXECUTED. No Salesforce org exists in the environment these were written in, so every
 * assertion here is unverified.
 */
@IsTest
private class AffiliationControllerTest {
    @IsTest
    static void namesTheOrganizationOnAPersonRecord() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            List<Contact> people = RelationshipTestDataFactory.contacts(1, 'Garcia');
            List<Account> orgs = RelationshipTestDataFactory.organizations(1, 'Union Foundation');
            insert RelationshipTestDataFactory.affiliation(people[0], orgs[0], 'Program Officer');

            Test.startTest();
            List<AffiliationController.AffiliationView> views = AffiliationController.getAffiliations(
                people[0].Id
            );
            Test.stopTest();

            Assert.areEqual(1, views.size(), 'One affiliation on this person');
            Assert.isFalse(views[0].readFromOrganization, 'Read from the person side');
            Assert.areEqual(orgs[0].Id, views[0].organizationId, 'Naming the organization');
        }
    }

    @IsTest
    static void namesThePersonOnAnOrganizationRecord() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            List<Contact> people = RelationshipTestDataFactory.contacts(1, 'Garcia');
            List<Account> orgs = RelationshipTestDataFactory.organizations(1, 'Union Foundation');
            insert RelationshipTestDataFactory.affiliation(people[0], orgs[0], 'Program Officer');

            Test.startTest();
            List<AffiliationController.AffiliationView> views = AffiliationController.getAffiliations(
                orgs[0].Id
            );
            Test.stopTest();

            Assert.areEqual(1, views.size(), 'The same record, read from the organization');
            Assert.isTrue(views[0].readFromOrganization, 'And the row says which end this is');
            Assert.areEqual(people[0].Id, views[0].personId, 'Naming the person');
        }
    }

    @IsTest
    static void makingOneAffiliationPrimaryMovesTheBadge() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            List<Contact> people = RelationshipTestDataFactory.contacts(1, 'Garcia');
            List<Account> orgs = RelationshipTestDataFactory.organizations(2, 'Organization');
            Affiliation__c first = RelationshipTestDataFactory.affiliation(
                people[0],
                orgs[0],
                'Officer'
            );
            first.Is_Primary__c = true;
            insert first;
            Affiliation__c second = RelationshipTestDataFactory.affiliation(
                people[0],
                orgs[1],
                'Chair'
            );
            insert second;

            Test.startTest();
            List<AffiliationController.AffiliationView> views = AffiliationController.makePrimary(
                second.Id,
                people[0].Id
            );
            Test.stopTest();

            Integer primaries = 0;
            for (AffiliationController.AffiliationView view : views) {
                if (view.isPrimary == true) {
                    primaries++;
                    Assert.areEqual(second.Id, view.id, 'The one just chosen carries the badge');
                }
            }
            Assert.areEqual(1, primaries, 'And only that one');
        }
    }

    @IsTest
    static void refusesToReadWithoutARecord() {
        System.runAs(TestUsers.admin()) {
            Boolean refused = false;

            Test.startTest();
            try {
                AffiliationController.getAffiliations(null);
            } catch (AuraHandledException expected) {
                refused = true;
            }
            Test.stopTest();

            Assert.isTrue(refused, 'A card with no record behind it asks for nothing');
        }
    }

    @IsTest
    static void refusesToChangeThePrimaryWithoutAnAffiliation() {
        System.runAs(TestUsers.admin()) {
            Boolean refused = false;

            Test.startTest();
            try {
                AffiliationController.makePrimary(null, null);
            } catch (AuraHandledException expected) {
                refused = true;
            }
            Test.stopTest();

            Assert.isTrue(refused, 'Nothing is changed without being named');
        }
    }

    @IsTest
    static void aContactsCardAddsAnOrganization() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            List<Contact> people = RelationshipTestDataFactory.contacts(1, 'Garcia');

            Test.startTest();
            AffiliationController.CardContext context = AffiliationController.getCardContext(
                people[0].Id
            );
            Test.stopTest();

            Assert.areEqual('Contact__c', context.ownerField, 'The contact is the person end');
            Assert.areEqual('Organization__c', context.otherEndField, 'An organization is added');
        }
    }

    /**
     * An organization with no affiliations on file is still read as an organization: the
     * card used to guess from the affiliations already shown and saved it as a person.
     */
    @IsTest
    static void anOrganizationWithNoAffiliationsYetIsStillTheOrganizationEnd() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            List<Account> orgs = RelationshipTestDataFactory.organizations(1, 'Union Foundation');

            Test.startTest();
            AffiliationController.CardContext context = AffiliationController.getCardContext(
                orgs[0].Id
            );
            Test.stopTest();

            Assert.areEqual('Organization__c', context.ownerField, 'The organization end');
            Assert.areEqual(
                HouseholdService.isPersonAccountOrg() ? 'Person_Account__c' : 'Contact__c',
                context.otherEndField,
                'The person end is the lookup this org stores people through'
            );
        }
    }
}
