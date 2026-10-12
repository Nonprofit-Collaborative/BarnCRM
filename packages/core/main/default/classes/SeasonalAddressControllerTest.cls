/**
 * SeasonalAddressController: what the Addresses page of the settings console shows about the
 * nightly swap, and the two buttons that are the only way an administrator starts it.
 *
 * The permission is the point of most of these. The run itself reads and writes in system mode
 * (ADR-0027), so the check here is where the authorization for that actually happens.
 */
@IsTest
private class SeasonalAddressControllerTest {
    /**
     * The permission has to be committed before the test methods run, which is what @TestSetup
     * is for, and it also keeps the permission set assignment out of the same transaction as
     * the address records the tests write.
     */
    @TestSetup
    static void grantPermission() {
        SettingsTestPermissions.grantTo('C18_Seasonal_Swap_Test', UserInfo.getUserId());
    }

    @IsTest
    static void theViewSaysTheJobHasNeverRunBeforeItHasRun() {
        Test.startTest();
        SeasonalAddressController.SwapView view = SeasonalAddressController.getSwap();
        Test.stopTest();

        Assert.isNull(
            view.lastRun,
            'An org that has never run the swap must be shown as never having run it.'
        );
        Assert.isFalse(view.scheduled, 'Nothing schedules the job on install.');
        Assert.isFalse(view.stale, 'An org that has not switched the job on has not missed a run.');
    }

    @IsTest
    static void theViewShowsTheLastRunAndWhatItDid() {
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

    @IsTest
    static void anAdministratorCanScheduleAndStopTheNightlySwap() {
        Test.startTest();
        SeasonalAddressController.SwapView started = SeasonalAddressController.setSchedule(true);
        SeasonalAddressController.SwapView stopped = SeasonalAddressController.setSchedule(false);
        Test.stopTest();

        Assert.isTrue(
            started.scheduled,
            'Choosing Schedule the nightly swap must actually schedule it, with no trip to Setup.'
        );
        Assert.isNotNull(
            started.nextRunAt,
            'A scheduled job shows the administrator when it will next run.'
        );
        Assert.isFalse(stopped.scheduled, 'And choosing Stop must actually stop it.');
    }

    @IsTest
    static void runningTheSwapNowSwapsTheHouseholdWithoutWaitingForTonight() {
        Account garcia = AddressTestDataFactory.newHousehold('The Garcia Family');
        garcia.BillingStreet = '812 Willow Lane';
        garcia.BillingCity = 'Springfield';
        insert garcia;
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

    @IsTest
    static void aUserWithoutThePermissionCannotChangeTheSchedule() {
        User reader = readOnlyUser();

        Test.startTest();
        System.runAs(reader) {
            try {
                SeasonalAddressController.setSchedule(true);
                Assert.fail('Scheduling a nightly job must require Manage Nonprofit Settings.');
            } catch (AuraHandledException expected) {
                Assert.areEqual(
                    System.Label.Core_SeasonalAddress_PermissionRequired,
                    expected.getMessage(),
                    'The refusal must tell the reader which permission they need.'
                );
            }
        }
        Test.stopTest();

        Assert.isFalse(
            SeasonalAddressScheduler.isScheduled(),
            'The job must not have been scheduled by a user who cannot schedule it.'
        );
    }

    @IsTest
    static void aUserWithoutThePermissionCannotRunTheSwapByHand() {
        User reader = readOnlyUser();

        Test.startTest();
        System.runAs(reader) {
            try {
                SeasonalAddressController.runNow();
                Assert.fail('Running the swap by hand must require Manage Nonprofit Settings.');
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

    /** A user holding no packaged permission set, so the custom permission is genuinely absent. */
    private static User readOnlyUser() {
        Profile standard = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User reader = new User(
            Alias = 'oiread',
            Email = 'seasonal.reader@barncrm.invalid',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Reader',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = standard.Id,
            TimeZoneSidKey = 'America/Chicago',
            UserName = 'seasonal.reader.' + DateTime.now().getTime() + '@barncrm.invalid'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert reader;
        }
        return reader;
    }
}
