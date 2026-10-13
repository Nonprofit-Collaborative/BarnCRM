/**
 * C-32 import matching (ADR-0068, `0068-import-matching-per-entity-and-per-file-values.md`):
 * a row whose key finds several records is rejected unless the template says to take the most
 * recently changed (R-IT9), organizations have a rule of their own and are searched only among
 * organizations (R-IT2), and a chosen matching field must be one describe offers (R-IT8).
 */
@IsTest
private class ImportMatchingRulesTest {
    @TestSetup
    static void setUp() {
        System.runAs(TestUsers.admin()) {
            TestDataFactory.defaultSettings();
        }
    }

    private static final List<String> PERSON_COLUMNS = new List<String>{
        'Contact1.FirstName',
        'Contact1.LastName',
        'Contact1.MailingPostalCode',
        'Contact1.MailingCity',
        'Organization.Name'
    };

    /** A template under the Name plus postal code rule, with the given several-matches choice. */
    private static Import_Template__c template(String severalMatches) {
        ImportMapping mapping = new ImportMapping();
        for (String target : PERSON_COLUMNS) {
            mapping.columns.add(new ImportMapping.Column(target, target));
        }
        Import_Template__c template = ImportTestDataFactory.template(
            mapping.serialize(),
            ImportTemplateService.RULE_NAME_POSTAL
        );
        template.Several_Matches__c = severalMatches;
        update template;
        return template;
    }

    /** A Smith at 12345, with the given first name (blank for none). */
    private static Map<String, String> smithRow(String firstName) {
        return new Map<String, String>{
            'Contact1.FirstName' => firstName,
            'Contact1.LastName' => 'Smith',
            'Contact1.MailingPostalCode' => '12345'
        };
    }

    private static Contact smith(String firstName) {
        return new Contact(FirstName = firstName, LastName = 'Smith', MailingPostalCode = '12345');
    }

    private static Id organizationRecordTypeId() {
        return Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get('Organization')
            .getRecordTypeId();
    }

    /** Runs one pass the way the platform drives the batch, in one chunk of up to 200 rows. */
    private static Import_Batch__c run(Id batchId, Boolean dryRun) {
        ImportBatchService.beginPass(batchId);
        ImportProcessorBatch job = new ImportProcessorBatch(batchId, dryRun);
        List<Import_Row__c> chunk = new List<Import_Row__c>();
        Database.QueryLocatorIterator rows = job.start(null).iterator();
        while (rows.hasNext()) {
            chunk.add((Import_Row__c) rows.next());
            if (chunk.size() == 200 || !rows.hasNext()) {
                job.execute(null, chunk);
                chunk = new List<Import_Row__c>();
            }
        }
        job.finish(null);
        return ImportBatchSelector.selectById(batchId);
    }

    /** Dry runs then commits, checking the dry run counted what the commit did. */
    private static Import_Batch__c load(Import_Batch__c batch) {
        Import_Batch__c dryRun = run(batch.Id, true);
        Import_Batch__c committed = run(batch.Id, false);
        Assert.areEqual(dryRun.Rows_Created__c, committed.Rows_Created__c, 'Created as previewed.');
        Assert.areEqual(dryRun.Rows_Matched__c, committed.Rows_Matched__c, 'Matched as previewed.');
        Assert.areEqual(
            dryRun.Rows_Rejected__c,
            committed.Rows_Rejected__c,
            'Rejected as previewed.'
        );
        return committed;
    }

    private static List<Import_Row__c> rowsOf(Id batchId) {
        return [
            SELECT
                Id,
                Status__c,
                Error_Message__c,
                Several_Matches__c,
                Contact_1__c,
                Organization__c
            FROM Import_Row__c
            WHERE Import_Batch__c = :batchId
            ORDER BY Row_Number__c ASC
        ];
    }

    @IsTest
    static void aRowWithNoFirstNameAtACoupleIsRejectedByDefault() {
        System.runAs(TestUsers.admin()) {
            insert new List<Contact>{ smith('John'), smith('Jane') };
            Import_Batch__c batch = ImportTestDataFactory.batch(template(null));
            ImportTestDataFactory.rows(batch, new List<Map<String, String>>{ smithRow('') });

            Test.startTest();
            load(batch);
            Test.stopTest();

            Import_Row__c row = rowsOf(batch.Id)[0];
            Assert.areEqual(ImportRowProcessor.STATUS_REJECTED, row.Status__c, 'Not guessed at.');
            Assert.areEqual(
                Label.Core_Import_ErrorSeveralPeopleMatch,
                row.Error_Message__c,
                'Says why.'
            );
            Assert.isTrue(row.Several_Matches__c, 'And is ticked so it can be listed.');
            Assert.areEqual(2, [SELECT COUNT() FROM Contact], 'Nobody added.');
        }
    }

    @IsTest
    static void twoRecordsWithOneFirstNameAreSeveralMatchesToo() {
        System.runAs(TestUsers.admin()) {
            insert new List<Contact>{ smith('Jane'), smith('Jane') };
            Import_Batch__c batch = ImportTestDataFactory.batch(template(null));
            ImportTestDataFactory.rows(batch, new List<Map<String, String>>{ smithRow('Jane') });

            Test.startTest();
            load(batch);
            Test.stopTest();

            Import_Row__c row = rowsOf(batch.Id)[0];
            Assert.areEqual(
                ImportRowProcessor.STATUS_REJECTED,
                row.Status__c,
                'Two Janes: rejected.'
            );
            Assert.isTrue(row.Several_Matches__c, 'Ticked.');
        }
    }

    @IsTest
    static void theMostRecentlyChangedIsUsedWhenTheTemplateSaysSo() {
        System.runAs(TestUsers.admin()) {
            Contact john = smith('John');
            insert john;
            Contact jane = smith('Jane');
            insert jane;
            Import_Batch__c batch = ImportTestDataFactory.batch(
                template(ImportTemplateService.SEVERAL_MOST_RECENT)
            );
            ImportTestDataFactory.rows(batch, new List<Map<String, String>>{ smithRow('') });

            Test.startTest();
            Import_Batch__c committed = load(batch);
            Test.stopTest();

            Import_Row__c row = rowsOf(batch.Id)[0];
            Assert.areNotEqual(ImportRowProcessor.STATUS_REJECTED, row.Status__c, 'Loaded.');
            // Saved in one test second, the two tie on Last Modified Date: the later created wins.
            Assert.areEqual(jane.Id, row.Contact_1__c, 'The most recently changed, Jane.');
            Assert.isTrue(row.Several_Matches__c, 'Still ticked, so it can be checked.');
            Assert.isTrue(
                committed.Run_Log__c.contains(Label.Core_Import_LogSeveralMatchesUsedRecent),
                'The run log says so.'
            );
            Assert.areEqual(2, [SELECT COUNT() FROM Contact], 'Nobody added.');
        }
    }

    @IsTest
    static void twoOrganizationsWithOneNameRejectTheRow() {
        System.runAs(TestUsers.admin()) {
            Id organizationType = organizationRecordTypeId();
            insert new List<Account>{
                new Account(Name = 'First Baptist', RecordTypeId = organizationType),
                new Account(Name = 'First Baptist', RecordTypeId = organizationType)
            };
            Import_Batch__c batch = ImportTestDataFactory.batch(template(null));
            Map<String, String> values = smithRow('Ana');
            values.put('Organization.Name', 'first baptist');
            ImportTestDataFactory.rows(batch, new List<Map<String, String>>{ values });

            Test.startTest();
            load(batch);
            Test.stopTest();

            Import_Row__c row = rowsOf(batch.Id)[0];
            Assert.areEqual(
                Label.Core_Import_ErrorSeveralOrganizationsMatch,
                row.Error_Message__c,
                'Two organizations by that name: rejected.'
            );
            Assert.isTrue(row.Several_Matches__c, 'Ticked.');
            Assert.areEqual(0, [SELECT COUNT() FROM Contact], 'Nothing of the row was written.');
        }
    }

    @IsTest
    static void anOrganizationIsMatchedByNameOnlyAmongOrganizations() {
        System.runAs(TestUsers.admin()) {
            Id organizationType = organizationRecordTypeId();
            Account organization = new Account(
                Name = 'Harbor Trust',
                RecordTypeId = organizationType
            );
            insert organization;
            Import_Batch__c batch = ImportTestDataFactory.batch(template(null));
            Map<String, String> values = smithRow('Ana');
            values.put('Organization.Name', 'Harbor Trust');
            ImportTestDataFactory.rows(batch, new List<Map<String, String>>{ values });

            Test.startTest();
            load(batch);
            Test.stopTest();

            Import_Row__c row = rowsOf(batch.Id)[0];
            Assert.areEqual(organization.Id, row.Organization__c, 'Found by its name.');
            Assert.isFalse(row.Several_Matches__c, 'One organization holds it.');
        }
    }

    @IsTest
    static void aMatchingFieldDescribeDoesNotOfferIsRefused() {
        System.runAs(TestUsers.admin()) {
            Import_Template__c template = template(null);
            ImportTemplateService.MatchingChoices choices = new ImportTemplateService.MatchingChoices();
            choices.personRule = ImportTemplateService.RULE_EXTERNAL_ID;
            choices.personMatchField = 'Email';
            Boolean refused = false;
            Test.startTest();
            try {
                ImportTemplateService.saveMatching(template.Id, choices);
            } catch (ImportException e) {
                refused = e.getMessage().contains('Email');
            }
            Test.stopTest();
            Assert.isTrue(refused, 'Email is neither External ID nor Unique, so it is refused.');
        }
    }

    @IsTest
    static void matchingChoicesAreSavedNormalized() {
        System.runAs(TestUsers.admin()) {
            Import_Template__c template = template(null);
            ImportTemplateService.MatchingChoices choices = new ImportTemplateService.MatchingChoices();
            choices.personRule = 'email EXACT';
            choices.personMatchField = 'Ignored_Without_The_Rule__c';
            choices.organizationRule = 'something else';
            choices.severalMatches = 'use the most recently changed';

            Test.startTest();
            ImportTemplateService.saveMatching(template.Id, choices);
            Test.stopTest();

            Import_Template__c saved = ImportTemplateSelector.selectById(template.Id);
            Assert.areEqual(
                ImportTemplateService.RULE_EMAIL,
                saved.Matching_Rule__c,
                'Person rule.'
            );
            Assert.isNull(saved.Person_Match_Field__c, 'No field without the External ID rule.');
            Assert.areEqual(
                ImportTemplateService.ORGANIZATION_RULE_NAME,
                saved.Organization_Matching_Rule__c,
                'An unknown organization rule is Name exact.'
            );
            Assert.areEqual(
                ImportTemplateService.SEVERAL_MOST_RECENT,
                saved.Several_Matches__c,
                'The several-matches choice.'
            );
        }
    }

    /**
     * The matcher's chosen-field lookup on a field describe offers: Import Template's own
     * Template Key, External ID and unique, which every org has. A blank value is never
     * looked up, and a value is found whatever its case.
     */
    @IsTest
    static void aChosenFieldFindsByValueAndNeverByBlank() {
        System.runAs(TestUsers.admin()) {
            Import_Template__c template = template(null);
            Assert.areEqual(
                'Template_Key__c',
                ImportMatcher.matchField(Import_Template__c.SObjectType, 'template_key__c'),
                'Offered, and named as describe names it.'
            );
            Assert.isNull(
                ImportMatcher.matchField(Import_Template__c.SObjectType, 'Name'),
                'A field neither External ID nor Unique is not offered.'
            );

            Test.startTest();
            Map<String, Id> found = ImportMatcher.byMatchField(
                Import_Template__c.SObjectType,
                'Template_Key__c',
                new Set<String>{ template.Template_Key__c.toUpperCase(), '', null },
                null
            );
            Test.stopTest();

            Assert.areEqual(1, found.size(), 'Only the real value was looked up.');
            Assert.areEqual(
                template.Id,
                found.get(template.Template_Key__c.toLowerCase()),
                'Found by its value.'
            );
        }
    }

    @IsTest
    static void twoHundredRowsAtCouplesAreRejectedInOneChunk() {
        System.runAs(TestUsers.admin()) {
            List<Contact> couples = new List<Contact>();
            List<Map<String, String>> values = new List<Map<String, String>>();
            for (Integer i = 0; i < 200; i++) {
                couples.add(
                    new Contact(
                        FirstName = 'John',
                        LastName = 'Smith' + i,
                        MailingPostalCode = '12345'
                    )
                );
                couples.add(
                    new Contact(
                        FirstName = 'Jane',
                        LastName = 'Smith' + i,
                        MailingPostalCode = '12345'
                    )
                );
                values.add(
                    new Map<String, String>{
                        'Contact1.LastName' => 'Smith' + i,
                        'Contact1.MailingPostalCode' => '12345'
                    }
                );
            }
            insert couples;
            Import_Batch__c batch = ImportTestDataFactory.batch(template(null));
            ImportTestDataFactory.rows(batch, values);

            Test.startTest();
            Import_Batch__c committed = load(batch);
            Test.stopTest();

            Assert.areEqual(200, committed.Rows_Rejected__c, 'Every row matches a couple.');
            Assert.areEqual(
                200,
                [
                    SELECT COUNT()
                    FROM Import_Row__c
                    WHERE Import_Batch__c = :batch.Id AND Several_Matches__c = TRUE
                ],
                'Every row is ticked.'
            );
            Assert.areEqual(400, [SELECT COUNT() FROM Contact], 'Nobody added, nobody renamed.');
        }
    }

    @IsTest
    static void twoHundredRowsTakeTheMostRecentWhenChosen() {
        System.runAs(TestUsers.admin()) {
            List<Contact> couples = new List<Contact>();
            List<Map<String, String>> values = new List<Map<String, String>>();
            for (Integer i = 0; i < 200; i++) {
                couples.add(
                    new Contact(
                        FirstName = 'John',
                        LastName = 'Smith' + i,
                        MailingPostalCode = '12345'
                    )
                );
                couples.add(
                    new Contact(
                        FirstName = 'Jane',
                        LastName = 'Smith' + i,
                        MailingPostalCode = '12345'
                    )
                );
                values.add(
                    new Map<String, String>{
                        'Contact1.LastName' => 'Smith' + i,
                        'Contact1.MailingPostalCode' => '12345'
                    }
                );
            }
            insert couples;
            Import_Batch__c batch = ImportTestDataFactory.batch(
                template(ImportTemplateService.SEVERAL_MOST_RECENT)
            );
            ImportTestDataFactory.rows(batch, values);

            Test.startTest();
            Import_Batch__c committed = load(batch);
            Test.stopTest();

            Assert.areEqual(0, committed.Rows_Rejected__c, 'Every row is loaded.');
            Assert.areEqual(200, committed.Rows_Matched__c, 'Into a record already there.');
            Assert.areEqual(400, [SELECT COUNT() FROM Contact], 'Nobody added.');
        }
    }
}
