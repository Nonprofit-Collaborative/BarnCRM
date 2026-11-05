/**
 * The nightly Record Cleanup (L-08, R-NJ8): each pass deletes only rows past the org's retention
 * and keeps newer ones, a finished import goes only once its undo window has closed, and each
 * retention setting falls back to its default and is held between its bounds.
 */
@IsTest(testFor='ApexClass:RecordRetentionBatch')
private class RecordRetentionBatchTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    /** Runs one pass's start and execute in this transaction, as the job would. */
    private static void runPass(Integer pass) {
        RecordRetentionBatch.chain = false;
        RecordRetentionBatch cleanup = new RecordRetentionBatch(pass);
        List<SObject> scope = new List<SObject>();
        Database.QueryLocatorIterator found = cleanup.start(null).iterator();
        while (found.hasNext()) {
            scope.add(found.next());
        }
        if (!scope.isEmpty()) {
            cleanup.execute(null, scope);
        }
        cleanup.finish(null);
    }

    @IsTest
    static void settingChangesPastTheirDaysAreDeleted() {
        System.runAs(TestUsers.admin()) {
            Setting_Change__c old = new Setting_Change__c(
                Setting_Name__c = 'Old',
                Changed_At__c = Datetime.now().addDays(-731)
            );
            Setting_Change__c recent = new Setting_Change__c(
                Setting_Name__c = 'Recent',
                Changed_At__c = Datetime.now().addDays(-10)
            );
            insert as system new List<Setting_Change__c>{ old, recent };

            Test.startTest();
            runPass(RecordRetentionBatch.SETTING_CHANGES);
            Test.stopTest();

            List<Setting_Change__c> left = [SELECT Id FROM Setting_Change__c WITH SYSTEM_MODE];
            Assert.areEqual(1, left.size(), 'Only the change past 730 days is deleted');
            Assert.areEqual(recent.Id, left[0].Id, 'The recent change is kept');
        }
    }

    @IsTest
    static void mergeJournalPastItsDaysIsDeleted() {
        System.runAs(TestUsers.admin()) {
            Merge_Journal__c old = new Merge_Journal__c(Merged_Name__c = 'Old');
            Merge_Journal__c recent = new Merge_Journal__c(Merged_Name__c = 'Recent');
            insert as system new List<Merge_Journal__c>{ old, recent };
            Test.setCreatedDate(old.Id, Datetime.now().addDays(-366));

            Test.startTest();
            runPass(RecordRetentionBatch.MERGE_JOURNAL);
            Test.stopTest();

            List<Merge_Journal__c> left = [SELECT Id FROM Merge_Journal__c WITH SYSTEM_MODE];
            Assert.areEqual(1, left.size(), 'Only the entry past 365 days is deleted');
            Assert.areEqual(recent.Id, left[0].Id, 'The recent entry is kept');
        }
    }

    @IsTest
    static void finishedImportsGoOnlyOnceTheirUndoWindowCloses() {
        System.runAs(TestUsers.admin()) {
            Import_Template__c template = ImportTestDataFactory.template(
                ImportTestDataFactory.donorMapping(),
                ImportTemplateService.RULE_EMAIL
            );
            Import_Batch__c closed = ImportTestDataFactory.batch(template);
            Import_Batch__c undoOpen = ImportTestDataFactory.batch(template);
            Import_Batch__c running = ImportTestDataFactory.batch(template);
            for (Import_Batch__c batch : new List<Import_Batch__c>{ closed, undoOpen, running }) {
                Test.setCreatedDate(batch.Id, Datetime.now().addDays(-400));
                ImportTestDataFactory.rows(
                    batch,
                    new List<Map<String, String>>{
                        ImportTestDataFactory.donorRow('Ana', 'Row', 'row@example.org', null)
                    }
                );
            }
            // After the rows, which save each batch's in-memory status again.
            update as system new List<Import_Batch__c>{
                new Import_Batch__c(
                    Id = closed.Id,
                    Status__c = ImportBatchService.STATUS_COMPLETE,
                    Undo_Deadline__c = Datetime.now().addDays(-300)
                ),
                new Import_Batch__c(
                    Id = undoOpen.Id,
                    Status__c = ImportBatchService.STATUS_COMPLETE,
                    Undo_Deadline__c = Datetime.now().addDays(5)
                )
            };
            insert as system new Import_Journal__c(Import_Batch__c = closed.Id);

            Test.startTest();
            runPass(RecordRetentionBatch.IMPORT_JOURNAL);
            runPass(RecordRetentionBatch.IMPORT_ROWS);
            runPass(RecordRetentionBatch.IMPORT_BATCHES);
            Test.stopTest();

            Set<Id> left = new Map<Id, Import_Batch__c>(
                    [SELECT Id FROM Import_Batch__c WITH SYSTEM_MODE]
                )
                .keySet();
            Assert.isFalse(left.contains(closed.Id), 'A finished import past its undo is deleted');
            Assert.isTrue(left.contains(undoOpen.Id), 'An import that can still be undone is kept');
            Assert.isTrue(left.contains(running.Id), 'An unfinished import is kept');
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Import_Journal__c WITH SYSTEM_MODE],
                'The deleted import\'s journal goes first'
            );
            Assert.areEqual(
                2,
                [SELECT COUNT() FROM Import_Row__c WITH SYSTEM_MODE],
                'Only the deleted import\'s rows go'
            );
        }
    }

    @IsTest
    static void fieldUseCountsPastTheirDaysAreDeleted() {
        System.runAs(TestUsers.admin()) {
            Field_Utilization_Snapshot__c old = new Field_Utilization_Snapshot__c(
                Object_Name__c = 'Account',
                Field_Name__c = 'Name',
                Taken_At__c = Datetime.now().addDays(-800)
            );
            Field_Utilization_Snapshot__c recent = new Field_Utilization_Snapshot__c(
                Object_Name__c = 'Account',
                Field_Name__c = 'Name',
                Taken_At__c = Datetime.now().addDays(-1)
            );
            insert as system new List<Field_Utilization_Snapshot__c>{ old, recent };

            Test.startTest();
            runPass(RecordRetentionBatch.FIELD_UTILIZATION);
            Test.stopTest();

            List<Field_Utilization_Snapshot__c> left = [
                SELECT Id
                FROM Field_Utilization_Snapshot__c
                WITH SYSTEM_MODE
            ];
            Assert.areEqual(1, left.size(), 'Only the count past 730 days is deleted');
            Assert.areEqual(recent.Id, left[0].Id, 'The recent count is kept');
        }
    }

    @IsTest
    static void daysFallBackToDefaultsAndStayInBounds() {
        System.runAs(TestUsers.admin()) {
            Assert.areEqual(365, RecordRetentionBatch.mergeJournalDays(), 'Merge journal default');
            Assert.areEqual(
                730,
                RecordRetentionBatch.settingChangeDays(),
                'Setting change default'
            );

            BarnCRM_Settings__c settings = BarnCRM_Settings__c.getOrgDefaults();
            settings.Merge_Journal_Retention_Days__c = 5;
            settings.Setting_Change_Retention_Days__c = 9000;
            settings.Import_History_Retention_Days__c = 90;
            TestDataFactory.saveSettings(settings);

            Assert.areEqual(30, RecordRetentionBatch.mergeJournalDays(), 'Held at the minimum');
            Assert.areEqual(3650, RecordRetentionBatch.settingChangeDays(), 'Held at ten years');
            Assert.areEqual(
                90,
                RecordRetentionBatch.importHistoryDays(),
                'A value in range is kept'
            );
        }
    }

    @IsTest
    static void theStepStartsTheFirstPassAndChainsTheRest() {
        // runs-as: deploying user (only starts a batch; reads AsyncApexJob, no permission set involved)
        NightlyStep step = RecordRetentionBatch.step();
        Assert.areEqual(RecordRetentionBatch.JOB_NAME, step.key, 'The step carries the job key');

        Test.startTest();
        new RecordRetentionBatch().execute((SchedulableContext) null);
        Test.stopTest();

        Assert.isTrue(
            [
                SELECT COUNT()
                FROM AsyncApexJob
                WHERE ApexClass.Name = 'RecordRetentionBatch' AND JobType = 'BatchApex'
            ] >= 1,
            'The step starts the first pass'
        );
    }
}
