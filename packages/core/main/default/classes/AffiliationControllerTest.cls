/**
 * The affiliation card's one server call: which lookups a new affiliation fills in, decided
 * from the record itself.
 */
@IsTest(testFor='ApexClass:AffiliationController')
private class AffiliationControllerTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
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
