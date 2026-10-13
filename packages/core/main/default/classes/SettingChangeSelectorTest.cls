/** Recent changes are what Maria checks when she is not sure a change went in. */
@IsTest
private class SettingChangeSelectorTest {
    @TestSetup
    static void makeData() {
        System.runAs(TestUsers.admin()) {
            List<Setting_Change__c> changes = new List<Setting_Change__c>();
            for (Integer i = 0; i < 5; i++) {
                changes.add(
                    new Setting_Change__c(
                        Setting_Name__c = 'Household_Name_Pattern__c',
                        Old_Value__c = 'pattern ' + i,
                        New_Value__c = 'pattern ' + (i + 1),
                        Changed_By__c = UserInfo.getUserId(),
                        Changed_At__c = System.now().addMinutes(i)
                    )
                );
            }
            insert changes;
        }
    }

    @IsTest
    static void returnsTheNewestChangesFirst() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            List<Setting_Change__c> changes = SettingChangeSelector.getRecent(3);
            Test.stopTest();

            Assert.areEqual(3, changes.size(), 'Maria asked for three');
            Assert.isTrue(
                changes[0].Changed_At__c >= changes[1].Changed_At__c,
                'The most recent change is the one at the top'
            );
        }
    }

    @IsTest
    static void fallsBackToASensibleNumber() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            List<Setting_Change__c> withoutLimit = SettingChangeSelector.getRecent(null);
            List<Setting_Change__c> withZero = SettingChangeSelector.getRecent(0);
            Test.stopTest();

            Assert.areEqual(
                5,
                withoutLimit.size(),
                'No number means the default of ten, and there are five'
            );
            Assert.areEqual(5, withZero.size(), 'Zero means the same');
        }
    }
}
