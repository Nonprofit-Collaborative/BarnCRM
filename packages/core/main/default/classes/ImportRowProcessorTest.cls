/**
 * The processor: what a row means, what a dry run promises, and what happens to a row that
 * cannot be loaded.
 *
 * The assertion that matters most here is the one in `dryRunWritesNothing`: the preview an
 * administrator decides on has to be free.
 */
@IsTest(testFor='ApexClass:ImportRowProcessor')
private class ImportRowProcessorTest {
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

    @IsTest
    static void createsAPersonAndTheirHousehold() {
        System.runAs(TestUsers.admin()) {
            given(
                new List<Map<String, String>>{
                    ImportTestDataFactory.donorRow('Ana', 'Ramirez', 'ana@example.org', null)
                }
            );
            Test.startTest();
            ImportRowProcessor.Outcome outcome = run(false);
            Test.stopTest();

            Assert.areEqual(1, outcome.created, 'The row created a person.');
            List<Contact> contacts = [SELECT Id, LastName, AccountId FROM Contact];
            Assert.areEqual(1, contacts.size(), 'One contact was inserted.');
            Assert.isNotNull(
                contacts[0].AccountId,
                'And the household trigger gave them a household, which the importer did not build.'
            );
            Import_Row__c row = ImportTestDataFactory.reload(batch.Id)[0];
            Assert.areEqual(ImportRowProcessor.STATUS_CREATED, row.Status__c, 'The row says so.');
            Assert.areEqual(contacts[0].Id, row.Contact_1__c, 'And points at what it created.');
        }
    }

    @IsTest
    static void tagsEveryRecordWithTheImportThatCreatedIt() {
        System.runAs(TestUsers.admin()) {
            given(
                new List<Map<String, String>>{
                    ImportTestDataFactory.donorRow('Ana', 'Ramirez', 'ana@example.org', 'Rose City')
                }
            );
            Test.startTest();
            run(false);
            Test.stopTest();

            Assert.areEqual(
                batch.Id,
                [SELECT Created_By_Import_Batch__c FROM Contact LIMIT 1].Created_By_Import_Batch__c,
                'The person carries the batch tag (R-IB3).'
            );
            Assert.areEqual(
                batch.Id,
                [
                    SELECT Created_By_Import_Batch__c
                    FROM Account
                    WHERE Name = 'Rose City'
                    LIMIT 1
                ]
                .Created_By_Import_Batch__c,
                'So does the organization.'
            );
            Assert.areEqual(
                batch.Id,
                [
                    SELECT Created_By_Import_Batch__c
                    FROM Account
                    WHERE Id IN (SELECT AccountId FROM Contact)
                    LIMIT 1
                ]
                .Created_By_Import_Batch__c,
                'And the household made for the new person, so an undo can remove it too.'
            );
            Assert.areEqual(
                0,
                ImportJournalService.entryCount(batch.Id, ImportJournalService.PHASE_COMMIT),
                'Nothing is journaled for records the import tagged: the tag is their record.'
            );
            Assert.areEqual(
                1,
                ImportJournalService.entryCount(batch.Id, ImportJournalService.PHASE_CREATED),
                'Only the affiliation with Rose City, which carries no tag, is journaled (R-AF5).'
            );
        }
    }

    /**
     * A checkbox the file gives as "Yes" is the true already stored, so re-importing an
     * unchanged opt-out leaves the person unchanged, in the preview and the commit, and puts
     * nothing in the undo journal.
     */
    @IsTest
    static void reImportingAnUnchangedCheckboxChangesNothing() {
        System.runAs(TestUsers.admin()) {
            TestDataFactory.defaultSettings();
            insert new Contact(
                FirstName = 'Ana',
                LastName = 'Ramirez',
                Email = 'ana@example.org',
                MailingCity = 'Portland',
                HasOptedOutOfEmail = true,
                DoNotCall = false
            );
            ImportMapping mapping = ImportMapping.parse(ImportTestDataFactory.donorMapping());
            mapping.columns.add(
                new ImportMapping.Column('Email Opt Out', 'Contact1.HasOptedOutOfEmail')
            );
            mapping.columns.add(new ImportMapping.Column('Do Not Call', 'Contact1.DoNotCall'));
            template = ImportTestDataFactory.template(
                mapping.serialize(),
                ImportTemplateService.RULE_EMAIL
            );
            batch = ImportTestDataFactory.batch(template);
            Map<String, String> row = ImportTestDataFactory.donorRow(
                'Ana',
                'Ramirez',
                'ana@example.org',
                null
            );
            row.put('Email Opt Out', 'Yes');
            row.put('Do Not Call', 'No');
            ImportTestDataFactory.rows(batch, new List<Map<String, String>>{ row });

            Test.startTest();
            ImportRowProcessor.Outcome preview = run(true);
            ImportRowProcessor.Outcome outcome = run(false);
            Test.stopTest();

            Assert.areEqual(1, preview.matched, 'The preview says she is unchanged.');
            Assert.areEqual(0, preview.updated, 'Not updated.');
            Assert.areEqual(1, outcome.matched, 'So does the commit.');
            Assert.areEqual(0, outcome.updated, 'Nothing was written to her.');
            Assert.areEqual(0, [SELECT COUNT() FROM Import_Journal__c], 'And nothing journaled.');
        }
    }

    @IsTest
    static void dryRunWritesNothing() {
        System.runAs(TestUsers.admin()) {
            given(
                new List<Map<String, String>>{
                    ImportTestDataFactory.donorRow('Ana', 'Ramirez', 'ana@example.org', 'Rose City')
                }
            );
            Test.startTest();
            ImportRowProcessor.Outcome outcome = run(true);
            Test.stopTest();

            Assert.areEqual(1, outcome.created, 'The preview says the row would create something.');
            Assert.areEqual(0, [SELECT COUNT() FROM Contact], 'And nothing at all was written.');
            Assert.areEqual(0, [SELECT COUNT() FROM Account], 'Not an organization either.');
            Assert.areEqual(0, [SELECT COUNT() FROM Import_Journal__c], 'Nor a journal page.');
            Assert.areEqual(
                ImportRowProcessor.STATUS_CREATED,
                ImportTestDataFactory.reload(batch.Id)[0].Status__c,
                'The staged row still records what would happen, which is what the preview shows.'
            );
        }
    }

    @IsTest
    static void matchesAnExistingPersonInsteadOfDuplicatingThem() {
        System.runAs(TestUsers.admin()) {
            insert new Contact(FirstName = 'Ana', LastName = 'Ramirez', Email = 'ana@example.org');
            given(
                new List<Map<String, String>>{
                    ImportTestDataFactory.donorRow('Ana', 'Ramirez', 'ana@example.org', null)
                }
            );
            Test.startTest();
            ImportRowProcessor.Outcome outcome = run(false);
            Test.stopTest();

            Assert.areEqual(0, outcome.created, 'Nobody new was created.');
            Assert.areEqual(1, [SELECT COUNT() FROM Contact], 'There is still one Ana Ramirez.');
            Assert.areEqual(
                1,
                outcome.matched + outcome.updated,
                'The row matched the person already there.'
            );
        }
    }

    @IsTest
    static void runningTheSameFileTwiceDoesNotDuplicate() {
        System.runAs(TestUsers.admin()) {
            given(
                new List<Map<String, String>>{
                    ImportTestDataFactory.donorRow('Ana', 'Ramirez', 'ana@example.org', 'Rose City')
                }
            );
            Test.startTest();
            run(false);
            ImportBatchService.beginPass(batch.Id);
            run(false);
            Test.stopTest();

            Assert.areEqual(1, [SELECT COUNT() FROM Contact], 'Idempotent per row (R-IB4).');
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Account WHERE Name = 'Rose City'],
                'And the organization was not created twice either.'
            );
        }
    }

    @IsTest
    static void twoRowsNamingOneNewOrganizationCreateItOnce() {
        System.runAs(TestUsers.admin()) {
            given(
                new List<Map<String, String>>{
                    ImportTestDataFactory.donorRow(
                        'Ana',
                        'Ramirez',
                        'ana@example.org',
                        'Rose City'
                    ),
                    ImportTestDataFactory.donorRow('Ben', 'Okafor', 'ben@example.org', 'Rose City')
                }
            );
            Test.startTest();
            run(false);
            Test.stopTest();

            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Account WHERE Name = 'Rose City'],
                'One file never creates the same organization twice.'
            );
            for (Import_Row__c row : ImportTestDataFactory.reload(batch.Id)) {
                Assert.isNotNull(row.Organization__c, 'Both rows point at it.');
            }
        }
    }

    @IsTest
    static void rejectsARowWithNoLastNameAndKeepsTheRest() {
        System.runAs(TestUsers.admin()) {
            given(
                new List<Map<String, String>>{
                    ImportTestDataFactory.donorRow('Ana', 'Ramirez', 'ana@example.org', null),
                    ImportTestDataFactory.donorRow('Nobody', null, null, null)
                }
            );
            Test.startTest();
            ImportRowProcessor.Outcome outcome = run(false);
            Test.stopTest();

            Assert.areEqual(1, outcome.created, 'The good row went through.');
            Assert.areEqual(1, outcome.rejected, 'The bad row did not take it with it (R-IB5).');
            List<Import_Row__c> rows = ImportTestDataFactory.reload(batch.Id);
            Assert.areEqual(
                ImportRowProcessor.STATUS_REJECTED,
                rows[1].Status__c,
                'The failing row is marked rejected.'
            );
            Assert.areEqual(
                Label.Core_Import_ErrorLastNameMissing,
                rows[1].Error_Message__c,
                'With the reason the admin guide quotes word for word.'
            );
        }
    }

    @IsTest
    static void rejectsARowThatDescribesNobody() {
        System.runAs(TestUsers.admin()) {
            given(new List<Map<String, String>>{ new Map<String, String>{ 'City' => 'Portland' } });
            Test.startTest();
            ImportRowProcessor.Outcome outcome = run(false);
            Test.stopTest();
            Assert.areEqual(1, outcome.rejected, 'A row with only an address creates nothing.');
            Assert.areEqual(
                Label.Core_Import_ErrorRowIdentifiesNobody,
                ImportTestDataFactory.reload(batch.Id)[0].Error_Message__c,
                'And says why.'
            );
        }
    }

    @IsTest
    static void staysBulkSafeAcrossAWholeChunk() {
        System.runAs(TestUsers.admin()) {
            List<Map<String, String>> values = new List<Map<String, String>>();
            for (Integer i = 0; i < 50; i++) {
                values.add(
                    ImportTestDataFactory.donorRow(
                        'Person' + i,
                        'Surname' + i,
                        'person' + i + '@example.org',
                        'Shared Organization'
                    )
                );
            }
            given(values);

            Test.startTest();
            Integer queriesBefore = Limits.getQueries();
            run(false);
            Integer queriesUsed = Limits.getQueries() - queriesBefore;
            Test.stopTest();

            Assert.areEqual(50, [SELECT COUNT() FROM Contact], 'Every row was loaded.');
            Assert.isTrue(
                queriesUsed < 25,
                'Fifty rows cost a handful of queries, not one per row: got ' + queriesUsed
            );
        }
    }

    /** The donor mapping with a birthdate and a title, for the value tests below. */
    private static void givenWithBirthdateAndTitle(List<Map<String, String>> values) {
        TestDataFactory.defaultSettings();
        ImportMapping mapping = ImportMapping.parse(ImportTestDataFactory.donorMapping());
        mapping.columns.add(new ImportMapping.Column('Born', 'Contact1.Birthdate'));
        mapping.columns.add(new ImportMapping.Column('Title', 'Contact1.Title'));
        template = ImportTestDataFactory.template(
            mapping.serialize(),
            ImportTemplateService.RULE_EMAIL
        );
        batch = ImportTestDataFactory.batch(template);
        ImportTestDataFactory.rows(batch, values);
    }

    private static Map<String, String> bornRow(Integer i, String born, String title) {
        Map<String, String> row = ImportTestDataFactory.donorRow(
            'Person' + i,
            'Surname' + i,
            'person' + i + '@example.org',
            null
        );
        row.put('Born', born);
        row.put('Title', title);
        return row;
    }

    /**
     * People read dates as Load one object does (IMPORT-4): a date written in the user's
     * locale loads, where it was dropped before with the row still counted a success, and a
     * value that cannot be read rejects its row with the field and value named. Two hundred
     * rows, a full default chunk.
     */
    @IsTest
    static void aLocaleDateLoadsAndAnUnreadableValueRejectsItsRow() {
        System.runAs(TestUsers.admin()) {
            Date expected = Date.newInstance(1980, 4, 2);
            String localeDate = expected.format();
            List<Map<String, String>> values = new List<Map<String, String>>();
            for (Integer i = 0; i < 199; i++) {
                values.add(bornRow(i, localeDate, 'Treasurer'));
            }
            values.add(bornRow(199, 'not a date', 'Treasurer'));
            givenWithBirthdateAndTitle(values);

            Test.startTest();
            ImportRowProcessor.Outcome outcome = run(false);
            Test.stopTest();

            Assert.areEqual(199, outcome.created, 'Every readable row loaded: ' + outcome.notes);
            Assert.areEqual(
                199,
                [SELECT COUNT() FROM Contact WHERE Birthdate = :expected],
                'With the birthdate as written in the user\'s locale.'
            );
            Assert.areEqual(1, outcome.rejected, 'The unreadable row is rejected.');
            Import_Row__c rejected = ImportTestDataFactory.reload(batch.Id)[199];
            Assert.areEqual(ImportRowProcessor.STATUS_REJECTED, rejected.Status__c);
            Assert.isTrue(
                rejected.Error_Message__c.contains('not a date'),
                'The reason names the value: ' + rejected.Error_Message__c
            );
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Contact WHERE Email = 'person199@example.org'],
                'Nobody was created for it.'
            );
        }
    }

    /**
     * Amounts load as spreadsheets export them: currency symbols and codes, grouping in the
     * user's locale and accounting brackets for a negative. A value that cannot be read
     * without guessing still rejects its row. Two hundred rows, a full default chunk.
     */
    @IsTest
    static void spreadsheetAmountsLoadAndAnUnreadableOneRejectsItsRow() {
        System.runAs(TestUsers.admin()) {
            // Written as the user's locale writes them, so the test holds in any locale.
            List<String> written = new List<String>{
                '$' + Decimal.valueOf('1250.5').format(),
                '€' + Decimal.valueOf('100').format(),
                '(' +
                Decimal.valueOf('45.5').format() +
                ')',
                'USD ' + Decimal.valueOf('1250000').format()
            };
            List<Decimal> expected = new List<Decimal>{ 1250.5, 100, -45.5, 1250000 };
            List<Map<String, String>> values = new List<Map<String, String>>();
            for (Integer i = 0; i < 200; i++) {
                Map<String, String> row = ImportTestDataFactory.donorRow(
                    'Person' + i,
                    'Surname' + i,
                    'person' + i + '@example.org',
                    'Employer ' + i
                );
                row.put('Revenue', i == 199 ? '12abc' : written[Math.mod(i, 4)]);
                values.add(row);
            }
            TestDataFactory.defaultSettings();
            ImportMapping mapping = ImportMapping.parse(ImportTestDataFactory.donorMapping());
            mapping.columns.add(new ImportMapping.Column('Revenue', 'Organization.AnnualRevenue'));
            template = ImportTestDataFactory.template(
                mapping.serialize(),
                ImportTemplateService.RULE_EMAIL
            );
            batch = ImportTestDataFactory.batch(template);
            ImportTestDataFactory.rows(batch, values);

            Test.startTest();
            ImportRowProcessor.Outcome outcome = run(false);
            Test.stopTest();

            Assert.areEqual(199, outcome.created, 'Every readable row loaded: ' + outcome.notes);
            Assert.areEqual(1, outcome.rejected, 'The unreadable amount rejects its row.');
            Map<String, Decimal> revenueByName = new Map<String, Decimal>();
            for (Account organization : [
                SELECT Name, AnnualRevenue
                FROM Account
                WHERE Name LIKE 'Employer %'
            ]) {
                revenueByName.put(organization.Name, organization.AnnualRevenue);
            }
            for (Integer i = 0; i < 199; i++) {
                Assert.isTrue(
                    revenueByName.get('Employer ' + i) == expected[Math.mod(i, 4)],
                    'Read as written: ' + written[Math.mod(i, 4)]
                );
            }
            Assert.isFalse(revenueByName.containsKey('Employer 199'), 'Nothing made for it.');
        }
    }

    /**
     * A re-import compares as the save would write (IMPORT-8): a date written differently is
     * no change, while a correction of capitals is one, as in Load one object.
     */
    @IsTest
    static void aReimportComparesTypedValuesAndAppliesCapitals() {
        System.runAs(TestUsers.admin()) {
            List<Contact> existing = new List<Contact>();
            List<Map<String, String>> values = new List<Map<String, String>>();
            for (Integer i = 0; i < 200; i++) {
                existing.add(
                    new Contact(
                        FirstName = 'Person' + i,
                        LastName = 'Surname' + i,
                        Email = 'person' + i + '@example.org',
                        MailingCity = 'Portland',
                        Birthdate = Date.newInstance(1980, 1, 5),
                        Title = Math.mod(i, 2) == 0 ? 'treasurer' : 'Treasurer'
                    )
                );
                values.add(bornRow(i, '1980-1-5', 'Treasurer'));
            }
            insert existing;
            givenWithBirthdateAndTitle(values);

            Test.startTest();
            ImportRowProcessor.Outcome outcome = run(false);
            Test.stopTest();

            Assert.areEqual(100, outcome.updated, 'Only the capitals corrections update.');
            Assert.areEqual(100, outcome.matched, 'The same date, written another way, is none.');
            for (Contact person : [SELECT Title FROM Contact]) {
                // Compared in Apex: SOQL compares text without regard to capitals.
                Assert.isTrue('Treasurer'.equals(person.Title), 'Corrected: ' + person.Title);
            }
        }
    }

    @IsTest
    static void splitsAFullNameColumn() {
        System.runAs(TestUsers.admin()) {
            TestDataFactory.defaultSettings();
            ImportMapping mapping = new ImportMapping();
            mapping.columns.add(new ImportMapping.Column('Donor', 'Contact1.FullName'));
            mapping.columns.add(new ImportMapping.Column('Email', 'Contact1.Email'));
            template = ImportTestDataFactory.template(
                mapping.serialize(),
                ImportTemplateService.RULE_EMAIL
            );
            batch = ImportTestDataFactory.batch(template);
            ImportTestDataFactory.rows(
                batch,
                new List<Map<String, String>>{
                    new Map<String, String>{
                        'Donor' => 'Ana Ramirez',
                        'Email' => 'ana@example.org'
                    },
                    new Map<String, String>{
                        'Donor' => 'Okafor, Ben',
                        'Email' => 'ben@example.org'
                    }
                }
            );

            Test.startTest();
            run(false);
            Test.stopTest();

            Map<String, Contact> byEmail = new Map<String, Contact>();
            for (Contact record : [SELECT FirstName, LastName, Email FROM Contact]) {
                byEmail.put(record.Email, record);
            }
            Assert.areEqual(
                'Ana',
                byEmail.get('ana@example.org').FirstName,
                'First name from "Ana Ramirez".'
            );
            Assert.areEqual(
                'Ramirez',
                byEmail.get('ana@example.org').LastName,
                'And the last name.'
            );
            Assert.areEqual(
                'Ben',
                byEmail.get('ben@example.org').FirstName,
                'The comma form reads too.'
            );
            Assert.areEqual('Okafor', byEmail.get('ben@example.org').LastName, 'Surname first.');
        }
    }

    @IsTest
    static void saysInTheRunLogWhatItCouldNotLoad() {
        System.runAs(TestUsers.admin()) {
            TestDataFactory.defaultSettings();
            ImportMapping mapping = new ImportMapping();
            mapping.columns.add(new ImportMapping.Column('Email', 'Contact1.Email'));
            mapping.columns.add(new ImportMapping.Column('Last Name', 'Contact1.LastName'));
            mapping.columns.add(new ImportMapping.Column('Amount', 'Gift.Amount__c'));
            template = ImportTestDataFactory.template(
                mapping.serialize(),
                ImportTemplateService.RULE_EMAIL
            );
            batch = ImportTestDataFactory.batch(template);
            ImportTestDataFactory.rows(
                batch,
                new List<Map<String, String>>{
                    new Map<String, String>{
                        'Email' => 'ana@example.org',
                        'Last Name' => 'Ramirez',
                        'Amount' => '100'
                    }
                }
            );

            // An org with Giving deployed has a processor; this test is about one without.
            ImportEntityProcessors.noneForTest = true;

            Test.startTest();
            ImportRowProcessor.Outcome outcome = run(false);
            Test.stopTest();

            Assert.areEqual(1, outcome.created, 'The person still loaded.');
            Assert.isFalse(
                outcome.notes.isEmpty(),
                'And the run log says the gift column did not.'
            );
        }
    }

    @IsTest
    static void anUnreadableStagedRowIsRejectedNotThrown() {
        System.runAs(TestUsers.admin()) {
            given(
                new List<Map<String, String>>{
                    ImportTestDataFactory.donorRow('Ana', 'Ramirez', 'ana@example.org', null)
                }
            );
            List<Import_Row__c> rows = ImportTestDataFactory.reload(batch.Id);
            rows[0].Raw_Values_JSON__c = 'not JSON at all';
            update rows;

            Test.startTest();
            ImportRowProcessor.Outcome outcome = run(false);
            Test.stopTest();

            Assert.areEqual(1, outcome.rejected, 'The row is rejected.');
            Assert.areEqual(
                Label.Core_Import_ErrorRowUnreadable,
                ImportTestDataFactory.reload(batch.Id)[0].Error_Message__c,
                'With a reason, rather than an unhandled exception.'
            );
        }
    }

    @IsTest
    static void anEmptyChunkDoesNothing() {
        System.runAs(TestUsers.admin()) {
            TestDataFactory.defaultSettings();
            template = ImportTestDataFactory.template(
                ImportTestDataFactory.donorMapping(),
                ImportTemplateService.RULE_EMAIL
            );
            batch = ImportTestDataFactory.batch(template);
            Test.startTest();
            ImportRowProcessor.Outcome outcome = ImportRowProcessor.process(
                batch,
                template,
                ImportMapping.parse(template.Column_Mapping_JSON__c),
                new List<Import_Row__c>(),
                false
            );
            Test.stopTest();
            Assert.areEqual(0, outcome.created, 'Nothing in, nothing out, no exception.');
        }
    }

    // -------------------------------------------------------------------------------------
    // A row with two people in it
    // -------------------------------------------------------------------------------------

    /**
     * The couple mapping: a household name, and two people each carrying both a Name column
     * and the name parts.
     *
     * One mapping serves both ways of storing a person. Contact has no writable Name, so the
     * Name column is skipped there and the parts are used; an org that stores people as
     * accounts has Name and, unless Person Accounts are actually switched on in the org
     * running this test, none of the parts, so it takes Name and reports the rest in the run
     * log. Nothing here names a Person Account field at compile time (ADR-0009).
     */
    private static String coupleMapping() {
        ImportMapping mapping = new ImportMapping();
        mapping.columns.add(new ImportMapping.Column('Household', 'Household.Name'));
        mapping.columns.add(new ImportMapping.Column('Person 1', 'Contact1.Name'));
        mapping.columns.add(new ImportMapping.Column('First 1', 'Contact1.FirstName'));
        mapping.columns.add(new ImportMapping.Column('Last 1', 'Contact1.LastName'));
        mapping.columns.add(new ImportMapping.Column('Person 2', 'Contact2.Name'));
        mapping.columns.add(new ImportMapping.Column('First 2', 'Contact2.FirstName'));
        mapping.columns.add(new ImportMapping.Column('Last 2', 'Contact2.LastName'));
        return mapping.serialize();
    }

    /** One row naming a household and the two people who live in it. */
    private static void givenACoupleOnOneRow(String personMode) {
        template = ImportTestDataFactory.template(
            coupleMapping(),
            ImportTemplateService.RULE_EMAIL
        );
        template.Person_Mode__c = personMode;
        update template;
        batch = ImportTestDataFactory.batch(template);
        ImportTestDataFactory.rows(
            batch,
            new List<Map<String, String>>{
                new Map<String, String>{
                    'Household' => 'The Garcia Lee Household',
                    'Person 1' => 'Maria Garcia',
                    'First 1' => 'Maria',
                    'Last 1' => 'Garcia',
                    'Person 2' => 'Wei Lee',
                    'First 2' => 'Wei',
                    'Last 2' => 'Lee'
                }
            }
        );
    }

    /** The households this org has, which is the number a two person row has to produce. */
    private static List<Account> households() {
        return [
            SELECT Id, Name, Custom_Name__c, Member_Count__c
            FROM Account
            WHERE RecordTypeId = :HouseholdService.householdRecordTypeId()
            WITH SYSTEM_MODE
        ];
    }

    /**
     * Junction mode, which is the mode a Nonprofit Cloud org is put into on its first day.
     *
     * The household itself is made by the household trigger for the first person (ADR-0037);
     * what this asserts is that the second person is joined to that one rather than being
     * given a household of their own, and that the join is a membership row, because that is
     * what membership means in this mode.
     */
    @IsTest
    static void aRowWithTwoPeopleMakesOneHouseholdInJunctionMode() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);
            givenACoupleOnOneRow(ImportTemplateService.PERSON_MODE_CONTACTS);

            Test.startTest();
            run(false);
            Test.stopTest();

            List<Account> households = households();
            Assert.areEqual(1, households.size(), 'One row of two people is one household.');
            Assert.areEqual(
                'The Garcia Lee Household',
                households[0].Name,
                'Named from the row, which is what the household column on the row means.'
            );
            Assert.isTrue(
                households[0].Custom_Name__c,
                'And named by hand, so naming leaves it be.'
            );
            Assert.areEqual(
                2,
                [
                    SELECT COUNT()
                    FROM Household_Member__c
                    WHERE Household__c = :households[0].Id AND Contact__c != NULL
                ],
                'Both people are joined to it by a membership row, which is what junction mode means.'
            );
            Assert.areEqual(2, [SELECT COUNT() FROM Contact], 'And there are two people, not one.');
        }
    }

    /**
     * The same row in contact mode, where membership is the person's own account reference.
     * The behaviour an administrator sees is identical, which is the point of the service
     * the importer joins people through.
     */
    @IsTest
    static void aRowWithTwoPeopleMakesOneHouseholdInContactMode() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            givenACoupleOnOneRow(ImportTemplateService.PERSON_MODE_CONTACTS);

            Test.startTest();
            run(false);
            Test.stopTest();

            List<Account> households = households();
            Assert.areEqual(1, households.size(), 'One row of two people is still one household.');
            Assert.areEqual(
                'The Garcia Lee Household',
                households[0].Name,
                'Named from the row here too.'
            );
            Assert.isTrue(households[0].Custom_Name__c, 'And named by hand.');
            Assert.areEqual(
                2,
                [SELECT COUNT() FROM Contact WHERE AccountId = :households[0].Id],
                'Both people point at it, which is what contact mode means.'
            );
            Assert.areEqual(
                2,
                households[0].Member_Count__c,
                'And the household counts both of them.'
            );
        }
    }

    /**
     * The configuration the product recommends: people stored as accounts, membership in
     * junction mode. This is the half the old importer could never do, because it joined the
     * second person by writing an account reference and skipped that entirely for a person
     * stored as an account.
     *
     * What this test substitutes and what it does not: in an org with person accounts,
     * nothing; the people are real person accounts. On a Platform only org, which has no
     * person accounts to make (ADR-0013), the org shape is declared, through
     * `OrgShapeDetector.overrideShape` and `PersonRecordSelector.personRecordOverride`, and
     * the person details are declared because that org has no person name fields to hold
     * them. The records, the membership rows and the household are real in both.
     */
    @IsTest
    static void aRowWithTwoPeopleMakesOneHouseholdWherePeopleAreStoredAsAccounts() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);
            if (!OrgShapeDetector.detect().hasPersonAccounts) {
                HouseholdService.personAccountOverride = true;
                PersonRecordSelector.personRecordOverride = true;
                PersonRecordSelector.personOverridesByName = new Map<String, HouseholdService.Person>{
                    'Maria Garcia' => HouseholdTestDataFactory.person(
                        'Ms.',
                        'Maria',
                        'Garcia',
                        'Head'
                    ),
                    'Wei Lee' => HouseholdTestDataFactory.person('Mr.', 'Wei', 'Lee', null)
                };
                OrgShapeDetector.OrgShape shape = new OrgShapeDetector.OrgShape();
                shape.hasPersonAccounts = true;
                shape.personAccountRecordTypeIds = new Set<Id>{ organizationRecordTypeId() };
                OrgShapeDetector.overrideShape = shape;
            } else if (PersonAccountTestShape.skipReason() != null) {
                // Person accounts, but none of their record types is given to the running
                // user: skipReason fails the test there, naming the script that fixes the
                // org (PEOPLE-29), so this return is never reached in a person account org.
                return;
            }
            givenACoupleOnOneRow(ImportTemplateService.PERSON_MODE_PERSON_ACCOUNTS);

            Test.startTest();
            run(false);
            Test.stopTest();

            List<Account> households = households();
            Assert.areEqual(
                1,
                households.size(),
                'A couple stored as accounts is one household, not two and not none.'
            );
            Assert.areEqual(
                'The Garcia Lee Household',
                households[0].Name,
                'Named from the row, whichever object holds the people.'
            );
            Assert.isTrue(households[0].Custom_Name__c, 'And named by hand.');
            List<Household_Member__c> memberships = [
                SELECT Account__c
                FROM Household_Member__c
                WHERE Household__c = :households[0].Id AND Account__c != NULL
            ];
            Assert.areEqual(2, memberships.size(), 'Both people are joined to it.');
            Set<Id> members = new Set<Id>();
            for (Household_Member__c membership : memberships) {
                members.add(membership.Account__c);
            }
            Assert.areEqual(
                2,
                [SELECT COUNT() FROM Account WHERE Id IN :members AND Name != NULL],
                'And they are two different people.'
            );
            Import_Row__c row = ImportTestDataFactory.reload(batch.Id)[0];
            Assert.areEqual(
                households[0].Id,
                row.Household__c,
                'The row records the household it resolved to.'
            );
        }
    }

    /**
     * A row that names only a second person, with nobody for them to join, still gets a
     * household of its own: the two pass save must not leave that person behind.
     */
    @IsTest
    static void aSecondPersonWithNobodyToJoinStillGetsAHousehold() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);
            template = ImportTestDataFactory.template(
                coupleMapping(),
                ImportTemplateService.RULE_EMAIL
            );
            batch = ImportTestDataFactory.batch(template);
            ImportTestDataFactory.rows(
                batch,
                new List<Map<String, String>>{
                    new Map<String, String>{ 'First 2' => 'Wei', 'Last 2' => 'Lee' }
                }
            );

            Test.startTest();
            run(false);
            Test.stopTest();

            Assert.areEqual(1, [SELECT COUNT() FROM Contact], 'The person was created.');
            Assert.areEqual(1, households().size(), 'And given a household of their own.');
            Assert.areEqual(
                batch.Id,
                [SELECT Created_By_Import_Batch__c FROM Account WHERE Id = :households()[0].Id]
                .Created_By_Import_Batch__c,
                'Which carries the import tag, because the import made it.'
            );
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Household_Member__c],
                'Joined to it by one membership row.'
            );
        }
    }

    /**
     * An update to a person the import matched is journaled with the value it replaced, so
     * an undo can put it back (R-IJ3). A record the import created is not journaled: undoing
     * it deletes it.
     */
    @IsTest
    static void anUpdateToAMatchedPersonIsJournaledWithTheValueItReplaced() {
        System.runAs(TestUsers.admin()) {
            TestDataFactory.defaultSettings();
            insert new Contact(
                FirstName = 'Ana',
                LastName = 'Ramirez',
                Email = 'ana@example.org',
                MailingCity = 'Salem'
            );
            given(
                new List<Map<String, String>>{
                    ImportTestDataFactory.donorRow('Ana', 'Ramirez', 'ana@example.org', null)
                }
            );
            Test.startTest();
            run(false);
            Test.stopTest();

            List<Import_Journal__c> pages = ImportJournalService.pages(
                batch.Id,
                ImportJournalService.PHASE_COMMIT,
                10
            );
            Assert.areEqual(1, pages.size(), 'The chunk wrote one journal page.');
            List<Map<String, Object>> entries = ImportJournalService.entries(pages[0]);
            Assert.areEqual(1, entries.size(), 'One record was updated.');
            Map<String, Object> fields = (Map<String, Object>) entries[0].get('fields');
            Map<String, Object> city = (Map<String, Object>) fields.get('MailingCity');
            Assert.areEqual('Salem', city.get('before'), 'The value the import replaced is kept.');
            Assert.areEqual('Portland', city.get('after'), 'Beside the value it wrote.');
            Assert.areEqual(2, entries[0].get('row'), 'And the file row that wrote it.');
            Assert.isNull(
                [
                    SELECT Created_By_Import_Batch__c
                    FROM Account
                    WHERE Id IN (SELECT AccountId FROM Contact)
                    LIMIT 1
                ]
                .Created_By_Import_Batch__c,
                'The household an existing person already had is never tagged, so an undo keeps it.'
            );
        }
    }

    /** Renaming a household the import did not create is journaled with the old name. */
    @IsTest
    static void renamingAnExistingHouseholdIsJournaledWithTheOldName() {
        System.runAs(TestUsers.admin()) {
            TestDataFactory.defaultSettings();
            insert new Contact(FirstName = 'Ana', LastName = 'Ramirez', Email = 'ana@example.org');
            Account household = [
                SELECT Id, Name, Custom_Name__c
                FROM Account
                WHERE Id IN (SELECT AccountId FROM Contact)
                LIMIT 1
            ];
            ImportMapping mapping = new ImportMapping();
            mapping.columns.add(new ImportMapping.Column('Household', 'Household.Name'));
            mapping.columns.add(new ImportMapping.Column('First Name', 'Contact1.FirstName'));
            mapping.columns.add(new ImportMapping.Column('Last Name', 'Contact1.LastName'));
            mapping.columns.add(new ImportMapping.Column('Email', 'Contact1.Email'));
            template = ImportTestDataFactory.template(
                mapping.serialize(),
                ImportTemplateService.RULE_EMAIL
            );
            batch = ImportTestDataFactory.batch(template);
            ImportTestDataFactory.rows(
                batch,
                new List<Map<String, String>>{
                    new Map<String, String>{
                        'Household' => 'Ana and Luis Ramirez',
                        'First Name' => 'Ana',
                        'Last Name' => 'Ramirez',
                        'Email' => 'ana@example.org'
                    }
                }
            );

            Test.startTest();
            run(false);
            Test.stopTest();

            Account renamed = [
                SELECT Name, Created_By_Import_Batch__c
                FROM Account
                WHERE Id = :household.Id
            ];
            Assert.areEqual('Ana and Luis Ramirez', renamed.Name, 'The household was renamed.');
            Assert.isNull(renamed.Created_By_Import_Batch__c, 'But not claimed by the import.');
            Map<String, Object> entry = ImportJournalService.entries(
                ImportJournalService.pages(batch.Id, ImportJournalService.PHASE_COMMIT, 10)[0]
            )[0];
            Map<String, Object> name = (Map<String, Object>) ((Map<String, Object>) entry.get(
                    'fields'
                ))
                .get('Name');
            Assert.areEqual(
                String.valueOf(household.Id),
                (String) entry.get('id'),
                'The entry names the household.'
            );
            Assert.areEqual(household.Name, name.get('before'), 'With the name it had before.');
        }
    }

    private static Id organizationRecordTypeId() {
        return AccountKindsTestData.organizationRecordTypeId();
    }

    /** Two hundred rows, each naming its own organization; the last has no last name. */
    private static List<Map<String, String>> organizationRows() {
        List<Map<String, String>> values = new List<Map<String, String>>();
        for (Integer i = 0; i < 199; i++) {
            values.add(
                ImportTestDataFactory.donorRow(
                    'Person' + i,
                    'Surname' + i,
                    'person' + i + '@example.org',
                    'Employer ' + i
                )
            );
        }
        values.add(
            ImportTestDataFactory.donorRow('Lonely', '', 'lonely@example.org', 'Lonely Employer')
        );
        return values;
    }

    /**
     * A row rejected for its person creates no organization (IMPORT-3, R-IB1), so the preview
     * and the commit agree, and re-importing the fixed row creates it once.
     */
    @IsTest
    static void aRowRejectedForItsPersonCreatesNoOrganization() {
        System.runAs(TestUsers.admin()) {
            given(organizationRows());

            Test.startTest();
            ImportRowProcessor.Outcome preview = run(true);
            ImportRowProcessor.Outcome committed = run(false);
            Test.stopTest();

            Assert.areEqual(1, preview.rejected, 'The preview rejects the row.');
            Assert.areEqual(preview.created, committed.created, 'The commit does what it showed.');
            Assert.areEqual(preview.rejected, committed.rejected);
            Id organizationType = organizationRecordTypeId();
            Assert.areEqual(
                199,
                [SELECT COUNT() FROM Account WHERE RecordTypeId = :organizationType],
                'One organization per clean row.'
            );
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Account WHERE Name = 'Lonely Employer'],
                'None for the rejected row.'
            );
            Import_Row__c rejected = ImportTestDataFactory.reload(batch.Id)[199];
            Assert.areEqual(Label.Core_Import_ErrorLastNameMissing, rejected.Error_Message__c);
            Assert.isNull(rejected.Organization__c, 'Pointing at nothing it did not create.');
        }
    }

    /**
     * The heaviest chunk (IMPORT-9): two hundred rows, two people each, an organization and a
     * household name, committed in one transaction within stated budgets. The budgets leave
     * room for an org's own automation; an org run reports the real figures.
     */
    @IsTest
    static void aFullChunkOfCouplesWithOrganizationsStaysWithinBudget() {
        System.runAs(TestUsers.admin()) {
            TestDataFactory.defaultSettings();
            ImportMapping mapping = new ImportMapping();
            mapping.columns.add(new ImportMapping.Column('Household', 'Household.Name'));
            mapping.columns.add(new ImportMapping.Column('First 1', 'Contact1.FirstName'));
            mapping.columns.add(new ImportMapping.Column('Last 1', 'Contact1.LastName'));
            mapping.columns.add(new ImportMapping.Column('Email 1', 'Contact1.Email'));
            mapping.columns.add(new ImportMapping.Column('First 2', 'Contact2.FirstName'));
            mapping.columns.add(new ImportMapping.Column('Last 2', 'Contact2.LastName'));
            mapping.columns.add(new ImportMapping.Column('Email 2', 'Contact2.Email'));
            mapping.columns.add(new ImportMapping.Column('Employer', 'Organization.Name'));
            template = ImportTestDataFactory.template(
                mapping.serialize(),
                ImportTemplateService.RULE_EMAIL
            );
            batch = ImportTestDataFactory.batch(template);
            List<Map<String, String>> values = new List<Map<String, String>>();
            for (Integer i = 0; i < 200; i++) {
                values.add(
                    new Map<String, String>{
                        'Household' => 'The Family ' + i,
                        'First 1' => 'Ana' + i,
                        'Last 1' => 'Family' + i,
                        'Email 1' => 'ana' +
                        i +
                        '@example.org',
                        'First 2' => 'Ben' + i,
                        'Last 2' => 'Family' + i,
                        'Email 2' => 'ben' +
                        i +
                        '@example.org',
                        'Employer' => 'Employer ' + Math.mod(i, 20)
                    }
                );
            }
            ImportTestDataFactory.rows(batch, values);

            Test.startTest();
            ImportRowProcessor.Outcome outcome = run(false);
            Integer queries = Limits.getQueries();
            Integer statements = Limits.getDmlStatements();
            Integer cpu = Limits.getCpuTime();
            Test.stopTest();

            Assert.areEqual(200, outcome.created, 'Every row loaded: ' + outcome.notes);
            Assert.areEqual(400, [SELECT COUNT() FROM Contact], 'Two people a row.');
            Id organizationType = organizationRecordTypeId();
            Assert.areEqual(
                20,
                [SELECT COUNT() FROM Account WHERE RecordTypeId = :organizationType],
                'Each employer once.'
            );
            Assert.isTrue(queries <= 60, 'Queries within budget: ' + queries);
            Assert.isTrue(statements <= 60, 'DML statements within budget: ' + statements);
            Assert.isTrue(cpu <= 8000, 'CPU within budget (ms): ' + cpu);
        }
    }

    // -------------------------------------------------------------------------------------
    // The entity processor seam (R-IR6, R-IR7)
    // -------------------------------------------------------------------------------------

    /**
     * Stands in for a dependent package's processor. A row's Gift Amount says what it does:
     * "reject" rejects the row, "match" matches it, anything else creates. It records what it
     * was handed so the tests can see the rows as the processor saw them.
     */
    private class StubProcessor implements ImportEntityProcessor {
        Boolean throwOnResolve = false;
        Boolean sawDryRun;
        Map<Id, Import_Row__c> seen = new Map<Id, Import_Row__c>();
        Map<Id, Map<String, Map<String, String>>> seenEntities;

        public List<ImportMapping.Target> targets() {
            return new List<ImportMapping.Target>();
        }

        public ImportEntityResult resolve(
            Import_Batch__c batch,
            Import_Template__c template,
            List<Import_Row__c> rows,
            Map<Id, Map<String, Map<String, String>>> entitiesByRowId,
            Boolean dryRun
        ) {
            if (throwOnResolve) {
                // Something saved before the failure, as a gift would be, must not survive it.
                insert as user new Account(Name = 'Saved before the failure');
                throw new IllegalArgumentException('stub failed');
            }
            sawDryRun = dryRun;
            seenEntities = entitiesByRowId;
            Decimal total = 0;
            for (Import_Row__c row : rows) {
                seen.put(row.Id, row.clone(true, true));
                Map<String, String> gift = entitiesByRowId.get(row.Id).get('Gift');
                String amount = gift == null ? null : gift.get('Amount__c');
                if (amount != null && amount.isNumeric()) {
                    total += Decimal.valueOf(amount);
                }
                if (row.Status__c == ImportRowProcessor.STATUS_REJECTED) {
                    continue;
                }
                if (amount == 'reject') {
                    row.Status__c = ImportRowProcessor.STATUS_REJECTED;
                    row.Error_Message__c = 'No fund named Nowhere.';
                } else if (amount == 'match') {
                    row.Status__c = ImportRowProcessor.STATUS_MATCHED;
                } else {
                    row.Status__c = ImportRowProcessor.STATUS_CREATED;
                }
            }
            return new ImportEntityResult('stub note', total);
        }

        public List<Schema.SObjectType> taggedObjects() {
            return new List<Schema.SObjectType>();
        }

        public Map<Id, String> reasonsToKeep(
            Id batchId,
            Schema.SObjectType type,
            Set<Id> recordIds
        ) {
            return new Map<Id, String>();
        }
    }

    private static void givenGiftRows(List<Map<String, String>> values) {
        TestDataFactory.defaultSettings();
        ImportMapping mapping = new ImportMapping();
        mapping.columns.add(new ImportMapping.Column('Email', 'Contact1.Email'));
        mapping.columns.add(new ImportMapping.Column('Last Name', 'Contact1.LastName'));
        mapping.columns.add(new ImportMapping.Column('Amount', 'Gift.Amount__c'));
        template = ImportTestDataFactory.template(
            mapping.serialize(),
            ImportTemplateService.RULE_EMAIL
        );
        batch = ImportTestDataFactory.batch(template);
        ImportTestDataFactory.rows(batch, values);
    }

    private static Map<String, String> giftRow(String email, String lastName, String amount) {
        return new Map<String, String>{
            'Email' => email,
            'Last Name' => lastName,
            'Amount' => amount
        };
    }

    private static Map<String, Import_Row__c> rowsByEmail() {
        Map<String, Import_Row__c> result = new Map<String, Import_Row__c>();
        for (Import_Row__c row : ImportTestDataFactory.reload(batch.Id)) {
            Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(
                row.Raw_Values_JSON__c
            );
            result.put((String) raw.get('Email'), row);
        }
        return result;
    }

    @IsTest
    static void theProcessorSeesThePeopleCoreResolved() {
        System.runAs(TestUsers.admin()) {
            givenGiftRows(
                new List<Map<String, String>>{ giftRow('ana@example.org', 'Ramirez', '50') }
            );
            StubProcessor stub = new StubProcessor();
            ImportEntityProcessors.processorOverride = stub;

            Test.startTest();
            ImportRowProcessor.Outcome outcome = run(false);
            Test.stopTest();

            Id contactId = [SELECT Id FROM Contact LIMIT 1].Id;
            Import_Row__c seen = stub.seen.values()[0];
            Assert.areEqual(
                contactId,
                seen.Contact_1__c,
                'The row carried the donor when offered.'
            );
            Assert.isNotNull(seen.Household__c, 'And the household.');
            Assert.areEqual(
                ImportRowProcessor.STATUS_PENDING,
                seen.Status__c,
                'Pending, not final.'
            );
            Assert.areEqual(
                '50',
                stub.seenEntities.get(seen.Id).get('Gift').get('Amount__c'),
                'With its gift values grouped by entity.'
            );
            Assert.isFalse(stub.sawDryRun, 'A commit is not a dry run.');
            Assert.areEqual(1, outcome.created, 'The row counts once.');
            Assert.isTrue(
                outcome.fileAmount == 50,
                'The amount read is handed back for control totals.'
            );
            Assert.isTrue(
                outcome.notes.contains('stub note'),
                'The processor note is in the run log.'
            );
            Assert.isFalse(
                outcome.notes.contains(
                    String.format(
                        Label.Core_Import_LogEntitiesNotLoaded,
                        new List<String>{ 'Gift' }
                    )
                ),
                'Nothing says the gift columns were not loaded when a processor loaded them.'
            );
        }
    }

    @IsTest
    static void aRejectionByTheProcessorWinsAndARowCoreRejectedStaysAlone() {
        System.runAs(TestUsers.admin()) {
            givenGiftRows(
                new List<Map<String, String>>{
                    giftRow('ana@example.org', 'Ramirez', 'reject'),
                    giftRow('ben@example.org', 'Okafor', 'match'),
                    giftRow('cy@example.org', 'Lee', '20'),
                    giftRow('', '', '10')
                }
            );
            StubProcessor stub = new StubProcessor();
            ImportEntityProcessors.processorOverride = stub;

            Test.startTest();
            ImportRowProcessor.Outcome outcome = run(false);
            Test.stopTest();

            Map<String, Import_Row__c> rows = rowsByEmail();
            Import_Row__c rejected = rows.get('ana@example.org');
            Assert.areEqual(
                ImportRowProcessor.STATUS_REJECTED,
                rejected.Status__c,
                'Rejection wins.'
            );
            Assert.areEqual(
                'No fund named Nowhere.',
                rejected.Error_Message__c,
                'With its reason.'
            );
            Assert.areEqual(
                ImportRowProcessor.STATUS_CREATED,
                rows.get('ben@example.org').Status__c,
                'A match leaves what Core did: it created Ben.'
            );
            Assert.areEqual(
                ImportRowProcessor.STATUS_CREATED,
                rows.get('cy@example.org').Status__c,
                'A creation counts the row created.'
            );
            Import_Row__c nobody = rows.get('');
            Assert.areEqual(
                ImportRowProcessor.STATUS_REJECTED,
                stub.seen.get(nobody.Id).Status__c,
                'Core rejected the row before offering it.'
            );
            Assert.areEqual(
                Label.Core_Import_ErrorRowIdentifiesNobody,
                nobody.Error_Message__c,
                'And its own reason stays.'
            );
            Assert.areEqual(2, outcome.rejected, 'Two rows rejected.');
            Assert.areEqual(2, outcome.created, 'Two created.');
            Assert.isTrue(
                outcome.fileAmount == 30,
                'Every readable amount counts, rejected or not.'
            );
        }
    }

    /**
     * A processor that throws part way leaves nothing of its own behind, and every row that
     * carried its columns is rejected with the reason, not reported loaded. The people stay,
     * on the row, and a row without its columns keeps Core's outcome.
     */
    @IsTest
    static void aProcessorThatThrowsIsRolledBackAndItsRowsRejected() {
        System.runAs(TestUsers.admin()) {
            List<Map<String, String>> values = new List<Map<String, String>>();
            for (Integer i = 0; i < 199; i++) {
                values.add(giftRow('donor' + i + '@example.org', 'Surname' + i, '50'));
            }
            values.add(giftRow('nogift@example.org', 'Nogift', ''));
            givenGiftRows(values);
            StubProcessor stub = new StubProcessor();
            stub.throwOnResolve = true;
            ImportEntityProcessors.processorOverride = stub;

            Test.startTest();
            ImportRowProcessor.Outcome outcome = run(false);
            Test.stopTest();

            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Account WHERE Name = 'Saved before the failure'],
                'What the processor saved before it failed was rolled back.'
            );
            Assert.areEqual(200, [SELECT COUNT() FROM Contact], 'The people stay saved.');
            Assert.areEqual(199, outcome.rejected, 'Every row with a gift is rejected.');
            Assert.areEqual(1, outcome.created, 'The row without one keeps its outcome.');
            Assert.isTrue(outcome.notes.contains('stub failed'), 'The run log says why.');
            Map<String, Import_Row__c> rows = rowsByEmail();
            Import_Row__c rejected = rows.get('donor0@example.org');
            Assert.areEqual(ImportRowProcessor.STATUS_REJECTED, rejected.Status__c);
            Assert.areEqual(
                String.format(
                    Label.Core_Import_ErrorEntitiesNotLoaded,
                    new List<String>{ 'Gift', 'stub failed' }
                ),
                rejected.Error_Message__c,
                'The row says its gift was not loaded, and why.'
            );
            Assert.isNotNull(rejected.Contact_1__c, 'And still points at its person.');
            Assert.areEqual(
                ImportRowProcessor.STATUS_CREATED,
                rows.get('nogift@example.org').Status__c,
                'Nothing was lost for a row with no gift.'
            );
        }
    }

    /** A staged row that cannot be saved is said, in the run log, not left silently stale. */
    @IsTest
    static void aRowThatCannotBeSavedIsReported() {
        System.runAs(TestUsers.admin()) {
            givenGiftRows(
                new List<Map<String, String>>{
                    giftRow('ana@example.org', 'Ramirez', '50'),
                    giftRow('ben@example.org', 'Okafor', '50')
                }
            );
            List<Import_Row__c> rows = ImportTestDataFactory.reload(batch.Id);
            delete rows[1];
            for (Import_Row__c row : rows) {
                row.Status__c = ImportRowProcessor.STATUS_MATCHED;
            }
            ImportRowProcessor.Outcome outcome = new ImportRowProcessor.Outcome();

            Test.startTest();
            ImportRowProcessor.saveRows(rows, outcome, 'ImportRowProcessorTest');
            Test.stopTest();

            Assert.areEqual(1, outcome.notes.size(), 'One line for the chunk: ' + outcome.notes);
            String line = new List<String>(outcome.notes)[0];
            Assert.isTrue(line.startsWith('1 '), 'It counts the row that failed: ' + line);
            Assert.isTrue(line.contains(' 3: '), 'And names it by its file row: ' + line);
            Assert.areEqual(
                ImportRowProcessor.STATUS_MATCHED,
                ImportTestDataFactory.reload(batch.Id)[0].Status__c,
                'The other row saved.'
            );
        }
    }

    @IsTest
    static void aDryRunOffersTheRowsWithoutWriting() {
        System.runAs(TestUsers.admin()) {
            givenGiftRows(
                new List<Map<String, String>>{ giftRow('ana@example.org', 'Ramirez', '50') }
            );
            StubProcessor stub = new StubProcessor();
            ImportEntityProcessors.processorOverride = stub;

            Test.startTest();
            ImportRowProcessor.Outcome outcome = run(true);
            Test.stopTest();

            Assert.isTrue(stub.sawDryRun, 'The processor is told it is a dry run.');
            Assert.areEqual(0, [SELECT COUNT() FROM Contact], 'Nothing was written.');
            Assert.areEqual(1, outcome.created, 'The row would create.');
        }
    }
}
