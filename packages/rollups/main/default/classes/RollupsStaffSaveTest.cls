/**
 * Someone who holds only Core's BarnCRM Staff set, and neither Rollup Builder set, still saves
 * records and still has the totals over them kept current (ADR-NEXT `NEXT-rollup-builder-module.md`,
 * decision 8). The rollup grants left Core's sets for the module's, so every package-owned read
 * and write on the save path has to run in system mode: a user mode read of the definitions, or a
 * user mode write to the queue, would fail this person's save or silently skip their totals.
 */
@IsTest(testFor='ApexClass:RollupTriggerHandler, ApexClass:RollupQueue, ApexClass:RollupSelector')
private class RollupsStaffSaveTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.adminWith('Rollup_Builder_Admin');
    }

    @IsTest
    static void aStaffOnlySaveStillUpdatesItsTotals() {
        User staff;
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            insert new Rollup_Definition__c(
                Name = 'People per organization',
                Definition_Key__c = 'Test_Staff_People_Per_Organization',
                Source_Object__c = 'Contact',
                Relationship_Path__c = 'AccountId',
                Aggregate__c = 'COUNT',
                Target_Object__c = 'Account',
                Target_Field__c = 'NumberOfEmployees',
                Mode__c = RollupService.MODE_BOTH,
                Fiscal_Year_Aware__c = false,
                Active__c = true
            );
            staff = TestDataFactory.createUser('Staffonly', new List<String>{ 'BarnCRM_Staff' });
        }
        Account organization;

        System.runAs(staff) {
            organization = new Account(
                Name = 'Food Bank',
                RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
                    .get('Organization')
                    .getRecordTypeId()
            );
            insert organization;

            Test.startTest();
            insert new Contact(LastName = 'Volunteer', AccountId = organization.Id);
            Test.getEventBus().deliver();
            Test.stopTest();
        }

        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            Assert.areEqual(
                1,
                [SELECT NumberOfEmployees FROM Account WHERE Id = :organization.Id]
                .NumberOfEmployees,
                'The save went through and its total was kept current without a rollup set'
            );
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Error_Log__c WHERE Context__c LIKE 'Rollup%'],
                'Nothing on the save path was refused for want of a permission'
            );
        }
    }

    /** A Staff-only person's save made inside a Queueable, as an integration's job makes it. */
    private class SaveInAQueueable implements Queueable {
        private final Id organizationId;

        SaveInAQueueable(Id organizationId) {
            this.organizationId = organizationId;
        }

        public void execute(QueueableContext context) {
            insert new Contact(LastName = 'Queued Volunteer', AccountId = organizationId);
            // Asserted here, where the job's own transaction state is: a Queueable leaves the
            // processor job to its caller and announces the entries with the ready event.
            Assert.areEqual(
                1,
                RollupQueue.readyEventsPublished,
                'The Staff-only save inside a Queueable published Rollup_Queue_Ready__e'
            );
        }
    }

    @IsTest
    static void aStaffOnlySaveInsideAQueueablePublishesTheReadyEvent() {
        User staff;
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            insert new Rollup_Definition__c(
                Name = 'People per organization',
                Definition_Key__c = 'Test_Staff_Queueable_People',
                Source_Object__c = 'Contact',
                Relationship_Path__c = 'AccountId',
                Aggregate__c = 'COUNT',
                Target_Object__c = 'Account',
                Target_Field__c = 'NumberOfEmployees',
                Mode__c = RollupService.MODE_BOTH,
                Fiscal_Year_Aware__c = false,
                Active__c = true
            );
            staff = TestDataFactory.createUser('Staffqueued', new List<String>{ 'BarnCRM_Staff' });
        }
        Account organization;

        System.runAs(staff) {
            organization = new Account(
                Name = 'Shelter',
                RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
                    .get('Organization')
                    .getRecordTypeId()
            );
            insert organization;

            Test.startTest();
            System.enqueueJob(new SaveInAQueueable(organization.Id));
            Test.stopTest();
        }

        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Contact WHERE AccountId = :organization.Id],
                'The save inside the Queueable went through'
            );
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Error_Log__c WHERE Context__c LIKE 'Rollup%'],
                'Publishing the ready event was not refused for want of a permission'
            );
        }
    }
}
