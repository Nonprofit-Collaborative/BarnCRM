/**
 * The rules an affiliation has to pass before it is saved.
 *
 * NOT EXECUTED. No Salesforce org exists in the environment these were written in, so every
 * assertion here is unverified.
 */
@IsTest
private class AffiliationDomainTest {
    @IsTest
    static void refusesAnAffiliationWithNoPerson() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            List<Account> orgs = RelationshipTestDataFactory.organizations(1, 'Union Foundation');

            Test.startTest();
            Database.SaveResult result = Database.insert(
                new Affiliation__c(Organization__c = orgs[0].Id, Role__c = 'Officer'),
                false
            );
            Test.stopTest();

            Assert.isFalse(result.isSuccess(), 'An affiliation needs a person');
        }
    }

    @IsTest
    static void refusesAnAffiliationWithNoOrganization() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            List<Contact> people = RelationshipTestDataFactory.contacts(1, 'Garcia');

            Test.startTest();
            Database.SaveResult result = Database.insert(
                new Affiliation__c(Contact__c = people[0].Id, Role__c = 'Officer'),
                false
            );
            Test.stopTest();

            Assert.isFalse(result.isSuccess(), 'An affiliation needs an organization');
        }
    }

    @IsTest
    static void refusesAPersonAffiliatedWithThemselves() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            List<Account> people = RelationshipTestDataFactory.peopleAsAccounts(1, 'Okafor');

            Test.startTest();
            Database.SaveResult result = Database.insert(
                new Affiliation__c(
                    Person_Account__c = people[0].Id,
                    Organization__c = people[0].Id,
                    Role__c = 'Self'
                ),
                false
            );
            Test.stopTest();

            Assert.isFalse(result.isSuccess(), 'A record is not affiliated with itself');
        }
    }

    @IsTest
    static void refusesTwoOpenEndedAffiliationsForTheSameRole() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            List<Contact> people = RelationshipTestDataFactory.contacts(1, 'Garcia');
            List<Account> orgs = RelationshipTestDataFactory.organizations(1, 'Union Foundation');
            insert RelationshipTestDataFactory.affiliation(people[0], orgs[0], 'Board member');

            Test.startTest();
            Database.SaveResult result = Database.insert(
                RelationshipTestDataFactory.affiliation(people[0], orgs[0], 'Board member'),
                false
            );
            Test.stopTest();

            Assert.isFalse(
                result.isSuccess(),
                'The same open ended role twice is the mistake to catch'
            );
            Assert.isTrue(
                result.getErrors()[0].getMessage().contains('AF-'),
                'And the message names the record to open'
            );
        }
    }

    @IsTest
    static void allowsTheSameRoleTwiceOverDifferentDates() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            List<Contact> people = RelationshipTestDataFactory.contacts(1, 'Garcia');
            List<Account> orgs = RelationshipTestDataFactory.organizations(1, 'Union Foundation');
            Affiliation__c earlier = RelationshipTestDataFactory.affiliation(
                people[0],
                orgs[0],
                'Board member'
            );
            earlier.Start_Date__c = Date.newInstance(2019, 1, 1);
            earlier.End_Date__c = Date.newInstance(2022, 12, 31);
            insert earlier;
            Affiliation__c later = RelationshipTestDataFactory.affiliation(
                people[0],
                orgs[0],
                'Board member'
            );
            later.Start_Date__c = Date.newInstance(2025, 1, 1);

            Test.startTest();
            Database.SaveResult result = Database.insert(later, false);
            Test.stopTest();

            Assert.isTrue(
                result.isSuccess(),
                'Two terms on the same board is a fact, not an error'
            );
        }
    }

    @IsTest
    static void allowsTheSameOrganizationInTwoDifferentRoles() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            List<Contact> people = RelationshipTestDataFactory.contacts(1, 'Garcia');
            List<Account> orgs = RelationshipTestDataFactory.organizations(1, 'Union Foundation');
            insert RelationshipTestDataFactory.affiliation(people[0], orgs[0], 'Board member');

            Test.startTest();
            Database.SaveResult result = Database.insert(
                RelationshipTestDataFactory.affiliation(people[0], orgs[0], 'Volunteer'),
                false
            );
            Test.stopTest();

            Assert.isTrue(result.isSuccess(), 'One person can do two things at one organization');
        }
    }

    @IsTest
    static void anEndDateMakesAnAffiliationFormerAndNotPrimary() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            List<Contact> people = RelationshipTestDataFactory.contacts(1, 'Garcia');
            List<Account> orgs = RelationshipTestDataFactory.organizations(1, 'Union Foundation');
            Affiliation__c ended = RelationshipTestDataFactory.affiliation(
                people[0],
                orgs[0],
                'Officer'
            );
            ended.Is_Primary__c = true;
            ended.End_Date__c = Date.today().addDays(-1);

            Test.startTest();
            insert ended;
            Test.stopTest();

            Affiliation__c reloaded = RelationshipTestDataFactory.allAffiliations()[0];
            Assert.areEqual('Former', reloaded.Status__c, 'The dates decide the status');
            Assert.isFalse(
                reloaded.Is_Primary__c,
                'And a former affiliation is never the primary one'
            );
        }
    }
}
