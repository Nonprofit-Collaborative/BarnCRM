/**
 * Every long Core job a person starts from a page tells them once when it is over (Q-04), and
 * opens the right place: the job's record for an import, bulk update or bulk delete and their
 * undos, the settings console section for the rest. With the setting off, none of them sends.
 *
 * Each test drives the job's last step directly, as the job's own tests do, and asserts on
 * `JobNotifier.sent`, because a sent notification cannot be read back. These tests have not been
 * executed: no org in this environment.
 */
@IsTest(
    testFor='ApexClass:JobNotifier, ApexClass:ImportBatchService, ApexClass:ImportUndoService, ApexClass:BulkUpdateBatch, ApexClass:BulkDeleteUndoBatch, ApexClass:SeasonalAddressBatch, ApexClass:HouseholdNamingBatch, ApexClass:SampleDataStageBatch'
)
private class JobNotificationPathsTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    /** A sample data load of one stage that throws, or one that works. */
    private class OneStage implements SampleDataStages {
        private final Boolean fails;

        OneStage(Boolean fails) {
            this.fails = fails;
        }

        public String name() {
            return 'OneStage';
        }

        public Integer stageCount() {
            return 1;
        }

        public void runStage(Integer stage) {
            if (fails) {
                throw new IllegalArgumentException('stage stopped');
            }
        }

        public void finish() {
        }
    }

    /** Runs the one stage the way the stage batch does. */
    private static void runOneStage(Boolean fails) {
        SampleDataStageBatch batch = new SampleDataStageBatch(new OneStage(fails));
        batch.start(null);
        batch.runStage(0);
    }

    private static void notifications(Boolean turnedOn) {
        insert new BarnCRM_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Job_Notifications__c = turnedOn
        );
        SettingsService.clearCaches();
    }

    private static Import_Batch__c job(String operation) {
        Import_Batch__c job = new Import_Batch__c(
            Status__c = ImportBatchService.STATUS_COMMITTING,
            Operation__c = operation
        );
        insert job;
        return job;
    }

    private static String title(String label, String jobName) {
        return String.format(label, new List<Object>{ jobName });
    }

    /** Exactly one notification, to the running user, about this record. */
    private static JobNotifier.Notice assertOneAboutRecord(Id recordId, String title) {
        Assert.areEqual(1, JobNotifier.sent.size(), 'Exactly one notification: ' + title);
        JobNotifier.Notice notice = JobNotifier.sent[0];
        Assert.areEqual(UserInfo.getUserId(), notice.recipientId, 'To the person who started it');
        Assert.areEqual(recordId, notice.targetId, 'Opening the job record');
        Assert.areEqual(title, notice.title, 'Saying what happened');
        return notice;
    }

    /** Exactly one notification, to the running user, opening this settings section. */
    private static void assertOneAboutSection(String section, String title) {
        Assert.areEqual(1, JobNotifier.sent.size(), 'Exactly one notification: ' + title);
        JobNotifier.Notice notice = JobNotifier.sent[0];
        Assert.areEqual(UserInfo.getUserId(), notice.recipientId, 'To the person who started it');
        Assert.isNull(notice.targetId, 'No record');
        Assert.areEqual(section, notice.section, 'Opening the settings section');
        Assert.areEqual(title, notice.title, 'Saying what happened');
    }

    @IsTest
    static void importAndPreviewOpenTheImport() {
        System.runAs(TestUsers.admin()) {
            notifications(true);
            Import_Batch__c committed = job(null);

            ImportBatchService.finish(committed.Id, false, false, new List<String>(), null, null);

            JobNotifier.Notice notice = assertOneAboutRecord(
                committed.Id,
                title(System.Label.Core_JobNotice_Finished, System.Label.Core_JobNotice_Import)
            );
            Assert.isTrue(notice.body.contains('0'), 'With the counts');

            JobNotifier.sent.clear();
            Import_Batch__c previewed = job(null);
            ImportBatchService.finish(previewed.Id, true, true, new List<String>(), null, null);
            assertOneAboutRecord(
                previewed.Id,
                title(
                    System.Label.Core_JobNotice_Stopped,
                    System.Label.Core_JobNotice_ImportPreview
                )
            );
        }
    }

    @IsTest
    static void importUndoAndBulkUpdateUndoOpenTheJob() {
        System.runAs(TestUsers.admin()) {
            notifications(true);
            Import_Batch__c imported = job(null);

            ImportUndoService.finish(imported.Id, 0, 0, false, 0);

            assertOneAboutRecord(
                imported.Id,
                title(System.Label.Core_JobNotice_Finished, System.Label.Core_JobNotice_ImportUndo)
            );

            JobNotifier.sent.clear();
            Import_Batch__c updated = job(BulkUpdateService.OPERATION_UPDATE);
            ImportUndoService.finish(updated.Id, 0, 3, true, 0);
            assertOneAboutRecord(
                updated.Id,
                title(
                    System.Label.Core_JobNotice_Stopped,
                    System.Label.Core_JobNotice_BulkUpdateUndo
                )
            );
        }
    }

    @IsTest
    static void aBulkUpdateUndoLogSaysOnlyWhatAUpdateCanDo() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c updated = job(BulkUpdateService.OPERATION_UPDATE);
            Import_Batch__c imported = job(null);

            ImportUndoService.finish(updated.Id, 0, 2, false, 0);
            ImportUndoService.finish(imported.Id, 0, 2, false, 0);

            Map<Id, Import_Batch__c> logs = new Map<Id, Import_Batch__c>(
                [SELECT Run_Log__c FROM Import_Batch__c]
            );
            String updateLog = logs.get(updated.Id).Run_Log__c;
            String importLog = logs.get(imported.Id).Run_Log__c;
            Assert.isTrue(updateLog.contains('2 values put back'), 'Says what was put back');
            Assert.isFalse(updateLog.contains('records deleted'), 'No import wording');
            Assert.isTrue(importLog.contains('records deleted'), 'An import keeps its wording');
        }
    }

    @IsTest
    static void bulkUpdateOpensTheJob() {
        System.runAs(TestUsers.admin()) {
            notifications(true);
            Import_Batch__c updated = job(BulkUpdateService.OPERATION_UPDATE);

            new BulkUpdateBatch(updated.Id).finish(null);

            assertOneAboutRecord(
                updated.Id,
                title(System.Label.Core_JobNotice_Finished, System.Label.Core_JobNotice_BulkUpdate)
            );
        }
    }

    @IsTest
    static void bulkDeleteAndItsUndoOpenTheJob() {
        System.runAs(TestUsers.admin()) {
            notifications(true);
            Import_Batch__c deleted = job(BulkDeleteService.OPERATION_DELETE);

            new BulkDeleteBatch(deleted.Id).finish(null);

            assertOneAboutRecord(
                deleted.Id,
                title(System.Label.Core_JobNotice_Finished, System.Label.Core_JobNotice_BulkDelete)
            );

            JobNotifier.sent.clear();
            BulkDeleteUndoBatch.jobErrorsForTest = 1;
            new BulkDeleteUndoBatch(deleted.Id, 0).finish(null);
            assertOneAboutRecord(
                deleted.Id,
                title(
                    System.Label.Core_JobNotice_Stopped,
                    System.Label.Core_JobNotice_BulkDeleteUndo
                )
            );
        }
    }

    @IsTest
    static void sampleDataLoadOpensGeneralWhenDoneOrStopped() {
        System.runAs(TestUsers.admin()) {
            notifications(true);
            SampleDataModules.moduleOverride = new List<SampleDataModule>();

            SampleDataModules.startFirst();

            assertOneAboutSection(
                JobNotifier.SECTION_GENERAL,
                title(System.Label.Core_JobNotice_Finished, System.Label.Core_JobNotice_SampleData)
            );

            JobNotifier.sent.clear();
            runOneStage(false);
            Assert.areEqual(0, JobNotifier.sent.size(), 'A stage that worked says nothing');
            runOneStage(true);
            assertOneAboutSection(
                JobNotifier.SECTION_GENERAL,
                title(System.Label.Core_JobNotice_Stopped, System.Label.Core_JobNotice_SampleData)
            );
        }
    }

    @IsTest
    static void fieldUtilizationOnDemandSendsNothing() {
        System.runAs(TestUsers.admin()) {
            notifications(true);

            // Field utilization counts on demand on its own tab (ADR-0101): the count runs while
            // the person watches the page, so no job is left to tell them about.
            FieldUtilizationController.countFields('Contact', new List<String>{ 'LastName' });

            Assert.areEqual(0, JobNotifier.sent.size(), 'An on-demand count sends no notice');
        }
    }

    @IsTest
    static void seasonalAddressRunNowOpensAddresses() {
        System.runAs(TestUsers.admin()) {
            notifications(true);

            new SeasonalAddressBatch().finish(null);

            assertOneAboutSection(
                JobNotifier.SECTION_ADDRESSES,
                title(
                    System.Label.Core_JobNotice_Finished,
                    System.Label.Core_JobNotice_SeasonalAddress
                )
            );
        }
    }

    @IsTest
    static void duplicateScanOpensHouseholds() {
        System.runAs(TestUsers.admin()) {
            notifications(true);

            new DuplicateScanBatch('Contact', new List<String>()).finish(null);

            assertOneAboutSection(
                JobNotifier.SECTION_HOUSEHOLDS,
                title(
                    System.Label.Core_JobNotice_Finished,
                    System.Label.Core_JobNotice_DuplicateScan
                )
            );
        }
    }

    @IsTest
    static void householdNameRecomputeOpensHouseholds() {
        System.runAs(TestUsers.admin()) {
            notifications(true);

            new HouseholdNamingBatch().finish(null);

            assertOneAboutSection(
                JobNotifier.SECTION_HOUSEHOLDS,
                title(
                    System.Label.Core_JobNotice_Finished,
                    System.Label.Core_JobNotice_HouseholdNaming
                )
            );
        }
    }

    @IsTest
    static void withTheSettingOffNoJobSendsAnything() {
        System.runAs(TestUsers.admin()) {
            notifications(false);
            Import_Batch__c updated = job(BulkUpdateService.OPERATION_UPDATE);

            new BulkUpdateBatch(updated.Id).finish(null);
            ImportUndoService.finish(updated.Id, 0, 0, false, 0);
            new HouseholdNamingBatch().finish(null);
            new SeasonalAddressBatch().finish(null);
            runOneStage(true);

            Assert.areEqual(0, JobNotifier.sent.size(), 'Turned off, no job sends');
            Assert.areEqual(
                ImportBatchService.STATUS_UNDONE,
                [SELECT Status__c FROM Import_Batch__c WHERE Id = :updated.Id].Status__c,
                'And the jobs still finish as before'
            );
        }
    }
}
