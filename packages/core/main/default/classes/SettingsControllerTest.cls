/**
 * Maria opens the console and changes a setting. David opens the same page without the
 * Manage BarnCRM Settings permission and gets a read-only view that names the permission.
 */
@IsTest(critical=true)
private class SettingsControllerTest {
    private static final String TEXT_KEY = 'Household_Name_Pattern__c';
    private static final String CHECKBOX_KEY = 'Auto_Create_Households__c';
    private static final String EDIT_PERMISSION = 'Manage_BarnCRM_Settings';

    @TestSetup
    static void makeData() {
        System.runAs(TestUsers.admin()) {
            PermissionSet permissionSet = SettingsTestPermissions.build(
                'C03_Settings_Console_Test'
            );
            User maria = SettingsTestPermissions.buildStandardUser('Maria', 'Alvarez', 'mariac');
            insert maria;
            insert new List<PermissionSetAssignment>{
                new PermissionSetAssignment(
                    AssigneeId = UserInfo.getUserId(),
                    PermissionSetId = permissionSet.Id
                ),
                new PermissionSetAssignment(
                    AssigneeId = maria.Id,
                    PermissionSetId = permissionSet.Id
                )
            };
        }
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
                MasterLabel = 'How BarnCRM fits your org',
                Setting_Key__c = 'Coexistence_Mode__c',
                Section__c = SettingSections.GENERAL,
                Module__c = 'Core',
                Data_Type__c = 'Picklist',
                Picklist_Values__c = 'Standalone:On its own;NonprofitCloud:Alongside Nonprofit Cloud',
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
        return SettingsTestPermissions.buildStandardUser('David', 'Okonkwo', 'david');
    }

    @IsTest
    static void showsEverySectionWithItsSettings() {
        System.runAs(TestUsers.admin()) {
            stubDefinitions();
            // An org with the Nonprofit Cloud objects, so both stubbed coexistence choices apply.
            OrgShapeDetector.OrgShape shape = new OrgShapeDetector.OrgShape();
            shape.hasIndustriesNonprofit = true;
            OrgShapeDetector.overrideShape = shape;

            Test.startTest();
            SettingsController.ConsoleModel model = SettingsController.getConsoleModel();
            Test.stopTest();

            Assert.areEqual(
                3,
                model.sections.size(),
                'Sections with something to show appear; Giving is not installed'
            );
            // The rows arrive Households first; the console lists sections as
            // SettingSections.all() does, so it opens on General.
            Assert.areEqual(
                SettingSections.GENERAL,
                model.sections[0].name,
                'The console opens on General'
            );
            Assert.areEqual(SettingSections.HOUSEHOLDS, model.sections[1].name, 'Then Households');
            Assert.areEqual(SettingSections.AUTOMATION, model.sections[2].name, 'Then Automation');
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
    }

    @IsTest
    static void offersAProductsCoexistenceModeOnlyWhereThatProductIsDetected() {
        System.runAs(TestUsers.admin()) {
            stubDefinitions();
            OrgShapeDetector.overrideShape = new OrgShapeDetector.OrgShape();

            Test.startTest();
            List<SettingsController.Option> fresh = coexistenceOptions();
            SettingsService.saveValues(
                new Map<String, Object>{
                    'Coexistence_Mode__c' => CoexistenceService.MODE_NONPROFIT_CLOUD
                }
            );
            List<SettingsController.Option> saved = coexistenceOptions();
            Test.stopTest();

            Assert.areEqual(
                1,
                fresh.size(),
                'An org without Nonprofit Cloud is offered Standalone only'
            );
            Assert.areEqual(
                CoexistenceService.MODE_STANDALONE,
                fresh[0].value,
                'Standalone is always there'
            );
            Assert.areEqual(
                2,
                saved.size(),
                'A mode already saved stays visible, so the choice is never hidden from its maker'
            );
        }
    }

    private static List<SettingsController.Option> coexistenceOptions() {
        for (
            SettingsController.SectionModel section : SettingsController.getConsoleModel().sections
        ) {
            for (SettingsController.SettingModel setting : section.settings) {
                if (setting.key == 'Coexistence_Mode__c') {
                    return setting.options;
                }
            }
        }
        return new List<SettingsController.Option>();
    }

    @IsTest
    static void findsSettingsByWordsMariaWouldUse() {
        System.runAs(TestUsers.admin()) {
            stubDefinitions();

            Test.startTest();
            List<SettingsController.SearchHit> byDescription = SettingsController.search(
                'greetings'
            );
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
    }

    @IsTest
    static void searchNeverListsARowThePageHides() {
        System.runAs(TestUsers.admin()) {
            stubDefinitions();

            Test.startTest();
            List<SettingsController.SearchHit> hits = SettingsController.search('grant program');
            SettingsController.ConsoleModel model = SettingsController.getConsoleModel();
            Test.stopTest();

            for (SettingsController.SectionModel section : model.sections) {
                for (SettingsController.SettingModel setting : section.settings) {
                    Assert.areNotEqual(
                        'Default_Grant_Program__c',
                        setting.key,
                        'The page hides a row whose module is not installed'
                    );
                }
            }
            Assert.isTrue(hits.isEmpty(), 'So search does not offer it either: ' + hits);
        }
    }

    @IsTest
    static void aRowForAModulePermissionIsHiddenFromThoseWithoutIt() {
        System.runAs(TestUsers.admin()) {
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
            Assert.isTrue(
                shown.contains('Held_Page'),
                'Shown to one who holds it, named unprefixed.'
            );
            Assert.isTrue(hits.isEmpty(), 'Nor found by search.');
        }
    }

    @IsTest
    static void savesWhatMariaChanged() {
        System.runAs(TestUsers.admin()) {
            stubDefinitions();
            Assert.isTrue(
                FeatureManagement.checkPermission(EDIT_PERMISSION),
                'The permission set built in setup carries Manage BarnCRM Settings'
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
    }

    @IsTest
    static void letsAStandardUserWithThePermissionSave() {
        System.runAs(TestUsers.admin()) {
            User maria = [
                SELECT Id
                FROM User
                WHERE LastName = 'Alvarez' AND IsActive = TRUE
                LIMIT 1
            ];
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
    }

    @IsTest
    static void tellsDavidWhichPermissionHeNeeds() {
        System.runAs(TestUsers.admin()) {
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
    }

    @IsTest
    static void savingNothingChangesNothing() {
        System.runAs(TestUsers.admin()) {
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
    }

    @IsTest
    static void listsRecentChangesForThePageFooter() {
        System.runAs(TestUsers.admin()) {
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

    @IsTest
    static void recentChangesNameASettingByItsLabel() {
        System.runAs(TestUsers.admin()) {
            stubDefinitions();
            insert new List<Setting_Change__c>{
                new Setting_Change__c(
                    Setting_Name__c = SettingsService.CORE_SETTINGS_OBJECT + '.' + TEXT_KEY,
                    Changed_By__c = UserInfo.getUserId(),
                    Changed_At__c = System.now()
                ),
                new Setting_Change__c(
                    Setting_Name__c = 'Health Check: Create the missing rollups',
                    Changed_By__c = UserInfo.getUserId(),
                    Changed_At__c = System.now().addMinutes(-1)
                )
            };

            Test.startTest();
            List<SettingsController.ChangeModel> changes = SettingsController.getRecentChanges(5);
            Test.stopTest();

            Set<String> names = new Set<String>();
            for (SettingsController.ChangeModel change : changes) {
                names.add(change.settingName);
            }
            Assert.isTrue(
                names.contains('Household name pattern'),
                'A setting reads as its label, not its API name: ' + names
            );
            Assert.isTrue(
                names.contains('Health Check: Create the missing rollups'),
                'A row that is not a setting reads as it was stored: ' + names
            );
        }
    }

    @IsTest
    static void aRecordRowNamesItsObjectAndARecordTypeRowListsItsChoices() {
        System.runAs(TestUsers.admin()) {
            SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>{
                new Setting_Definition__mdt(
                    DeveloperName = 'Picked_Account',
                    MasterLabel = 'Picked account',
                    Setting_Key__c = 'Organization_Legal_Name__c',
                    Section__c = SettingSections.GENERAL,
                    Module__c = 'Core',
                    Data_Type__c = SettingsService.RECORD,
                    Record_Object__c = 'Account',
                    Sort_Order__c = 1
                ),
                new Setting_Definition__mdt(
                    DeveloperName = 'Picked_Record_Types',
                    MasterLabel = 'Picked record types',
                    Setting_Key__c = 'Formal_Greeting_Pattern__c',
                    Section__c = SettingSections.GENERAL,
                    Module__c = 'Core',
                    Data_Type__c = SettingsService.RECORD_TYPE_LIST,
                    Record_Object__c = 'Account',
                    Sort_Order__c = 2
                ),
                new Setting_Definition__mdt(
                    DeveloperName = 'Picked_From_Nowhere',
                    MasterLabel = 'Picked from an object this org lacks',
                    Setting_Key__c = 'Informal_Greeting_Pattern__c',
                    Section__c = SettingSections.GENERAL,
                    Module__c = 'Core',
                    Data_Type__c = SettingsService.RECORD,
                    Record_Object__c = 'Not_An_Object_Here__c',
                    Sort_Order__c = 3
                )
            };

            Test.startTest();
            SettingsController.ConsoleModel model = SettingsController.getConsoleModel();
            Test.stopTest();

            List<SettingsController.SettingModel> rows = model.sections[0].settings;
            Assert.areEqual(2, rows.size(), 'A row about an object this org lacks is left out');
            Assert.areEqual('Account', rows[0].objectApiName, 'The picker is told its object');
            Assert.areEqual(
                SettingsService.recordTypes(Account.SObjectType).size(),
                rows[1].options.size(),
                'Every active record type is offered'
            );
            Assert.isNotNull(rows[1].options[0].label, 'Each choice carries the label Setup shows');
            Assert.isNotNull(rows[1].options[0].value, 'Each choice stores its developer name');
        }
    }

    @IsTest
    static void setupChecksSayWhetherEachPrerequisiteIsMet() {
        System.runAs(TestUsers.admin()) {
            Integer barnMonth = FiscalYearSelector.settingsFiscalYearStartMonth();
            FiscalYearSelector.orgStartMonthOverridden = true;
            FiscalYearSelector.orgStartMonthOverride = barnMonth;
            SettingsController.emailAllowedOverride = true;
            Map<String, Boolean> met = SettingsController.getSetupChecks();

            FiscalYearSelector.orgStartMonthOverride = Math.mod(barnMonth, 12) + 1;
            SettingsController.emailAllowedOverride = false;
            Map<String, Boolean> unmet = SettingsController.getSetupChecks();

            Assert.isTrue(met.get(SettingsController.CHECK_FISCAL_YEAR), 'Same month is done');
            Assert.isTrue(met.get(SettingsController.CHECK_EMAIL), 'Email allowed is done');
            Assert.isFalse(unmet.get(SettingsController.CHECK_FISCAL_YEAR), 'Months differ');
            Assert.isFalse(unmet.get(SettingsController.CHECK_EMAIL), 'Email blocked');
        }
    }

    @IsTest
    static void aSetupCheckThatCannotBeReadIsLeftOut() {
        System.runAs(TestUsers.admin()) {
            FiscalYearSelector.orgStartMonthOverridden = true;
            FiscalYearSelector.orgStartMonthOverride = null;
            SettingsController.emailAllowedOverride = true;
            Map<String, Boolean> checks = SettingsController.getSetupChecks();

            Assert.isFalse(
                checks.containsKey(SettingsController.CHECK_FISCAL_YEAR),
                'An unreadable fiscal year is no answer, so the note shows its instruction only'
            );
            Assert.isTrue(
                checks.containsKey(SettingsController.CHECK_EMAIL),
                'The other check still answers'
            );

            SettingsController.emailAllowedOverride = null;
            Assert.isNotNull(
                SettingsController.getSetupChecks(),
                'Asking this org itself whether it may send email never fails the page'
            );
        }
    }
}
