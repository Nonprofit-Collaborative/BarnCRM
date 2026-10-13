/**
 * The full and nightly recalculation of BarnCRM's own rollup engine (rollup proposal, slice S7).
 * Core holds no giving objects, so these count people onto their organization, which runs the
 * same code the giving totals run. The giving totals are judged by the regression suite in Giving.
 *
 * These tests have not been executed: no Salesforce org exists in this environment.
 */
@IsTest(testFor='ApexClass:RollupFullRecalcBatch')
private class RollupFullRecalcBatchTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static Rollup_Definition__c peopleCount() {
        Rollup_Definition__c definition = new Rollup_Definition__c(
            Name = 'People per organization',
            Definition_Key__c = 'Test_People_Per_Organization',
            Source_Object__c = 'Contact',
            Relationship_Path__c = 'AccountId',
            Aggregate__c = 'COUNT',
            Target_Object__c = 'Account',
            Target_Field__c = 'NumberOfEmployees',
            Mode__c = RollupService.MODE_BOTH,
            Fiscal_Year_Aware__c = false,
            Active__c = true
        );
        insert definition;
        return definition;
    }

    /** Organizations whose stored count says what the last run counted, and their people. */
    private static List<Account> organizations(List<Integer> storedCounts, List<Integer> people) {
        Id organizationType = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get('Organization')
            .getRecordTypeId();
        List<Account> organizations = new List<Account>();
        for (Integer i = 0; i < storedCounts.size(); i++) {
            organizations.add(
                new Account(
                    Name = 'Organization ' + i,
                    RecordTypeId = organizationType,
                    NumberOfEmployees = storedCounts[i]
                )
            );
        }
        insert organizations;
        List<Contact> contacts = new List<Contact>();
        for (Integer i = 0; i < organizations.size(); i++) {
            for (Integer j = 0; j < people[i]; j++) {
                contacts.add(
                    new Contact(LastName = 'Person ' + j, AccountId = organizations[i].Id)
                );
            }
        }
        insert contacts;
        return organizations;
    }

    private static Map<Id, Integer> countsOf(List<Account> organizations) {
        Map<Id, Integer> counts = new Map<Id, Integer>();
        for (Account organization : [
            SELECT Id, NumberOfEmployees
            FROM Account
            WHERE Id IN :organizations
        ]) {
            counts.put(organization.Id, organization.NumberOfEmployees);
        }
        return counts;
    }

    private static Datetime lastCalculated(Rollup_Definition__c definition) {
        return [SELECT Last_Calculated__c FROM Rollup_Definition__c WHERE Id = :definition.Id]
        .Last_Calculated__c;
    }

    /**
     * 250 organizations, every count wrong, in one run: every count is put right, the rollup is
     * marked calculated only once the run has finished, and a second run writes nothing.
     */
    @IsTest
    static void everyRecordIsRecalculatedAndASecondRunWritesNothing() {
        System.runAs(TestUsers.admin()) {
            List<Integer> stored = new List<Integer>();
            List<Integer> people = new List<Integer>();
            for (Integer i = 0; i < 250; i++) {
                stored.add(99);
                people.add(Math.mod(i, 3));
            }
            List<Account> organizations = organizations(stored, people);
            Rollup_Definition__c definition = peopleCount();

            Test.startTest();
            Id jobId = RollupFullRecalcBatch.begin(new List<Rollup_Definition__c>{ definition });
            Datetime markedWhileRunning = lastCalculated(definition);
            Test.stopTest();

            Assert.isNotNull(jobId, 'The run started');
            Assert.isNull(
                markedWhileRunning,
                'Not marked calculated before the totals are written'
            );
            Assert.isNotNull(lastCalculated(definition), 'Marked calculated once the run finished');
            Map<Id, Integer> counts = countsOf(organizations);
            for (Integer i = 0; i < organizations.size(); i++) {
                Assert.areEqual(
                    Math.mod(i, 3),
                    counts.get(organizations[i].Id),
                    'Each organization\'s own people'
                );
            }
            RollupFullRecalcBatch.Progress progress = RollupFullRecalcBatch.progress();
            Assert.areEqual(jobId, progress.jobId, 'The progress is the run\'s');
            Assert.isFalse(progress.running, 'And says it has finished');
            Assert.areEqual(0, progress.chunksStopped, 'With nothing stopped');

            RollupFullRecalcBatch second = RollupFullRecalcBatch.firstPass(
                new List<Rollup_Definition__c>{ definition }
            );
            second.runInline();
            Assert.areEqual(0, second.run.written, 'A second run finds nothing to change');
        }
    }

    /**
     * A catch-all organization the last run counted 500 people on is calculated alone, and a
     * chunk whose records together expect more rows than the budget is split: the records that
     * do not fit are held back for a pass with smaller chunks. Every count is still right.
     */
    @IsTest
    static void aHeavyRecordIsCalculatedAloneAndADenseChunkIsSplit() {
        System.runAs(TestUsers.admin()) {
            List<Account> organizations = organizations(
                new List<Integer>{ 500, 40, 40, 40, 40, 40 },
                new List<Integer>{ 3, 2, 2, 2, 2, 2 }
            );
            Account anonymous = organizations[0];
            Rollup_Definition__c definition = peopleCount();
            RollupFullRecalcBatch.rowBudget = 100;
            RollupFullRecalcBatch pass = RollupFullRecalcBatch.firstPass(
                new List<Rollup_Definition__c>{ definition }
            );

            Test.startTest();
            pass.execute(
                null,
                [SELECT Id, NumberOfEmployees FROM Account WHERE Id IN :organizations ORDER BY Id]
            );
            Set<Id> alone = pass.alone.clone();
            Integer heldBack = pass.later.size();
            pass.finish(null);
            Test.stopTest();

            Assert.areEqual(
                new Set<Id>{ anonymous.Id },
                alone,
                'The heavy record waits to go alone'
            );
            Assert.areEqual(3, heldBack, 'Two records of 40 fit a budget of 100, three wait');
            Map<Id, Integer> counts = countsOf(organizations);
            Assert.areEqual(3, counts.get(anonymous.Id), 'The heavy record is calculated');
            for (Account organization : organizations) {
                if (organization.Id != anonymous.Id) {
                    Assert.areEqual(2, counts.get(organization.Id), 'So is every other');
                }
            }
            Assert.isNotNull(lastCalculated(definition), 'And the run marks the rollup calculated');
        }
    }

    /**
     * R-RQ4: a Failed queue entry whose records the run has now saved is taken off the list; an
     * entry for another kind of record is left alone.
     */
    @IsTest
    static void aFailedEntryIsClearedOnceTheRunSavesItsRecords() {
        System.runAs(TestUsers.admin()) {
            Account organization = organizations(new List<Integer>{ 7 }, new List<Integer>{ 1 })[0];
            Rollup_Definition__c definition = peopleCount();
            Rollup_Queue__c resolved = new Rollup_Queue__c(
                Target_Object__c = 'Account',
                Record_Ids__c = String.valueOf(organization.Id),
                Record_Count__c = 1,
                Status__c = RollupQueue.STATUS_FAILED,
                Attempts__c = RollupQueue.MAX_ATTEMPTS
            );
            Rollup_Queue__c elsewhere = resolved.clone();
            elsewhere.Target_Object__c = 'Contact';
            insert new List<Rollup_Queue__c>{ resolved, elsewhere };
            RollupFullRecalcBatch pass = RollupFullRecalcBatch.firstPass(
                new List<Rollup_Definition__c>{ definition }
            );
            pass.run.startedAt = Datetime.now().addMinutes(1);

            Test.startTest();
            pass.runInline();
            Test.stopTest();

            Assert.areEqual(1, countsOf(new List<Account>{ organization }).get(organization.Id));
            Assert.isTrue(
                [SELECT Id FROM Rollup_Queue__c WHERE Id = :resolved.Id].isEmpty(),
                'The entry the run resolved is gone'
            );
            Assert.isFalse(
                [SELECT Id FROM Rollup_Queue__c WHERE Id = :elsewhere.Id].isEmpty(),
                'The other entity\'s entry stays'
            );
        }
    }

    /** While all automation is paused the run does not start, and says so in the Error Log. */
    @IsTest
    static void nothingRunsWhileAutomationIsPaused() {
        System.runAs(TestUsers.admin()) {
            Rollup_Definition__c definition = peopleCount();
            TestDataFactory.pausedSettings(2);

            Test.startTest();
            Id jobId = RollupFullRecalcBatch.begin(new List<Rollup_Definition__c>{ definition });
            Test.stopTest();

            Assert.isNull(jobId, 'Nothing started');
            Assert.isNull(lastCalculated(definition), 'Nothing marked calculated');
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Error_Log__c WHERE Context__c = 'RollupFullRecalcBatch'],
                'One entry saying why'
            );
        }
    }

    /** On BarnCRM's own engine the nightly job and Recalculate all start the full run. */
    @IsTest
    static void theNightlyRunIsTheFullRecalculation() {
        System.runAs(TestUsers.admin()) {
            Account organization = organizations(new List<Integer>{ 0 }, new List<Integer>{ 2 })[0];
            Rollup_Definition__c definition = peopleCount();

            Test.startTest();
            Id jobId = RollupScheduler.runNow();
            Test.stopTest();

            Assert.areEqual(
                'RollupFullRecalcBatch',
                [SELECT ApexClass.Name FROM AsyncApexJob WHERE Id = :jobId].ApexClass.Name,
                'The nightly run is the full recalculation'
            );
            Assert.areEqual(2, countsOf(new List<Account>{ organization }).get(organization.Id));
            Assert.isNotNull(lastCalculated(definition), 'Marked calculated when it finished');
        }
    }
}
