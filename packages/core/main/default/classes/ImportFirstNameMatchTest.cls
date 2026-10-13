/**
 * A person with a first name is found only by it, never by the key they share with somebody
 * else, such as a partner at the same address (canonical model R-IB12, ADR-0067). The shared
 * key alone finds a person only when the row gives no first name; otherwise the person is
 * created, never taken for somebody else and renamed, even where one record holds the key.
 */
@IsTest
private class ImportFirstNameMatchTest {
    @TestSetup
    static void setUp() {
        System.runAs(TestUsers.admin()) {
            TestDataFactory.defaultSettings();
        }
    }

    private static final List<String> COLUMNS = new List<String>{
        'Contact1.FirstName',
        'Contact1.LastName',
        'Contact1.MailingPostalCode',
        'Contact2.FirstName',
        'Contact2.LastName',
        'Contact2.MailingPostalCode'
    };

    /** A Smith at 12345 on each row: one first name, or two for a couple. */
    private static Import_Batch__c file(List<List<String>> firstNames) {
        ImportMapping mapping = new ImportMapping();
        for (String target : COLUMNS) {
            mapping.columns.add(new ImportMapping.Column(target, target));
        }
        Import_Batch__c batch = ImportTestDataFactory.batch(
            ImportTestDataFactory.template(
                mapping.serialize(),
                ImportTemplateService.RULE_NAME_POSTAL
            )
        );
        List<Map<String, String>> rows = new List<Map<String, String>>();
        for (List<String> names : firstNames) {
            Map<String, String> row = new Map<String, String>{
                'Contact1.FirstName' => names[0],
                'Contact1.LastName' => 'Smith',
                'Contact1.MailingPostalCode' => '12345'
            };
            if (names.size() > 1) {
                row.putAll(
                    new Map<String, String>{
                        'Contact2.FirstName' => names[1],
                        'Contact2.LastName' => 'Smith',
                        'Contact2.MailingPostalCode' => '12345'
                    }
                );
            }
            rows.add(row);
        }
        ImportTestDataFactory.rows(batch, rows);
        return batch;
    }

    private static Contact smith(String firstName) {
        return new Contact(FirstName = firstName, LastName = 'Smith', MailingPostalCode = '12345');
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

    /** Dry runs then commits the file, checking the dry run counted what the commit did. */
    private static List<Import_Row__c> load(Import_Batch__c batch, Integer chunkSize) {
        Import_Batch__c dryRun = runInChunks(batch.Id, true, chunkSize);
        Import_Batch__c committed = runInChunks(batch.Id, false, chunkSize);
        Assert.areEqual(
            committed.Rows_Created__c,
            dryRun.Rows_Created__c,
            'Created, as previewed.'
        );
        Assert.areEqual(
            committed.Rows_Matched__c,
            dryRun.Rows_Matched__c,
            'Matched, as previewed.'
        );
        Assert.areEqual(
            committed.Rows_Updated__c,
            dryRun.Rows_Updated__c,
            'Updated, as previewed.'
        );
        Assert.areEqual(0, committed.Rows_Rejected__c, 'Nothing refused.');
        return ImportTestDataFactory.reload(batch.Id);
    }

    /** The first names of the Smiths in the org, in the order they were created. */
    private static List<String> smiths() {
        List<String> names = new List<String>();
        for (Contact person : [SELECT FirstName FROM Contact ORDER BY CreatedDate, Id]) {
            names.add(person.FirstName);
        }
        return names;
    }

    private static List<String> sorted(List<String> names) {
        List<String> copy = new List<String>(names);
        copy.sort();
        return copy;
    }

    private static String firstNameOf(Id contactId) {
        return [SELECT FirstName FROM Contact WHERE Id = :contactId].FirstName;
    }

    @IsTest
    static void aRowNamingJaneAloneFindsJaneNotHerHusband() {
        System.runAs(TestUsers.admin()) {
            insert new List<Contact>{ smith('John'), smith('Jane') };

            Test.startTest();
            List<Import_Row__c> rows = load(
                file(new List<List<String>>{ new List<String>{ 'Jane' } }),
                200
            );
            Test.stopTest();

            Assert.areEqual(
                'Jane',
                firstNameOf(rows[0].Contact_1__c),
                'Jane, found by first name.'
            );
            Assert.areEqual(
                new List<String>{ 'John', 'Jane' },
                smiths(),
                'Nobody renamed or added.'
            );
        }
    }

    @IsTest
    static void aRowNamingJohnAloneFindsJohnWhenJaneIsTheOlderRecord() {
        System.runAs(TestUsers.admin()) {
            insert smith('Jane');
            insert smith('John');

            Test.startTest();
            List<Import_Row__c> rows = load(
                file(new List<List<String>>{ new List<String>{ 'John' } }),
                200
            );
            Test.stopTest();

            Assert.areEqual('John', firstNameOf(rows[0].Contact_1__c), 'John, not the older Jane.');
            Assert.areEqual(
                new List<String>{ 'Jane', 'John' },
                smiths(),
                'Nobody renamed or added.'
            );
        }
    }

    @IsTest
    static void aRowAfterACoupleInTheSameChunkFindsTheRightPartner() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            List<Import_Row__c> rows = load(
                file(
                    new List<List<String>>{
                        new List<String>{ 'John', 'Jane' },
                        new List<String>{ 'Jane' },
                        new List<String>{ 'Mary' }
                    }
                ),
                200
            );
            Test.stopTest();

            Assert.areEqual(
                rows[0].Contact_2__c,
                rows[1].Contact_1__c,
                'The Jane row is that Jane.'
            );
            Assert.areEqual('Mary', firstNameOf(rows[2].Contact_1__c), 'Mary is nobody else.');
            // Jane is saved with the second people, after Mary, so the order says nothing here.
            Assert.areEqual(
                sorted(new List<String>{ 'John', 'Jane', 'Mary' }),
                sorted(smiths()),
                'Three people.'
            );
            assertOneHousehold(rows[0].Contact_1__c, rows[0].Contact_2__c);
            Assert.areEqual(rows[0].Household__c, rows[1].Household__c, 'Her row names it too.');
        }
    }

    @IsTest
    static void aRowNamingJaneBeforeHerCoupleRowIsInTheCouplesHousehold() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            List<Import_Row__c> rows = load(
                file(
                    new List<List<String>>{
                        new List<String>{ 'Jane' },
                        new List<String>{ 'John', 'Jane' }
                    }
                ),
                200
            );
            Test.stopTest();

            Assert.areEqual(rows[1].Contact_2__c, rows[0].Contact_1__c, 'One Jane, not two.');
            Assert.areEqual(new List<String>{ 'John', 'Jane' }, smiths(), 'Two people.');
            assertOneHousehold(rows[1].Contact_1__c, rows[1].Contact_2__c);
            Assert.areEqual(rows[1].Household__c, rows[0].Household__c, 'Her row names it too.');
        }
    }

    private static void assertOneHousehold(Id john, Id jane) {
        Map<Id, Contact> couple = new Map<Id, Contact>(
            [SELECT AccountId FROM Contact WHERE Id IN :new List<Id>{ john, jane }]
        );
        Assert.areEqual(
            couple.get(john).AccountId,
            couple.get(jane).AccountId,
            'John and Jane share one household.'
        );
        Assert.areEqual(
            2,
            [SELECT COUNT() FROM Contact WHERE AccountId = :couple.get(john).AccountId],
            'Nobody else is in it.'
        );
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Account WHERE Id NOT IN (SELECT AccountId FROM Contact)],
            'No empty household is left behind.'
        );
    }

    @IsTest
    static void aMatchIsFoundHoweverManyPeopleShareTheSurnameElsewhere() {
        System.runAs(TestUsers.admin()) {
            List<Contact> elsewhere = new List<Contact>();
            for (Integer i = 0; i < 3; i++) {
                elsewhere.add(
                    new Contact(
                        FirstName = 'Al' + i,
                        LastName = 'Smith',
                        MailingPostalCode = '99999'
                    )
                );
            }
            insert elsewhere;
            insert smith('John');
            // Smiths elsewhere once filled the lookup before John was reached.
            ImportMatcher.rowCap = 3;

            Test.startTest();
            List<Import_Row__c> rows = load(
                file(new List<List<String>>{ new List<String>{ 'John' } }),
                200
            );
            Test.stopTest();

            Assert.areEqual(ImportRowProcessor.STATUS_MATCHED, rows[0].Status__c, 'John is found.');
            Assert.areEqual(4, [SELECT COUNT() FROM Contact], 'Nobody added.');
        }
    }

    @IsTest
    static void aLookupStoppedAtTheCapNeverRenamesAnybody() {
        System.runAs(TestUsers.admin()) {
            insert smith('John');
            // The lookup reads as many records as it may, so another holder may be unseen.
            ImportMatcher.rowCap = 1;

            Test.startTest();
            List<Import_Row__c> rows = load(
                file(new List<List<String>>{ new List<String>{ 'Jane' } }),
                200
            );
            Test.stopTest();

            Assert.areEqual('Jane', firstNameOf(rows[0].Contact_1__c), 'Jane is created.');
            Assert.areEqual(new List<String>{ 'John', 'Jane' }, smiths(), 'John is not renamed.');
            Assert.isTrue(
                [
                    SELECT COUNT()
                    FROM Error_Log__c
                    WHERE Severity__c = :ErrorLogger.SEVERITY_WARNING
                ] > 0,
                'And the stop is logged.'
            );
        }
    }

    @IsTest
    static void twoCouplesAtOneAddressAreToldApartByFirstName() {
        System.runAs(TestUsers.admin()) {
            insert new List<Contact>{ smith('John'), smith('Jane'), smith('Bob'), smith('Mary') };

            Test.startTest();
            List<Import_Row__c> rows = load(
                file(
                    new List<List<String>>{ new List<String>{ 'Mary' }, new List<String>{ 'Ann' } }
                ),
                200
            );
            Test.stopTest();

            Assert.areEqual(
                'Mary',
                firstNameOf(rows[0].Contact_1__c),
                'Mary, not the first Smith.'
            );
            Assert.areEqual('Ann', firstNameOf(rows[1].Contact_1__c), 'Ann is new, not a guess.');
            Assert.areEqual(
                new List<String>{ 'John', 'Jane', 'Bob', 'Mary', 'Ann' },
                smiths(),
                'Nobody renamed.'
            );
        }
    }

    @IsTest
    static void aDryRunInOneRowChunksCountsWhatTheCommitDoes() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            List<Import_Row__c> rows = load(
                file(
                    new List<List<String>>{
                        new List<String>{ 'John' },
                        new List<String>{ 'John', 'Jane' },
                        new List<String>{ 'Jane' },
                        new List<String>{ 'Mary' }
                    }
                ),
                1
            );
            Test.stopTest();

            Assert.areEqual(
                rows[0].Contact_1__c,
                rows[1].Contact_1__c,
                'The couple row finds John.'
            );
            Assert.areEqual(rows[1].Contact_2__c, rows[2].Contact_1__c, 'And the Jane row, Jane.');
            Assert.areEqual(new List<String>{ 'John', 'Jane', 'Mary' }, smiths(), 'Three people.');
        }
    }

    @IsTest
    static void firstNamesAreComparedIgnoringCaseButNotAccents() {
        System.runAs(TestUsers.admin()) {
            insert new List<Contact>{ smith('John'), smith('Jane') };

            Test.startTest();
            List<Import_Row__c> rows = load(
                file(
                    new List<List<String>>{ new List<String>{ 'JANE' }, new List<String>{ 'Jáne' } }
                ),
                200
            );
            Test.stopTest();

            Assert.areEqual('Jane', firstNameOf(rows[0].Contact_1__c), 'Whatever the case.');
            Assert.areEqual(
                'Jáne',
                firstNameOf(rows[1].Contact_1__c),
                'An accent is a different name: created, not guessed.'
            );
            // A row with no first name at this couple matches both: ImportMatchingRulesTest (R-IT9).
            Assert.areEqual(
                new List<String>{ 'John', 'Jane', 'Jáne' },
                smiths(),
                'Nobody renamed.'
            );
        }
    }

    /** One person per row under the given rule, each row's values as given. */
    private static Import_Batch__c fileOf(String rule, List<Map<String, String>> rows) {
        ImportMapping mapping = new ImportMapping();
        for (
            String target : new List<String>{
                'Contact1.FirstName',
                'Contact1.LastName',
                'Contact1.MailingPostalCode',
                'Contact1.Email'
            }
        ) {
            mapping.columns.add(new ImportMapping.Column(target, target));
        }
        Import_Batch__c batch = ImportTestDataFactory.batch(
            ImportTestDataFactory.template(mapping.serialize(), rule)
        );
        ImportTestDataFactory.rows(batch, rows);
        return batch;
    }

    private static Map<String, String> row(String firstName, String lastName) {
        return new Map<String, String>{
            'Contact1.FirstName' => firstName,
            'Contact1.LastName' => lastName,
            'Contact1.MailingPostalCode' => '12345'
        };
    }

    @IsTest
    static void aRowWithAnotherFirstNameIsCreatedNotTheSoleHolderRenamed() {
        System.runAs(TestUsers.admin()) {
            Contact john = smith('John');
            insert john;
            Import_Batch__c batch = file(new List<List<String>>{ new List<String>{ 'Jane' } });

            Test.startTest();
            List<Import_Row__c> rows = load(batch, 200);
            Test.stopTest();

            Assert.areEqual(ImportRowProcessor.STATUS_CREATED, rows[0].Status__c, 'Jane is new.');
            Assert.areNotEqual(john.Id, rows[0].Contact_1__c, 'Not John.');
            Assert.areEqual(new List<String>{ 'John', 'Jane' }, smiths(), 'John is not renamed.');
            Contact jane = [
                SELECT Created_By_Import_Batch__c
                FROM Contact
                WHERE Id = :rows[0].Contact_1__c
            ];
            Assert.areEqual(batch.Id, jane.Created_By_Import_Batch__c, 'Undo would remove Jane.');
            Assert.isNull(
                [SELECT Created_By_Import_Batch__c FROM Contact WHERE Id = :john.Id]
                .Created_By_Import_Batch__c,
                'And leave John, whom the import never touched.'
            );
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Import_Journal__c WHERE Import_Batch__c = :batch.Id],
                'Nothing of John was changed, so there is nothing for undo to put back.'
            );
        }
    }

    @IsTest
    static void aRowWithNoFirstNameMatchesTheHolderAndRenamesNobody() {
        System.runAs(TestUsers.admin()) {
            Contact john = smith('John');
            insert john;

            Test.startTest();
            List<Import_Row__c> rows = load(
                file(new List<List<String>>{ new List<String>{ '' } }),
                200
            );
            Test.stopTest();

            Assert.areEqual(john.Id, rows[0].Contact_1__c, 'No first name: found on the rest.');
            Assert.areEqual(new List<String>{ 'John' }, smiths(), 'Still John, nobody added.');
        }
    }

    @IsTest
    static void aHolderWithNoFirstNameIsNotTakenByARowWithOne() {
        System.runAs(TestUsers.admin()) {
            Contact unnamed = new Contact(LastName = 'Smith', MailingPostalCode = '12345');
            insert unnamed;

            Test.startTest();
            List<Import_Row__c> rows = load(
                file(new List<List<String>>{ new List<String>{ 'Jane' } }),
                200
            );
            Test.stopTest();

            Assert.areNotEqual(unnamed.Id, rows[0].Contact_1__c, 'Jane is somebody else.');
            Assert.isNull(firstNameOf(unnamed.Id), 'The record with no first name is not renamed.');
            Assert.areEqual(2, [SELECT COUNT() FROM Contact], 'Jane is created.');
        }
    }

    @IsTest
    static void spacingAndCaseAreIgnoredButInitialsAreNot() {
        System.runAs(TestUsers.admin()) {
            Contact john = smith('John');
            Contact maryAnn = smith('Mary Ann');
            insert new List<Contact>{ john, maryAnn };

            Test.startTest();
            List<Import_Row__c> rows = load(
                file(
                    new List<List<String>>{
                        new List<String>{ ' JOHN ' },
                        new List<String>{ 'mary   ann' },
                        new List<String>{ 'J.' }
                    }
                ),
                200
            );
            Test.stopTest();

            Assert.areEqual(john.Id, rows[0].Contact_1__c, 'Capitals and outer spaces: John.');
            Assert.areEqual(maryAnn.Id, rows[1].Contact_1__c, 'Inner spaces: Mary Ann.');
            Assert.areEqual('J.', firstNameOf(rows[2].Contact_1__c), 'An initial is created.');
            Assert.areEqual(3, [SELECT COUNT() FROM Contact], 'Only J. is added.');
            Assert.isTrue(
                'John'.equalsIgnoreCase(firstNameOf(john.Id).trim()),
                'John is not renamed to J.'
            );
        }
    }

    @IsTest
    static void johnThenJaneInOneFileAreTwoPeopleInOneChunkOrTwo() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            List<Import_Row__c> together = load(
                file(
                    new List<List<String>>{ new List<String>{ 'John' }, new List<String>{ 'Jane' } }
                ),
                200
            );
            Test.stopTest();

            Assert.areNotEqual(together[0].Contact_1__c, together[1].Contact_1__c, 'Two people.');
            Assert.areEqual(new List<String>{ 'John', 'Jane' }, smiths(), 'Neither renamed.');

            // Loaded again in one-row chunks: each row now finds its own person by first name.
            List<Import_Row__c> again = load(
                file(
                    new List<List<String>>{ new List<String>{ 'John' }, new List<String>{ 'Jane' } }
                ),
                1
            );
            Assert.areEqual(together[0].Contact_1__c, again[0].Contact_1__c, 'John again.');
            Assert.areEqual(together[1].Contact_1__c, again[1].Contact_1__c, 'Jane again.');
            Assert.areEqual(2, [SELECT COUNT() FROM Contact], 'Nobody added.');
        }
    }

    @IsTest
    static void aNewJohnThenJaneAcrossOneRowChunksAreTwoPeople() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            List<Import_Row__c> rows = load(
                file(
                    new List<List<String>>{ new List<String>{ 'John' }, new List<String>{ 'Jane' } }
                ),
                1
            );
            Test.stopTest();

            Assert.areNotEqual(rows[0].Contact_1__c, rows[1].Contact_1__c, 'Two people.');
            Assert.areEqual(new List<String>{ 'John', 'Jane' }, smiths(), 'Neither renamed.');
        }
    }

    @IsTest
    static void aRowWithNoFirstNameThenJaneInOneChunkAreTwoPeople() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            List<Import_Row__c> rows = load(
                file(new List<List<String>>{ new List<String>{ '' }, new List<String>{ 'Jane' } }),
                200
            );
            Test.stopTest();

            Assert.areNotEqual(rows[0].Contact_1__c, rows[1].Contact_1__c, 'Jane is not taken.');
            Assert.isNull(firstNameOf(rows[0].Contact_1__c), 'The unnamed person is not renamed.');
            Assert.areEqual(2, [SELECT COUNT() FROM Contact], 'Two people.');
        }
    }

    @IsTest
    static void theEmailRuleCreatesAnotherFirstNameAtASharedEmail() {
        System.runAs(TestUsers.admin()) {
            Contact john = new Contact(
                FirstName = 'John',
                LastName = 'Smith',
                Email = 'smiths@example.org'
            );
            insert john;
            Map<String, String> jane = row('Jane', 'Smith');
            jane.put('Contact1.Email', 'smiths@example.org');
            Map<String, String> unnamed = row('', 'Smith');
            unnamed.put('Contact1.Email', 'SMITHS@example.org');

            Test.startTest();
            List<Import_Row__c> rows = load(
                fileOf(
                    ImportTemplateService.RULE_EMAIL,
                    new List<Map<String, String>>{ jane, unnamed }
                ),
                200
            );
            Test.stopTest();

            Assert.areNotEqual(john.Id, rows[0].Contact_1__c, 'Jane is not John.');
            Assert.areEqual('Jane', firstNameOf(rows[0].Contact_1__c), 'She is created.');
            Assert.areEqual(john.Id, rows[1].Contact_1__c, 'No first name: the earliest holder.');
            Assert.areEqual('John', firstNameOf(john.Id), 'John is not renamed.');
        }
    }

    @IsTest
    static void twoHundredRowsMatchOrCreateByFirstNameInOneChunk() {
        System.runAs(TestUsers.admin()) {
            List<Contact> holders = new List<Contact>();
            List<Map<String, String>> values = new List<Map<String, String>>();
            for (Integer i = 0; i < 200; i++) {
                holders.add(
                    new Contact(
                        FirstName = 'John',
                        LastName = 'Smith' + i,
                        MailingPostalCode = '12345'
                    )
                );
                values.add(row(Math.mod(i, 2) == 0 ? 'John' : 'Jane', 'Smith' + i));
            }
            insert holders;
            Import_Batch__c batch = fileOf(ImportTemplateService.RULE_NAME_POSTAL, values);

            Test.startTest();
            List<Import_Row__c> rows = load(batch, 200);
            Test.stopTest();

            Set<Id> holderIds = new Map<Id, Contact>(holders).keySet();
            for (Integer i = 0; i < 200; i++) {
                Boolean john = Math.mod(i, 2) == 0;
                Assert.areEqual(
                    john,
                    holderIds.contains(rows[i].Contact_1__c),
                    'Row ' + i + ': John finds John, Jane is created.'
                );
            }
            Import_Batch__c committed = ImportBatchSelector.selectById(batch.Id);
            Assert.areEqual(100, committed.Rows_Created__c, 'One Jane per address.');
            Assert.areEqual(100, committed.Rows_Matched__c, 'Each John found and unchanged.');
            Assert.areEqual(
                200,
                [SELECT COUNT() FROM Contact WHERE FirstName = 'John'],
                'No John renamed.'
            );
            Assert.areEqual(
                100,
                [SELECT COUNT() FROM Contact WHERE FirstName = 'Jane'],
                'Jane x100.'
            );
        }
    }
}
