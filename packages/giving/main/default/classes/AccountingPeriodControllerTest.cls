/**
 * The Accounting Periods page (G-20, R-G14, ADR-0053).
 *
 * Maria closes last month. She can close further, never through yesterday or today, and she cannot reopen a
 * month unless she holds Override Posting Lock, in which case the reopening is written down.
 * David, on the staff permission sets, can read the date and change nothing.
 */
@IsTest
private class AccountingPeriodControllerTest {
    private static User maria() {
        return TestDataFactory.createUser(
            'Maria',
            new List<String>{ 'BarnCRM_Admin', 'Giving_Admin' }
        );
    }

    private static User david() {
        return TestDataFactory.createUser(
            'David',
            new List<String>{ 'BarnCRM_Staff', 'Giving_Staff' }
        );
    }

    /** The end of the month before the day before yesterday: always closable, even on the 1st. */
    private static Date lastMonthEnd() {
        return Date.today().addDays(-2).toStartOfMonth().addDays(-1);
    }

    private static String refusalOf(Date closeDate) {
        try {
            AccountingPeriodController.closeThrough(closeDate);
            return null;
        } catch (AuraHandledException refused) {
            return refused.getMessage();
        }
    }

    @IsTest
    static void closesTheBooksAndRecordsTheChange() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            System.runAs(maria()) {
                AccountingPeriodController.PeriodView before = AccountingPeriodController.getPeriod();
                Assert.isNull(before.closedThrough, 'Nothing is closed on install');
                Assert.isTrue(before.canManage, 'Maria can close a period');
                Assert.isFalse(before.canReopen, 'Nobody can reopen without the override');
                Assert.areEqual(Date.today().addDays(-2), before.latestAllowed);

                AccountingPeriodController.PeriodView after = AccountingPeriodController.closeThrough(
                    lastMonthEnd()
                );

                Assert.areEqual(lastMonthEnd(), after.closedThrough);
                Assert.areEqual(
                    lastMonthEnd(),
                    GiftPostingLock.closedThrough(),
                    'The lock reads it'
                );
            }
            List<Setting_Change__c> changes = [
                SELECT Setting_Name__c, Old_Value__c, New_Value__c
                FROM Setting_Change__c
            ];
            Assert.areEqual(1, changes.size(), 'One Setting Change');
            Assert.areEqual(
                'Giving_Settings__c.Books_Closed_Through__c',
                changes[0].Setting_Name__c
            );
            Assert.areEqual(String.valueOf(lastMonthEnd()), changes[0].New_Value__c);
        }
    }

    @IsTest
    static void movesForwardButNeverThroughYesterday() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            System.runAs(maria()) {
                AccountingPeriodController.closeThrough(lastMonthEnd().addDays(-10));
                AccountingPeriodController.closeThrough(lastMonthEnd());
                Assert.areEqual(lastMonthEnd(), GiftPostingLock.closedThrough(), 'Forward is fine');

                Assert.areEqual(Label.Giving_Periods_NotBeforeToday, refusalOf(Date.today()));
                // Yesterday in Maria's time zone can be today in the org's.
                Assert.areEqual(
                    Label.Giving_Periods_NotBeforeToday,
                    refusalOf(Date.today().addDays(-1))
                );
                AccountingPeriodController.closeThrough(Date.today().addDays(-2));
                Assert.areEqual(Date.today().addDays(-2), GiftPostingLock.closedThrough());
                Assert.areEqual(
                    Label.Giving_Periods_NotBeforeToday,
                    refusalOf(Date.today().addDays(3))
                );
                Assert.isNull(
                    refusalOf(Date.today().addDays(-2)),
                    'Saving the same date changes nothing'
                );
            }

        }
    }

    @IsTest
    static void reopeningNeedsTheOverride() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            System.runAs(maria()) {
                AccountingPeriodController.closeThrough(lastMonthEnd());

                Assert.areEqual(
                    Label.Giving_Periods_ReopenNeedsOverride,
                    refusalOf(lastMonthEnd().addDays(-5)),
                    'Moving back reopens days'
                );
                Assert.areEqual(
                    Label.Giving_Periods_ReopenNeedsOverride,
                    refusalOf(null),
                    'Clearing reopens everything'
                );
                Assert.areEqual(lastMonthEnd(), GiftPostingLock.closedThrough(), 'Still closed');
            }
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Error_Log__c WHERE Context__c = 'Posting lock override'],
                'A refused reopening leaves no trace'
            );
        }
    }

    @IsTest
    static void theOverrideReopensAndIsLogged() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            User maria = maria();
            System.runAs(maria) {
                AccountingPeriodController.closeThrough(lastMonthEnd());
                GiftPostingLock.overrideHeld = true;

                // The Error Log entry is delivered as an event, which Test.stopTest publishes.
                Test.startTest();
                AccountingPeriodController.PeriodView view = AccountingPeriodController.closeThrough(
                    lastMonthEnd().addDays(-5)
                );
                Test.stopTest();

                Assert.areEqual(lastMonthEnd().addDays(-5), view.closedThrough);
                Assert.isTrue(view.canReopen);
            }
            List<Error_Log__c> logs = [
                SELECT Message__c, Severity__c, User__c
                FROM Error_Log__c
                WHERE Context__c = 'Posting lock override'
            ];
            Assert.areEqual(1, logs.size(), 'The reopening is written down');
            Assert.areEqual(ErrorLogger.SEVERITY_WARNING, logs[0].Severity__c);
            Assert.isTrue(
                logs[0].Message__c.contains(String.valueOf(lastMonthEnd())),
                logs[0].Message__c
            );
            Assert.areEqual(maria.Id, logs[0].User__c);
        }
    }

    @IsTest
    static void staffCanReadButNotClose() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            System.runAs(david()) {
                AccountingPeriodController.PeriodView view = AccountingPeriodController.getPeriod();
                Assert.isFalse(view.canManage);
                Assert.areEqual(Label.Giving_Periods_PermissionRequired, refusalOf(lastMonthEnd()));
                Assert.isNull(GiftPostingLock.closedThrough(), 'Nothing closed');
            }

        }
    }
}
