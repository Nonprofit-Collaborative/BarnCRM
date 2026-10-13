/**
 * One primary affiliation per person, and the person's Primary Affiliation field kept equal to
 * it, through insert, edit, delete, and two hundred at a time.
 *
 * NOT EXECUTED. No Salesforce org exists in the environment these were written in, so every
 * assertion here is unverified.
 */
@IsTest
private class AffiliationServiceTest {
    @IsTest
    static void copiesThePrimaryOrganizationToThePerson() {
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

            Test.startTest();
            insert work;
            Test.stopTest();

            Contact reloaded = [
                SELECT Primary_Affiliation__c
                FROM Contact
                WHERE Id = :people[0].Id
            ];
            Assert.areEqual(
                orgs[0].Id,
                reloaded.Primary_Affiliation__c,
                'The person carries the organization they are chiefly associated with'
            );
        }
    }

    @IsTest
    static void copiesThePrimaryOrganizationToAPersonHeldAsAnAccount() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            List<Account> people = RelationshipTestDataFactory.peopleAsAccounts(1, 'Okafor');
            List<Account> orgs = RelationshipTestDataFactory.organizations(1, 'Union Foundation');
            Affiliation__c work = RelationshipTestDataFactory.affiliation(
                people[0],
                orgs[0],
                'Trustee'
            );
            work.Is_Primary__c = true;

            Test.startTest();
            insert work;
            Test.stopTest();

            Account reloaded = [
                SELECT Primary_Affiliation__c
                FROM Account
                WHERE Id = :people[0].Id
            ];
            Assert.areEqual(
                orgs[0].Id,
                reloaded.Primary_Affiliation__c,
                'The same field on the same person, held the other way'
            );
        }
    }

    @IsTest
    static void markingASecondPrimaryClearsTheFirst() {
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
            second.Is_Primary__c = true;

            Test.startTest();
            insert second;
            Test.stopTest();

            Map<Id, Affiliation__c> byId = new Map<Id, Affiliation__c>(
                RelationshipTestDataFactory.allAffiliations()
            );
            Assert.isFalse(byId.get(first.Id).Is_Primary__c, 'The first one is no longer primary');
            Assert.isTrue(byId.get(second.Id).Is_Primary__c, 'The one just saved is');
            Contact reloaded = [
                SELECT Primary_Affiliation__c
                FROM Contact
                WHERE Id = :people[0].Id
            ];
            Assert.areEqual(
                orgs[1].Id,
                reloaded.Primary_Affiliation__c,
                'And the person follows it'
            );
        }
    }

    @IsTest
    static void endingThePrimaryAffiliationEmptiesThePersonsField() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            List<Contact> people = RelationshipTestDataFactory.contacts(1, 'Garcia');
            List<Account> orgs = RelationshipTestDataFactory.organizations(1, 'Union Foundation');
            Affiliation__c work = RelationshipTestDataFactory.affiliation(
                people[0],
                orgs[0],
                'Officer'
            );
            work.Is_Primary__c = true;
            insert work;

            Test.startTest();
            update new Affiliation__c(Id = work.Id, End_Date__c = Date.today().addDays(-1));
            Test.stopTest();

            Affiliation__c reloaded = RelationshipTestDataFactory.allAffiliations()[0];
            Assert.areEqual('Former', reloaded.Status__c, 'It has ended');
            Assert.isFalse(reloaded.Is_Primary__c, 'So it is not the primary one');
            Contact person = [SELECT Primary_Affiliation__c FROM Contact WHERE Id = :people[0].Id];
            Assert.isNull(
                person.Primary_Affiliation__c,
                'A field naming an employer someone left is worse than an empty one'
            );
        }
    }

    @IsTest
    static void deletingThePrimaryAffiliationEmptiesThePersonsField() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            List<Contact> people = RelationshipTestDataFactory.contacts(1, 'Garcia');
            List<Account> orgs = RelationshipTestDataFactory.organizations(1, 'Union Foundation');
            Affiliation__c work = RelationshipTestDataFactory.affiliation(
                people[0],
                orgs[0],
                'Officer'
            );
            work.Is_Primary__c = true;
            insert work;

            Test.startTest();
            delete work;
            Test.stopTest();

            Contact person = [SELECT Primary_Affiliation__c FROM Contact WHERE Id = :people[0].Id];
            Assert.isNull(person.Primary_Affiliation__c, 'Nothing left to be primary');
        }
    }

    @IsTest
    static void anAffiliationNeverMovesThePersonsHousehold() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            List<Contact> people = RelationshipTestDataFactory.contacts(1, 'Garcia');
            Id householdBefore = [SELECT AccountId FROM Contact WHERE Id = :people[0].Id].AccountId;
            List<Account> orgs = RelationshipTestDataFactory.organizations(1, 'Union Foundation');
            Affiliation__c work = RelationshipTestDataFactory.affiliation(
                people[0],
                orgs[0],
                'Officer'
            );
            work.Is_Primary__c = true;

            Test.startTest();
            insert work;
            Test.stopTest();

            Id householdAfter = [SELECT AccountId FROM Contact WHERE Id = :people[0].Id].AccountId;
            Assert.areEqual(
                householdBefore,
                householdAfter,
                'R-AF3: a donor who works at a foundation is still in their own household'
            );
        }
    }

    @IsTest
    static void settlesTwoHundredPeopleInOneSave() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            List<Contact> people = RelationshipTestDataFactory.contacts(200, 'Bulk');
            List<Account> orgs = RelationshipTestDataFactory.organizations(1, 'Union Foundation');
            List<Affiliation__c> batch = new List<Affiliation__c>();
            for (Contact person : people) {
                Affiliation__c work = RelationshipTestDataFactory.affiliation(
                    person,
                    orgs[0],
                    'Member'
                );
                work.Is_Primary__c = true;
                batch.add(work);
            }

            Test.startTest();
            insert batch;
            Test.stopTest();

            Integer carried = 0;
            for (Contact person : [
                SELECT Primary_Affiliation__c
                FROM Contact
                WHERE Id IN :people
            ]) {
                if (person.Primary_Affiliation__c == orgs[0].Id) {
                    carried++;
                }
            }
            Assert.areEqual(200, carried, 'Every person in a two hundred record save carries it');
        }
    }

    @IsTest
    static void keepsOnePrimaryWhenTwoAreFlaggedInOneSave() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            List<Contact> people = RelationshipTestDataFactory.contacts(1, 'Garcia');
            List<Account> orgs = RelationshipTestDataFactory.organizations(2, 'Organization');
            List<Affiliation__c> both = new List<Affiliation__c>();
            for (Account org : orgs) {
                Affiliation__c work = RelationshipTestDataFactory.affiliation(
                    people[0],
                    org,
                    'Member'
                );
                work.Is_Primary__c = true;
                both.add(work);
            }

            Test.startTest();
            insert both;
            Test.stopTest();

            Integer primaries = 0;
            for (Affiliation__c affiliation : RelationshipTestDataFactory.allAffiliations()) {
                if (affiliation.Is_Primary__c == true) {
                    primaries++;
                }
            }
            Assert.areEqual(1, primaries, 'Two flagged in one save still leaves one primary');
        }
    }

    /** PEOPLE-39: editing the role settles nothing, so it costs less than moving the flag. */
    @IsTest
    static void aRoleEditDoesNotSettleThePrimaryAgain() {
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

            Test.startTest();
            Integer before = Limits.getQueries();
            update new Affiliation__c(Id = work.Id, Role__c = 'Director');
            Integer forRole = Limits.getQueries() - before;
            before = Limits.getQueries();
            update new Affiliation__c(Id = work.Id, Is_Primary__c = false);
            Integer forFlag = Limits.getQueries() - before;
            Test.stopTest();

            Assert.isTrue(forRole < forFlag, 'Role ' + forRole + ', flag ' + forFlag);
            Assert.isNull(
                [SELECT Primary_Affiliation__c FROM Contact WHERE Id = :people[0].Id]
                .Primary_Affiliation__c,
                'Moving the flag still settles the person'
            );
        }
    }
}
