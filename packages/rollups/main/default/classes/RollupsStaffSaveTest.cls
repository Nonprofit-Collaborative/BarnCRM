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
}
