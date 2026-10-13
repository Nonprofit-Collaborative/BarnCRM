/**
 * The nightly reconciliation and the schedule the console starts and stops.
 *
 * Core holds no giving objects, so the run here counts organizations up to their parent account
 * (`ParentId`), as `RollupEngineTest` does.
 */
@IsTest(testFor='ApexClass:RollupScheduler')
private class RollupSchedulerTest {
    private static Rollup_Definition__c childCount(
        String key,
        String targetField,
        String mode,
        Boolean active
    ) {
        return new Rollup_Definition__c(
            Name = key,
            Definition_Key__c = key,
            Source_Object__c = 'Account',
            Target_Object__c = 'Account',
            Relationship_Path__c = 'ParentId',
            Aggregate__c = 'COUNT',
            Target_Field__c = targetField,
            Mode__c = mode,
            Fiscal_Year_Aware__c = false,
            Active__c = active
        );
    }

    private static Account organization(String name, Id parentId) {
        return new Account(
            Name = name,
            ParentId = parentId,
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
                .get('Organization')
                .getRecordTypeId()
        );
    }

    @IsTest
    static void theNightlyRunCoversScheduledAndBothAndNothingElse() {
        System.runAs(TestUsers.admin()) {
            Account parent = organization('Parent', null);
            insert parent;
            insert organization('Child', parent.Id);
            insert new List<Rollup_Definition__c>{
                childCount(
                    'Core_Scheduled',
                    'NumberOfEmployees',
                    RollupService.MODE_SCHEDULED,
                    true
                ),
                childCount('Core_Both', 'Member_Count__c', RollupService.MODE_BOTH, true),
                childCount('Core_Real_Time', 'AnnualRevenue', RollupService.MODE_REAL_TIME, true),
                childCount(
                    'Core_Inactive',
                    'NumberOfEmployees',
                    RollupService.MODE_SCHEDULED,
                    false
                )
            };

            Test.startTest();
            Id jobId = RollupScheduler.runNow();
            Test.stopTest();

            Assert.isNotNull(jobId, 'The run started');
            Set<String> keys = new Set<String>();
            for (Rollup_Definition__c definition : [
                SELECT Definition_Key__c
                FROM Rollup_Definition__c
                WHERE Last_Calculated__c != NULL
            ]) {
                keys.add(definition.Definition_Key__c);
            }
            Assert.areEqual(
                new Set<String>{ 'Core_Scheduled', 'Core_Both' },
                keys,
                'R-R4: a real time rollup is already right, and an inactive one does not run'
            );
            Account counted = [
                SELECT NumberOfEmployees, Member_Count__c
                FROM Account
                WHERE Id = :parent.Id
            ];
            Assert.areEqual(1, counted.NumberOfEmployees, 'The scheduled total is written');
            Assert.areEqual(1, counted.Member_Count__c, 'And the Both one');
        }
    }

    @IsTest
    static void theScheduledJobStartsTheFullRecalculation() {
        System.runAs(TestUsers.admin()) {
            insert childCount('Core_Both', 'NumberOfEmployees', RollupService.MODE_BOTH, true);
            insert organization('Parent', null);

            Test.startTest();
            new RollupScheduler().execute(null);
            Test.stopTest();

            Assert.areEqual(
                1,
                [
                    SELECT COUNT()
                    FROM AsyncApexJob
                    WHERE JobType = 'BatchApex' AND ApexClass.Name = 'RollupFullRecalcBatch'
                ],
                'The nightly job runs the full recalculation of BarnCRM own engine'
            );
        }
    }

    @IsTest
    static void theScheduleIsStartedAndStoppedFromTheConsole() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            RollupScheduler.start();
            Boolean scheduledAfterStart = RollupScheduler.isScheduled();
            RollupScheduler.stop();
            Boolean scheduledAfterStop = RollupScheduler.isScheduled();
            Test.stopTest();

            System.Assert.isTrue(scheduledAfterStart, 'Starting the nightly run schedules it');
            System.Assert.isFalse(scheduledAfterStop, 'And stopping it takes it away');
        }
    }

    @IsTest
    static void startingTwiceDoesNotScheduleTwoJobs() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            Id first = RollupScheduler.start();
            Id second = RollupScheduler.start();
            Test.stopTest();

            System.Assert.areEqual(
                first,
                second,
                'The same job, so a second click changes nothing'
            );
        }
    }
}
