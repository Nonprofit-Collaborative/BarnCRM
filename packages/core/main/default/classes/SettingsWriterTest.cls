/**
 * The settings object is a protected component, so no permission set can grant a subscriber
 * user write access to it. The write therefore runs in system mode and the Manage Nonprofit
 * Settings custom permission is the gate. These tests hold that gate honest.
 */
@IsTest
private class SettingsWriterTest {
    @TestSetup
    static void makeData() {
        PermissionSet permissionSet = SettingsTestPermissions.build('C03_Settings_Writer_Test');
        User maria = SettingsTestPermissions.buildStandardUser('Maria', 'Alvarez', 'mariaw');
        User david = SettingsTestPermissions.buildStandardUser('David', 'Okonkwo', 'davidw');
        insert new List<User>{ maria, david };
        insert new PermissionSetAssignment(
            AssigneeId = maria.Id,
            PermissionSetId = permissionSet.Id
        );
    }

    private static User userNamed(String lastName) {
        return [SELECT Id FROM User WHERE LastName = :lastName AND IsActive = TRUE LIMIT 1];
    }

    @IsTest
    static void letsAStandardUserWithThePermissionSave() {
        User maria = userNamed('Alvarez');
        Boolean saved = false;

        Test.startTest();
        System.runAs(maria) {
            SettingsWriter.saveOrgDefault(
                Nonprofit_Settings__c.SObjectType,
                null,
                patternChange('The {LastName} Family')
            );
            saved = true;
        }
        Test.stopTest();

        Assert.isTrue(
            saved,
            'Maria holds the permission and is not an administrator, and she saves'
        );
        Assert.areEqual(
            'The {LastName} Family',
            Nonprofit_Settings__c.getOrgDefaults().Household_Name_Pattern__c,
            'What she saved is what the org now runs on'
        );
    }

    @IsTest
    static void refusesAStandardUserWithoutThePermission() {
        User david = userNamed('Okonkwo');
        Boolean refused = false;

        Test.startTest();
        System.runAs(david) {
            try {
                SettingsWriter.saveOrgDefault(
                    Nonprofit_Settings__c.SObjectType,
                    null,
                    patternChange('The {LastName} Clan')
                );
            } catch (SettingsWriter.PermissionException e) {
                refused = true;
                Assert.areEqual(
                    System.Label.Core_Settings_PermissionRequiredError,
                    e.getMessage(),
                    'The message names the permission to ask for'
                );
            }
        }
        Test.stopTest();

        Assert.isTrue(refused, 'System mode is reachable only through the permission');
    }

    @IsTest
    static void ignoresNothingToSave() {
        Test.startTest();
        SettingsWriter.saveOrgDefault(Nonprofit_Settings__c.SObjectType, null, null);
        SettingsWriter.saveOrgDefault(
            Nonprofit_Settings__c.SObjectType,
            null,
            new Map<Schema.SObjectField, Object>()
        );
        Test.stopTest();

        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Nonprofit_Settings__c],
            'Nothing to save writes nothing and raises nothing'
        );
    }

    /**
     * Another administrator saved a different key after this transaction read its copy. The
     * save writes only its own key, so theirs survives (plan Section 11.3, follow-up 1).
     */
    @IsTest
    static void savesOnlyTheChangedKeyOverTheStoredRecord() {
        insert new Nonprofit_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Household_Name_Pattern__c = 'The {LastName} Family',
            Relationship_Auto_Reciprocal__c = true
        );
        Nonprofit_Settings__c stored = OrgSettingsSystemWriter.lockStored();
        Nonprofit_Settings__c theirs = new Nonprofit_Settings__c(
            Id = stored.Id,
            Relationship_Auto_Reciprocal__c = false
        );
        update theirs;
        User maria = userNamed('Alvarez');

        Test.startTest();
        System.runAs(maria) {
            SettingsWriter.saveOrgDefault(
                Nonprofit_Settings__c.SObjectType,
                stored,
                patternChange('{LastName} Household')
            );
        }
        Test.stopTest();

        Nonprofit_Settings__c saved = [
            SELECT Household_Name_Pattern__c, Relationship_Auto_Reciprocal__c
            FROM Nonprofit_Settings__c
            WHERE Id = :stored.Id
        ];
        Assert.areEqual(
            '{LastName} Household',
            saved.Household_Name_Pattern__c,
            'Her key is saved'
        );
        Assert.isFalse(
            saved.Relationship_Auto_Reciprocal__c,
            'And the key the other administrator saved is not written back from her copy'
        );
    }

    private static Map<Schema.SObjectField, Object> patternChange(String pattern) {
        return new Map<Schema.SObjectField, Object>{
            Nonprofit_Settings__c.Household_Name_Pattern__c => pattern
        };
    }
}
