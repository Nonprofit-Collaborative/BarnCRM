/**
 * SeasonalAddressController: what the Addresses page of the settings console shows about the
 * nightly swap, and the Run now button. The schedule itself follows the Seasonal Addresses
 * switch (SeasonalAddressSwitchTest).
 *
 * The permission is the point of most of these. The run itself reads and writes in system mode
 * (ADR-0027), so the check here is where the authorization for that actually happens.
 */
@IsTest(testFor='ApexClass:SeasonalAddressController')
private class SeasonalAddressControllerTest {
    /**
     * The permission has to be committed before the test methods run, which is what @TestSetup
     * is for, and it also keeps the permission set assignment out of the same transaction as
     * the address records the tests write.
     */
    @TestSetup
    static void grantPermission() {
        System.runAs(TestUsers.admin()) {
            SettingsTestPermissions.grantTo('C18_Seasonal_Swap_Test', UserInfo.getUserId());
        }
    }

    @IsTest
    static void theViewSaysTheJobHasNeverRunBeforeItHasRun() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            SeasonalAddressController.SwapView view = SeasonalAddressController.getSwap();
            Test.stopTest();

            Assert.isNull(
                view.lastRun,
                'An org that has never run the swap must be shown as never having run it.'
            );
            Assert.isFalse(view.scheduled, 'Nothing schedules the job on install.');
            Assert.isFalse(
                view.stale,
                'An org that has not switched the job on has not missed a run.'
            );
        }
    }

    @IsTest
    static void theViewShowsTheLastRunAndWhatItDid() {
        System.runAs(TestUsers.admin()) {
            SeasonalAddressService.RunSummary summary = new SeasonalAddressService.RunSummary();
            summary.movedIn = 4;
            Datetime finishedAt = Datetime.newInstance(2027, 1, 15, 0, 30, 0);
            SeasonalAddressService.recordRun(summary, finishedAt);

            Test.startTest();
            SeasonalAddressController.SwapView view = SeasonalAddressController.getSwap();
            Test.stopTest();

            Assert.areEqual(
                finishedAt,
                view.lastRun,
                'The page shows the time the last run finished, which is the whole point of C-18.'
            );
            Assert.isTrue(
                view.lastRunSummary.contains('4'),
                'The page shows what the run did, and it reads: ' + view.lastRunSummary
            );
        }
    }

    /** PEOPLE-37: the view asks about the job twice, not seven times. */
    @IsTest
    static void theViewOfAScheduledSwapCostsTwoQueries() {
        System.runAs(TestUsers.admin()) {
            SeasonalAddressScheduler.start();

            Test.startTest();
            Integer before = Limits.getQueries();
            SeasonalAddressController.SwapView view = SeasonalAddressController.getSwap();
            Integer used = Limits.getQueries() - before;
            Test.stopTest();

            Assert.isTrue(view.scheduled, 'Scheduled');
            Assert.isNotNull(view.nextRunAt, 'With its next run');
            Assert.isTrue(used <= 2, 'Whether it is scheduled, and when it runs next: ' + used);
        }
    }

    @IsTest
    static void runningTheSwapNowSwapsTheHouseholdWithoutWaitingForTonight() {
        System.runAs(TestUsers.admin()) {
            Account garcia = AddressTestDataFactory.newHousehold('The Garcia Family');
            garcia.BillingStreet = '812 Willow Lane';
            garcia.BillingCity = 'Springfield';
            Database.insert(garcia, AccessLevel.SYSTEM_MODE);
            insert new Address__c(
                Account__c = garcia.Id,
                Type__c = 'Seasonal',
                Street__c = '4120 East Camelback Road',
                City__c = 'Phoenix',
                Seasonal_Start_Month__c = 1,
                Seasonal_Start_Day__c = 1,
                Seasonal_End_Month__c = 12,
                Seasonal_End_Day__c = 31
            );

            Test.startTest();
            SeasonalAddressController.runNow();
            Test.stopTest();

            Assert.areEqual(
                'Phoenix',
                [SELECT BillingCity FROM Account WHERE Id = :garcia.Id].BillingCity,
                'A season covering the whole year is in season today, so Run now must swap it now.'
            );
        }
    }

    @IsTest
    static void aUserWithoutThePermissionCannotRunTheSwapByHand() {
        System.runAs(TestUsers.admin()) {
            User reader = readOnlyUser();

            Test.startTest();
            System.runAs(reader) {
                try {
                    SeasonalAddressController.runNow();
                    Assert.fail('Running the swap by hand must require Manage BarnCRM Settings.');
                } catch (AuraHandledException expected) {
                    Assert.areEqual(
                        System.Label.Core_SeasonalAddress_PermissionRequired,
                        expected.getMessage(),
                        'The refusal must name the permission rather than show a stack trace.'
                    );
                }
            }
            Test.stopTest();
        }
    }

    /** A user holding no packaged permission set, so the custom permission is genuinely absent. */
    private static User readOnlyUser() {
        return TestUsers.standardUser('Reader');
    }
}
