/**
 * SeasonalAddressBatch and SeasonalAddressScheduler: the nightly run end to end, the record it
 * leaves behind, and the schedule an administrator starts from the settings console.
 */
@IsTest
private class SeasonalAddressBatchTest {
    private static final String HOME_STREET = '812 Willow Lane';
    private static final String HOME_CITY = 'Springfield';
    private static final String WINTER_CITY = 'Phoenix';

    @IsTest
    static void aNightlyRunSwapsTheHouseholdAndRecordsWhatItDid() {
        System.runAs(TestUsers.admin()) {
            Account garcia = householdWithSeasonalAddress('The Garcia Family', 11, 1, 3, 31);

            Test.startTest();
            Database.executeBatch(
                new SeasonalAddressBatch(Date.newInstance(2027, 1, 15)),
                SeasonalAddressBatch.CHUNK_SIZE
            );
            Test.stopTest();

            List<Address__c> inUse = [
                SELECT Id, Type__c, City__c
                FROM Address__c
                WHERE Account__c = :garcia.Id AND Is_Default__c = TRUE
            ];
            Assert.areEqual(1, inUse.size(), 'A household has one address in use at a time.');
            Assert.areEqual(
                WINTER_CITY,
                inUse[0].City__c,
                'In January the household should be at its winter address.'
            );
            Assert.isNotNull(
                SeasonalAddressService.lastRun(),
                'The run must record when it finished, or the Hub has nothing to show.'
            );
            Assert.isTrue(
                SeasonalAddressService.lastRunSummary().contains('1'),
                'The summary should say one household moved, and reads: ' +
                SeasonalAddressService.lastRunSummary()
            );
        }
    }

    @IsTest
    static void aRunWithNothingToDoStillRecordsThatItRan() {
        System.runAs(TestUsers.admin()) {
            householdWithSeasonalAddress('The Garcia Family', 11, 1, 3, 31);

            Test.startTest();
            Database.executeBatch(
                new SeasonalAddressBatch(Date.newInstance(2027, 7, 4)),
                SeasonalAddressBatch.CHUNK_SIZE
            );
            Test.stopTest();

            Assert.isNotNull(
                SeasonalAddressService.lastRun(),
                'A job that ran and had nothing to do is not the same as a job that did not run.'
            );
        }
    }

    @IsTest
    static void anOrgWithNoSeasonalAddressesRunsCleanly() {
        System.runAs(TestUsers.admin()) {
            Account garcia = AddressTestDataFactory.newHousehold('The Garcia Family');
            garcia.BillingStreet = HOME_STREET;
            garcia.BillingCity = HOME_CITY;
            insert garcia;

            Test.startTest();
            Database.executeBatch(new SeasonalAddressBatch(), SeasonalAddressBatch.CHUNK_SIZE);
            Test.stopTest();

            Assert.areEqual(
                HOME_CITY,
                [SELECT BillingCity FROM Account WHERE Id = :garcia.Id].BillingCity,
                'A household with no seasonal address must be left exactly where it was.'
            );
            Assert.isNotNull(
                SeasonalAddressService.lastRun(),
                'The run is recorded even in an org that has no seasonal addresses at all.'
            );
        }
    }

    @IsTest
    static void theRunUsesOneDayForEveryOwnerEvenAcrossMidnight() {
        System.runAs(TestUsers.admin()) {
            Account garcia = householdWithSeasonalAddress('The Garcia Family', 1, 1, 3, 31);

            Test.startTest();
            // December 31 is the day before the season. A run held to that date must not move the
            // household, however long it takes to reach it.
            Database.executeBatch(
                new SeasonalAddressBatch(Date.newInstance(2026, 12, 31)),
                SeasonalAddressBatch.CHUNK_SIZE
            );
            Test.stopTest();

            Assert.areEqual(
                HOME_CITY,
                [SELECT BillingCity FROM Account WHERE Id = :garcia.Id].BillingCity,
                'A run held to December 31 must leave the household at its home address.'
            );
        }
    }

    @IsTest
    static void schedulingTheJobCreatesOneNightlyRunAndStoppingItRemovesIt() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            Id first = SeasonalAddressScheduler.start();
            Id second = SeasonalAddressScheduler.start();
            Boolean scheduled = SeasonalAddressScheduler.isScheduled();
            Datetime nextRun = SeasonalAddressScheduler.nextRunAt();
            Integer jobs = [
                SELECT COUNT()
                FROM CronJobDetail
                WHERE Name = :SeasonalAddressScheduler.JOB_NAME
            ];
            SeasonalAddressScheduler.stop();
            Boolean scheduledAfterStop = SeasonalAddressScheduler.isScheduled();
            Test.stopTest();

            Assert.areEqual(
                first,
                second,
                'Scheduling twice must not give the org two nightly swaps competing with each other.'
            );
            Assert.isTrue(scheduled, 'The console must be able to see that the job is scheduled.');
            Assert.isNotNull(nextRun, 'A scheduled job has a next run to show the administrator.');
            Assert.areEqual(1, jobs, 'One job, under the name the settings console looks for.');
            Assert.isFalse(scheduledAfterStop, 'Stopping the schedule must actually stop it.');
        }
    }

    @IsTest
    static void stoppingTheJobLeavesTheAddressesWhereTheLastRunPutThem() {
        System.runAs(TestUsers.admin()) {
            Account garcia = householdWithSeasonalAddress('The Garcia Family', 11, 1, 3, 31);
            SeasonalAddressService.swapOwners(
                new Set<Id>{ garcia.Id },
                Date.newInstance(2027, 1, 15)
            );

            Test.startTest();
            SeasonalAddressScheduler.start();
            SeasonalAddressScheduler.stop();
            Test.stopTest();

            Assert.areEqual(
                WINTER_CITY,
                [SELECT BillingCity FROM Account WHERE Id = :garcia.Id].BillingCity,
                'Stopping the nightly job must not undo the swap the last run made.'
            );
        }
    }

    @IsTest
    static void aScheduledJobThatHasNeverRunIsReportedAsStale() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            SeasonalAddressScheduler.start();
            Boolean stale = SeasonalAddressService.isStale();
            SeasonalAddressScheduler.stop();
            Test.stopTest();

            Assert.isTrue(
                stale,
                'A job that is switched on and has never run is exactly what the Hub must warn about.'
            );
        }
    }

    private static Account householdWithSeasonalAddress(
        String name,
        Integer startMonth,
        Integer startDay,
        Integer endMonth,
        Integer endDay
    ) {
        Account household = AddressTestDataFactory.newHousehold(name);
        household.BillingStreet = HOME_STREET;
        household.BillingCity = HOME_CITY;
        insert household;
        insert new Address__c(
            Account__c = household.Id,
            Type__c = 'Seasonal',
            Street__c = '4120 East Camelback Road',
            City__c = WINTER_CITY,
            State__c = 'AZ',
            Postal_Code__c = '85018',
            Seasonal_Start_Month__c = startMonth,
            Seasonal_Start_Day__c = startDay,
            Seasonal_End_Month__c = endMonth,
            Seasonal_End_Day__c = endDay
        );
        return household;
    }
}
