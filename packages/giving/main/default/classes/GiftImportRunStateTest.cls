/**
 * What a gift import run carries from chunk to chunk (R-DM1, R-DM4): a repeat of an external
 * ID loaded by an earlier chunk is Matched, in the dry run as in the commit, and under Never
 * match too.
 */
@IsTest
private class GiftImportRunStateTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.adminWith('Giving_Admin');
    }

    private static User maria() {
        return TestDataFactory.createUser(
            'Maria',
            new List<String>{ 'BarnCRM_Admin', 'Giving_Admin' }
        );
    }

    /** Runs each row as a chunk of its own, the state carried between them as the batch does. */
    private static List<Import_Row__c> runInChunks(
        Import_Batch__c batch,
        Import_Template__c template,
        Boolean dryRun
    ) {
        ImportEntityProcessors.carriedState = null;
        for (Import_Row__c row : ImportTestDataFactory.reload(batch.Id)) {
            ImportRowProcessor.process(
                batch,
                template,
                ImportMapping.parse(template.Column_Mapping_JSON__c),
                new List<Import_Row__c>{ row },
                dryRun
            );
        }
        return [
            SELECT Status__c, Error_Message__c
            FROM Import_Row__c
            WHERE Import_Batch__c = :batch.Id
            ORDER BY Row_Number__c
        ];
    }

    @IsTest
    static void aDryRunChunkCarriesAndAsksTheSameHoweverManyExternalIdsCameBefore() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            TestDataFactory.defaultSettings();
            insert new Fund__c(Name = 'General', Active__c = true, Is_Default__c = true);
            insert new Contact(LastName = 'Ramirez', Email = 'ana@example.org');
            ImportMapping mapping = new ImportMapping();
            for (
                String target : new List<String>{
                    'Contact1.Email',
                    'Contact1.LastName',
                    'Gift.Amount__c',
                    'Gift.Gift_Date__c',
                    'Gift.Type__c',
                    'Gift.External_Id__c'
                }
            ) {
                mapping.columns.add(new ImportMapping.Column(target, target));
            }
            Import_Template__c template = ImportTestDataFactory.template(
                mapping.serialize(),
                ImportTemplateService.RULE_EMAIL
            );
            Import_Batch__c batch = ImportTestDataFactory.batch(template);
            List<Map<String, String>> rows = new List<Map<String, String>>();
            // A repeat in chunks 2 and 4 finds the key chunk 1 stored, under the same check; chunks
            // 3 and 5 are new gifts. A repeat asks less than a new gift, so like is compared with like.
            for (
                String externalId : new List<String>{
                    'order-0',
                    'order-0',
                    'order-1',
                    'ORDER-0',
                    'order-2'
                }
            ) {
                rows.add(
                    new Map<String, String>{
                        'Contact1.Email' => 'ana@example.org',
                        'Contact1.LastName' => 'Ramirez',
                        'Gift.Amount__c' => '25',
                        'Gift.Gift_Date__c' => '2026-03-15',
                        'Gift.Type__c' => 'cash',
                        'Gift.External_Id__c' => externalId
                    }
                );
            }
            ImportTestDataFactory.rows(batch, rows);
            List<Integer> queries = new List<Integer>();
            List<Integer> carried = new List<Integer>();

            System.runAs(maria()) {
                Test.startTest();
                ImportEntityProcessors.carriedState = null;
                for (Import_Row__c row : ImportTestDataFactory.reload(batch.Id)) {
                    Integer before = Limits.getQueries();
                    ImportRowProcessor.process(
                        batch,
                        template,
                        ImportMapping.parse(template.Column_Mapping_JSON__c),
                        new List<Import_Row__c>{ row },
                        true
                    );
                    queries.add(Limits.getQueries() - before);
                    carried.add(ImportEntityProcessors.carriedState.length());
                }
                Test.stopTest();
            }

            for (Integer index = 1; index < carried.size(); index++) {
                Assert.areEqual(carried[0], carried[index], 'No external ID is carried (R-DM1).');
            }
            Assert.areEqual(queries[1], queries[3], 'The later repeat asks as often as the first.');
            Assert.areEqual(queries[2], queries[4], 'The later new gift asks as often too.');
            Assert.areEqual(
                3,
                // In no permission set, so read in system mode (ADR-0021).
                Database.countQueryWithBinds(
                    'SELECT COUNT() FROM Import_Row__c' +
                    ' WHERE Import_Batch__c = :batchId AND Processor_Key__c != NULL',
                    new Map<String, Object>{ 'batchId' => batch.Id },
                    AccessLevel.SYSTEM_MODE
                ),
                'Each row that would load a gift keeps its external ID digest instead.'
            );
            List<Import_Row__c> previewed = ImportTestDataFactory.reload(batch.Id);
            Assert.areEqual(ImportRowProcessor.STATUS_MATCHED, previewed[1].Status__c, 'A repeat.');
            Assert.areEqual(ImportRowProcessor.STATUS_MATCHED, previewed[3].Status__c, 'Another.');
            Assert.areEqual(0, [SELECT COUNT() FROM Gift__c], 'A dry run writes no gift.');
        }
    }

    @IsTest
    static void aRepeatInALaterChunkIsMatchedInTheDryRunAsInTheCommit() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            TestDataFactory.defaultSettings();
            insert new Fund__c(Name = 'General', Active__c = true, Is_Default__c = true);
            // Ana is already here, so each row's status is its gift's alone.
            insert new Contact(LastName = 'Ramirez', Email = 'ana@example.org');
            ImportMapping mapping = new ImportMapping();
            for (
                String target : new List<String>{
                    'Contact1.Email',
                    'Contact1.LastName',
                    'Gift.Amount__c',
                    'Gift.Gift_Date__c',
                    'Gift.Type__c',
                    'Gift.External_Id__c'
                }
            ) {
                mapping.columns.add(new ImportMapping.Column(target, target));
            }
            Import_Template__c template = ImportTestDataFactory.template(
                mapping.serialize(),
                ImportTemplateService.RULE_EMAIL
            );
            template.Payment_Matching__c = DonationMatcher.NEVER_MATCH;
            update template;
            Import_Batch__c batch = ImportTestDataFactory.batch(template);
            List<Map<String, String>> rows = new List<Map<String, String>>();
            for (String externalId : new List<String>{ 'order-1', 'ORDER-1' }) {
                rows.add(
                    new Map<String, String>{
                        'Contact1.Email' => 'ana@example.org',
                        'Contact1.LastName' => 'Ramirez',
                        'Gift.Amount__c' => '25',
                        'Gift.Gift_Date__c' => '2026-03-15',
                        'Gift.Type__c' => 'cash',
                        'Gift.External_Id__c' => externalId
                    }
                );
            }
            ImportTestDataFactory.rows(batch, rows);
            List<Import_Row__c> dryRun;
            List<Import_Row__c> committed;

            System.runAs(maria()) {
                Test.startTest();
                dryRun = runInChunks(batch, template, true);
                committed = runInChunks(batch, template, false);
                Test.stopTest();
            }

            Assert.areEqual(
                ImportRowProcessor.STATUS_CREATED,
                dryRun[0].Status__c,
                'Would be new.'
            );
            Assert.areEqual(
                ImportRowProcessor.STATUS_MATCHED,
                dryRun[1].Status__c,
                'The repeat would be the same gift: ' + dryRun[1].Error_Message__c
            );
            for (Integer index = 0; index < 2; index++) {
                Assert.areEqual(
                    dryRun[index].Status__c,
                    committed[index].Status__c,
                    'The commit agrees on row ' + index + ': ' + committed[index].Error_Message__c
                );
            }
            Assert.areEqual(1, [SELECT COUNT() FROM Gift__c], 'One gift, not two.');
        }
    }

    @IsTest
    static void aStateItDidNotWriteCarriesNothing() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            ImportEntityProcessors.carriedState = 'not a state';
            GiftImportRunState state = GiftImportRunState.carried();
            Assert.isTrue(state.claimedInstallments.isEmpty(), 'No payments.');
            Assert.isNull(state.settings, 'No matching values.');

            String prefix = Installment__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
                .getKeyPrefix();
            state.claimedInstallments.add(Id.valueOf(prefix + '000000000001'));
            state.carry();

            Assert.areEqual(1, GiftImportRunState.carried().claimedInstallments.size(), 'Carried.');
            Assert.areEqual(
                GiftImportRunState.key('Order-7'),
                GiftImportRunState.key('ORDER-7'),
                'An external ID has one key whatever its case.'
            );
        }
    }

    @IsTest
    static void theMatchingValuesAreReadWithoutTheRestOfTheState() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            ImportEntityProcessors.carriedState = null;
            Assert.isNull(GiftImportRunState.carriedSettings(), 'Nothing carried yet.');
            GiftImportRunState state = GiftImportRunState.carried();
            state.settings = '{"donationMatching":"Match only"}';
            state.carry();

            Assert.areEqual(
                '{"donationMatching":"Match only"}',
                GiftImportRunState.carriedSettings(),
                'Read from the head of the state.'
            );
            GiftImportRunState again = GiftImportRunState.carried();
            Assert.areEqual(state.settings, again.settings, 'And kept by a full read too.');
            ImportEntityProcessors.carriedState = 'not a state';
            Assert.isNull(
                GiftImportRunState.carriedSettings(),
                'A state it did not write has none.'
            );
        }
    }
}
