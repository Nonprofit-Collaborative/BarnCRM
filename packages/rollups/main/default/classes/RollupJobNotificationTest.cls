/**
 * The nightly rollup recalculation tells the person who started it that it finished, and the
 * notification opens the Rollups section (Q-04). Moved from Core's JobNotificationPathsTest
 * with the engine (ADR-0125).
 */
@IsTest(testFor='ApexClass:RollupFullRecalcBatch')
private class RollupJobNotificationTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.adminWith('Rollup_Builder_Admin');
    }

    @IsTest
    static void rollupRecalculationOpensRollups() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            insert new BarnCRM_Settings__c(
                SetupOwnerId = UserInfo.getOrganizationId(),
                Job_Notifications__c = true
            );
            SettingsService.clearCaches();
            Id organizationType = AccountKindsTestData.organizationRecordTypeId();
            Account organization = new Account(Name = 'Food Bank', RecordTypeId = organizationType);
            insert organization;
            insert new Contact(LastName = 'Volunteer', AccountId = organization.Id);
            Rollup_Definition__c definition = new Rollup_Definition__c(
                Name = 'People per organization',
                Definition_Key__c = 'Test_Q04_People_Per_Organization',
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
            JobNotifier.sentNotices().clear();

            RollupFullRecalcBatch.firstPass(new List<Rollup_Definition__c>{ definition })
                .runInline();

            Assert.areEqual(1, JobNotifier.sentNotices().size(), 'Exactly one notification');
            JobNotifier.Notice notice = JobNotifier.sentNotices()[0];
            Assert.areEqual(
                UserInfo.getUserId(),
                notice.recipientId,
                'To the person who started it'
            );
            Assert.isNull(notice.targetId, 'No record');
            Assert.areEqual(
                JobNotifier.SECTION_ROLLUPS,
                notice.section,
                'Opening the Rollups section'
            );
            Assert.areEqual(
                String.format(
                    System.Label.Core_JobNotice_Finished,
                    new List<Object>{ System.Label.Core_JobNotice_Rollups }
                ),
                notice.title,
                'Saying what happened'
            );
        }
    }
}
