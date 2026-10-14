/**
 * Health Check's person-link findings (PEOPLE-19): relationships and affiliations left with
 * no person after a person was deleted. A delete blanks the lookup (the people are not merged),
 * so these tests delete people and then run Health Check as Maria, who holds the permission the
 * findings are shown under.
 */
@IsTest(testFor='ApexClass:HealthCheckHouseholdChecks, ApexClass:PersonLinkOrphanSelector')
private class HealthCheckPersonLinkChecksTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static final String RELATIONSHIP_KEY = 'relationships_without_person';
    private static final String AFFILIATION_KEY = 'affiliations_without_person';

    private static HealthCheckService.Finding runAsMaria(String key) {
        User maria = HealthCheckTestHelper.mariaWithManageSettings();
        HealthCheckService.Finding found;
        System.runAs(maria) {
            for (HealthCheckService.Finding finding : HealthCheckService.run()) {
                if (key.equals(finding.key)) {
                    found = finding;
                }
            }
        }
        return found;
    }

    private static List<Relationship__c> relationshipsBetween(
        List<Contact> people,
        List<Contact> others
    ) {
        List<Relationship__c> rows = new List<Relationship__c>();
        for (Integer i = 0; i < people.size(); i++) {
            Relationship__c row = RelationshipTestDataFactory.between(
                people[i],
                others[i],
                'Sibling'
            );
            row.Is_Reciprocal_Managed__c = false;
            rows.add(row);
        }
        insert rows;
        return rows;
    }

    @IsTest
    static void aRelationshipWhoseRelatedPersonWasDeletedIsReported() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            List<Contact> people = RelationshipTestDataFactory.contacts(2, 'Garcia');
            List<Contact> others = RelationshipTestDataFactory.contacts(2, 'Lee');
            List<Relationship__c> rows = relationshipsBetween(people, others);

            delete others[0];

            HealthCheckService.Finding finding = runAsMaria(RELATIONSHIP_KEY);

            Assert.isNotNull(finding, 'A relationship with nobody on one side is reported.');
            Assert.isTrue(finding.title.startsWith('1 '), 'One of the two: ' + finding.title);
            Assert.areEqual(HealthCheckService.SEVERITY_WARNING, finding.severity, 'A warning.');
            Assert.isNull(finding.fixTarget, 'Detection only: there is no fix button.');
            Assert.areEqual(1, finding.links.size(), 'It is linked.');
            Assert.areEqual(
                '/lightning/r/Relationship__c/' + rows[0].Id + '/view',
                finding.links[0].url,
                'To the relationship record page.'
            );
            Assert.isTrue(
                finding.detail.contains(System.Label.Core_HealthCheck_RelationshipsNoPersonDetail),
                'It says what to do next.'
            );
        }
    }

    @IsTest
    static void aRelationshipWhoseOwnerPersonWasDeletedIsReported() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            List<Contact> people = RelationshipTestDataFactory.contacts(1, 'Garcia');
            List<Contact> others = RelationshipTestDataFactory.contacts(1, 'Lee');
            relationshipsBetween(people, others);

            delete people;

            HealthCheckService.Finding finding = runAsMaria(RELATIONSHIP_KEY);

            Assert.isNotNull(finding, 'A blank person on the owner side is reported too.');
            Assert.isTrue(finding.title.startsWith('1 '), finding.title);
        }
    }

    @IsTest
    static void relationshipsBetweenPeopleWhoStillExistAreNotReported() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            List<Contact> people = RelationshipTestDataFactory.contacts(3, 'Garcia');
            List<Contact> others = RelationshipTestDataFactory.contacts(3, 'Lee');
            relationshipsBetween(people, others);

            Assert.isNull(runAsMaria(RELATIONSHIP_KEY), 'Nothing is blank, so nothing is shown.');
            Assert.isNull(runAsMaria(AFFILIATION_KEY), 'Nor for affiliations.');
        }
    }

    @IsTest
    static void anAffiliationWhoseContactStillExistsIsNotReported() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            List<Contact> people = RelationshipTestDataFactory.contacts(1, 'Garcia');
            List<Account> organizations = RelationshipTestDataFactory.organizations(1, 'Acme');
            insert RelationshipTestDataFactory.affiliation(people[0], organizations[0], 'Officer');

            Assert.isNull(runAsMaria(AFFILIATION_KEY), 'The person is still there.');
        }
    }

    @IsTest
    static void anAffiliationWhoseContactWasDeletedIsReported() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            List<Contact> people = RelationshipTestDataFactory.contacts(2, 'Garcia');
            List<Account> organizations = RelationshipTestDataFactory.organizations(1, 'Acme');
            List<Affiliation__c> rows = new List<Affiliation__c>{
                RelationshipTestDataFactory.affiliation(people[0], organizations[0], 'Officer'),
                RelationshipTestDataFactory.affiliation(people[1], organizations[0], 'Member')
            };
            insert rows;

            delete people[0];

            HealthCheckService.Finding finding = runAsMaria(AFFILIATION_KEY);

            Assert.isNotNull(finding, 'An affiliation with no person is reported.');
            Assert.isTrue(finding.title.startsWith('1 '), finding.title);
            Assert.areEqual(
                '/lightning/r/Affiliation__c/' + rows[0].Id + '/view',
                finding.links[0].url,
                'To the affiliation record page.'
            );
            Assert.isTrue(
                finding.detail.contains(System.Label.Core_HealthCheck_AffiliationsNoPersonDetail),
                'It says what to do next.'
            );
        }
    }

    @IsTest
    static void twoHundredRelationshipsAndAffiliationsLeftBlankAreCountedAndFiveLinked() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            List<Contact> people = RelationshipTestDataFactory.contacts(200, 'Garcia');
            List<Contact> others = RelationshipTestDataFactory.contacts(200, 'Lee');
            List<Account> organizations = RelationshipTestDataFactory.organizations(1, 'Acme');
            relationshipsBetween(people, others);
            List<Affiliation__c> affiliations = new List<Affiliation__c>();
            for (Contact person : people) {
                affiliations.add(
                    RelationshipTestDataFactory.affiliation(person, organizations[0], 'Member')
                );
            }
            insert affiliations;

            delete others;
            delete people;

            HealthCheckService.Finding relationships = runAsMaria(RELATIONSHIP_KEY);
            HealthCheckService.Finding affiliationFinding = runAsMaria(AFFILIATION_KEY);

            Assert.isTrue(relationships.title.startsWith('200 '), relationships.title);
            Assert.areEqual(5, relationships.links.size(), 'Five are linked.');
            Assert.isTrue(affiliationFinding.title.startsWith('200 '), affiliationFinding.title);
            Assert.areEqual(5, affiliationFinding.links.size(), 'Five are linked.');
        }
    }

    @IsTest
    static void theCountStopsAtTheCapAndSaysMoreThan() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            List<Contact> people = RelationshipTestDataFactory.contacts(3, 'Garcia');
            List<Account> organizations = RelationshipTestDataFactory.organizations(1, 'Acme');
            List<Affiliation__c> affiliations = new List<Affiliation__c>();
            for (Contact person : people) {
                affiliations.add(
                    RelationshipTestDataFactory.affiliation(person, organizations[0], 'Member')
                );
            }
            insert affiliations;
            delete people;
            HealthCheckHouseholdChecks.countCap = 2;

            HealthCheckService.Finding finding = runAsMaria(AFFILIATION_KEY);

            Assert.isTrue(
                finding.title.startsWith(
                    String.format(
                        System.Label.Core_HealthCheck_OrphansMoreThan,
                        new List<Object>{ '2' }
                    )
                ),
                'Past the cap it says more than: ' + finding.title
            );
        }
    }

    @IsTest
    static void theFindingsAreShownOnlyToSomebodyWhoManagesSettings() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            List<Contact> people = RelationshipTestDataFactory.contacts(1, 'Garcia');
            List<Account> organizations = RelationshipTestDataFactory.organizations(1, 'Acme');
            insert RelationshipTestDataFactory.affiliation(people[0], organizations[0], 'Officer');
            delete people;
            User priya = HealthCheckTestHelper.priyaWithoutManageSettings();

            System.runAs(priya) {
                for (HealthCheckService.Finding finding : HealthCheckService.run()) {
                    Assert.areNotEqual(RELATIONSHIP_KEY, finding.key, 'Hidden from her.');
                    Assert.areNotEqual(AFFILIATION_KEY, finding.key, 'Hidden from her.');
                }
            }
        }
    }
}
