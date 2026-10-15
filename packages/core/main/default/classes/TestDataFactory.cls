/**
 * Shared test data for Core and for every module package (plan Section 7.3).
 *
 * Public and namespace accessible, never global (ADR-0017), so a module package's tests can call
 * it without it becoming part of the subscriber-facing API. Test only: it is never on a code path
 * a subscriber runs.
 */
@IsTest
@NamespaceAccessible
public class TestDataFactory {
    /**
     * The org level BarnCRM Settings, with the shipped v0.1 defaults, saved and cached.
     */
    @NamespaceAccessible
    public static BarnCRM_Settings__c defaultSettings() {
        BarnCRM_Settings__c settings = BarnCRM_Settings__c.getOrgDefaults();
        settings.Coexistence_Mode__c = SettingsService.COEXISTENCE_MODE_DEFAULT;
        settings.Household_Membership_Mode__c = SettingsService.MEMBERSHIP_MODE_DEFAULT;
        settings.Auto_Create_Households__c = true;
        settings.Delete_Empty_Households__c = true;
        settings.Household_Name_Pattern__c = 'The {LastName} Family';
        settings.Formal_Greeting_Pattern__c = '{Salutation} {FirstName} {LastName}';
        settings.Informal_Greeting_Pattern__c = '{FirstName}';
        settings.Include_Deceased_In_Name__c = false;
        settings.Relationship_Auto_Reciprocal__c = true;
        saveSettings(settings);
        return settings;
    }

    /**
     * Saves the org level settings and clears the transaction cache so the next read sees them.
     */
    @NamespaceAccessible
    public static void saveSettings(BarnCRM_Settings__c settings) {
        if (settings.Id == null) {
            insert settings;
        } else {
            update settings;
        }
        SettingsService.clearCaches();
        AutomationControl.clearCache();
    }

    /**
     * Puts automation into a paused state that ends the given number of hours from now. A
     * negative number produces a pause that has already expired.
     */
    @NamespaceAccessible
    public static BarnCRM_Settings__c pausedSettings(Integer hoursFromNow) {
        BarnCRM_Settings__c settings = defaultSettings();
        settings.Automation_Paused_Until__c = System.now().addHours(hoursFromNow);
        saveSettings(settings);
        return settings;
    }

    @NamespaceAccessible
    public static Automation_Setting__c automationSetting(String automationName, Boolean enabled) {
        return new Automation_Setting__c(
            Name = automationName,
            Automation_Name__c = automationName,
            Description__c = 'Test automation used by the BarnCRM test suite.',
            Enabled__c = enabled,
            Handler_Class__c = automationName,
            Object_Name__c = 'Error_Log__c',
            Execution_Order__c = 10,
            Is_Package_Default__c = false
        );
    }

    @NamespaceAccessible
    public static List<Automation_Setting__c> insertAutomationSettings(
        Map<String, Boolean> enabledByName
    ) {
        List<Automation_Setting__c> settings = new List<Automation_Setting__c>();
        for (String automationName : enabledByName.keySet()) {
            settings.add(automationSetting(automationName, enabledByName.get(automationName)));
        }
        insert settings;
        AutomationControl.clearCache();
        return settings;
    }

    /**
     * A shipped registry entry, built in memory. Custom metadata cannot be inserted by a test,
     * so tests hand these to `AutomationRegistrySelector.registryOverride`, or, from another
     * package, to `useRegistry`.
     */
    @NamespaceAccessible
    public static Automation_Registry__mdt registryEntry(String developerName, Boolean enabled) {
        return new Automation_Registry__mdt(
            DeveloperName = developerName,
            MasterLabel = developerName.replace('_', ' '),
            Description__c = 'Shipped test automation.',
            Handler_Class__c = developerName + 'Handler',
            Object_Name__c = 'Error_Log__c',
            Execution_Order__c = 20,
            Enabled_By_Default__c = enabled
        );
    }

    /**
     * Makes these in-memory rows the whole registry for the rest of the test, in place of the
     * shipped one. A module's test cannot set Core's private override itself (ADR-0017 rule 1).
     */
    @NamespaceAccessible
    public static void useRegistry(List<Automation_Registry__mdt> rows) {
        AutomationRegistrySelector.registryOverride = rows;
        AutomationRegistrySelector.clearCache();
    }

    /**
     * A user on the least privileged standard profile whose only BarnCRM access comes from the
     * packaged permission sets named here, so that a test proves what those sets actually grant
     * rather than what a system administrator profile already allows. Built by
     * `TestUsers.standardUserWith`.
     */
    @NamespaceAccessible
    public static User createUser(String lastName, List<String> permissionSetNames) {
        return TestUsers.standardUserWith(lastName, permissionSetNames);
    }

    /**
     * A user on the running user's own profile, holding the packaged permission sets named here:
     * the same access the running user has, without being the running user. Built by
     * `TestUsers.onRunningProfileWith`.
     *
     * For a test that has nothing to prove about access, but must not share something the
     * platform keeps per user with the other test classes running in parallel as the running
     * user (see "The org test gate" in docs/contributor-guide/ci.md).
     */
    @NamespaceAccessible
    public static User createUserOnTheRunningUsersProfile(
        String lastName,
        List<String> permissionSetNames
    ) {
        return TestUsers.onRunningProfileWith(lastName, permissionSetNames);
    }

    /**
     * Makes a packaged role assignable inside a test, and hands back the group behind it.
     *
     * Test.calculatePermissionSetGroup takes the group's record Id, not its DeveloperName:
     * given a name it throws System.StringException: Invalid permission set group id. The
     * package itself never refers to a group by Id (see PermissionSetGroupSelector), so every
     * test that needs a role has to look the Id up first, which is what this does once for all
     * of them.
     *
     * The group is recalculated only when the platform has not already finished with it, so
     * this works both in an org where the metadata has just been deployed and in one where the
     * groups have been settled for weeks.
     *
     * @param developerName the DeveloperName of a packaged permission set group
     * @return the group, ready to be assigned
     */
    @NamespaceAccessible
    public static PermissionSetGroup prepareRoleGroup(String developerName) {
        List<PermissionSetGroup> groups = [
            SELECT Id, DeveloperName, Status
            FROM PermissionSetGroup
            WHERE DeveloperName = :developerName
            LIMIT 1
        ];
        Assert.isFalse(
            groups.isEmpty(),
            'This org does not have the packaged permission set group ' +
                developerName +
                ', so no test that hands out that role can prove anything. Deploy the package ' +
                'metadata into the org before running the tests.'
        );
        if (!'Updated'.equalsIgnoreCase(groups[0].Status)) {
            Test.calculatePermissionSetGroup(groups[0].Id);
        }
        return groups[0];
    }

    /**
     * Error Log records that already exist, so a selector or a tile has something to read.
     */
    @NamespaceAccessible
    public static List<Error_Log__c> insertErrorLogs(Integer howMany, String status) {
        List<Error_Log__c> logs = new List<Error_Log__c>();
        for (Integer i = 0; i < howMany; i++) {
            logs.add(
                new Error_Log__c(
                    Timestamp__c = System.now().addMinutes(-i),
                    User__c = UserInfo.getUserId(),
                    Context__c = 'Test context ' + i,
                    Message__c = 'Something went wrong, number ' + i + '.',
                    Technical_Detail__c = 'TestException: number ' + i,
                    Severity__c = ErrorLogger.SEVERITY_ERROR,
                    Status__c = status
                )
            );
        }
        insert logs;
        return logs;
    }
}
