/**
 * The Rollup Queue never strands work and never hides it (rollup review ROLLUPS-7, Core quality
 * pass Q-01): entries no save started a processor for are started by the nightly run, the end of
 * a pause, Retry and Start now; Failed and long-waiting entries are Health Check findings; and
 * the engine reads its definitions once per transaction (ROLLUPS-5).
 *
 * Core holds no giving objects, so people (Contact) are counted on their organization
 * (`AccountId`).
 */
@IsTest
private class RollupQueueRecoveryTest {
    private static Rollup_Definition__c staffCount() {
        return new Rollup_Definition__c(
            Name = 'Staff count',
            Definition_Key__c = 'Test_Recovery_Staff_Count',
            Source_Object__c = 'Contact',
            Relationship_Path__c = 'AccountId',
            Aggregate__c = 'COUNT',
            Target_Object__c = 'Account',
            Target_Field__c = 'NumberOfEmployees',
            Mode__c = RollupService.MODE_BOTH,
            Fiscal_Year_Aware__c = false,
            Active__c = true
        );
    }

    private static Account organization() {
        Account created = new Account(
            Name = 'Organization',
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
                .get('Organization')
                .getRecordTypeId()
        );
        insert created;
        return created;
    }

    private static Integer countOn(Id organizationId) {
        Integer count = [SELECT NumberOfEmployees FROM Account WHERE Id = :organizationId]
        .NumberOfEmployees;
        return count == null ? 0 : count;
    }

    private static Integer pending() {
        return [SELECT COUNT() FROM Rollup_Queue__c WHERE Status__c = :RollupQueue.STATUS_PENDING];
    }

    /** ROLLUPS-7: Start now recalculates entries that no processor is coming for. */
    @IsTest
    static void startNowRecalculatesWaitingEntries() {
        System.runAs(TestUsers.admin()) {
            insert staffCount();
            Account organization = organization();
            AutomationControl.bypass('Core_Rollups_Contact');
            insert new Contact(LastName = 'Ames', AccountId = organization.Id);
            AutomationControl.clearBypass('Core_Rollups_Contact');
            insert new Rollup_Queue__c(
                Target_Object__c = 'Account',
                Record_Ids__c = String.valueOf(organization.Id),
                Record_Count__c = 1,
                Attempts__c = 0,
                Status__c = RollupQueue.STATUS_PENDING
            );

            Test.startTest();
            RollupAttentionController.Attention attention = RollupAttentionController.processNow();
            Test.stopTest();

            Assert.isTrue(attention.hasWaiting, 'The list said a record was waiting');
            Assert.areEqual(1, countOn(organization.Id), 'Start now recalculated it');
            Assert.areEqual(0, pending(), 'Nothing is left waiting');
        }
    }

    @IsTest
    static void processPendingDoesNothingWhenNothingWaits() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            Boolean started = RollupQueue.processPending();
            Test.stopTest();
            Assert.isFalse(started, 'No entry, no processor');
        }
    }

    /** Failed entries and entries waiting over an hour are Health Check findings. */
    @IsTest
    static void healthCheckReportsFailedAndStuckEntries() {
        System.runAs(TestUsers.admin()) {
            Rollup_Queue__c stuck = new Rollup_Queue__c(
                Target_Object__c = 'Account',
                Record_Ids__c = '001000000000001AAA',
                Record_Count__c = 1,
                Attempts__c = 0,
                Status__c = RollupQueue.STATUS_PENDING
            );
            insert stuck;
            Test.setCreatedDate(stuck.Id, Datetime.now().addHours(-2));

            HealthCheckService.Finding finding = new HealthCheckSettingsChecks.RollupQueueCheck()
                .run();
            Assert.areEqual('rollup_queue_stuck', finding.key, 'Waiting two hours is stuck');
            Assert.isTrue(finding.fixTarget.contains('Rollup_Builder'), 'Fixed in Needs attention');

            insert new Rollup_Queue__c(
                Target_Object__c = 'Account',
                Record_Ids__c = '001000000000002AAA',
                Record_Count__c = 1,
                Attempts__c = RollupQueue.MAX_ATTEMPTS,
                Status__c = RollupQueue.STATUS_FAILED
            );
            finding = new HealthCheckSettingsChecks.RollupQueueCheck().run();
            Assert.areEqual(
                'rollup_queue_failed',
                finding.key,
                'A failed entry is the finding to act on first'
            );
            Assert.areEqual(
                HealthCheckService.SEVERITY_WARNING,
                finding.severity,
                'It is a warning'
            );

            delete [SELECT Id FROM Rollup_Queue__c];
            Assert.isNull(
                new HealthCheckSettingsChecks.RollupQueueCheck().run(),
                'An empty queue is no finding'
            );
        }
    }

    /** ROLLUPS-5: the definitions are read once per transaction, and again after a change. */
    @IsTest
    static void definitionsAreReadOncePerTransactionUntilOneChanges() {
        System.runAs(TestUsers.admin()) {
            insert staffCount();
            Test.startTest();
            RollupSelector.clearCache();
            Integer before = Limits.getQueries();
            RollupSelector.selectAll();
            RollupSelector.selectActiveForModes(RollupService.scheduledModes());
            Integer spent = Limits.getQueries() - before;
            Rollup_Definition__c second = staffCount();
            second.Definition_Key__c = 'Test_Recovery_Second';
            second.Target_Field__c = 'AnnualRevenue';
            second.Mode__c = RollupService.MODE_SCHEDULED;
            insert second;
            Integer afterChange = RollupSelector.selectAll().size();
            Test.stopTest();

            Assert.areEqual(1, spent, 'Two reads, one query');
            Assert.areEqual(2, afterChange, 'A definition saved since is in the next read');
        }
    }
}
