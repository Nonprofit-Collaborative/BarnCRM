/**
 * The Batch Apex wrapper: a whole run end to end, and the promise that a chunk which dies
 * does not take the run with it.
 */
@IsTest(critical=true)
private class ImportProcessorBatchTest {
    @TestSetup
    static void setUp() {
        System.runAs(TestUsers.admin()) {
            TestDataFactory.defaultSettings();
        }
    }

    private static Import_Batch__c staged(Integer howManyRows) {
        Import_Template__c template = ImportTestDataFactory.template(
            ImportTestDataFactory.donorMapping(),
            ImportTemplateService.RULE_EMAIL
        );
        Import_Batch__c batch = ImportTestDataFactory.batch(template);
        List<Map<String, String>> values = new List<Map<String, String>>();
        for (Integer i = 0; i < howManyRows; i++) {
            values.add(
                ImportTestDataFactory.donorRow(
                    'Person' + i,
                    'Surname' + i,
                    'person' + i + '@example.org',
                    null
                )
            );
        }
        ImportTestDataFactory.rows(batch, values);
        return batch;
    }

    @IsTest
    static void aDryRunFinishesWithCountsAndWritesNothing() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c batch = staged(3);

            Test.startTest();
            Database.executeBatch(new ImportProcessorBatch(batch.Id, true), 200);
            Test.stopTest();

            Import_Batch__c after = ImportBatchSelector.selectById(batch.Id);
            Assert.areEqual(
                ImportBatchService.STATUS_DRY_RUN_COMPLETE,
                after.Status__c,
                'The run ended ready for a commit.'
            );
            Assert.areEqual(3, after.Rows_Created__c, 'Three rows would create somebody.');
            Assert.areEqual(0, [SELECT COUNT() FROM Contact], 'And nobody was actually created.');
            Assert.isTrue(
                after.Run_Log__c.contains(Label.Core_Import_LogDryRunHeader),
                'The run log says plainly that nothing was written.'
            );
        }
    }

    @IsTest
    static void aCommitLoadsTheRowsAndReportsWhatItDid() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c batch = staged(3);
            batch.Status__c = ImportBatchService.STATUS_DRY_RUN_COMPLETE;
            update batch;

            Test.startTest();
            Database.executeBatch(new ImportProcessorBatch(batch.Id, false), 200);
            Test.stopTest();

            Import_Batch__c after = ImportBatchSelector.selectById(batch.Id);
            Assert.areEqual(ImportBatchService.STATUS_COMPLETE, after.Status__c, 'It completed.');
            Assert.areEqual(3, after.Rows_Created__c, 'Three rows created somebody.');
            Assert.areEqual(3, [SELECT COUNT() FROM Contact], 'And three people exist.');
            Assert.isNotNull(after.Completed_At__c, 'With a finish time on the record.');
        }
    }

    @IsTest
    static void honorsTheChunkSizeAsTheBatchScope() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c batch = staged(5);
            batch.Chunk_Size__c = 2;
            batch.Status__c = ImportBatchService.STATUS_DRY_RUN_COMPLETE;
            update batch;

            // Two rows per chunk, which is what the org's setting asks for (R-IB2). A test may run
            // only one chunk of a real batch job, so the job is driven here the way the platform
            // drives it: its own query, then one execute per chunk of that size, then finish.
            ImportProcessorBatch job = new ImportProcessorBatch(batch.Id, false);
            Integer chunkSize = batch.Chunk_Size__c.intValue();
            List<List<Import_Row__c>> chunks = new List<List<Import_Row__c>>();
            Database.QueryLocatorIterator rows = job.start(null).iterator();
            while (rows.hasNext()) {
                if (chunks.isEmpty() || chunks[chunks.size() - 1].size() == chunkSize) {
                    chunks.add(new List<Import_Row__c>());
                }
                chunks[chunks.size() - 1].add((Import_Row__c) rows.next());
            }

            Test.startTest();
            for (List<Import_Row__c> chunk : chunks) {
                job.execute(null, chunk);
            }
            job.finish(null);
            Test.stopTest();

            Assert.areEqual(3, chunks.size(), 'Five rows at two a chunk is three chunks.');
            Assert.areEqual(
                5,
                [SELECT COUNT() FROM Contact],
                'Every row was processed even though the chunk was smaller than the file.'
            );
        }
    }

    /** Runs one pass the way the platform drives the batch, in chunks of this size. */
    private static Import_Batch__c runInChunks(Id batchId, Boolean dryRun, Integer chunkSize) {
        ImportBatchService.beginPass(batchId);
        ImportProcessorBatch job = new ImportProcessorBatch(batchId, dryRun);
        List<Import_Row__c> chunk = new List<Import_Row__c>();
        Database.QueryLocatorIterator rows = job.start(null).iterator();
        while (rows.hasNext()) {
            chunk.add((Import_Row__c) rows.next());
            if (chunk.size() == chunkSize || !rows.hasNext()) {
                job.execute(null, chunk);
                chunk = new List<Import_Row__c>();
            }
        }
        job.finish(null);
        return ImportBatchSelector.selectById(batchId);
    }

    @IsTest
    static void aNewPersonInTwoChunksIsCreatedOnceInTheDryRunAsInTheCommit() {
        System.runAs(TestUsers.admin()) {
            Import_Template__c template = ImportTestDataFactory.template(
                ImportTestDataFactory.donorMapping(),
                ImportTemplateService.RULE_EMAIL
            );
            Import_Batch__c batch = ImportTestDataFactory.batch(template);
            // Ana, and her organization, are new, and appear again in the second chunk.
            ImportTestDataFactory.rows(
                batch,
                new List<Map<String, String>>{
                    ImportTestDataFactory.donorRow(
                        'Ana',
                        'Ramirez',
                        'ana@example.org',
                        'Rose City'
                    ),
                    ImportTestDataFactory.donorRow('Ben', 'Okafor', 'ben@example.org', null),
                    ImportTestDataFactory.donorRow('Ana', 'Ramirez', 'ANA@example.org', 'Rose City')
                }
            );

            Test.startTest();
            Import_Batch__c dryRun = runInChunks(batch.Id, true, 2);
            Import_Batch__c committed = runInChunks(batch.Id, false, 2);
            Test.stopTest();

            Assert.areEqual(2, dryRun.Rows_Created__c, 'Ana is created once, not once a chunk.');
            Assert.areEqual(1, dryRun.Rows_Matched__c, 'Her second row matches her (R-IB12).');
            Assert.areEqual(
                dryRun.Rows_Created__c,
                committed.Rows_Created__c,
                'As the commit did.'
            );
            Assert.areEqual(dryRun.Rows_Matched__c, committed.Rows_Matched__c, 'And matched.');
            Assert.areEqual(dryRun.Rows_Updated__c, committed.Rows_Updated__c, 'And updated.');
            Assert.areEqual(2, [SELECT COUNT() FROM Contact], 'Two people exist.');
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Account WHERE Name = 'Rose City'],
                'One organization.'
            );
        }
    }

    @IsTest
    static void aDryRunChunkCostsTheSameHoweverManyChunksCameBefore() {
        System.runAs(TestUsers.admin()) {
            Import_Template__c template = ImportTestDataFactory.template(
                ImportTestDataFactory.donorMapping(),
                ImportTemplateService.RULE_EMAIL
            );
            Import_Batch__c batch = ImportTestDataFactory.batch(template);
            // Every row is a new person with a new organization, except that each later chunk opens
            // with a person and organization the first chunk would create, so every chunk after the
            // first finds one stored key under the same check.
            List<Map<String, String>> values = new List<Map<String, String>>();
            for (Integer i = 0; i < 20; i++) {
                Integer who = i >= 5 && Math.mod(i, 5) == 0 ? i / 5 - 1 : i;
                values.add(
                    ImportTestDataFactory.donorRow(
                        'Person' + who,
                        'Surname' + who,
                        'person' + who + '@example.org',
                        'Organization ' + who
                    )
                );
            }
            ImportTestDataFactory.rows(batch, values);
            List<Integer> queries = new List<Integer>();
            List<Integer> queryRows = new List<Integer>();
            List<Integer> carried = new List<Integer>();

            Test.startTest();
            ImportBatchService.beginPass(batch.Id);
            ImportProcessorBatch job = new ImportProcessorBatch(batch.Id, true);
            List<Import_Row__c> chunk = new List<Import_Row__c>();
            Database.QueryLocatorIterator rows = job.start(null).iterator();
            while (rows.hasNext()) {
                chunk.add((Import_Row__c) rows.next());
                if (chunk.size() == 5 || !rows.hasNext()) {
                    Integer queriesBefore = Limits.getQueries();
                    Integer rowsBefore = Limits.getQueryRows();
                    job.execute(null, chunk);
                    queries.add(Limits.getQueries() - queriesBefore);
                    queryRows.add(Limits.getQueryRows() - rowsBefore);
                    // What the batch holds between chunks, the Stateful job itself.
                    carried.add(JSON.serialize(job).length());
                    chunk = new List<Import_Row__c>();
                }
            }
            job.finish(null);
            Test.stopTest();

            Import_Batch__c finished = ImportBatchSelector.selectById(batch.Id);
            Assert.areEqual(17, finished.Rows_Created__c, 'Seventeen people would be new.');
            Assert.areEqual(3, finished.Rows_Matched__c, 'The three repeats find them (R-IB12).');
            Assert.areEqual(4, queries.size(), 'Twenty rows at five a chunk is four chunks.');
            for (Integer index = 2; index < queries.size(); index++) {
                Assert.areEqual(queries[1], queries[index], 'Chunk ' + index + ' asks as often.');
                Assert.areEqual(queryRows[1], queryRows[index], 'And reads as many rows.');
            }
            for (Integer index = 1; index < carried.size(); index++) {
                Assert.areEqual(carried[0], carried[index], 'Nothing carried grows (R-IB12).');
            }
            // The digest fields are in no permission set and are read in system mode (ADR-0021).
            Assert.areEqual(
                17,
                Database.countQueryWithBinds(
                    'SELECT COUNT() FROM Import_Row__c WHERE Import_Batch__c = :batchId' +
                    ' AND Person_1_Key__c != NULL AND Organization_Key__c != NULL',
                    new Map<String, Object>{ 'batchId' => batch.Id },
                    AccessLevel.SYSTEM_MODE
                ),
                'Each row that would create keeps the digests instead.'
            );
            Assert.areEqual(0, [SELECT COUNT() FROM Contact], 'A dry run writes no person.');
        }
    }

    @IsTest
    static void aPersonTheCommitCannotFindAgainIsCountedCreatedInEachChunkByBoth() {
        System.runAs(TestUsers.admin()) {
            // Name plus postal code, with the postal code only in the household column: the person
            // the commit creates carries no postal code of their own, so a later chunk cannot find
            // them and creates them again. The dry run must say so, not promise a match.
            ImportMapping mapping = new ImportMapping();
            mapping.columns.add(new ImportMapping.Column('Last Name', 'Contact1.LastName'));
            mapping.columns.add(new ImportMapping.Column('Zip', 'Household.BillingPostalCode'));
            Import_Batch__c batch = ImportTestDataFactory.batch(
                ImportTestDataFactory.template(
                    mapping.serialize(),
                    ImportTemplateService.RULE_NAME_POSTAL
                )
            );
            Map<String, String> ramirez = new Map<String, String>{
                'Last Name' => 'Ramirez',
                'Zip' => '97201'
            };
            ImportTestDataFactory.rows(batch, new List<Map<String, String>>{ ramirez, ramirez });

            Test.startTest();
            Import_Batch__c dryRun = runInChunks(batch.Id, true, 1);
            Import_Batch__c committed = runInChunks(batch.Id, false, 1);
            Test.stopTest();

            Assert.areEqual(
                committed.Rows_Created__c,
                dryRun.Rows_Created__c,
                'The dry run counts what the commit creates.'
            );
            Assert.areEqual(committed.Rows_Matched__c, dryRun.Rows_Matched__c, 'And matches.');
            Assert.areEqual(
                [SELECT COUNT() FROM Contact],
                dryRun.Rows_Created__c,
                'One created row per person the commit made.'
            );
        }
    }

    @IsTest
    static void twelveRowsOfOneNewDonorInOneChunkCreateOnePerson() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c batch = ImportTestDataFactory.batch(
                ImportTestDataFactory.template(
                    ImportTestDataFactory.donorMapping(),
                    ImportTemplateService.RULE_EMAIL
                )
            );
            List<Map<String, String>> rows = new List<Map<String, String>>();
            for (Integer month = 0; month < 12; month++) {
                rows.add(ImportTestDataFactory.donorRow('Ana', 'Ramirez', 'ana@example.org', null));
            }
            rows.add(ImportTestDataFactory.donorRow('Ben', 'Okafor', 'ben@example.org', null));
            ImportTestDataFactory.rows(batch, rows);

            Test.startTest();
            Import_Batch__c dryRun = runInChunks(batch.Id, true, 200);
            Import_Batch__c committed = runInChunks(batch.Id, false, 200);
            Test.stopTest();

            Assert.areEqual(2, [SELECT COUNT() FROM Contact], 'Ana once and Ben, not twelve Anas.');
            Set<Id> anas = new Set<Id>();
            Set<Id> households = new Set<Id>();
            for (Import_Row__c row : ImportTestDataFactory.reload(batch.Id)) {
                if (row.Row_Number__c < rows.size()) {
                    anas.add(row.Contact_1__c);
                    households.add(row.Household__c);
                }
            }
            Assert.areEqual(1, anas.size(), 'Every one of her rows names the same Ana.');
            Assert.areEqual(1, households.size(), 'In one household.');
            Assert.areEqual(
                2,
                committed.Rows_Created__c,
                'Her first row and Ben created somebody.'
            );
            Assert.areEqual(11, committed.Rows_Matched__c, 'Her other eleven matched her.');
            Assert.areEqual(
                committed.Rows_Created__c,
                dryRun.Rows_Created__c,
                'As the dry run said.'
            );
            Assert.areEqual(committed.Rows_Matched__c, dryRun.Rows_Matched__c, 'Both counts.');
        }
    }

    @IsTest
    static void aSecondPersonColumnSharesTheNewPersonTheFirstColumnCreates() {
        System.runAs(TestUsers.admin()) {
            ImportMapping mapping = new ImportMapping();
            for (
                String target : new List<String>{
                    'Contact1.Email',
                    'Contact1.LastName',
                    'Contact2.Email',
                    'Contact2.LastName'
                }
            ) {
                mapping.columns.add(new ImportMapping.Column(target, target));
            }
            Import_Batch__c batch = ImportTestDataFactory.batch(
                ImportTestDataFactory.template(
                    mapping.serialize(),
                    ImportTemplateService.RULE_EMAIL
                )
            );
            // Ana is the second person on the first row and the first person on the second. The
            // commit saves first people before second people, so the second row creates her.
            ImportTestDataFactory.rows(
                batch,
                new List<Map<String, String>>{
                    new Map<String, String>{
                        'Contact2.Email' => 'ana@example.org',
                        'Contact2.LastName' => 'Ramirez'
                    },
                    new Map<String, String>{
                        'Contact1.Email' => 'ana@example.org',
                        'Contact1.LastName' => 'Ramirez'
                    }
                }
            );

            Test.startTest();
            runInChunks(batch.Id, true, 200);
            List<Import_Row__c> previewed = ImportTestDataFactory.reload(batch.Id);
            runInChunks(batch.Id, false, 200);
            List<Import_Row__c> committed = ImportTestDataFactory.reload(batch.Id);
            Test.stopTest();

            Assert.areEqual(1, [SELECT COUNT() FROM Contact], 'One Ana.');
            Assert.areEqual(ImportRowProcessor.STATUS_MATCHED, committed[0].Status__c, 'Shared.');
            Assert.areEqual(ImportRowProcessor.STATUS_CREATED, committed[1].Status__c, 'Created.');
            for (Integer index = 0; index < 2; index++) {
                Assert.areEqual(
                    committed[index].Status__c,
                    previewed[index].Status__c,
                    'The dry run names the same row as the one that creates her: ' + index
                );
            }
            Assert.areEqual(committed[1].Contact_1__c, committed[0].Contact_2__c, 'The same Ana.');
        }
    }

    /**
     * John and Jane Smith share one matching key under the rule. Loads their row, after a row
     * naming John alone when `johnRowFirst`, or with John already in the org when `johnExists`,
     * and checks both are two people in one household, John never renamed as Jane, and the dry
     * run counting what the commit did (R-IB12).
     */
    private static void aCoupleSharingAKeyIsTwoPeople(
        String rule,
        Boolean johnExists,
        Boolean johnRowFirst,
        Integer chunkSize
    ) {
        Map<String, String> john = new Map<String, String>{
            'Contact1.FirstName' => 'John',
            'Contact1.LastName' => 'Smith',
            'Contact1.MailingPostalCode' => '12345',
            'Contact1.Email' => 'smiths@example.org'
        };
        Map<String, String> couple = new Map<String, String>(john);
        couple.putAll(
            new Map<String, String>{
                'Contact2.FirstName' => 'Jane',
                'Contact2.LastName' => 'Smith',
                'Contact2.MailingPostalCode' => '12345',
                'Contact2.Email' => 'smiths@example.org'
            }
        );
        ImportMapping mapping = new ImportMapping();
        for (String target : couple.keySet()) {
            mapping.columns.add(new ImportMapping.Column(target, target));
        }
        Import_Batch__c batch = ImportTestDataFactory.batch(
            ImportTestDataFactory.template(mapping.serialize(), rule)
        );
        ImportTestDataFactory.rows(
            batch,
            johnRowFirst
                ? new List<Map<String, String>>{ john, couple }
                : new List<Map<String, String>>{ couple }
        );
        if (johnExists) {
            insert new Contact(
                FirstName = 'John',
                LastName = 'Smith',
                MailingPostalCode = '12345',
                Email = 'smiths@example.org'
            );
        }

        Test.startTest();
        Import_Batch__c dryRun = runInChunks(batch.Id, true, chunkSize);
        Import_Batch__c committed = runInChunks(batch.Id, false, chunkSize);
        Test.stopTest();

        List<Import_Row__c> rows = ImportTestDataFactory.reload(batch.Id);
        Import_Row__c row = rows[rows.size() - 1];
        Assert.areNotEqual(
            ImportRowProcessor.STATUS_REJECTED,
            row.Status__c,
            'The couple loads: ' + row.Error_Message__c
        );
        Assert.areNotEqual(row.Contact_1__c, row.Contact_2__c, 'Two people, not one.');
        Map<Id, Contact> people = new Map<Id, Contact>([SELECT FirstName FROM Contact]);
        Assert.areEqual(2, people.size(), 'John and Jane, each once.');
        Assert.areEqual('John', people.get(row.Contact_1__c).FirstName, 'John is not renamed.');
        Assert.areEqual('Jane', people.get(row.Contact_2__c).FirstName, 'Jane is herself.');
        Assert.areEqual(1, [SELECT COUNT() FROM Account], 'One household for the two of them.');
        Assert.areEqual(committed.Rows_Created__c, dryRun.Rows_Created__c, 'As the dry run said.');
        Assert.areEqual(committed.Rows_Matched__c, dryRun.Rows_Matched__c, 'Both counts.');
        Assert.areEqual(committed.Rows_Updated__c, dryRun.Rows_Updated__c, 'All three.');
    }

    @IsTest
    static void aCoupleWithOneSurnameAndPostalCodeIsTwoPeople() {
        System.runAs(TestUsers.admin()) {
            aCoupleSharingAKeyIsTwoPeople(
                ImportTemplateService.RULE_NAME_POSTAL,
                false,
                false,
                200
            );
        }
    }

    @IsTest
    static void aCoupleSharingOneEmailIsTwoPeople() {
        System.runAs(TestUsers.admin()) {
            aCoupleSharingAKeyIsTwoPeople(ImportTemplateService.RULE_EMAIL, false, false, 200);
        }
    }

    @IsTest
    static void aCoupleAfterARowNamingHimInTheSameChunkIsTwoPeople() {
        System.runAs(TestUsers.admin()) {
            aCoupleSharingAKeyIsTwoPeople(ImportTemplateService.RULE_NAME_POSTAL, false, true, 200);
        }
    }

    @IsTest
    static void aCoupleAfterARowNamingHimInAnEarlierChunkIsTwoPeople() {
        System.runAs(TestUsers.admin()) {
            aCoupleSharingAKeyIsTwoPeople(ImportTemplateService.RULE_NAME_POSTAL, false, true, 1);
        }
    }

    @IsTest
    static void aCoupleWhoseHusbandIsAlreadyHereIsTwoPeople() {
        System.runAs(TestUsers.admin()) {
            aCoupleSharingAKeyIsTwoPeople(ImportTemplateService.RULE_NAME_POSTAL, true, false, 200);
        }
    }

    @IsTest
    static void aCoupleSharingAnEmailWhoseHusbandIsAlreadyHereIsTwoPeople() {
        System.runAs(TestUsers.admin()) {
            aCoupleSharingAKeyIsTwoPeople(ImportTemplateService.RULE_EMAIL, true, false, 200);
        }
    }

    /** Imports John and Jane Smith's row, sharing one key under the rule, as a new file. */
    private static Import_Batch__c coupleFile(String rule, String janeFirstName) {
        Map<String, String> couple = new Map<String, String>{
            'Contact1.FirstName' => 'John',
            'Contact1.LastName' => 'Smith',
            'Contact1.MailingPostalCode' => '12345',
            'Contact1.Email' => 'smiths@example.org',
            'Contact2.FirstName' => janeFirstName,
            'Contact2.LastName' => 'Smith',
            'Contact2.MailingPostalCode' => '12345',
            'Contact2.Email' => 'smiths@example.org'
        };
        ImportMapping mapping = new ImportMapping();
        for (String target : couple.keySet()) {
            mapping.columns.add(new ImportMapping.Column(target, target));
        }
        Import_Batch__c batch = ImportTestDataFactory.batch(
            ImportTestDataFactory.template(mapping.serialize(), rule)
        );
        ImportTestDataFactory.rows(batch, new List<Map<String, String>>{ couple });
        return batch;
    }

    private static void aCoupleLoadedAgainIsMatchedNotMadeAgain(String rule) {
        Import_Batch__c first = coupleFile(rule, 'Jane');
        Import_Batch__c again = coupleFile(rule, 'Jane');

        Test.startTest();
        runInChunks(first.Id, false, 200);
        Import_Batch__c dryRun = runInChunks(again.Id, true, 200);
        Import_Batch__c committed = runInChunks(again.Id, false, 200);
        Test.stopTest();

        Import_Row__c before = ImportTestDataFactory.reload(first.Id)[0];
        Import_Row__c row = ImportTestDataFactory.reload(again.Id)[0];
        Assert.areEqual(
            ImportRowProcessor.STATUS_MATCHED,
            row.Status__c,
            // A null message fails the assertion itself, so the reason is never passed bare.
            'The row loaded again is matched: ' + row.Error_Message__c
        );
        Assert.areEqual(before.Contact_1__c, row.Contact_1__c, 'John matches John.');
        Assert.areEqual(before.Contact_2__c, row.Contact_2__c, 'And Jane matches Jane.');
        Map<Id, Contact> people = new Map<Id, Contact>([SELECT FirstName FROM Contact]);
        Assert.areEqual(2, people.size(), 'Still two people, not a new Jane each time.');
        Assert.areEqual('John', people.get(row.Contact_1__c).FirstName, 'John is not renamed.');
        Assert.areEqual('Jane', people.get(row.Contact_2__c).FirstName, 'Nor is Jane.');
        Assert.areEqual(1, dryRun.Rows_Matched__c, 'The dry run of the second file says so.');
        Assert.areEqual(committed.Rows_Matched__c, dryRun.Rows_Matched__c, 'As the commit did.');
        Assert.areEqual(committed.Rows_Created__c, dryRun.Rows_Created__c, 'Both counts.');
    }

    @IsTest
    static void aCoupleWithOneSurnameAndPostalCodeLoadedAgainIsMatched() {
        System.runAs(TestUsers.admin()) {
            aCoupleLoadedAgainIsMatchedNotMadeAgain(ImportTemplateService.RULE_NAME_POSTAL);
        }
    }

    @IsTest
    static void aCoupleSharingOneEmailLoadedAgainIsMatched() {
        System.runAs(TestUsers.admin()) {
            aCoupleLoadedAgainIsMatchedNotMadeAgain(ImportTemplateService.RULE_EMAIL);
        }
    }

    @IsTest
    static void twoPeopleOnARowWithOneKeyAndOneFirstNameAreRefused() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c batch = coupleFile(ImportTemplateService.RULE_EMAIL, 'john');

            Test.startTest();
            Import_Batch__c dryRun = runInChunks(batch.Id, true, 200);
            runInChunks(batch.Id, false, 200);
            Test.stopTest();

            Import_Row__c row = ImportTestDataFactory.reload(batch.Id)[0];
            Assert.areEqual(ImportRowProcessor.STATUS_REJECTED, row.Status__c, 'Not guessed at.');
            Assert.areEqual(Label.Core_Import_ErrorTwoPeopleOneKey, row.Error_Message__c, 'Why.');
            Assert.areEqual(1, dryRun.Rows_Rejected__c, 'The dry run says so first.');
            Assert.areEqual(0, [SELECT COUNT() FROM Contact], 'Nobody is created.');
        }
    }

    @IsTest
    static void rowsSharingAPersonWhoCouldNotBeSavedAreRejectedWithTheReason() {
        System.runAs(TestUsers.admin()) {
            ImportMapping mapping = new ImportMapping();
            for (
                String target : new List<String>{
                    'Contact1.Email',
                    'Contact1.LastName',
                    'Contact1.ReportsToId'
                }
            ) {
                mapping.columns.add(new ImportMapping.Column(target, target));
            }
            Import_Batch__c batch = ImportTestDataFactory.batch(
                ImportTestDataFactory.template(
                    mapping.serialize(),
                    ImportTemplateService.RULE_EMAIL
                )
            );
            // Only the first row reports to an account, which a contact cannot, so only the row
            // that creates Ana fails to save; the two after it name her and share that failure. (A
            // value too long for its field is shortened to fit, so it cannot make a save fail.)
            Account notAPerson = new Account(Name = 'Not a person');
            insert notAPerson;
            List<Map<String, String>> rows = new List<Map<String, String>>();
            for (Integer i = 0; i < 3; i++) {
                rows.add(
                    new Map<String, String>{
                        'Contact1.Email' => 'ana@example.org',
                        'Contact1.LastName' => 'Ramirez',
                        'Contact1.ReportsToId' => i == 0 ? (String) notAPerson.Id : ''
                    }
                );
            }
            ImportTestDataFactory.rows(batch, rows);

            Test.startTest();
            runInChunks(batch.Id, false, 200);
            Test.stopTest();

            List<Import_Row__c> loaded = ImportTestDataFactory.reload(batch.Id);
            Assert.areEqual(0, [SELECT COUNT() FROM Contact], 'Ana could not be saved.');
            Assert.areEqual(ImportRowProcessor.STATUS_REJECTED, loaded[0].Status__c, 'Her row.');
            String prefix = Label.Core_Import_ErrorSamePersonNotSaved.substringBefore('{0}');
            for (Integer index = 1; index < 3; index++) {
                Assert.areEqual(
                    ImportRowProcessor.STATUS_REJECTED,
                    loaded[index].Status__c,
                    'A row sharing her is rejected too: ' + index
                );
                Assert.isTrue(
                    loaded[index].Error_Message__c.startsWith(prefix),
                    'Saying the earlier row could not be saved: ' + loaded[index].Error_Message__c
                );
            }
        }
    }

    /** A processor that counts the chunks it has seen in the state it carries. */
    private class CountingProcessor implements ImportEntityProcessor {
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
            String seen = ImportEntityProcessors.carriedState;
            ImportEntityProcessors.carriedState = (seen == null ? '' : seen) + 'x';
            return new ImportEntityResult();
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

    @IsTest
    static void theProcessorStateIsCarriedFromChunkToChunk() {
        System.runAs(TestUsers.admin()) {
            ImportMapping mapping = new ImportMapping();
            for (
                String target : new List<String>{
                    'Contact1.Email',
                    'Contact1.LastName',
                    'Gift.Amount__c'
                }
            ) {
                mapping.columns.add(new ImportMapping.Column(target, target));
            }
            Import_Template__c template = ImportTestDataFactory.template(
                mapping.serialize(),
                ImportTemplateService.RULE_EMAIL
            );
            Import_Batch__c batch = ImportTestDataFactory.batch(template);
            List<Map<String, String>> values = new List<Map<String, String>>();
            for (Integer i = 0; i < 2; i++) {
                values.add(
                    new Map<String, String>{
                        'Contact1.Email' => 'person' +
                        i +
                        '@example.org',
                        'Contact1.LastName' => 'Surname' + i,
                        'Gift.Amount__c' => '10'
                    }
                );
            }
            ImportTestDataFactory.rows(batch, values);
            ImportEntityProcessors.processorOverride = new CountingProcessor();
            ImportProcessorBatch job = new ImportProcessorBatch(batch.Id, true);
            List<Import_Row__c> rows = new List<Import_Row__c>();
            Database.QueryLocatorIterator staged = job.start(null).iterator();
            while (staged.hasNext()) {
                rows.add((Import_Row__c) staged.next());
            }

            Test.startTest();
            job.execute(null, new List<Import_Row__c>{ rows[0] });
            // A new chunk is a new transaction, whose statics start empty.
            ImportEntityProcessors.carriedState = null;
            job.execute(null, new List<Import_Row__c>{ rows[1] });
            Test.stopTest();

            Assert.areEqual(
                'xx',
                ImportEntityProcessors.carriedState,
                'The second chunk started from what the first left.'
            );
        }
    }

    /** A processor that reports the settings it ran under, and what a commit was handed. */
    private class SettingsProcessor implements ImportEntityProcessor {
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
            ImportEntityResult result = new ImportEntityResult();
            if (dryRun) {
                result.settings = '{"window":7}';
            } else {
                handedToTheCommit = batch.Processor_Settings_JSON__c;
                result.settings = '{"window":0}';
            }
            return result;
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

    private static String handedToTheCommit;

    @IsTest
    static void theCommitIsHandedTheSettingsItsDryRunRecorded() {
        System.runAs(TestUsers.admin()) {
            ImportMapping mapping = new ImportMapping();
            for (
                String target : new List<String>{
                    'Contact1.Email',
                    'Contact1.LastName',
                    'Gift.Amount__c'
                }
            ) {
                mapping.columns.add(new ImportMapping.Column(target, target));
            }
            Import_Batch__c batch = ImportTestDataFactory.batch(
                ImportTestDataFactory.template(
                    mapping.serialize(),
                    ImportTemplateService.RULE_EMAIL
                )
            );
            ImportTestDataFactory.rows(
                batch,
                new List<Map<String, String>>{
                    new Map<String, String>{
                        'Contact1.Email' => 'ana@example.org',
                        'Contact1.LastName' => 'Ramirez',
                        'Gift.Amount__c' => '10'
                    }
                }
            );
            ImportEntityProcessors.processorOverride = new SettingsProcessor();

            Test.startTest();
            ImportProcessorBatch previewing = new ImportProcessorBatch(batch.Id, true);
            previewing.execute(null, ImportTestDataFactory.reload(batch.Id));
            previewing.finish(null);
            Import_Batch__c afterDryRun = ImportBatchSelector.selectById(batch.Id);
            ImportBatchService.beginPass(batch.Id);
            ImportProcessorBatch committing = new ImportProcessorBatch(batch.Id, false);
            committing.execute(null, ImportTestDataFactory.reload(batch.Id));
            committing.finish(null);
            Test.stopTest();

            Assert.areEqual(
                '{"window":7}',
                afterDryRun.Processor_Settings_JSON__c,
                'The dry run recorded what it ran under (R-IB11).'
            );
            Assert.areEqual('{"window":7}', handedToTheCommit, 'And the commit was handed it.');
            Assert.areEqual(
                '{"window":7}',
                ImportBatchSelector.selectById(batch.Id).Processor_Settings_JSON__c,
                'A commit does not replace what its dry run recorded.'
            );
        }
    }

    @IsTest
    static void aChunkThatDiesRejectsItsOwnRowsAndSaysWhy() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c batch = staged(2);
            // Deleting the template is the simplest way to make the chunk fail for a reason the
            // administrator would recognize, and it exercises the same path a limit error takes.
            delete [SELECT Id FROM Import_Template__c LIMIT 1];

            Test.startTest();
            Database.executeBatch(new ImportProcessorBatch(batch.Id, false), 200);
            Test.stopTest();

            Import_Batch__c after = ImportBatchSelector.selectById(batch.Id);
            Assert.areEqual(
                ImportBatchService.STATUS_FAILED,
                after.Status__c,
                'The run says it failed rather than reporting a clean finish.'
            );
            for (Import_Row__c row : ImportTestDataFactory.reload(batch.Id)) {
                Assert.areEqual(
                    ImportRowProcessor.STATUS_REJECTED,
                    row.Status__c,
                    'Every row of the lost chunk is marked, so nothing disappears unexplained.'
                );
                Assert.isNotNull(row.Error_Message__c, 'With a reason on each one.');
            }
        }
    }

    @IsTest
    static void aChunkThatDiesAfterWritingLeavesNothingBehind() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c batch = staged(2);
            batch.Status__c = ImportBatchService.STATUS_DRY_RUN_COMPLETE;
            update batch;
            // The chunk creates both people, then dies.
            ImportProcessorBatch.failAfterProcessForTest = true;

            Test.startTest();
            Database.executeBatch(new ImportProcessorBatch(batch.Id, false), 200);
            Test.stopTest();

            Assert.areEqual(0, [SELECT COUNT() FROM Contact], 'The people it made were undone.');
            for (Import_Row__c row : ImportTestDataFactory.reload(batch.Id)) {
                Assert.areEqual(ImportRowProcessor.STATUS_REJECTED, row.Status__c, 'Rejected.');
                Assert.areEqual('Failed for the test.', row.Error_Message__c, 'Saying why.');
                Assert.isNull(row.Contact_1__c, 'Naming nobody the rollback removed.');
            }
            Assert.areEqual(
                ImportBatchService.STATUS_FAILED,
                ImportBatchSelector.selectById(batch.Id).Status__c,
                'The run says it failed.'
            );
        }
    }

    @IsTest
    static void aRunOverNoRowsStillFinishesCleanly() {
        System.runAs(TestUsers.admin()) {
            Import_Template__c template = ImportTestDataFactory.template(
                ImportTestDataFactory.donorMapping(),
                ImportTemplateService.RULE_EMAIL
            );
            Import_Batch__c batch = ImportTestDataFactory.batch(template);

            Test.startTest();
            Database.executeBatch(new ImportProcessorBatch(batch.Id, true), 200);
            Test.stopTest();

            Import_Batch__c after = ImportBatchSelector.selectById(batch.Id);
            Assert.areEqual(
                ImportBatchService.STATUS_DRY_RUN_COMPLETE,
                after.Status__c,
                'An empty run is not a failed run.'
            );
            Assert.areEqual(0, after.Rows_Created__c, 'And it created nothing.');
        }
    }

    @IsTest
    static void theRunReadsEveryStagedRowWhoeverStartsIt() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c batch = staged(200);
            // No packaged permission set, so no access to the staged rows at all: API 67.0 reads in
            // user mode unless told otherwise, and the rows are bookkeeping read in system mode.
            User limited = TestDataFactory.createUser('Nolimport', new List<String>());

            Integer read = 0;
            Test.startTest();
            System.runAs(limited) {
                Database.QueryLocatorIterator rows = new ImportProcessorBatch(batch.Id, true)
                    .start(null)
                    .iterator();
                while (rows.hasNext()) {
                    rows.next();
                    read++;
                }
            }
            Test.stopTest();

            Assert.areEqual(
                200,
                read,
                'Every staged row is read, not only those the user may see.'
            );
        }
    }

    /**
     * The run log puts chunk failures before the notes, so the field's length never cuts them
     * off, and keeps a bounded number of notes however many distinct ones the chunks raise.
     */
    @IsTest
    static void chunkFailuresComeFirstAndNotesAreCapped() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c batch = staged(1);
            ImportProcessorBatch run = new ImportProcessorBatch(batch.Id, true);
            ImportRowProcessor.Outcome outcome = new ImportRowProcessor.Outcome();
            for (Integer i = 0; i < ImportProcessorBatch.MAX_NOTES + 50; i++) {
                outcome.notes.add('Note number ' + i);
            }
            run.addNotes(outcome);
            run.addLog('Chunk 7 failed for the test.');

            Test.startTest();
            run.finish(null);
            Test.stopTest();

            String log = ImportBatchSelector.selectById(batch.Id).Run_Log__c;
            Assert.isTrue(
                log.indexOf('Chunk 7 failed') < log.indexOf('Note number'),
                'The chunk failure comes before the notes.'
            );
            Assert.areEqual(
                ImportProcessorBatch.MAX_NOTES,
                log.countMatches('Note number '),
                'Notes past the cap are left out.'
            );
            Assert.isTrue(log.contains(Label.Core_Import_LogNotesCut), 'And the run log says so.');
        }
    }
}
