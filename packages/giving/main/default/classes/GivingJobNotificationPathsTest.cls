/**
 * Giving's long jobs tell the person who started them once when they are over (Q-04), through
 * Core's `JobNotifier`: the statement run and the acknowledgment send open their run record, the
 * donor level recalculation opens the Giving section, and only at the end of its last pass. With
 * the setting off nothing is sent.
 *
 * Asserts on `JobNotifier.sentNotices()`, because a sent notification cannot be read back. These
 * tests have not been executed: no org in this environment.
 */
@IsTest(
    testFor='ApexClass:DonorLevelBatch, ApexClass:AcknowledgmentBatch, ApexClass:ReceiptStatementBatch'
)
private class GivingJobNotificationPathsTest {
    private static final Integer YEAR = 2025;

    private static User admin() {
        return TestUsers.adminWith('Giving_Admin');
    }

    private static String title(String jobName) {
        return String.format(System.Label.Core_JobNotice_Finished, new List<Object>{ jobName });
    }

    private static JobNotifier.Notice onlyNotice(String title) {
        List<JobNotifier.Notice> sent = JobNotifier.sentNotices();
        Assert.areEqual(1, sent.size(), 'Exactly one notification: ' + title);
        Assert.areEqual(UserInfo.getUserId(), sent[0].recipientId, 'To the person who started it');
        Assert.areEqual(title, sent[0].title, 'Saying what finished');
        return sent[0];
    }

    @IsTest
    static void aStatementRunOpensItsRunRecord() {
        System.runAs(admin()) {
            Receipt_Run__c run = new Receipt_Run__c(
                Type__c = ReceiptNumberSequence.TYPE_STATEMENT,
                Statement_Year__c = YEAR,
                Status__c = ReceiptRunService.STATUS_RUNNING,
                Donors_Processed__c = 0,
                Receipts_Issued__c = 0,
                Errors__c = 0
            );
            insert run;

            new ReceiptStatementBatch(YEAR, run.Id).finish(null);

            JobNotifier.Notice notice = onlyNotice(title(System.Label.Giving_JobNotice_Statements));
            Assert.areEqual(run.Id, notice.targetId, 'Opening the run');
        }
    }

    @IsTest
    static void anAcknowledgmentSendOpensItsRunRecord() {
        System.runAs(admin()) {
            Acknowledgment_Run__c run = new Acknowledgment_Run__c(
                Channel__c = AcknowledgmentRuleService.CHANNEL_EMAIL,
                Status__c = AcknowledgmentRunService.STATUS_RUNNING
            );
            insert run;

            new AcknowledgmentBatch(run.Id).finish(null);

            JobNotifier.Notice notice = onlyNotice(
                title(System.Label.Giving_JobNotice_Acknowledgments)
            );
            Assert.areEqual(run.Id, notice.targetId, 'Opening the run');
        }
    }

    @IsTest
    static void aDonorLevelRecalculationNotifiesOnceAtTheEnd() {
        System.runAs(admin()) {
            new DonorLevelBatch().finish(null);
            Assert.areEqual(
                0,
                JobNotifier.sentNotices().size(),
                'The accounts pass hands on to the contacts pass and says nothing'
            );

            new DonorLevelBatch(DonorLevelBatch.CONTACTS).finish(null);

            JobNotifier.Notice notice = onlyNotice(
                title(System.Label.Giving_JobNotice_DonorLevels)
            );
            Assert.isNull(notice.targetId, 'No record');
            Assert.areEqual('Giving', notice.section, 'Opening the Giving section');
        }
    }

    @IsTest
    static void withTheSettingOffNoGivingJobSendsAnything() {
        System.runAs(admin()) {
            SettingsService.saveValues(new Map<String, Object>{ 'Job_Notifications__c' => false });
            Acknowledgment_Run__c run = new Acknowledgment_Run__c(
                Channel__c = AcknowledgmentRuleService.CHANNEL_EMAIL,
                Status__c = AcknowledgmentRunService.STATUS_RUNNING
            );
            insert run;

            new AcknowledgmentBatch(run.Id).finish(null);
            new DonorLevelBatch(DonorLevelBatch.CONTACTS).finish(null);

            Assert.areEqual(0, JobNotifier.sentNotices().size(), 'Turned off, nothing is sent');
            Assert.areEqual(
                AcknowledgmentRunService.STATUS_COMPLETED,
                [SELECT Status__c FROM Acknowledgment_Run__c WHERE Id = :run.Id].Status__c,
                'And the send still closes its run'
            );
        }
    }
}
