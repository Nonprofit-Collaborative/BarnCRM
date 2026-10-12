/**
 * The nightly reconciliation and the schedule the console starts and stops.
 *
 * These tests have not been executed: no Salesforce org exists in this environment.
 */
@IsTest
private class RollupBatchTest {
    private static Rollup_Definition__c memberCount(String key, String mode, Boolean active) {
        return new Rollup_Definition__c(
            Name = key,
            Definition_Key__c = key,
            Source_Object__c = 'Household_Member__c',
            Target_Object__c = 'Account',
            Relationship_Path__c = 'Household__c',
            Aggregate__c = 'COUNT',
            Target_Field__c = 'Member_Count__c',
            Mode__c = mode,
            Fiscal_Year_Aware__c = false,
            Active__c = active
        );
    }

    @IsTest
    static void theNightlyRunCoversScheduledAndBothAndNothingElse() {
        insert new List<Rollup_Definition__c>{
            memberCount('Core_Scheduled', RollupService.MODE_SCHEDULED, true),
            memberCount('Core_Both', RollupService.MODE_BOTH, true),
            memberCount('Core_Real_Time', RollupService.MODE_REAL_TIME, true),
            memberCount('Core_Inactive', RollupService.MODE_SCHEDULED, false)
        };
        RollupService.skipEngine = true;

        // The scope has to hold every definition the query returns, which is why this is not the
        // scope of 1 the scheduler uses. A test method runs exactly one chunk, so a scope of 1
        // against the two definitions this run covers asks the platform for a second chunk and it
        // refuses with "No more than one executeBatch can be called from within a test method".
        // What is asserted here is which definitions the run covers, and that is decided by the
        // query in start(), not by how the rows are chunked.
        Test.startTest();
        Database.executeBatch(new RollupBatch(), 200);
        Test.stopTest();

        List<Rollup_Definition__c> stamped = [
            SELECT Definition_Key__c
            FROM Rollup_Definition__c
            WHERE Last_Calculated__c != NULL
        ];
        Set<String> keys = new Set<String>();
        for (Rollup_Definition__c definition : stamped) {
            keys.add(definition.Definition_Key__c);
        }
        System.Assert.areEqual(
            new Set<String>{ 'Core_Scheduled', 'Core_Both' },
            keys,
            'R-R4: a real time rollup is already right, and an inactive one does not run'
        );
    }

    @IsTest
    static void theNightlyRunReadsEveryDefinitionWhoeverScheduledIt() {
        List<Rollup_Definition__c> definitions = new List<Rollup_Definition__c>();
        for (Integer i = 0; i < 200; i++) {
            definitions.add(memberCount('Core_Bulk_' + i, RollupService.MODE_SCHEDULED, true));
        }
        definitions.add(memberCount('Core_Bulk_Real_Time', RollupService.MODE_REAL_TIME, true));
        insert definitions;
        // The job runs as whoever scheduled it. This user holds no packaged permission set, so a
        // user-mode read (the API 67.0 default) would see no definitions at all.
        User limited = TestDataFactory.createUser('Nolrollup', new List<String>());

        Integer read = 0;
        Test.startTest();
        System.runAs(limited) {
            Database.QueryLocatorIterator rows = new RollupBatch().start(null).iterator();
            while (rows.hasNext()) {
                rows.next();
                read++;
            }
        }
        Test.stopTest();

        System.Assert.areEqual(
            200,
            read,
            'Every scheduled definition is reconciled, whatever access the scheduler has'
        );
    }

    @IsTest
    static void theScheduleIsStartedAndStoppedFromTheConsole() {
        Test.startTest();
        RollupScheduler.start();
        Boolean scheduledAfterStart = RollupScheduler.isScheduled();
        RollupScheduler.stop();
        Boolean scheduledAfterStop = RollupScheduler.isScheduled();
        Test.stopTest();

        System.Assert.isTrue(scheduledAfterStart, 'Starting the nightly run schedules it');
        System.Assert.isFalse(scheduledAfterStop, 'And stopping it takes it away');
    }

    @IsTest
    static void startingTwiceDoesNotScheduleTwoJobs() {
        Test.startTest();
        Id first = RollupScheduler.start();
        Id second = RollupScheduler.start();
        Test.stopTest();

        System.Assert.areEqual(first, second, 'The same job, so a second click changes nothing');
    }
}
