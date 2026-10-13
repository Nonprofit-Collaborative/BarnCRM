/**
 * A module ships its own settings object, so Core reads the org-level record of an object it
 * does not know at compile time.
 */
@IsTest
private class SettingsRecordSelectorTest {
    @IsTest
    static void readsNothingWhenTheOrgHasNeverSaved() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            SObject record = SettingsRecordSelector.getOrgDefault(BarnCRM_Settings__c.SObjectType);
            Test.stopTest();

            Assert.isNull(record, 'An org that has never saved has no org-level record to read');
        }
    }

    @IsTest
    static void readsTheOrgLevelRecordOnceItExists() {
        System.runAs(TestUsers.admin()) {
            insert new BarnCRM_Settings__c(
                SetupOwnerId = UserInfo.getOrganizationId(),
                Household_Name_Pattern__c = 'The {LastName} Family'
            );

            Test.startTest();
            SObject record = SettingsRecordSelector.getOrgDefault(BarnCRM_Settings__c.SObjectType);
            Test.stopTest();

            Assert.isNotNull(record, 'The org-level record is found by its setup owner');
            Assert.areEqual(
                'The {LastName} Family',
                record.get('Household_Name_Pattern__c'),
                'The values on it come back with it'
            );
        }
    }
}
