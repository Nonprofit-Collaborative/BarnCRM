/**
 * SetupChangeController (C-56, R-SC5, R-SC6): the summary counts what is kept and lists its
 * sections, the search filters by day, section and words, newest first, says when more match
 * and when it stopped looking, Copy New Changes Now starts a copy and schedules the nightly
 * one, and every method refuses a person without Manage BarnCRM Settings.
 */
@IsTest(testFor='ApexClass:SetupChangeController')
private class SetupChangeControllerTest {
    /** Noon on 10 March 2026 in the test user's time zone. */
    private static final Datetime NOON = Datetime.newInstance(2026, 3, 10, 12, 0, 0);

    @TestSetup
    static void createData() {
        TestUsers.admin();
        // runs-as: deploying user (the kept rows are written by the copy job, never by a person)
        insert as system new List<Setup_Change__c>{
            change(
                'a',
                NOON.addDays(-20),
                'Pat Admin',
                'Customize Accounts',
                'Changed Phone field label'
            ),
            change(
                'b',
                NOON.addDays(-10),
                'Sam Admin',
                'Manage Users',
                'Changed profile for user Lee'
            ),
            change('c', NOON, 'Pat Admin', 'Customize Accounts', 'Changed Website field help text')
        };
    }

    private static Setup_Change__c change(
        String id,
        Datetime at,
        String author,
        String section,
        String display
    ) {
        return new Setup_Change__c(
            Audit_Trail_Id__c = id,
            Changed_At__c = at,
            Changed_By__c = author,
            Section__c = section,
            Action__c = 'changed',
            Display__c = display
        );
    }

    private static List<String> displays(SetupChangeController.Result result) {
        List<String> found = new List<String>();
        for (SetupChangeController.Change row : result.rows) {
            found.add(row.display);
        }
        return found;
    }

    @IsTest
    static void theSummaryCountsWhatIsKeptAndListsItsSections() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            SetupChangeController.Summary summary = SetupChangeController.getSummary();
            Test.stopTest();

            Assert.areEqual(3, summary.keptCount, 'Every kept change is counted.');
            Assert.areEqual(NOON.addDays(-20), summary.oldest, 'From the oldest.');
            Assert.areEqual(NOON, summary.newest, 'To the newest.');
            Assert.areEqual(
                new List<String>{ 'Customize Accounts', 'Manage Users' },
                summary.sections,
                'Each kept section once, in order.'
            );
            Assert.areEqual(730, summary.retentionDays, 'The retention in use.');
            Assert.isFalse(summary.scheduled, 'Nothing is scheduled in a new org.');
            Assert.areEqual(200, summary.pageRows, 'The table size.');
            Assert.areEqual(5000, summary.exportRows, 'The download size.');
        }
    }

    @IsTest
    static void theSearchFiltersByDaySectionAndWordsNewestFirst() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            SetupChangeController.Result all = SetupChangeController.getChanges(
                null,
                null,
                null,
                null,
                null
            );
            SetupChangeController.Result days = SetupChangeController.getChanges(
                '2026-02-27',
                '2026-03-01',
                '',
                '',
                200
            );
            SetupChangeController.Result section = SetupChangeController.getChanges(
                '',
                '',
                'Customize Accounts',
                '',
                200
            );
            SetupChangeController.Result words = SetupChangeController.getChanges(
                null,
                null,
                null,
                '  pat   HELP ',
                200
            );
            Test.stopTest();

            Assert.areEqual(
                new List<String>{
                    'Changed Website field help text',
                    'Changed profile for user Lee',
                    'Changed Phone field label'
                },
                displays(all),
                'Everything, newest first.'
            );
            Assert.isFalse(all.more, 'Nothing more matches.');
            Assert.areEqual('Pat Admin', all.rows[0].changedBy, 'Each row says who.');
            Assert.areEqual(
                new List<String>{ 'Changed profile for user Lee' },
                displays(days),
                'Only the change between the two days.'
            );
            Assert.areEqual(2, section.rows.size(), 'Only the section chosen.');
            Assert.areEqual(
                new List<String>{ 'Changed Website field help text' },
                displays(words),
                'Every word must appear somewhere, ignoring capitals.'
            );
        }
    }

    @IsTest
    static void theSearchSaysWhenMoreMatchAndWhenItStoppedLooking() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            SetupChangeController.Result first = SetupChangeController.getChanges(
                null,
                null,
                null,
                null,
                2
            );
            SetupChangeController.scanCap = 2;
            SetupChangeController.Result stopped = SetupChangeController.getChanges(
                null,
                null,
                null,
                'phone',
                200
            );
            Test.stopTest();

            Assert.areEqual(2, first.rows.size(), 'Only as many as asked for.');
            Assert.isTrue(first.more, 'And it says more match.');
            Assert.isTrue(stopped.scanStopped, 'The oldest change is past the rows looked at.');
            Assert.isTrue(stopped.rows.isEmpty(), 'So it is not found.');
            Assert.areEqual(2, stopped.scanCap, 'It says how many it looked at.');
        }
    }

    @IsTest
    static void aDayThatIsNotADayIsRefused() {
        System.runAs(TestUsers.admin()) {
            try {
                SetupChangeController.getChanges('tomorrow', null, null, null, null);
                Assert.fail('A day that is not a day is refused.');
            } catch (AuraHandledException refused) {
                Assert.isTrue(refused.getMessage().contains('tomorrow'), 'The message names it.');
            }
        }
    }

    @IsTest
    static void copyNowStartsACopyAndSchedulesTheNightlyOne() {
        delete as system [SELECT Id FROM Setup_Change__c WITH SYSTEM_MODE];
        insert as system change('now', Datetime.now(), null, null, 'marker');
        SetupChangeCopyJob.chainPurge = false;
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            SetupChangeController.CopyResult result = SetupChangeController.copyNow();
            Test.stopTest();

            Assert.isTrue(result.started, 'A copy started.');
            Assert.isTrue(result.scheduled, 'And the nightly copy is scheduled.');
        }
    }

    @IsTest
    static void everyMethodRefusesAPersonWhoCannotManageSettings() {
        System.runAs(TestUsers.admin()) {
            SetupChangeController.permissionOverride = false;
            Integer refused = 0;
            try {
                SetupChangeController.getSummary();
            } catch (AuraHandledException expected) {
                refused++;
            }
            try {
                SetupChangeController.getChanges(null, null, null, null, null);
            } catch (AuraHandledException expected) {
                refused++;
            }
            try {
                SetupChangeController.copyNow();
            } catch (AuraHandledException expected) {
                refused++;
                Assert.areEqual(
                    Label.Core_OrgOptimizer_ErrorNoPermission,
                    expected.getMessage(),
                    'The same message Org Optimizer gives.'
                );
            }
            Assert.areEqual(3, refused, 'All three refuse.');
            Assert.isFalse(SetupChangeCopyJob.isScheduled(), 'And nothing was scheduled.');
        }
    }
}
