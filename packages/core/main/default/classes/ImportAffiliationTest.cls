/**
 * A people import links each row's first person to the row's organization with an affiliation,
 * or finds the one they already have (R-AF5), counted in the preview and journaled for undo.
 */
@IsTest(testFor='ApexClass:ImportRowProcessor')
private class ImportAffiliationTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static Import_Template__c template;
    private static Import_Batch__c batch;

    private static void given(List<Map<String, String>> values) {
        TestDataFactory.defaultSettings();
        template = ImportTestDataFactory.template(
            ImportTestDataFactory.donorMapping(),
            ImportTemplateService.RULE_EMAIL
        );
        batch = ImportTestDataFactory.batch(template);
        ImportTestDataFactory.rows(batch, values);
    }

    private static ImportRowProcessor.Outcome run(Boolean dryRun) {
        return ImportRowProcessor.process(
            batch,
            template,
            ImportMapping.parse(template.Column_Mapping_JSON__c),
            ImportTestDataFactory.reload(batch.Id),
            dryRun
        );
    }

    private static Id organizationRecordTypeId() {
        return Account.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
            .getRecordTypeInfosByDeveloperName()
            .get('Organization')
            .getRecordTypeId();
    }

    private static List<Map<String, String>> staffRows() {
        List<Map<String, String>> values = new List<Map<String, String>>();
        for (Integer i = 0; i < 200; i++) {
            values.add(
                ImportTestDataFactory.donorRow(
                    'Person' + i,
                    'Surname' + i,
                    'person' + i + '@example.org',
                    'Employer ' + Math.mod(i, 20)
                )
            );
        }
        return values;
    }

    /** Two hundred people, each linked once to their employer, and journaled for undo. */
    @IsTest
    static void eachPersonIsLinkedToTheirOrganizationOnce() {
        System.runAs(TestUsers.admin()) {
            given(staffRows());

            Test.startTest();
            ImportRowProcessor.Outcome first = run(false);
            Test.stopTest();

            Assert.areEqual(200, first.created, 'Every row created: ' + first.notes);
            Assert.areEqual(200, [SELECT COUNT() FROM Affiliation__c], 'One affiliation each.');
            Contact person = [
                SELECT Id, (SELECT Organization__r.Name FROM Affiliations__r)
                FROM Contact
                WHERE Email = 'person21@example.org'
            ];
            Assert.areEqual(1, person.Affiliations__r.size());
            Assert.areEqual('Employer 1', person.Affiliations__r[0].Organization__r.Name);
            Assert.areEqual(
                200,
                ImportJournalService.entryCount(batch.Id, ImportJournalService.PHASE_CREATED),
                'Each affiliation is journaled as created, so an undo deletes it.'
            );
        }
    }

    /** Loading the same file again finds the affiliations and makes no more. */
    @IsTest
    static void aSecondLoadMatchesTheAffiliations() {
        System.runAs(TestUsers.admin()) {
            given(staffRows());
            run(false);
            Import_Template__c sameTemplate = template;
            batch = ImportTestDataFactory.batch(sameTemplate);
            ImportTestDataFactory.rows(batch, staffRows());

            Test.startTest();
            ImportRowProcessor.Outcome again = run(false);
            Test.stopTest();

            Assert.areEqual(0, again.created, 'Nothing new: ' + again.notes);
            Assert.areEqual(200, again.matched, 'Every row matched what is there.');
            Assert.areEqual(200, [SELECT COUNT() FROM Affiliation__c], 'Still one each.');
        }
    }

    /**
     * The preview counts a row that would add an affiliation as creating something and writes
     * nothing; a row whose pair is already affiliated matches. Two rows of one pair make one.
     */
    @IsTest
    static void thePreviewCountsWhatTheCommitDoes() {
        System.runAs(TestUsers.admin()) {
            Account employer = new Account(
                Name = 'Rose City',
                RecordTypeId = organizationRecordTypeId()
            );
            insert employer;
            Contact ana = new Contact(
                FirstName = 'Ana',
                LastName = 'Ramirez',
                Email = 'ana@example.org',
                MailingCity = 'Portland'
            );
            Contact ben = new Contact(
                FirstName = 'Ben',
                LastName = 'Okafor',
                Email = 'ben@example.org',
                MailingCity = 'Portland'
            );
            insert new List<Contact>{ ana, ben };
            insert new Affiliation__c(Contact__c = ana.Id, Organization__c = employer.Id);
            given(
                new List<Map<String, String>>{
                    ImportTestDataFactory.donorRow(
                        'Ana',
                        'Ramirez',
                        'ana@example.org',
                        'Rose City'
                    ),
                    ImportTestDataFactory.donorRow('Ben', 'Okafor', 'ben@example.org', 'Rose City'),
                    ImportTestDataFactory.donorRow('Ben', 'Okafor', 'ben@example.org', 'Rose City')
                }
            );

            Test.startTest();
            ImportRowProcessor.Outcome preview = run(true);
            Integer afterPreview = [SELECT COUNT() FROM Affiliation__c];
            ImportRowProcessor.Outcome committed = run(false);
            Test.stopTest();

            Assert.areEqual(1, afterPreview, 'The preview wrote nothing.');
            Assert.areEqual(1, preview.created, 'Ben would be affiliated, once.');
            Assert.areEqual(2, preview.matched, 'Ana already is, and Ben\'s second row matches.');
            Assert.areEqual(preview.created, committed.created, 'The commit agrees.');
            Assert.areEqual(preview.matched, committed.matched);
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Affiliation__c WHERE Contact__c = :ben.Id],
                'Ben has one affiliation.'
            );
        }
    }
}
