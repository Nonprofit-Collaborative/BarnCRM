/**
 * Builds, in a test, the access a person needs to change settings: the Manage Nonprofit
 * Settings custom permission plus create and read on the audit object, which is what the
 * packaged BarnCRM Admin permission set grants in a real org.
 *
 * Used from `@TestSetup` so that the permission set and its assignment are committed before a
 * test method runs, which also keeps setup objects out of the same transaction as the custom
 * object writes the tests make.
 */
@IsTest
public class SettingsTestPermissions {
    private static final String CUSTOM_PERMISSION = 'Manage_BarnCRM_Settings';
    private static final List<String> AUDIT_FIELDS = new List<String>{
        'Setting_Name__c',
        'Old_Value__c',
        'New_Value__c',
        'Changed_By__c',
        'Changed_At__c'
    };

    /** True when the custom permission C-04 ships is present in this org. */
    public static Boolean customPermissionExists() {
        return !getCustomPermissions().isEmpty();
    }

    /**
     * A permission set carrying the custom permission (when it exists) and the access the audit
     * trail needs.
     */
    public static PermissionSet build(String name) {
        PermissionSet permissionSet = new PermissionSet(Name = name, Label = name);
        insert permissionSet;
        List<CustomPermission> permissions = getCustomPermissions();
        if (!permissions.isEmpty()) {
            insert new SetupEntityAccess(
                ParentId = permissionSet.Id,
                SetupEntityId = permissions[0].Id
            );
        }
        insert new ObjectPermissions(
            ParentId = permissionSet.Id,
            SobjectType = 'Setting_Change__c',
            PermissionsRead = true,
            PermissionsCreate = true
        );
        List<FieldPermissions> fields = new List<FieldPermissions>();
        for (String field : AUDIT_FIELDS) {
            fields.add(
                new FieldPermissions(
                    ParentId = permissionSet.Id,
                    SobjectType = 'Setting_Change__c',
                    Field = 'Setting_Change__c.' + field,
                    PermissionsRead = true,
                    PermissionsEdit = true
                )
            );
        }
        insert fields;
        return permissionSet;
    }

    /** Builds the permission set and assigns it to the given user. */
    public static void grantTo(String name, Id userId) {
        insert new PermissionSetAssignment(AssigneeId = userId, PermissionSetId = build(name).Id);
    }

    /** A user on the Standard User profile, so a test can prove a non-administrator can save. */
    public static User buildStandardUser(String firstName, String lastName, String alias) {
        Profile standard = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        return new User(
            FirstName = firstName,
            LastName = lastName,
            Alias = alias,
            Email = alias + '.barncrm@example.com',
            Username = alias + '.barncrm.' + DateTime.now().getTime() + '@example.com',
            ProfileId = standard.Id,
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
    }

    private static List<CustomPermission> getCustomPermissions() {
        return [SELECT Id FROM CustomPermission WHERE DeveloperName = :CUSTOM_PERMISSION LIMIT 1];
    }
}
