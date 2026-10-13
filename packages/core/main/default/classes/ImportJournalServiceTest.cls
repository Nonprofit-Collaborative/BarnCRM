/**
 * The import journal: a page per chunk, split rather than shortened, read back as written,
 * and never the reason an import fails (canonical model Section 17A).
 */
@IsTest(testFor='ApexClass:ImportJournalService')
private class ImportJournalServiceTest {
    private static Import_Batch__c newBatch() {
        TestDataFactory.defaultSettings();
        return ImportTestDataFactory.batch(
            ImportTestDataFactory.template(
                ImportTestDataFactory.donorMapping(),
                ImportTemplateService.RULE_EMAIL
            )
        );
    }

    private static Map<String, Object> anUpdate(Integer row) {
        return ImportJournalService.updated(
            'Contact',
            null,
            row,
            new Map<String, Object>{ 'Email' => 'old@example.org' },
            new Map<String, Object>{ 'Email' => 'new@example.org' }
        );
    }

    @IsTest
    static void writesOnePageAndReadsItBackAsWritten() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c batch = newBatch();
            Test.startTest();
            Boolean written = ImportJournalService.write(
                batch.Id,
                ImportJournalService.PHASE_COMMIT,
                new List<Map<String, Object>>{ anUpdate(2), anUpdate(3) }
            );
            Test.stopTest();

            Assert.isTrue(written, 'The page was written.');
            List<Import_Journal__c> pages = ImportJournalService.pages(
                batch.Id,
                ImportJournalService.PHASE_COMMIT,
                10
            );
            Assert.areEqual(1, pages.size(), 'Two entries fit one page (R-IJ1).');
            Assert.areEqual(2, pages[0].Entry_Count__c, 'The page counts its entries.');
            Map<String, Object> entry = ImportJournalService.entries(pages[0])[0];
            Map<String, Object> email = (Map<String, Object>) ((Map<String, Object>) entry.get(
                    'fields'
                ))
                .get('Email');
            Assert.areEqual('old@example.org', email.get('before'), 'The value before is kept.');
            Assert.areEqual('new@example.org', email.get('after'), 'And the value written.');
            Assert.areEqual(
                2,
                ImportJournalService.entryCount(batch.Id, ImportJournalService.PHASE_COMMIT),
                'The total is a sum of the pages.'
            );
        }
    }

    @IsTest
    static void aPageTooLargeIsSplitNotShortened() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c batch = newBatch();
            List<Map<String, Object>> entries = new List<Map<String, Object>>();
            for (Integer i = 0; i < 4; i++) {
                entries.add(anUpdate(i + 2));
            }
            Integer onePage = JSON.serialize(
                    new Map<String, Object>{ 'version' => 1, 'entries' => entries }
                )
                .length();
            ImportJournalService.maxDocumentLength = onePage / 2;

            Test.startTest();
            ImportJournalService.write(batch.Id, ImportJournalService.PHASE_COMMIT, entries);
            Test.stopTest();

            List<Import_Journal__c> pages = ImportJournalService.pages(
                batch.Id,
                ImportJournalService.PHASE_COMMIT,
                10
            );
            Assert.isTrue(pages.size() > 1, 'The entries were spread over more than one page.');
            Assert.areEqual(
                4,
                ImportJournalService.entryCount(batch.Id, ImportJournalService.PHASE_COMMIT),
                'And none was lost, because a lost entry is a change nobody can put back.'
            );
        }
    }

    @IsTest
    static void anEntryTooLargeForAnyPageIsLoggedAndTheOthersAreWritten() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c batch = newBatch();
            Map<String, Object> small = anUpdate(2);
            Map<String, Object> large = anUpdate(3);
            ((Map<String, Object>) large.get('fields'))
                .put(
                    'Description',
                    new Map<String, Object>{
                        'before' => 'x'.repeat(4000),
                        'after' => 'y'.repeat(4000)
                    }
                );
            ImportJournalService.maxDocumentLength = 2000;
            Test.startTest();
            Boolean written = ImportJournalService.write(
                batch.Id,
                ImportJournalService.PHASE_COMMIT,
                new List<Map<String, Object>>{ small, large }
            );
            Test.stopTest();
            Assert.isFalse(written, 'The caller is told, so the run log can say so (R-IJ4).');
            Assert.areEqual(
                1,
                ImportJournalService.entryCount(batch.Id, ImportJournalService.PHASE_COMMIT),
                'The entry that fits is still written (R-IJ1).'
            );
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Error_Log__c WHERE Context__c = 'ImportJournalService.write'],
                'And the one that does not is in the Error Log.'
            );
        }
    }

    @IsTest
    static void aPageHoldsAtMostTheEntryCap() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c batch = newBatch();
            ImportJournalService.maxEntriesPerPage = 2;
            ImportJournalService.write(
                batch.Id,
                ImportJournalService.PHASE_COMMIT,
                new List<Map<String, Object>>{ anUpdate(2), anUpdate(3), anUpdate(4), anUpdate(5) }
            );
            Assert.areEqual(
                2,
                [SELECT COUNT() FROM Import_Journal__c WHERE Import_Batch__c = :batch.Id],
                'Four entries at two a page are two pages.'
            );
        }
    }

    @IsTest
    static void nothingToWriteWritesNothing() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c batch = newBatch();
            Assert.isTrue(
                ImportJournalService.write(
                    batch.Id,
                    ImportJournalService.PHASE_UNDO,
                    new List<Map<String, Object>>()
                ),
                'An empty chunk is not a failure.'
            );
            Assert.areEqual(0, [SELECT COUNT() FROM Import_Journal__c], 'And writes no page.');
        }
    }

    @IsTest
    static void keptAndNotRestoredEntriesCarryTheirReasons() {
        System.runAs(TestUsers.admin()) {
            Map<String, Object> kept = ImportJournalService.kept(
                'Account',
                null,
                'The Smith Family',
                'Somebody else lives here.'
            );
            Map<String, Object> notRestored = ImportJournalService.notRestored(
                'Contact',
                null,
                'Email',
                'Changed since the import.'
            );
            Assert.areEqual(ImportJournalService.ACTION_KEPT, kept.get('action'), 'A kept record.');
            Assert.areEqual('Somebody else lives here.', kept.get('reason'), 'With its reason.');
            Assert.areEqual(
                'Email',
                notRestored.get('field'),
                'A value left alone names its field.'
            );
        }
    }
}
