/**
 * The reads behind the affiliation cards: by person, held as a contact or as an account, and by
 * organization. Both come back in the order the cards show, current rows first.
 */
@IsTest(testFor='ApexClass:AffiliationSelector')
private class AffiliationSelectorTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static Set<Id> idsOf(List<Affiliation__c> rows) {
        return new Map<Id, Affiliation__c>(rows).keySet();
    }

    @IsTest
    static void noIdsReadNothingAndSpendNoQuery() {
        System.runAs(TestUsers.admin()) {
            Integer before = Limits.getQueries();

            Assert.isTrue(AffiliationSelector.selectByPersonIds(null).isEmpty(), 'null people');
            Assert.isTrue(
                AffiliationSelector.selectByPersonIds(new Set<Id>()).isEmpty(),
                'no people'
            );
            Assert.isTrue(AffiliationSelector.selectByOrganizationIds(null).isEmpty(), 'null orgs');
            Assert.isTrue(
                AffiliationSelector.selectByOrganizationIds(new Set<Id>()).isEmpty(),
                'no organizations'
            );

            Assert.areEqual(before, Limits.getQueries(), 'Nothing asked, nothing queried');
        }
    }

    @IsTest
    static void aPersonIsFoundWhetherHeldAsAContactOrAnAccount() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            List<Contact> contacts = RelationshipTestDataFactory.contacts(2, 'Garcia');
            List<Account> accounts = RelationshipTestDataFactory.peopleAsAccounts(1, 'Okafor');
            List<Account> orgs = RelationshipTestDataFactory.organizations(2, 'Union Foundation');
            Affiliation__c viaContact = RelationshipTestDataFactory.affiliation(
                contacts[0],
                orgs[0],
                'Board member'
            );
            Affiliation__c viaAccount = RelationshipTestDataFactory.affiliation(
                accounts[0],
                orgs[1],
                'Volunteer'
            );
            Affiliation__c someoneElse = RelationshipTestDataFactory.affiliation(
                contacts[1],
                orgs[0],
                'Officer'
            );
            insert new List<Affiliation__c>{ viaContact, viaAccount, someoneElse };

            Test.startTest();
            List<Affiliation__c> found = AffiliationSelector.selectByPersonIds(
                new Set<Id>{ contacts[0].Id, accounts[0].Id }
            );
            Test.stopTest();

            Assert.areEqual(
                new Set<Id>{ viaContact.Id, viaAccount.Id },
                idsOf(found),
                'Both the contact held and the account held person are found, and nobody else'
            );
            for (Affiliation__c row : found) {
                Assert.isNotNull(row.Organization__r.Name, 'The organization name rides along');
            }
        }
    }

    @IsTest
    static void currentAffiliationsComeBeforeFormerOnes() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            List<Contact> people = RelationshipTestDataFactory.contacts(1, 'Garcia');
            List<Account> orgs = RelationshipTestDataFactory.organizations(2, 'Union Foundation');
            Affiliation__c former = RelationshipTestDataFactory.affiliation(
                people[0],
                orgs[0],
                'Treasurer'
            );
            former.Status__c = 'Former';
            former.End_Date__c = Date.today().addDays(-30);
            Affiliation__c current = RelationshipTestDataFactory.affiliation(
                people[0],
                orgs[1],
                'Chair'
            );
            insert new List<Affiliation__c>{ former, current };

            List<Affiliation__c> found = AffiliationSelector.selectByPersonIds(
                new Set<Id>{ people[0].Id }
            );

            Assert.areEqual(2, found.size());
            Assert.areEqual('Current', found[0].Status__c, 'Current first');
            Assert.areEqual(current.Id, found[0].Id);
            Assert.areEqual(former.Id, found[1].Id, 'Former after');
        }
    }

    @IsTest
    static void anOrganizationSeesItsOwnAffiliationsOnly() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            List<Contact> contacts = RelationshipTestDataFactory.contacts(2, 'Garcia');
            List<Account> accounts = RelationshipTestDataFactory.peopleAsAccounts(1, 'Okafor');
            List<Account> orgs = RelationshipTestDataFactory.organizations(2, 'Union Foundation');
            Affiliation__c one = RelationshipTestDataFactory.affiliation(
                contacts[0],
                orgs[0],
                'Board member'
            );
            Affiliation__c two = RelationshipTestDataFactory.affiliation(
                accounts[0],
                orgs[0],
                'Volunteer'
            );
            Affiliation__c elsewhere = RelationshipTestDataFactory.affiliation(
                contacts[1],
                orgs[1],
                'Officer'
            );
            insert new List<Affiliation__c>{ one, two, elsewhere };

            Test.startTest();
            List<Affiliation__c> found = AffiliationSelector.selectByOrganizationIds(
                new Set<Id>{ orgs[0].Id }
            );
            List<Affiliation__c> both = AffiliationSelector.selectByOrganizationIds(
                new Set<Id>{ orgs[0].Id, orgs[1].Id }
            );
            Test.stopTest();

            Assert.areEqual(
                new Set<Id>{ one.Id, two.Id },
                idsOf(found),
                'Only the affiliations pointing at that organization'
            );
            Assert.areEqual(3, both.size(), 'Two organizations read together');
            for (Affiliation__c row : found) {
                Assert.areEqual(orgs[0].Name, row.Organization__r.Name);
            }
        }
    }
}
