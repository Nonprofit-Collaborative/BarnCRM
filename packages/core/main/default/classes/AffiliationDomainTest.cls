/**
 * The rules an affiliation has to pass before it is saved.
 *
 * NOT EXECUTED. No Salesforce org exists in the environment these were written in, so every
 * assertion here is unverified.
 */
@IsTest(testFor='ApexClass:AffiliationDomain')
private class AffiliationDomainTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

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

    /**
     * PEOPLE-23. Two overlapping affiliations loaded before the rule existed: editing one
     * without touching what the rule reads goes through, and moving its dates is still checked.
     */
    @IsTest
    static void anEditThatLeavesTheRoleAndDatesAloneIsNotRefusedForAnOldOverlap() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            List<Contact> people = RelationshipTestDataFactory.contacts(1, 'Garcia');
            List<Account> orgs = RelationshipTestDataFactory.organizations(1, 'Union Foundation');
            Affiliation__c first = RelationshipTestDataFactory.affiliation(
                people[0],
                orgs[0],
                'Board member'
            );
            Affiliation__c second = RelationshipTestDataFactory.affiliation(
                people[0],
                orgs[0],
                'Board member'
            );
            AutomationControl.bypass(AffiliationService.VALIDATION_AUTOMATION_NAME);
            insert new List<Affiliation__c>{ first, second };
            AutomationControl.clearBypass(AffiliationService.VALIDATION_AUTOMATION_NAME);

            Test.startTest();
            Database.SaveResult described = Database.update(
                new Affiliation__c(Id = first.Id, Description__c = 'Chairs the finance committee'),
                false
            );
            Database.SaveResult redated = Database.update(
                new Affiliation__c(Id = first.Id, Start_Date__c = Date.today().addYears(-1)),
                false
            );
            Test.stopTest();

            Assert.isTrue(described.isSuccess(), 'A description edit is not the overlap');
            Assert.isFalse(redated.isSuccess(), 'A date change is still checked');
        }
    }

    /**
     * PEOPLE-23, visible case unchanged: the existing row is one the saver can see, so the
     * message still names the record to open.
     */
    @IsTest
    static void anOverlapTheSaverCanSeeStillNamesTheRecord() {
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

            Assert.isFalse(result.isSuccess(), 'The overlap is refused');
            Assert.isTrue(
                result.getErrors()[0].getMessage().contains('AF-'),
                'The message names the record to open'
            );
        }
    }

    /**
     * PEOPLE-23. Private sharing cannot be set from a test, so the row is treated as invisible
     * through the test seam. The existence check comes from AffiliationUpkeepSelector, which
     * returns the row regardless of the user, and the message must carry nothing of it.
     */
    @IsTest
    static void anOverlapTheSaverCannotSeeIsStillRefusedWithAGenericMessage() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            List<Contact> people = RelationshipTestDataFactory.contacts(1, 'Garcia');
            List<Account> orgs = RelationshipTestDataFactory.organizations(1, 'Union Foundation');
            Affiliation__c hidden = RelationshipTestDataFactory.affiliation(
                people[0],
                orgs[0],
                'Board member'
            );
            insert hidden;
            Assert.areEqual(
                1,
                AffiliationUpkeepSelector.selectForOverlap(new Set<Id>{ people[0].Id }).size(),
                'The system mode selector finds the row'
            );
            AffiliationDomain.hiddenForTest = new Set<Id>{ hidden.Id };

            Test.startTest();
            Database.SaveResult result = Database.insert(
                RelationshipTestDataFactory.affiliation(people[0], orgs[0], 'Board member'),
                false
            );
            Test.stopTest();

            Assert.isFalse(result.isSuccess(), 'A hidden overlap is still refused');
            String message = result.getErrors()[0].getMessage();
            Assert.areEqual(Label.Core_Affiliation_OverlapHidden, message, 'The generic message');
            Assert.isFalse(message.contains('AF-'), 'No record number');
            Assert.isFalse(message.contains('Garcia'), 'No name');
            Assert.isFalse(message.contains('Union Foundation'), 'No organization');
        }
    }

    @IsTest
    static void twoHundredOverlapsWithRowsTheSaverCannotSeeAreAllRefused() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            List<Contact> people = RelationshipTestDataFactory.contacts(200, 'Garcia');
            List<Account> orgs = RelationshipTestDataFactory.organizations(1, 'Union Foundation');
            List<Affiliation__c> existing = new List<Affiliation__c>();
            List<Affiliation__c> incoming = new List<Affiliation__c>();
            for (Contact person : people) {
                existing.add(
                    RelationshipTestDataFactory.affiliation(person, orgs[0], 'Board member')
                );
                incoming.add(
                    RelationshipTestDataFactory.affiliation(person, orgs[0], 'Board member')
                );
            }
            insert existing;
            Set<Id> hiddenIds = new Set<Id>();
            for (Affiliation__c row : existing) {
                hiddenIds.add(row.Id);
            }
            AffiliationDomain.hiddenForTest = hiddenIds;

            Test.startTest();
            List<Database.SaveResult> results = Database.insert(incoming, false);
            Test.stopTest();

            for (Database.SaveResult result : results) {
                Assert.isFalse(result.isSuccess(), 'Every hidden overlap is refused');
                Assert.areEqual(
                    Label.Core_Affiliation_OverlapHidden,
                    result.getErrors()[0].getMessage(),
                    'With the generic message'
                );
            }
        }
    }
}
