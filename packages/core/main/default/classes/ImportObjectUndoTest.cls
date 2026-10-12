/**
 * Undoing a one-object import (canonical model R-IB8, R-IB9, R-IJ3): the records it created are
 * journaled on Created pages, counted under their object's label, and deleted from there; the
 * values it changed are put back; a journaled record the committer did not create during the
 * commit, or one edited since, is kept.
 *
 * The undo's passes are driven one after another through the job's own start query, as
 * `ImportUndoTest` drives them, and everything runs as a minimal-profile user holding only
 * BarnCRM Admin.
 */
@IsTest
private class ImportObjectUndoTest {
    private static final Integer MANY = 200;

    private static Import_Batch__c batch;

    @TestSetup
    static void setUp() {
        TestDataFactory.defaultSettings();
    }

    private static User admin() {
        return TestDataFactory.createUser('Maria', new List<String>{ 'BarnCRM_Admin' });
    }

    /** Upserts the rows as a commit started a minute ago by the running user. */
    private static void commitUpsert(List<Map<String, String>> values) {
        ImportEntityProcessors.noneForTest = true;
        ImportMapping mapping = new ImportMapping();
        mapping.columns.add(new ImportMapping.Column('Pair Key', 'Record.Pair_Key__c'));
        mapping.columns.add(new ImportMapping.Column('Reason', 'Record.Reason__c'));
        Import_Template__c template = ImportTestDataFactory.template(mapping.serialize(), null);
        template.Target_Object__c = 'Duplicate_Dismissal__c';
        template.Load_Operation__c = ImportObjectSchema.OPERATION_UPSERT;
        template.Load_Match_Field__c = 'Pair_Key__c';
        update template;
        batch = ImportTestDataFactory.batch(template);
        ImportTestDataFactory.rows(batch, values);
        batch.Is_Dry_Run__c = false;
        batch.Status__c = ImportBatchService.STATUS_COMMITTING;
        batch.Started_At__c = Datetime.now().addMinutes(-1);
        batch.Committed_By__c = UserInfo.getUserId();
        batch.Undo_Deadline__c = Datetime.now().addDays(30);
        update batch;
        ImportBatchService.beginPass(batch.Id);
        ImportRowProcessor.process(
            ImportBatchSelector.selectById(batch.Id),
            ImportTemplateSelector.selectById(template.Id),
            mapping,
            ImportTestDataFactory.reload(batch.Id),
            false
        );
        update new Import_Batch__c(
            Id = batch.Id,
            Status__c = ImportBatchService.STATUS_COMPLETE,
            Completed_At__c = Datetime.now()
        );
    }

    private static List<Map<String, String>> rowsFor(Integer count, String reason) {
        List<Map<String, String>> result = new List<Map<String, String>>();
        for (Integer i = 0; i < count; i++) {
            result.add(new Map<String, String>{ 'Pair Key' => 'K' + i, 'Reason' => reason });
        }
        return result;
    }

    private static List<Duplicate_Dismissal__c> dismissals(Integer count, String reason) {
        List<Duplicate_Dismissal__c> result = new List<Duplicate_Dismissal__c>();
        for (Integer i = 0; i < count; i++) {
            result.add(new Duplicate_Dismissal__c(Pair_Key__c = 'K' + i, Reason__c = reason));
        }
        insert result;
        return result;
    }

    /** Runs every pass of the undo, each page or chunk on its own, as the job would. */
    private static void undo(Integer total) {
        Datetime undoStartedAt = Datetime.now();
        for (String pass : ImportUndoBatch.passes()) {
            ImportUndoBatch job = new ImportUndoBatch(
                batch.Id,
                total,
                pass,
                0,
                false,
                undoStartedAt
            );
            Database.QueryLocatorIterator records = job.start(null).iterator();
            while (records.hasNext()) {
                job.execute(null, new List<SObject>{ records.next() });
            }
        }
    }

    private static String undoJournal() {
        String text = '';
        for (Import_Journal__c page : [
            SELECT Entries_JSON__c
            FROM Import_Journal__c
            WHERE Import_Batch__c = :batch.Id AND Phase__c = :ImportJournalService.PHASE_UNDO
        ]) {
            text += page.Entries_JSON__c;
        }
        return text;
    }

    @IsTest
    static void undoOfTwoHundredUpsertRowsDeletesWhatTheyCreatedAndPutsBackWhatTheyChanged() {
        System.runAs(admin()) {
            List<Duplicate_Dismissal__c> existing = dismissals(MANY / 2, 'Old');
            commitUpsert(rowsFor(MANY, 'New'));

            Test.startTest();
            ImportUndoService.Preview view = ImportUndoService.preview(batch.Id);
            undo(view.total);
            Test.stopTest();

            Assert.isTrue(view.allowed, 'A committed one-object import can be undone.');
            Assert.areEqual(MANY / 2, view.total, 'The records it created are confirmed.');
            Assert.areEqual(MANY / 2, view.updates, 'The values it changed are counted.');
            Assert.areEqual(1, view.others.size(), 'Under one object.');
            Assert.areEqual(
                Duplicate_Dismissal__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
                    .getLabelPlural(),
                view.others[0].label,
                'Labelled as the org labels it.'
            );
            Assert.areEqual(
                MANY / 2,
                [SELECT COUNT() FROM Duplicate_Dismissal__c],
                'Only the records that were there before are left: ' + undoJournal()
            );
            Assert.areEqual(
                MANY / 2,
                [
                    SELECT COUNT()
                    FROM Duplicate_Dismissal__c
                    WHERE Id IN :existing AND Reason__c = 'Old'
                ],
                'And each holds its value from before.'
            );
        }
    }

    @IsTest
    static void aJournaledRecordTheCommitterDidNotCreateDuringTheCommitIsKept() {
        Duplicate_Dismissal__c someoneElses = dismissals(1, 'Theirs')[0];
        User maria = admin();
        System.runAs(maria) {
            commitUpsert(
                new List<Map<String, String>>{
                    new Map<String, String>{ 'Pair Key' => 'Mine', 'Reason' => 'New' }
                }
            );
            // A journal entry naming somebody else's record, as a tampered page would.
            ImportJournalService.write(
                batch.Id,
                ImportJournalService.PHASE_CREATED,
                new List<Map<String, Object>>{
                    ImportJournalService.created('Duplicate_Dismissal__c', someoneElses.Id, 9)
                }
            );

            Test.startTest();
            undo(ImportUndoService.preview(batch.Id).total);
            Test.stopTest();
        }

        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Duplicate_Dismissal__c WHERE Id = :someoneElses.Id],
            'Somebody else record is never deleted by a journal entry.'
        );
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Duplicate_Dismissal__c WHERE Pair_Key__c = 'Mine'],
            'The record the import created is.'
        );
        Assert.isTrue(
            undoJournal().contains(Label.Core_Import_UndoKeptNotCreatedByImport.left(40)),
            'The kept record is journaled with why.'
        );
    }

    @IsTest
    static void aCreatedRecordSomebodyEditedSinceIsKept() {
        User maria = admin();
        System.runAs(maria) {
            commitUpsert(rowsFor(2, 'New'));
        }
        // Somebody other than the committer edits one record after the commit.
        Duplicate_Dismissal__c edited = [
            SELECT Id
            FROM Duplicate_Dismissal__c
            WHERE Pair_Key__c = 'K0'
        ];
        update new Duplicate_Dismissal__c(Id = edited.Id, Reason__c = 'Corrected');

        System.runAs(maria) {
            Test.startTest();
            undo(ImportUndoService.preview(batch.Id).total);
            Test.stopTest();
        }

        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Duplicate_Dismissal__c WHERE Id = :edited.Id],
            'An edited record is kept.'
        );
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Duplicate_Dismissal__c WHERE Pair_Key__c = 'K1'],
            'The other is deleted.'
        );
    }

    @IsTest
    static void aSecondRunCountsWhatIsAlreadyGoneAsGone() {
        System.runAs(admin()) {
            commitUpsert(rowsFor(3, 'New'));
            Integer total = ImportUndoService.preview(batch.Id).total;

            Test.startTest();
            undo(total);
            undo(total);
            ImportUndoService.finish(batch.Id, total, 0, false, total);
            Test.stopTest();

            Import_Batch__c finished = ImportBatchSelector.selectById(batch.Id);
            Assert.areEqual(0, [SELECT COUNT() FROM Duplicate_Dismissal__c], 'All gone.');
            Assert.areEqual(
                ImportBatchService.STATUS_UNDONE,
                finished.Status__c,
                'A second run is safe and the undo ends Undone.'
            );
        }
    }
}
