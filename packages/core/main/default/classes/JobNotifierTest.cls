/**
 * The job notification helper (Q-04): one notification to the person who started a job, opening
 * its record or its settings page; nothing when the setting is off, nobody is to be told, or the
 * org has no notification type; and a refused send is logged, never thrown.
 *
 * A sent notification cannot be read back, so these assert on `JobNotifier.sent`, the list of
 * what was handed to the platform. These tests have not been executed: no org in this
 * environment.
 */
@IsTest(testFor='ApexClass:JobNotifier')
private class JobNotifierTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    /** Saves the org's settings with notifications on or off. */
    private static void notifications(Boolean turnedOn) {
        insert new BarnCRM_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Job_Notifications__c = turnedOn
        );
        SettingsService.clearCaches();
    }

    @IsTest
    static void tellsTheRecipientAboutTheJobRecord() {
        System.runAs(TestUsers.admin()) {
            notifications(true);
            Account record = new Account(Name = 'Job record');
            insert record;

            JobNotifier.aboutRecord(UserInfo.getUserId(), 'Bulk update', false, 'Body', record.Id);

            Assert.areEqual(1, JobNotifier.sent.size(), 'One notification');
            JobNotifier.Notice notice = JobNotifier.sent[0];
            Assert.areEqual(UserInfo.getUserId(), notice.recipientId, 'To the person given');
            Assert.areEqual(record.Id, notice.targetId, 'Opening the record');
            Assert.isNull(notice.section, 'And no settings page');
            Assert.areEqual(
                String.format(
                    System.Label.Core_JobNotice_Finished,
                    new List<Object>{ 'Bulk update' }
                ),
                notice.title,
                'Saying what finished'
            );
            Assert.areEqual('Body', notice.body, 'With the outcome');
        }
    }

    @IsTest
    static void aJobThatStoppedSaysSoAndCanOpenTheSettingsPage() {
        System.runAs(TestUsers.admin()) {
            notifications(true);

            JobNotifier.aboutSettings(
                UserInfo.getUserId(),
                'Rollup recalculation',
                true,
                '',
                JobNotifier.SECTION_ROLLUPS
            );

            Assert.areEqual(1, JobNotifier.sent.size(), 'One notification');
            JobNotifier.Notice notice = JobNotifier.sent[0];
            Assert.areEqual(
                String.format(
                    System.Label.Core_JobNotice_Stopped,
                    new List<Object>{ 'Rollup recalculation' }
                ),
                notice.title,
                'Saying it did not finish'
            );
            Assert.areEqual(notice.title, notice.body, 'A blank body falls back to the title');
            Assert.areEqual(JobNotifier.SECTION_ROLLUPS, notice.section, 'Opening the section');
            Map<String, Object> page = (Map<String, Object>) JSON.deserializeUntyped(
                JobNotifier.pageReference(notice.section)
            );
            Assert.areEqual('standard__navItemPage', page.get('type'), 'A tab page');
            Map<String, Object> attributes = (Map<String, Object>) page.get('attributes');
            Assert.areEqual(
                NamespaceUtil.qualify('BarnCRM_Settings'),
                attributes.get('apiName'),
                'The settings console'
            );
            Map<String, Object> state = (Map<String, Object>) page.get('state');
            Assert.areEqual(
                JobNotifier.SECTION_ROLLUPS,
                state.get(NamespaceUtil.stateKey('section')),
                'At the Rollups section'
            );
        }
    }

    @IsTest
    static void shipsSwitchedOnBeforeTheOrgHasSavedItsSettings() {
        System.runAs(TestUsers.admin()) {
            SettingsService.clearCaches();

            JobNotifier.aboutSettings(
                UserInfo.getUserId(),
                'Import',
                false,
                'Body',
                JobNotifier.SECTION_GENERAL
            );

            Assert.areEqual(1, JobNotifier.sent.size(), 'On by default (ADR-0035)');
        }
    }

    @IsTest
    static void sendsNothingWhenTheSettingIsOff() {
        System.runAs(TestUsers.admin()) {
            notifications(false);

            JobNotifier.aboutSettings(
                UserInfo.getUserId(),
                'Import',
                false,
                'Body',
                JobNotifier.SECTION_GENERAL
            );

            Assert.areEqual(0, JobNotifier.sent.size(), 'Turned off, nothing is sent');
        }
    }

    @IsTest
    static void sendsNothingWhenNobodyIsToBeTold() {
        System.runAs(TestUsers.admin()) {
            notifications(true);

            JobNotifier.aboutSettings(null, 'Import', false, 'Body', JobNotifier.SECTION_GENERAL);

            Assert.areEqual(0, JobNotifier.sent.size(), 'A scheduled run has no recipient');
        }
    }

    @IsTest
    static void sendsNothingInAnOrgWithoutTheNotificationType() {
        System.runAs(TestUsers.admin()) {
            notifications(true);
            JobNotifier.typeName = 'No_Such_Notification_Type';

            JobNotifier.aboutSettings(
                UserInfo.getUserId(),
                'Import',
                false,
                'Body',
                JobNotifier.SECTION_GENERAL
            );

            Assert.areEqual(0, JobNotifier.sent.size(), 'Nothing to send with');
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Error_Log__c WHERE Context__c = :JobNotifier.LOG_CONTEXT],
                'And nothing to report: the job is unaffected'
            );
        }
    }

    @IsTest
    static void aRefusedSendIsLoggedAndNeverThrown() {
        System.runAs(TestUsers.admin()) {
            notifications(true);
            JobNotifier.refuseNextSend = true;

            Test.startTest();
            JobNotifier.aboutSettings(
                UserInfo.getUserId(),
                'Import',
                false,
                'Body',
                JobNotifier.SECTION_GENERAL
            );
            Test.stopTest();

            Assert.areEqual(1, JobNotifier.sent.size(), 'The send was tried');
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Error_Log__c WHERE Context__c = :JobNotifier.LOG_CONTEXT],
                'The refusal is in the Error Log'
            );
        }
    }

    @IsTest
    static void theStarterIsTheRunningUserButNobodyInAScheduledRun() {
        System.runAs(TestUsers.admin()) {
            Assert.areEqual(UserInfo.getUserId(), JobNotifier.starter(), 'From a page');

            Test.startTest();
            System.schedule('Q-04 starter test', '0 0 3 * * ?', new JobNotifierProbe());
            Test.stopTest();

            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Account WHERE Name = 'Starter: none'],
                'A scheduled run tells nobody'
            );
        }
    }
}
