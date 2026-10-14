/**
 * Undoing a gift import that created people (canonical model R-IB9, R-GI9, ADR-NEXT).
 *
 * Deleting the imported gifts sets off the donors' rollups. In an org the Rollup Queue saves
 * them, started by its platform event as the Automated Process user: somebody other than the
 * person undoing. Here the gift pass runs as a second user, so the totals it sets off are saved
 * by somebody who is not the undo, as they are in an org. Those saves are not edits, and the
 * people go; a person somebody edited after the import stays.
 *
 * The import is made in @TestSetup, the passes before the people's run after Test.startTest,
 * and the people's as a job, so each part has its own governor limits as each chunk of the job
 * does: the undo's checks keep what they cannot afford to ask about. Public so `GiftImportUndoPersonAccountsTest` shares it.
 */
@IsTest(testFor='ApexClass:GiftImportProcessor')
public class GiftImportUndoTest {
    private static final Integer DONORS = 3;

    @TestSetup
    static void importDonors() {
        createUsers();
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            imported(null);
        }
    }

    /** The users these tests run as, made once. */
    public static void createUsers() {
        TestUsers.adminWith('Giving_Admin');
        rollupQueue();
        TestUsers.admin();
    }

    /** The second user the gift pass runs as: it deletes gifts, so it holds Giving Admin. */
    private static User rollupQueue() {
        return TestUsers.withPermissionSets(
            new List<String>{ TestUsers.CORE_ADMIN, 'Giving_Admin', 'Giving_Staff' }
        );
    }

    /**
     * Imports one gift from each of three new donors, with the shipped rollups recalculated in
     * the save, and marks the batch committed by the running user, started five minutes ago.
     */
    public static void imported(String personMode) {
        TestDataFactory.defaultSettings();
        GivingTestDataFactory.insertDefaultFund();
        GivingRollupTestData.installShippedRollups();
        ImportMapping mapping = new ImportMapping();
        mapping.columns.add(new ImportMapping.Column('Email', 'Contact1.Email'));
        mapping.columns.add(new ImportMapping.Column('Last Name', 'Contact1.LastName'));
        mapping.columns.add(new ImportMapping.Column('Payment Method', 'Gift.Type__c'));
        mapping.columns.add(new ImportMapping.Column('Amount', 'Gift.Amount__c'));
        mapping.columns.add(new ImportMapping.Column('Date', 'Gift.Gift_Date__c'));
        Import_Template__c template = ImportTestDataFactory.template(
            mapping.serialize(),
            ImportTemplateService.RULE_EMAIL
        );
        if (personMode != null) {
            template.Person_Mode__c = personMode;
            update template;
        }
        Import_Batch__c batch = ImportTestDataFactory.batch(template);
        List<Map<String, String>> rows = new List<Map<String, String>>();
        for (Integer index = 0; index < DONORS; index++) {
            rows.add(
                new Map<String, String>{
                    'Email' => 'donor' +
                    index +
                    '@example.org',
                    'Last Name' => 'Donor' + index,
                    'Payment Method' => 'cash',
                    'Amount' => '100.00',
                    'Date' => '2026-03-15'
                }
            );
        }
        ImportTestDataFactory.rows(batch, rows);
        ImportRowProcessor.process(
            batch,
            template,
            ImportMapping.parse(template.Column_Mapping_JSON__c),
            ImportTestDataFactory.reload(batch.Id),
            false
        );
        batch.Is_Dry_Run__c = false;
        batch.Status__c = ImportBatchService.STATUS_COMPLETE;
        batch.Started_At__c = Datetime.now().addMinutes(-5);
        batch.Completed_At__c = Datetime.now().addMinutes(1);
        batch.Committed_By__c = UserInfo.getUserId();
        batch.Undo_Deadline__c = Datetime.now().addDays(30);
        update batch;
    }

    /** The batch the setup imported. */
    public static Import_Batch__c batch() {
        return [SELECT Id FROM Import_Batch__c WHERE Committed_By__c != NULL LIMIT 1];
    }

    /** The people and accounts the batch created that are still there. */
    public static Integer taggedLeft(Id batchId) {
        return [SELECT COUNT() FROM Contact WHERE Created_By_Import_Batch__c = :batchId] +
            [SELECT COUNT() FROM Account WHERE Created_By_Import_Batch__c = :batchId];
    }

    private static String undoJournal(Id batchId) {
        String text = '';
        for (Import_Journal__c page : [
            SELECT Entries_JSON__c
            FROM Import_Journal__c
            WHERE Import_Batch__c = :batchId AND Phase__c = :ImportJournalService.PHASE_UNDO
        ]) {
            text += page.Entries_JSON__c;
        }
        return text;
    }

    /**
     * Undoes the batch as the running user, its gifts deleted by the second user, so the
     * totals they set off are saved by somebody who is not the undo. The passes before the
     * people's run after Test.startTest, and the people's as a job, each with limits of their
     * own.
     */
    public static void undo(Id batchId) {
        Assert.areEqual(
            DONORS,
            [SELECT COUNT() FROM Gift__c WHERE Created_By_Import_Batch__c = :batchId],
            'One gift a donor was imported.'
        );
        GivingRollupTestData.nextSave();
        Integer total = ImportUndoService.preview(batchId).total;
        // Latched only: the passes below are the only ones that run.
        System.abortJob(ImportUndoService.start(batchId, total));
        ImportUndoTestSupport.Run run = new ImportUndoTestSupport.Run(
            batchId,
            total,
            Datetime.newInstance((Datetime.now().getTime() / 1000) * 1000)
        );
        Test.startTest();
        System.runAs(rollupQueue()) {
            run.beforePeople();
        }
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Gift__c WHERE Created_By_Import_Batch__c = :batchId],
            'The gifts are gone first. ' + undoJournal(batchId)
        );
        run.queueRest();
        Test.stopTest();
    }

    @IsTest
    static void undoingRemovesThePeopleWhoseTotalsTheUndoRecalculated() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Id batchId = batch().Id;

            undo(batchId);

            Assert.areEqual(
                0,
                taggedLeft(batchId),
                'Every person and household the import made goes. ' + undoJournal(batchId)
            );
        }
    }

    @IsTest
    static void aPersonEditedAfterTheImportIsKept() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Id batchId = batch().Id;
            Contact edited = [
                SELECT Id
                FROM Contact
                WHERE Created_By_Import_Batch__c = :batchId
                ORDER BY Id
                LIMIT 1
            ];
            System.runAs(TestUsers.admin()) {
                // Somebody else's edit to a field no rollup writes. A test runs within a
                // second, so the totals are dated an hour earlier, as they would be.
                Database.update(
                    new Contact(
                        Id = edited.Id,
                        Title = 'Board chair',
                        Rollups_Last_Calculated__c = Datetime.now().addHours(-1)
                    ),
                    AccessLevel.SYSTEM_MODE
                );
            }

            undo(batchId);

            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Contact WHERE Created_By_Import_Batch__c = :batchId],
                'Only the edited person stays. ' + undoJournal(batchId)
            );
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Contact WHERE Id = :edited.Id],
                'And it is the one edited.'
            );
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Account WHERE Created_By_Import_Batch__c = :batchId],
                'With the household they are still on.'
            );
        }
    }
}
