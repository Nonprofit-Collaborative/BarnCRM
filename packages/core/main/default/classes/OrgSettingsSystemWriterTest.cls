@IsTest(testFor='ApexClass:OrgSettingsSystemWriter')
private class OrgSettingsSystemWriterTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static BarnCRM_Settings__c stored() {
        List<BarnCRM_Settings__c> rows = [
            SELECT
                Id,
                Relationship_Auto_Reciprocal__c,
                Auto_Create_Households__c,
                Coexistence_Mode__c,
                Household_Membership_Mode__c,
                Automation_Paused_Until__c,
                Seasonal_Address_Last_Run__c
            FROM BarnCRM_Settings__c
            WHERE SetupOwnerId = :UserInfo.getOrganizationId()
        ];
        Assert.areEqual(1, rows.size(), 'One org-level settings record.');
        return rows[0];
    }

    private static void assertShippedDefaultsKept(BarnCRM_Settings__c saved) {
        Assert.isTrue(saved.Relationship_Auto_Reciprocal__c, 'A feature that ships on stays on.');
        Assert.isTrue(saved.Auto_Create_Households__c, 'Households are still created by default.');
        Assert.isNull(saved.Coexistence_Mode__c, 'Nobody confirmed a coexistence mode.');
        Assert.isNull(saved.Household_Membership_Mode__c, 'Nobody chose a membership mode.');
    }

    @IsTest
    static void aPauseAsTheFirstSaveKeepsTheShippedDefaults() {
        System.runAs(TestUsers.admin()) {
            Datetime until = System.now().addHours(2);
            Test.startTest();
            AutomationSettingsWriter.savePausedUntil(OrgSettingsSystemWriter.lockStored(), until);
            Test.stopTest();

            BarnCRM_Settings__c saved = stored();
            Assert.areEqual(until, saved.Automation_Paused_Until__c, 'The pause is saved.');
            assertShippedDefaultsKept(saved);
        }
    }

    @IsTest
    static void aSeasonalRunRecordAsTheFirstSaveKeepsTheShippedDefaults() {
        System.runAs(TestUsers.admin()) {
            Datetime finishedAt = System.now();
            Test.startTest();
            SeasonalAddressWriter.recordRun(finishedAt, 'Nothing to swap.');
            Test.stopTest();

            BarnCRM_Settings__c saved = stored();
            Assert.areEqual(finishedAt, saved.Seasonal_Address_Last_Run__c, 'The run is recorded.');
            assertShippedDefaultsKept(saved);
        }
    }

    @IsTest
    static void aLaterSaveChangesOnlyItsOwnKeys() {
        System.runAs(TestUsers.admin()) {
            insert new BarnCRM_Settings__c(
                SetupOwnerId = UserInfo.getOrganizationId(),
                Relationship_Auto_Reciprocal__c = false,
                Auto_Create_Households__c = true,
                Coexistence_Mode__c = 'Standalone'
            );
            Test.startTest();
            AutomationSettingsWriter.savePausedUntil(
                OrgSettingsSystemWriter.lockStored(),
                System.now().addHours(1)
            );
            AutomationSettingsWriter.savePausedUntil(OrgSettingsSystemWriter.lockStored(), null);
            Test.stopTest();

            BarnCRM_Settings__c saved = stored();
            Assert.isNull(saved.Automation_Paused_Until__c, 'The pause is cleared.');
            Assert.isFalse(
                saved.Relationship_Auto_Reciprocal__c,
                'A deliberate off is left alone.'
            );
            Assert.areEqual(
                'Standalone',
                saved.Coexistence_Mode__c,
                'A chosen mode is left alone.'
            );
        }
    }

    @IsTest
    static void twoFirstSavesAtOnceKeepBothRunsValues() {
        System.runAs(TestUsers.admin()) {
            OrgSettingsSystemWriter.competingFirstSaveForTest = new BarnCRM_Settings__c(
                SetupOwnerId = UserInfo.getOrganizationId(),
                Seasonal_Address_Last_Run_Summary__c = 'Swapped 2 households.',
                Relationship_Auto_Reciprocal__c = true,
                Auto_Create_Households__c = true
            );
            Datetime until = System.now().addHours(2);

            Test.startTest();
            AutomationSettingsWriter.savePausedUntil(OrgSettingsSystemWriter.lockStored(), until);
            Test.stopTest();

            Assert.areEqual(
                1,
                [
                    SELECT COUNT()
                    FROM BarnCRM_Settings__c
                    WHERE SetupOwnerId = :UserInfo.getOrganizationId()
                ],
                'Still one org-level record: the losing insert became an update.'
            );
            BarnCRM_Settings__c saved = [
                SELECT Automation_Paused_Until__c, Seasonal_Address_Last_Run_Summary__c
                FROM BarnCRM_Settings__c
                WHERE SetupOwnerId = :UserInfo.getOrganizationId()
            ];
            Assert.areEqual(until, saved.Automation_Paused_Until__c, 'This run saved its key.');
            Assert.areEqual(
                'Swapped 2 households.',
                saved.Seasonal_Address_Last_Run_Summary__c,
                'And the run that won keeps its own.'
            );
        }
    }
}
