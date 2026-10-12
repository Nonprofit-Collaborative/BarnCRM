/**
 * A full recalculation chunk the platform stopped, and one full run at a time (canonical model
 * R-R14). Core holds no giving objects, so the run counts people onto their organization, as
 * `RollupFullRecalcBatchTest` does.
 */
@IsTest
private class RollupRecalcErrorHandlerTest {
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

    private static List<Account> organizations(Integer count) {
        Id organizationType = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get('Organization')
            .getRecordTypeId();
        List<Account> organizations = new List<Account>();
        for (Integer i = 0; i < count; i++) {
            organizations.add(
                new Account(Name = 'Organization ' + i, RecordTypeId = organizationType)
            );
        }
        insert organizations;
        return organizations;
    }

    private static Set<Id> queuedIds(String targetObject) {
        Set<Id> ids = new Set<Id>();
        for (Rollup_Queue__c entry : [
            SELECT Target_Object__c, Record_Ids__c
            FROM Rollup_Queue__c
            WHERE Target_Object__c = :targetObject
        ]) {
            ids.addAll(RollupQueue.idsOf(entry));
        }
        return ids;
    }

    private static BatchApexErrorEvent event(Id jobId, String phase, String jobScope) {
        // The platform publishes these; the attributes cannot be written, so the event is built
        // as the trigger receives it.
        return (BatchApexErrorEvent) JSON.deserialize(
            JSON.serialize(
                new Map<String, Object>{
                    'AsyncApexJobId' => jobId,
                    'Phase' => phase,
                    'JobScope' => jobScope
                }
            ),
            BatchApexErrorEvent.class
        );
    }

    /** Two hundred organizations in one chunk, stopped as a governor limit would stop it. */
    @IsTest
    static void aStoppedChunkPutsItsRecordsInTheQueue() {
        System.runAs(TestUsers.admin()) {
            Rollup_Definition__c definition = peopleCount();
            List<Account> stopped = organizations(200);
            RollupFullRecalcBatch.stopNextChunk = true;

            try {
                Test.startTest();
                RollupFullRecalcBatch.begin(new List<Rollup_Definition__c>{ definition });
                Test.stopTest();
            } catch (Exception expected) {
                // The chunk's own error reaches the test, as the docs for BatchApexErrorEvent say.
                Assert.isTrue(expected.getMessage().contains('RollupFullRecalcBatch'), 'Our stop');
            }
            Test.getEventBus().deliver();
            Test.getEventBus().deliver();

            Assert.areEqual(
                new Map<Id, Account>(stopped).keySet(),
                queuedIds('Account'),
                'Every record of the stopped chunk waits in the queue, not until the next night'
            );
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Error_Log__c WHERE Context__c = 'RollupRecalcErrorHandler'],
                'And one entry says so'
            );
        }
    }

    @IsTest
    static void eventsFromOtherJobsOrPhasesAreLeftAlone() {
        System.runAs(TestUsers.admin()) {
            Rollup_Definition__c definition = peopleCount();
            Account organization = organizations(1)[0];

            Test.startTest();
            Id ours = RollupFullRecalcBatch.begin(new List<Rollup_Definition__c>{ definition });
            Id other = System.enqueueJob(new RollupQueue());
            RollupRecalcErrorHandler.handle(
                new List<BatchApexErrorEvent>{
                    event(other, 'EXECUTE', organization.Id),
                    event(ours, 'START', organization.Id),
                    event(ours, 'EXECUTE', 'not an id')
                }
            );
            Integer queuedBefore = queuedIds('Account').size();
            RollupRecalcErrorHandler.handle(
                new List<BatchApexErrorEvent>{ event(ours, 'EXECUTE', organization.Id) }
            );
            Integer queuedAfter = queuedIds('Account').size();
            Test.stopTest();

            Assert.areEqual(
                0,
                queuedBefore,
                'Another class, a start that failed and a scope with no records queue nothing'
            );
            Assert.areEqual(1, queuedAfter, 'A stopped chunk of the full run is queued');
        }
    }

    @IsTest
    static void aSecondFullRunIsRefusedWhileOneIsGoing() {
        System.runAs(TestUsers.admin()) {
            Rollup_Definition__c definition = peopleCount();
            organizations(1);

            Test.startTest();
            Id first = RollupService.startNightlyRun();
            Id running = RollupFullRecalcBatch.runningJobId();
            Id second = RollupService.startNightlyRun();
            Integer handedOver = RollupService.runFullRecalculation(
                new List<Rollup_Definition__c>{ definition }
            );
            Test.stopTest();
            Test.getEventBus().deliver();

            Assert.isNotNull(first, 'The first run starts');
            Assert.areEqual(first, running, 'And is the run going');
            Assert.areEqual(first, second, 'A second start answers the run that is going');
            Assert.areEqual(0, handedOver, 'And hands nothing over');
            Assert.areEqual(
                1,
                [
                    SELECT COUNT()
                    FROM AsyncApexJob
                    WHERE JobType = 'BatchApex' AND ApexClass.Name = 'RollupFullRecalcBatch'
                ],
                'One run, not three'
            );
            Assert.areEqual(
                2,
                [
                    SELECT COUNT()
                    FROM Error_Log__c
                    WHERE Context__c = 'RollupFullRecalcBatch' AND Severity__c = 'Info'
                ],
                'Each refused start says which run is going'
            );
            Assert.isNull(RollupFullRecalcBatch.runningJobId(), 'Nothing runs once it finished');
        }
    }

    @IsTest
    static void recalculateAllWhileARunIsGoingTellsTheAdmin() {
        System.runAs(TestUsers.admin()) {
            User maria = HealthCheckTestHelper.mariaWithManageSettings();
            peopleCount();

            System.runAs(maria) {
                Test.startTest();
                RollupService.startNightlyRun();
                try {
                    RollupController.recalculateAll();
                    Assert.fail('A second full run is refused');
                } catch (AuraHandledException expected) {
                    Assert.areEqual(
                        Label.Core_Rollups_FullRunAlreadyRunning,
                        expected.getMessage(),
                        'In plain words, with what to do'
                    );
                }
                Test.stopTest();
            }

        }
    }
}
