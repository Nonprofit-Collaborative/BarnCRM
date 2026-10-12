/**
 * Maria opens the console and changes a setting. David opens the same page without the
 * Manage Nonprofit Settings permission and gets a read-only view that names the permission.
 */
@IsTest
private class SettingsControllerTest {
    private static final String TEXT_KEY = 'Household_Name_Pattern__c';
    private static final String CHECKBOX_KEY = 'Auto_Create_Households__c';
    private static final String EDIT_PERMISSION = 'Manage_Nonprofit_Settings';

    @TestSetup
    static void makeData() {
        PermissionSet permissionSet = SettingsTestPermissions.build('C03_Settings_Console_Test');
        User maria = SettingsTestPermissions.buildStandardUser('Maria', 'Alvarez', 'mariac');
        insert maria;
        insert new List<PermissionSetAssignment>{
            new PermissionSetAssignment(
                AssigneeId = UserInfo.getUserId(),
                PermissionSetId = permissionSet.Id
            ),
            new PermissionSetAssignment(AssigneeId = maria.Id, PermissionSetId = permissionSet.Id)
        };
    }

    private static void stubDefinitions() {
        SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>{
            new Setting_Definition__mdt(
                DeveloperName = 'Household_Name_Pattern',
                MasterLabel = 'Household name pattern',
                Setting_Key__c = TEXT_KEY,
                Section__c = SettingSections.HOUSEHOLDS,
                Module__c = 'Core',
                Data_Type__c = 'Text',
                Description__c = 'How a household name and the greetings on your letters are built.',
                Help_Path__c = 'household-naming.md',
                Sort_Order__c = 1
            ),
            new Setting_Definition__mdt(
                DeveloperName = 'Auto_Create_Households',
                MasterLabel = 'Create households automatically',
                Setting_Key__c = CHECKBOX_KEY,
                Section__c = SettingSections.HOUSEHOLDS,
                Module__c = 'Core',
                Data_Type__c = 'Checkbox',
                Description__c = 'Whether adding a person with no household creates one.',
                Sort_Order__c = 2
            ),
            new Setting_Definition__mdt(
                DeveloperName = 'Coexistence_Mode_Choice',
                MasterLabel = 'How Open Impact fits your org',
                Setting_Key__c = 'Coexistence_Mode__c',
                Section__c = SettingSections.GENERAL,
                Module__c = 'Core',
                Data_Type__c = 'Picklist',
                Picklist_Values__c = 'Standalone:On its own;AgentforceNonprofit:Alongside Nonprofit Cloud',
                Sort_Order__c = 1
            ),
            new Setting_Definition__mdt(
                DeveloperName = 'Automation_Panel',
                MasterLabel = 'Automations',
                Section__c = SettingSections.AUTOMATION,
                Module__c = 'Core',
                Data_Type__c = 'Component',
                Component__c = 'automationControl',
                Sort_Order__c = 1
            ),
            // A row from a module that is not in this org. Its key has to be one no settings
            // object in the repo defines, because that absence is the whole test: Default_Fund__c
            // used to be such a key and is now a real Giving field (ADR-0059).
            new Setting_Definition__mdt(
                DeveloperName = 'Not_Installed_Yet',
                MasterLabel = 'Default grant program',
                Setting_Key__c = 'Default_Grant_Program__c',
                Section__c = SettingSections.GIVING,
                Module__c = 'Grants',
                Data_Type__c = 'Text',
                Sort_Order__c = 1
            )
        };
    }

    private static User buildDavid() {
        Profile standard = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        return new User(
            FirstName = 'David',
            LastName = 'Okonkwo',
            Alias = 'david',
            Email = 'david.openimpact@example.com',
            Username = 'david.openimpact.' + DateTime.now().getTime() + '@example.com',
            ProfileId = standard.Id,
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
    }

    @IsTest
    static void showsEverySectionWithItsSettings() {
        stubDefinitions();

        Test.startTest();
        SettingsController.ConsoleModel model = SettingsController.getConsoleModel();
        Test.stopTest();

        Assert.areEqual(
            3,
            model.sections.size(),
            'Sections with something to show appear; Giving is not installed'
        );
        Map<String, SettingsController.SectionModel> byName = new Map<String, SettingsController.SectionModel>();
        for (SettingsController.SectionModel section : model.sections) {
            byName.put(section.name, section);
        }
        Assert.isTrue(
            byName.containsKey(SettingSections.HOUSEHOLDS),
            'The household settings have their own section'
        );
        Assert.areEqual(
            2,
            byName.get(SettingSections.HOUSEHOLDS).settings.size(),
            'Both household settings are in it'
        );
        Assert.isTrue(
            byName.get(SettingSections.HOUSEHOLDS)
                .settings[0]
                .helpUrl.endsWith('household-naming.md'),
            'Learn more points at the admin guide page for that setting'
        );
        Assert.areEqual(
            2,
            byName.get(SettingSections.GENERAL).settings[0].options.size(),
            'A picklist setting arrives with its choices, labelled'
        );
        Assert.areEqual(
            'automationControl',
            byName.get(SettingSections.AUTOMATION).settings[0].component,
            'A section another feature renders arrives as a component to load'
        );
    }

    @IsTest
    static void findsSettingsByWordsMariaWouldUse() {
        stubDefinitions();

        Test.startTest();
        List<SettingsController.SearchHit> byDescription = SettingsController.search('greetings');
        List<SettingsController.SearchHit> bySection = SettingsController.search('households');
        List<SettingsController.SearchHit> nothing = SettingsController.search('   ');
        Test.stopTest();

        Assert.areEqual(
            1,
            byDescription.size(),
            'Searching the description finds the naming setting'
        );
        Assert.areEqual(
            SettingSections.HOUSEHOLDS,
            byDescription[0].section,
            'The result says which section to open'
        );
        Assert.areEqual(2, bySection.size(), 'Searching a section name finds everything in it');
        Assert.areEqual(0, nothing.size(), 'An empty search asks for nothing');
    }

    @IsTest
    static void aRowForAModulePermissionIsHiddenFromThoseWithoutIt() {
        stubDefinitions();
        SettingDefinitionSelector.stubbedRows.add(
            new Setting_Definition__mdt(
                DeveloperName = 'Module_Page',
                MasterLabel = 'Mirror page',
                Section__c = SettingSections.AUTOMATION,
                Module__c = 'Connect',
                Data_Type__c = 'Component',
                Component__c = 'modulePage',
                Required_Permission__c = 'Permission_Nobody_Holds',
                Sort_Order__c = 2
            )
        );
        SettingDefinitionSelector.stubbedRows.add(
            new Setting_Definition__mdt(
                DeveloperName = 'Held_Page',
                MasterLabel = 'Held page',
                Section__c = SettingSections.AUTOMATION,
                Module__c = 'Connect',
                Data_Type__c = 'Component',
                Component__c = 'heldPage',
                Required_Permission__c = EDIT_PERMISSION,
                Sort_Order__c = 3
            )
        );

        Test.startTest();
        SettingsController.ConsoleModel model = SettingsController.getConsoleModel();
        List<SettingsController.SearchHit> hits = SettingsController.search('mirror page');
        Test.stopTest();

        Set<String> shown = new Set<String>();
        for (SettingsController.SectionModel section : model.sections) {
            for (SettingsController.SettingModel setting : section.settings) {
                shown.add(setting.key);
            }
        }
        Assert.isFalse(shown.contains('Module_Page'), 'Not shown without the permission.');
        Assert.isTrue(shown.contains('Held_Page'), 'Shown to one who holds it, named unprefixed.');
        Assert.isTrue(hits.isEmpty(), 'Nor found by search.');
    }

    @IsTest
    static void savesWhatMariaChanged() {
        stubDefinitions();
        Assert.isTrue(
            FeatureManagement.checkPermission(EDIT_PERMISSION),
            'The permission set built in setup carries Manage Nonprofit Settings'
        );

        Test.startTest();
        SettingsController.ConsoleModel model = SettingsController.saveSettings(
            new Map<String, Object>{ TEXT_KEY => 'The {LastName} Family' }
        );
        Test.stopTest();

        Assert.isTrue(model.canEdit, 'The page comes back knowing Maria may keep editing');
        Assert.areEqual(
            'The {LastName} Family',
            SettingsService.getValue(TEXT_KEY),
            'The value Maria typed is the one in force'
        );
        Assert.areEqual(
            1,
            SettingsController.getRecentChanges(10).size(),
            'Her change is on the recent changes list'
        );
    }

    @IsTest
    static void letsAStandardUserWithThePermissionSave() {
        User maria = [SELECT Id FROM User WHERE LastName = 'Alvarez' AND IsActive = TRUE LIMIT 1];
        Boolean saved = false;

        Test.startTest();
        System.runAs(maria) {
            stubDefinitions();
            SettingsController.ConsoleModel model = SettingsController.saveSettings(
                new Map<String, Object>{ TEXT_KEY => 'The {LastName} Family' }
            );
            saved = model.canEdit;
        }
        Test.stopTest();

        Assert.isTrue(
            saved,
            'Maria is on the Standard User profile and holds only the permission, and she saves'
        );
    }

    @IsTest
    static void tellsDavidWhichPermissionHeNeeds() {
        stubDefinitions();
        User david = buildDavid();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert david;
        }
        Boolean refused = false;

        Test.startTest();
        System.runAs(david) {
            SettingsController.ConsoleModel model = SettingsController.getConsoleModel();
            Assert.isFalse(model.canEdit, 'David may read the settings but not change them');
            try {
                SettingsController.saveSettings(
                    new Map<String, Object>{ TEXT_KEY => 'The {LastName} Clan' }
                );
            } catch (AuraHandledException e) {
                refused = true;
            }
        }
        Test.stopTest();

        Assert.isTrue(refused, 'Saving without the permission is refused');
    }

    @IsTest
    static void savingNothingChangesNothing() {
        stubDefinitions();

        Test.startTest();
        SettingsController.ConsoleModel model = SettingsController.saveSettings(
            new Map<String, Object>()
        );
        Test.stopTest();

        Assert.isNotNull(model, 'An empty save still returns the page');
        Assert.areEqual(
            0,
            SettingsController.getRecentChanges(10).size(),
            'Nothing was changed, so nothing is recorded'
        );
    }

    @IsTest
    static void listsRecentChangesForThePageFooter() {
        insert new Setting_Change__c(
            Setting_Name__c = TEXT_KEY,
            Old_Value__c = 'The {LastName} Family',
            New_Value__c = 'The {LastName} Household',
            Changed_By__c = UserInfo.getUserId(),
            Changed_At__c = System.now()
        );

        Test.startTest();
        List<SettingsController.ChangeModel> changes = SettingsController.getRecentChanges(5);
        Test.stopTest();

        Assert.areEqual(1, changes.size(), 'The change is listed');
        Assert.areEqual(TEXT_KEY, changes[0].settingName, 'The row names the setting');
        Assert.isNotNull(changes[0].changedBy, 'The row names who changed it');
        Assert.isNotNull(changes[0].changedAt, 'The row says when');
    }
}
