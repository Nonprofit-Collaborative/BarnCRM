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

    /**
     * The org shape is stubbed, so the person account branch runs whether or not the org has
     * Person Accounts: an account whose record type the shape calls a person type is the
     * person end.
     */
    @IsTest
    static void anAccountOfAPersonRecordTypeIsThePersonEnd() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            List<Account> orgs = RelationshipTestDataFactory.organizations(1, 'Garcia Household');
            Id recordTypeId = [SELECT RecordTypeId FROM Account WHERE Id = :orgs[0].Id]
            .RecordTypeId;
            OrgShapeDetector.OrgShape shape = new OrgShapeDetector.OrgShape();
            shape.personAccountRecordTypeIds = new Set<Id>{ recordTypeId };
            OrgShapeDetector.overrideShape = shape;

            Test.startTest();
            AffiliationController.CardContext context = AffiliationController.getCardContext(
                orgs[0].Id
            );
            Test.stopTest();

            Assert.areEqual('Person_Account__c', context.ownerField, 'The person account is owner');
            Assert.areEqual('Organization__c', context.otherEndField, 'An organization is added');
        }
    }

    @IsTest
    static void anOrganizationAccountInAPersonAccountOrgPicksPeopleThroughPersonAccounts() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            List<Account> orgs = RelationshipTestDataFactory.organizations(1, 'Union Foundation');
            OrgShapeDetector.OrgShape shape = new OrgShapeDetector.OrgShape();
            // A person type that is not this account's, so the account stays an organization.
            shape.personAccountRecordTypeIds = new Set<Id>{ FakeIds.of(Account.SObjectType, 1) };
            OrgShapeDetector.overrideShape = shape;
            HouseholdService.personAccountOverride = true;

            Test.startTest();
            AffiliationController.CardContext context = AffiliationController.getCardContext(
                orgs[0].Id
            );
            Test.stopTest();

            Assert.areEqual('Organization__c', context.ownerField, 'The organization end');
            Assert.areEqual('Person_Account__c', context.otherEndField, 'People are accounts here');
        }
    }

    @IsTest
    static void anOrganizationAccountInAContactOrgPicksPeopleThroughContacts() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            List<Account> orgs = RelationshipTestDataFactory.organizations(1, 'Union Foundation');
            OrgShapeDetector.overrideShape = new OrgShapeDetector.OrgShape();
            HouseholdService.personAccountOverride = false;

            Test.startTest();
            AffiliationController.CardContext context = AffiliationController.getCardContext(
                orgs[0].Id
            );
            Test.stopTest();

            Assert.areEqual('Organization__c', context.ownerField, 'The organization end');
            Assert.areEqual('Contact__c', context.otherEndField, 'People are contacts here');
        }
    }

    @IsTest
    static void noRecordIsTreatedAsAContact() {
        System.runAs(TestUsers.admin()) {
            AffiliationController.CardContext context = AffiliationController.getCardContext(null);

            Assert.areEqual('Contact__c', context.ownerField, 'The default is the person end');
            Assert.areEqual('Organization__c', context.otherEndField, 'An organization is added');
        }
    }
}
