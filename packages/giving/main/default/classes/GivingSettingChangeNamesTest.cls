/**
 * Recent Changes shows a Record setting's value, such as the default fund, as the record's name,
 * read when the list is read, and as stored when the record is gone.
 */
@IsTest(testFor='ApexClass:SettingsController')
private class GivingSettingChangeNamesTest {
    private static final String SETTING = 'Giving_Settings__c.Default_Fund__c';

    @IsTest
    static void aFundIdReadsAsTheFundName() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Fund__c fund = new Fund__c(Name = 'Annual Fund', Active__c = true);
            insert fund;
            insert new Setting_Change__c(
                Setting_Name__c = SETTING,
                Old_Value__c = null,
                New_Value__c = fund.Id,
                Changed_By__c = UserInfo.getUserId(),
                Changed_At__c = System.now()
            );

            Test.startTest();
            List<SettingsController.ChangeModel> changes = SettingsController.getRecentChanges(5);
            Test.stopTest();

            Assert.areEqual(1, changes.size(), 'The change is listed');
            Assert.areEqual('Annual Fund', changes[0].newValue, 'The fund shows by name');
            Assert.isNull(changes[0].oldValue, 'A blank old value stays blank');
        }
    }

    @IsTest
    static void aDeletedFundShowsTheStoredId() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            // A well formed fund Id that no record has.
            String storedId = Fund__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001';
            insert new Setting_Change__c(
                Setting_Name__c = SETTING,
                New_Value__c = storedId,
                Changed_By__c = UserInfo.getUserId(),
                Changed_At__c = System.now()
            );

            List<SettingsController.ChangeModel> changes = SettingsController.getRecentChanges(5);

            Assert.areEqual(storedId, changes[0].newValue, 'A record that is gone shows as stored');
        }
    }
}
