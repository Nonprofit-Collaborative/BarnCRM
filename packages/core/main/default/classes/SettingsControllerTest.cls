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
                Section__c = SettingSections.PEOPLE_AND_HOUSEHOLDS,
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
                // Still names the old Households page, as a row not yet moved would (P1).
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

    @IsTest
    static void settingsLinkNamesTheTabAndSectionKeyThisOrgNeeds() {
        System.runAs(TestUsers.admin()) {
            SettingsController.SettingsLink link = SettingsController.getSettingsLink();

            Assert.areEqual(
                NamespaceUtil.qualify('BarnCRM_Settings'),
                link.tabApiName,
                'A page reference names the settings tab with this org\'s prefix'
            );
            Assert.areEqual(
                NamespaceUtil.stateKey('section'),
                link.sectionKey,
                'The section state key follows the namespace, as the console reads it'
            );
            Assert.isTrue(link.sectionKey.endsWith('__section'), 'The console matches the suffix');
        }
    }

    @IsTest
    static void hidesTheRowsOfAFeatureThatIsOff() {
        System.runAs(TestUsers.admin()) {
            stubDefinitions();
            TestSettings.newInstall();

            Test.startTest();
            SettingsController.ConsoleModel model = SettingsController.getConsoleModel();
            Test.stopTest();

            Set<String> keys = new Set<String>();
            for (SettingsController.SectionModel section : model.sections) {
                for (SettingsController.SettingModel setting : section.settings) {
                    keys.add(setting.key);
                }
            }
            Assert.isFalse(
                keys.contains(CHECKBOX_KEY),
                'Household upkeep is off on a new install, so its row is hidden'
            );
            Assert.isFalse(
                keys.contains(TEXT_KEY),
                'The naming pattern rows belong to Household upkeep, so they are hidden too'
            );
            Assert.isTrue(keys.contains('Coexistence_Mode__c'), 'A row of no feature still shows');
        }
    }

    /** The shipped Org Optimizer thresholds sit in their own section, not under General. */
    @IsTest
    static void orgOptimizerSectionIsHiddenWhileTheFeatureIsOff() {
        System.runAs(TestUsers.admin()) {
            TestSettings.newInstall();

            Test.startTest();
            Map<String, Set<String>> shown = keysBySection(SettingsController.getConsoleModel());
            Test.stopTest();

            Assert.isFalse(
                shown.containsKey(SettingSections.ORG_OPTIMIZER),
                'The section is hidden while the Org Optimizer feature is off'
            );
            Assert.isFalse(
                shown.get(SettingSections.GENERAL).contains('Unused_Login_Days__c'),
                'The thresholds do not fall back to General'
            );
        }
    }

    @IsTest
    static void orgOptimizerThresholdsHaveTheirOwnSectionWhileTheFeatureIsOn() {
        System.runAs(TestUsers.admin()) {
            TestSettings.newInstall();
            FeatureSwitchService.turnOn(FeatureSwitchService.ORG_OPTIMIZER);

            Test.startTest();
            Map<String, Set<String>> after = keysBySection(SettingsController.getConsoleModel());
            Test.stopTest();

            Assert.areEqual(
                new Set<String>{
                    'Stale_Record_Years__c',
                    'Unused_Login_Days__c',
                    'Unused_Report_Days__c'
                },
                after.get(SettingSections.ORG_OPTIMIZER),
                'The three thresholds are under Org Optimizer once the feature is on'
            );
            Assert.isFalse(
                after.get(SettingSections.GENERAL).contains('Unused_Login_Days__c'),
                'The thresholds no longer show under General'
            );
        }
    }

    private static Map<String, Set<String>> keysBySection(SettingsController.ConsoleModel model) {
        Map<String, Set<String>> keys = new Map<String, Set<String>>();
        for (SettingsController.SectionModel section : model.sections) {
            Set<String> inSection = new Set<String>();
            for (SettingsController.SettingModel setting : section.settings) {
                inSection.add(setting.key);
            }
            keys.put(section.name, inSection);
        }
        return keys;
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
            Assert.areEqual(
                SettingSections.PEOPLE_AND_HOUSEHOLDS,
                model.sections[1].name,
                'Then People and Households'
            );
            Assert.areEqual(SettingSections.AUTOMATION, model.sections[2].name, 'Then Automation');
            Map<String, SettingsController.SectionModel> byName = new Map<String, SettingsController.SectionModel>();
            for (SettingsController.SectionModel section : model.sections) {
                byName.put(section.name, section);
            }
            Assert.isFalse(
                byName.containsKey(SettingSections.HOUSEHOLDS),
                'A row still naming the old Households page makes no page of its own'
            );
            Assert.areEqual(
                2,
                byName.get(SettingSections.PEOPLE_AND_HOUSEHOLDS).settings.size(),
                'Both household settings are on People and Households'
            );
            Assert.areEqual(
                SettingSections.PEOPLE_AND_HOUSEHOLDS,
                byName.get(SettingSections.PEOPLE_AND_HOUSEHOLDS).settings[1].section,
                'The row that names the old page says the page it is on'
            );
            Assert.isTrue(
                byName.get(SettingSections.PEOPLE_AND_HOUSEHOLDS)
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

    /** The button for a row that opens another page names that page, so the row carries its name. */
    @IsTest
    static void aRowThatOpensAnotherPageCarriesThePageName() {
        System.runAs(TestUsers.admin()) {
            SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>{
                new Setting_Definition__mdt(
                    DeveloperName = 'Opens_Another_Page',
                    MasterLabel = 'Another page',
                    Section__c = SettingSections.HOUSEHOLDS,
                    Module__c = 'Core',
                    Data_Type__c = 'Component',
                    Navigation_Target__c = 'Data_Hygiene',
                    Navigation_Label__c = 'Org Optimizer',
                    Sort_Order__c = 1
                )
            };

            SettingsController.ConsoleModel model = SettingsController.getConsoleModel();

            SettingsController.SettingModel row;
            for (SettingsController.SectionModel section : model.sections) {
                for (SettingsController.SettingModel setting : section.settings) {
                    row = setting;
                }
            }
            Assert.isNotNull(row, 'The row arrives');
            Assert.areEqual('Data_Hygiene', row.navigationTarget, 'It names the tab it opens');
            Assert.areEqual('Org Optimizer', row.navigationLabel, 'And the name of that page');
        }
    }

    /** A module's own settings page shows only its rows, so each row says whose it is. */
    @IsTest
    static void eachRowNamesTheModuleItBelongsTo() {
        System.runAs(TestUsers.admin()) {
            stubDefinitions();
            SettingDefinitionSelector.stubbedRows[1].Module__c = null;

            SettingsController.ConsoleModel model = SettingsController.getConsoleModel();

            Map<String, String> moduleByKey = new Map<String, String>();
            for (SettingsController.SectionModel section : model.sections) {
                for (SettingsController.SettingModel setting : section.settings) {
                    moduleByKey.put(setting.key, setting.module);
                }
            }
            Assert.areEqual('Core', moduleByKey.get(TEXT_KEY), 'A row naming Core is Core');
            Assert.areEqual(
                'Core',
                moduleByKey.get(CHECKBOX_KEY),
                'A row naming no module is Core'
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
                SettingSections.PEOPLE_AND_HOUSEHOLDS,
                byDescription[0].section,
                'The result says which section to open'
            );
            Assert.areEqual(2, bySection.size(), 'Searching a section name finds everything in it');
            Assert.areEqual(
                2,
                SettingsController.search('people and').size(),
                'Searching the page name finds a row that still names the old Households page'
            );
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
                    Module__c = 'Mirror',
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
                    Module__c = 'Mirror',
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

    private static void stubMembershipRows() {
        SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>{
            new Setting_Definition__mdt(
                DeveloperName = 'Household_Membership_Mode',
                MasterLabel = 'How people belong to a household',
                Setting_Key__c = CoexistenceService.KEY_MEMBERSHIP_MODE,
                Section__c = SettingSections.HOUSEHOLDS,
                Module__c = 'Core',
                Data_Type__c = 'Picklist',
                Picklist_Values__c = 'Contact:One household per person (simple);Junction:A person can belong to more than one household (flexible)',
                Sort_Order__c = 1
            ),
            new Setting_Definition__mdt(
                DeveloperName = 'Household_Name_Pattern',
                MasterLabel = 'Household name pattern',
                Setting_Key__c = TEXT_KEY,
                Section__c = SettingSections.HOUSEHOLDS,
                Module__c = 'Core',
                Data_Type__c = 'Text',
                Sort_Order__c = 2
            ),
            // Detection saves the coexistence mode with the membership mode, and a save needs
            // a row for every key it writes.
            new Setting_Definition__mdt(
                DeveloperName = 'Coexistence_Mode_Choice',
                MasterLabel = 'How BarnCRM fits your org',
                Setting_Key__c = CoexistenceService.KEY_COEXISTENCE_MODE,
                Section__c = SettingSections.GENERAL,
                Module__c = 'Core',
                Data_Type__c = 'Picklist',
                Picklist_Values__c = 'Standalone:On its own;NPSP:Alongside NPSP;NonprofitCloud:Alongside Nonprofit Cloud',
                Sort_Order__c = 1
            )
        };
    }

    private static String membershipValueShown() {
        for (
            SettingsController.SectionModel section : SettingsController.getConsoleModel().sections
        ) {
            for (SettingsController.SettingModel setting : section.settings) {
                if (setting.key == CoexistenceService.KEY_MEMBERSHIP_MODE) {
                    return setting.value;
                }
            }
        }
        return 'not shown';
    }

    @IsTest
    static void aHouseholdChoiceNobodyHasMadeShowsOneHouseholdPerPersonSelected() {
        System.runAs(TestUsers.admin()) {
            stubMembershipRows();
            OrgShapeDetector.overrideShape = new OrgShapeDetector.OrgShape();

            Test.startTest();
            String shown = membershipValueShown();
            Test.stopTest();

            Assert.areEqual(
                CoexistenceService.MEMBERSHIP_CONTACT,
                shown,
                'A blank choice is shown as the simple way, never as an empty picklist'
            );
            Assert.isFalse(
                CoexistenceService.membershipModeChosen(),
                'Showing the default does not save it: blank still means not chosen yet'
            );
        }
    }

    @IsTest
    static void savingAnUnrelatedSettingLeavesTheHouseholdChoiceOpenForDetection() {
        System.runAs(TestUsers.admin()) {
            stubMembershipRows();
            OrgShapeDetector.OrgShape shape = new OrgShapeDetector.OrgShape();
            shape.hasPersonAccounts = true;
            OrgShapeDetector.overrideShape = shape;

            Test.startTest();
            SettingsController.saveSettings(new Map<String, Object>{ TEXT_KEY => '{LastName}' });
            Test.stopTest();

            Assert.isFalse(
                CoexistenceService.membershipModeChosen(),
                'An unrelated save must not write the household choice'
            );
            CoexistenceService.applyRecommendedIfUnset();
            Assert.areEqual(
                CoexistenceService.MEMBERSHIP_JUNCTION,
                CoexistenceService.getMembershipMode(),
                'Detection still proposes the flexible way for an org with Person Accounts'
            );
            Assert.areEqual(
                CoexistenceService.MEMBERSHIP_JUNCTION,
                membershipValueShown(),
                'And the console then shows the flexible way'
            );
        }
    }

    @IsTest
    static void aSavedHouseholdChoiceIsShownAsSaved() {
        System.runAs(TestUsers.admin()) {
            stubMembershipRows();
            OrgShapeDetector.overrideShape = new OrgShapeDetector.OrgShape();
            SettingsService.saveValues(
                new Map<String, Object>{
                    CoexistenceService.KEY_MEMBERSHIP_MODE => CoexistenceService.MEMBERSHIP_JUNCTION
                }
            );

            Assert.areEqual(
                CoexistenceService.MEMBERSHIP_JUNCTION,
                membershipValueShown(),
                'A choice somebody made is never replaced by the default'
            );
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

    private static final List<String> ADDRESS_KEYS = new List<String>{
        'Organization_Street__c',
        'Organization_Street_2__c',
        'Organization_City__c',
        'Organization_State__c',
        'Organization_Postal_Code__c',
        'Organization_Country__c'
    };

    private static void stubAddressDefinitions() {
        List<Setting_Definition__mdt> rows = new List<Setting_Definition__mdt>();
        for (String key : ADDRESS_KEYS) {
            rows.add(
                new Setting_Definition__mdt(
                    DeveloperName = key.removeEnd('__c'),
                    MasterLabel = key,
                    Setting_Key__c = key,
                    Section__c = SettingSections.ORGANIZATION,
                    Module__c = 'Core',
                    Data_Type__c = 'Text'
                )
            );
        }
        SettingDefinitionSelector.stubbedRows = rows;
    }

    @IsTest
    static void savesTheOrganizationAddressAndReadsItBackByPart() {
        System.runAs(TestUsers.admin()) {
            stubAddressDefinitions();

            Test.startTest();
            SettingsController.saveSettings(
                new Map<String, Object>{
                    'Organization_Street__c' => '14 Bridge Street',
                    'Organization_City__c' => 'Springfield',
                    'Organization_State__c' => 'IL',
                    'Organization_Postal_Code__c' => '62701'
                }
            );
            Map<String, String> parts = SettingsController.getOrganizationAddress();
            Test.stopTest();

            Assert.areEqual('Springfield', parts.get('Organization_City__c'), 'The city she typed');
            Assert.areEqual('', parts.get('Organization_Country__c'), 'Country stayed optional');
            Assert.areEqual(6, parts.size(), 'Every part is answered, saved or not');
        }
    }

    @IsTest
    static void refusesAHalfFilledAddressWithAFriendlyMessageAndSavesNothing() {
        System.runAs(TestUsers.admin()) {
            stubAddressDefinitions();
            String message;

            Test.startTest();
            try {
                SettingsController.saveSettings(
                    new Map<String, Object>{
                        'Organization_Street__c' => '14 Bridge Street',
                        'Organization_City__c' => 'Springfield'
                    }
                );
            } catch (AuraHandledException e) {
                message = e.getMessage();
            }
            Test.stopTest();

            Assert.isNotNull(message, 'A street and city alone are not an address');
            Assert.isTrue(
                message.contains(System.Label.Core_OrganizationAddress_PostalCode),
                'The message names the missing Zip Code'
            );
            Assert.areEqual(
                '',
                SettingsController.getOrganizationAddress().get('Organization_Street__c'),
                'Nothing was saved'
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
    static void recentChangesHideRowsWhoseShownValuesMatch() {
        System.runAs(TestUsers.admin()) {
            String featuresName = SettingsService.CORE_SETTINGS_OBJECT + '.Features_Turned_On__c';
            insert new List<Setting_Change__c>{
                // "None" and "NoneChosen" both show as "No features": not a visible change.
                new Setting_Change__c(
                    Setting_Name__c = featuresName,
                    Old_Value__c = FeatureSwitchService.NONE_CHOSEN,
                    New_Value__c = FeatureSwitchService.NONE_ON,
                    Changed_By__c = UserInfo.getUserId(),
                    Changed_At__c = System.now()
                ),
                // A real change stays.
                new Setting_Change__c(
                    Setting_Name__c = SettingsService.CORE_SETTINGS_OBJECT + '.' + TEXT_KEY,
                    Old_Value__c = 'The {LastName} Family',
                    New_Value__c = 'The {LastName} Household',
                    Changed_By__c = UserInfo.getUserId(),
                    Changed_At__c = System.now().addMinutes(-1)
                )
            };

            Test.startTest();
            List<SettingsController.ChangeModel> changes = SettingsController.getRecentChanges(5);
            Test.stopTest();

            Assert.areEqual(1, changes.size(), 'Only the row that reads differently is listed');
            Assert.areNotEqual(
                System.Label.Core_Settings_FeaturesTurnedOn,
                changes[0].settingName,
                'The row with matching shown values is the one hidden'
            );
        }
    }

    @IsTest
    static void recentChangesShowARecordSettingByTheRecordsName() {
        System.runAs(TestUsers.admin()) {
            SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>{
                new Setting_Definition__mdt(
                    DeveloperName = 'Preferred_Account',
                    MasterLabel = 'Preferred account',
                    Setting_Key__c = 'Preferred_Account__c',
                    Section__c = SettingSections.GENERAL,
                    Module__c = 'Core',
                    Data_Type__c = SettingsService.RECORD,
                    Record_Object__c = 'Account',
                    Sort_Order__c = 1
                )
            };
            Account account = new Account(Name = 'Riverside Test Trust');
            insert account;
            // A well formed Account Id that no record has (the local `account` shadows the Account type).
            String gone = String.valueOf(account.Id).left(3) + '000000000001';
            String stored = SettingsService.CORE_SETTINGS_OBJECT + '.Preferred_Account__c';
            insert new List<Setting_Change__c>{
                new Setting_Change__c(
                    Setting_Name__c = stored,
                    Old_Value__c = gone,
                    New_Value__c = String.valueOf(account.Id),
                    Changed_By__c = UserInfo.getUserId(),
                    Changed_At__c = System.now()
                )
            };

            Test.startTest();
            List<SettingsController.ChangeModel> changes = SettingsController.getRecentChanges(5);
            Test.stopTest();

            Assert.areEqual(1, changes.size(), 'The change is listed');
            Assert.areEqual(
                'Riverside Test Trust',
                changes[0].newValue,
                'The record reads by name'
            );
            Assert.areEqual(
                System.Label.Core_Settings_RecordUnavailable,
                changes[0].oldValue,
                'A record that is gone or unreadable reads as a plain fallback, never an Id'
            );
        }
    }

    @IsTest
    static void recentChangesShowARecordTypeByItsLabel() {
        System.runAs(TestUsers.admin()) {
            SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>{
                new Setting_Definition__mdt(
                    DeveloperName = 'Picked_Type',
                    MasterLabel = 'Picked type',
                    Setting_Key__c = 'Picked_Type__c',
                    Section__c = SettingSections.GENERAL,
                    Module__c = 'Core',
                    Data_Type__c = SettingsService.RECORD_TYPE,
                    Record_Object__c = 'Account',
                    Sort_Order__c = 1
                )
            };
            insert new Setting_Change__c(
                Setting_Name__c = SettingsService.CORE_SETTINGS_OBJECT + '.Picked_Type__c',
                Old_Value__c = AccountKinds.NO_RECORD_TYPE,
                New_Value__c = 'Not_A_Real_Type',
                Changed_By__c = UserInfo.getUserId(),
                Changed_At__c = System.now()
            );

            Test.startTest();
            List<SettingsController.ChangeModel> changes = SettingsController.getRecentChanges(5);
            Test.stopTest();

            Assert.areEqual(
                System.Label.Core_Settings_NoRecordType,
                changes[0].oldValue,
                'No record type reads as its label'
            );
            Assert.areEqual(
                'Not_A_Real_Type',
                changes[0].newValue,
                'A value no record type names reads as stored'
            );
        }
    }

    @IsTest
    static void recentChangesShowAChoiceByItsLabel() {
        System.runAs(TestUsers.admin()) {
            stubDefinitions();
            Datetime now = System.now();
            insert new List<Setting_Change__c>{
                new Setting_Change__c(
                    Setting_Name__c = SettingsService.CORE_SETTINGS_OBJECT + '.Suite__c',
                    // Logged before ADR-0143, under the old code for the Standard Edition
                    Old_Value__c = 'Community',
                    New_Value__c = ModuleDetectionService.SUITE_NONPROFIT,
                    Changed_By__c = UserInfo.getUserId(),
                    Changed_At__c = now
                ),
                new Setting_Change__c(
                    Setting_Name__c = SettingsService.CORE_SETTINGS_OBJECT + '.Coexistence_Mode__c',
                    Old_Value__c = 'Standalone',
                    New_Value__c = 'Retired',
                    Changed_By__c = UserInfo.getUserId(),
                    Changed_At__c = now.addMinutes(-1)
                )
            };

            Test.startTest();
            List<SettingsController.ChangeModel> changes = SettingsController.getRecentChanges(5);
            Test.stopTest();

            Assert.areEqual(2, changes.size(), 'Both changes are listed');
            Assert.areEqual(
                System.Label.Core_SuiteChoice_StandardName,
                changes[0].oldValue,
                'The old edition reads as the edition picker names it'
            );
            Assert.areEqual(
                System.Label.Core_SuiteChoice_NonprofitName,
                changes[0].newValue,
                'The new edition reads as the edition picker names it'
            );
            Assert.areEqual('On its own', changes[1].oldValue, 'A choice reads as its label');
            Assert.areEqual(
                'Retired',
                changes[1].newValue,
                'A value no choice names reads as stored'
            );
        }
    }

    @IsTest
    static void theFeaturesRowReadsAsFeatureNamesNotStoredKeys() {
        System.runAs(TestUsers.admin()) {
            stubDefinitions();
            Datetime now = System.now();
            String stored = SettingsService.CORE_SETTINGS_OBJECT + '.Features_Turned_On__c';
            insert new List<Setting_Change__c>{
                new Setting_Change__c(
                    Setting_Name__c = stored,
                    Old_Value__c = FeatureSwitchService.NONE_ON,
                    New_Value__c = 'DataManager,HouseholdUpkeep',
                    Changed_By__c = UserInfo.getUserId(),
                    Changed_At__c = now
                )
            };

            Test.startTest();
            List<SettingsController.ChangeModel> changes = SettingsController.getRecentChanges(5);
            Test.stopTest();

            Assert.areEqual(1, changes.size(), 'The change is listed');
            Assert.areEqual(
                System.Label.Core_Settings_FeaturesTurnedOn,
                changes[0].settingName,
                'The row reads as a label, not the stored name'
            );
            Assert.areEqual(
                System.Label.Core_Settings_NoFeaturesOn,
                changes[0].oldValue,
                'None reads as No features'
            );
            Assert.areEqual(
                System.Label.Core_Feature_DataManager_Name +
                    ', ' +
                    System.Label.Core_Feature_HouseholdUpkeep_Name,
                changes[0].newValue,
                'Each key reads as its feature name'
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
    static void theOrganizationRecordTypeRowIsOneChoiceNeverBlank() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            SettingsController.ConsoleModel model = SettingsController.getConsoleModel();
            Test.stopTest();

            SettingsController.SettingModel row = rowWithKey(
                model,
                SettingSections.GENERAL,
                AccountKinds.KEY_ORGANIZATION_RECORD_TYPE
            );
            Assert.isNotNull(row, 'General always shows the record type for organizations');
            Assert.areEqual(SettingsService.RECORD_TYPE, row.dataType, 'One record type');
            Integer candidates = AccountKinds.candidateRecordTypes().size();
            SettingsController.Option last = row.options[row.options.size() - 1];
            if (candidates == 0) {
                Assert.areEqual(1, row.options.size(), 'No candidate: only No record type');
                Assert.areEqual(AccountKinds.NO_RECORD_TYPE, last.value, 'Stored as Master');
                Assert.areEqual(
                    System.Label.Core_Settings_NoRecordType,
                    last.label,
                    'Shown by name'
                );
            } else {
                Assert.areEqual(
                    candidates,
                    row.options.size(),
                    'The candidates only: No record type would not work here'
                );
                Assert.areNotEqual(AccountKinds.NO_RECORD_TYPE, last.value, 'Never offered');
            }
            Assert.areEqual(
                AccountKinds.detectOrganizationRecordType(),
                row.value,
                'Nothing stored: the detected record type is shown, never a blank'
            );
            Assert.isTrue(row.unsavedDefault, 'Shown, not saved, until somebody keeps it');
            for (SettingsController.Option option : row.options) {
                Assert.isFalse(
                    option.label.toLowerCase().contains('household'),
                    'A household record type is never offered'
                );
            }
        }
    }

    @IsTest
    static void aFieldListRowOffersTheObjectsCustomFieldsAndName() {
        System.runAs(TestUsers.admin()) {
            SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>{
                new Setting_Definition__mdt(
                    DeveloperName = 'Address_Card_Fields',
                    MasterLabel = 'Address Card Fields',
                    Setting_Key__c = 'Address_Card_Fields__c',
                    Section__c = 'Addresses',
                    Module__c = 'Core',
                    Data_Type__c = SettingsService.FIELD_LIST,
                    Record_Object__c = 'Address__c',
                    Sort_Order__c = 1
                )
            };

            Test.startTest();
            SettingsController.ConsoleModel model = SettingsController.getConsoleModel();
            Test.stopTest();

            SettingsController.SettingModel row = model.sections[0].settings[0];
            Set<String> offered = new Set<String>();
            for (SettingsController.Option option : row.options) {
                offered.add(option.value);
            }
            String verification = Address__c.Verification_Status__c.getDescribe().getName();
            Assert.isTrue(offered.contains(verification), 'A custom field is offered: ' + offered);
            Assert.isTrue(offered.contains('Name'), 'The address number is offered');
            Assert.isFalse(offered.contains('CreatedById'), 'A system field is not');
            Assert.isTrue(String.isBlank(row.value), 'Nothing is ticked until an admin ticks it');
            // RM1 with AH1: none ticked is not a shown default, so there is nothing to keep.
            Assert.isFalse(row.unsavedDefault, 'No Keep this setting for a list with none ticked');
            Assert.isFalse(row.detectionMayChange, 'Detection never writes this row');
        }
    }

    @IsTest
    static void setupChecksSayWhetherEachPrerequisiteIsMet() {
        System.runAs(TestUsers.admin()) {
            SettingsController.emailAllowedOverride = true;
            Map<String, Boolean> met = SettingsController.getSetupChecks();

            SettingsController.emailAllowedOverride = false;
            Map<String, Boolean> unmet = SettingsController.getSetupChecks();

            Assert.isTrue(met.get(SettingsController.CHECK_EMAIL), 'Email allowed is done');
            Assert.isFalse(unmet.get(SettingsController.CHECK_EMAIL), 'Email blocked');
            Assert.isFalse(
                met.containsKey('fiscalYear'),
                'BarnCRM keeps no fiscal year of its own (ADR-0135), so there is nothing to ' +
                'compare with Setup and no fiscal year check'
            );
        }
    }

    @IsTest
    static void theConsoleShowsSetupValuesReadOnlyWhereTheyBelong() {
        System.runAs(TestUsers.admin()) {
            FiscalYearSelector.setTestStartMonth(7);
            SetupValueSelector.organizationNameOverride = 'Barn Rescue';

            SettingsController.ConsoleModel model = SettingsController.getConsoleModel();

            SettingsController.SettingModel fiscal = rowWithKey(
                model,
                'General',
                'FiscalYearStartMonth'
            );
            Assert.isNotNull(fiscal, 'General shows the fiscal year start from Setup');
            Assert.areEqual('SetupValue', fiscal.dataType, 'Shown read only, never edited here');
            Assert.areEqual(FiscalYearSelector.monthName(7), fiscal.value, 'The org month by name');
            Assert.areEqual('Organization', fiscal.settingsObject, 'It names Setup, not a setting');

            List<SettingsController.SettingModel> organization = rowsOf(model, 'Organization');
            Assert.areEqual('Name', organization[0].key, 'Organization name heads its section');
            Assert.areEqual('SetupValue', organization[0].dataType, 'Read only, from Setup');
            Assert.areEqual('Barn Rescue', organization[0].value, 'The name Setup holds');
            Assert.areEqual(
                'Organization_Legal_Name__c',
                organization[1].key,
                'The legal name sits directly below it'
            );
        }
    }

    @IsTest
    static void aSetupValueRowNamingAnUnknownValueIsLeftOut() {
        System.runAs(TestUsers.admin()) {
            SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>{
                new Setting_Definition__mdt(
                    DeveloperName = 'Unknown_Setup_Value',
                    MasterLabel = 'Unknown',
                    Setting_Key__c = 'Phone',
                    Settings_Object__c = 'Organization',
                    Section__c = 'General',
                    Module__c = 'Core',
                    Data_Type__c = 'SetupValue',
                    Sort_Order__c = 1
                )
            };

            SettingsController.ConsoleModel model = SettingsController.getConsoleModel();

            Assert.isNull(
                rowWithKey(model, 'General', 'Phone'),
                'Only the values SetupValueSelector lists can be shown, so a row cannot be ' +
                'pointed at an arbitrary field'
            );
        }
    }

    @IsTest
    static void aBlankAddressUpdatesSettingShowsTheShippedChoice() {
        System.runAs(TestUsers.admin()) {
            // A row name of its own, so the Addresses feature switch does not hide it.
            SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>{
                new Setting_Definition__mdt(
                    DeveloperName = 'Address_Updates_Row',
                    MasterLabel = 'Address Updates',
                    Setting_Key__c = 'Contact_Address_Change_Behavior__c',
                    Section__c = SettingSections.ADDRESSES,
                    Module__c = 'Core',
                    Data_Type__c = 'Picklist',
                    Picklist_Values__c = 'Update household:Everyone in the household moves together;Create personal address:Only that person moves;Manual:Nobody moves until you choose',
                    Sort_Order__c = 1
                )
            };
            // Saved once, then emptied by an update, which never applies a field default.
            BarnCRM_Settings__c settings = BarnCRM_Settings__c.getOrgDefaults();
            settings.Contact_Address_Change_Behavior__c = 'Manual';
            upsert settings;
            settings.Contact_Address_Change_Behavior__c = null;
            upsert settings;

            Test.startTest();
            String shown;
            for (
                SettingsController.SectionModel section : SettingsController.getConsoleModel()
                    .sections
            ) {
                for (SettingsController.SettingModel setting : section.settings) {
                    if (setting.key == 'Contact_Address_Change_Behavior__c') {
                        shown = setting.value;
                    }
                }
            }
            Test.stopTest();

            Assert.areEqual(
                'Update household',
                shown,
                'A blank Address Updates reads as everyone moving together, so it shows that choice, never an empty box'
            );
        }
    }

    private static List<SettingsController.SettingModel> rowsOf(
        SettingsController.ConsoleModel model,
        String sectionName
    ) {
        for (SettingsController.SectionModel section : model.sections) {
            if (section.name == sectionName) {
                return section.settings;
            }
        }
        return new List<SettingsController.SettingModel>();
    }

    private static SettingsController.SettingModel rowWithKey(
        SettingsController.ConsoleModel model,
        String sectionName,
        String key
    ) {
        for (SettingsController.SettingModel setting : rowsOf(model, sectionName)) {
            if (setting.key == key) {
                return setting;
            }
        }
        return null;
    }

    // Owner QA 2026-10-31: the Custom Metadata note stayed after the Apex setting was turned on.
    @IsTest
    static void theMetadataCheckNeedsThePermissionAndConfirmsTheSettingByAWorkingSave() {
        Map<String, Boolean> withoutPermission;
        System.runAs(TestUsers.admin()) {
            withoutPermission = SettingsController.getSetupChecks();
        }
        User metadataAdmin = TestUsers.withPermissionSets(
            new List<String>{ TestUsers.CORE_ADMIN, 'BarnCRM_Metadata_Admin' }
        );
        Map<String, Boolean> beforeAnySave;
        Map<String, Boolean> afterASave;
        System.runAs(metadataAdmin) {
            beforeAnySave = SettingsController.getSetupChecks();
            // What CustomMetadataDeployCallback writes when a deployment succeeds.
            insert as system new Setting_Change__c(
                Setting_Name__c = 'Relationship_Type.Org_Close_friend',
                Changed_By__c = UserInfo.getUserId(),
                Changed_At__c = System.now(),
                Deployment_Id__c = '0Af000000000001AAA'
            );
            afterASave = SettingsController.getSetupChecks();
        }

        Assert.isFalse(
            withoutPermission.get(SettingsController.CHECK_METADATA),
            'Without Manage BarnCRM Metadata the note is not done'
        );
        Assert.isFalse(
            beforeAnySave.containsKey(SettingsController.CHECK_METADATA),
            'Apex cannot read the Apex setting, so before a save works the answer is unknown'
        );
        Assert.isTrue(
            afterASave.get(SettingsController.CHECK_METADATA),
            'A finished Custom Metadata save shows the setting lets saves through'
        );
    }

    @IsTest
    static void aSetupCheckThatCannotBeReadIsLeftOut() {
        System.runAs(TestUsers.admin()) {
            SettingsController.emailAllowedOverride = true;
            Map<String, Boolean> checks = SettingsController.getSetupChecks();

            Assert.isTrue(
                checks.containsKey(SettingsController.CHECK_EMAIL),
                'The email check answers'
            );

            SettingsController.emailAllowedOverride = null;
            Assert.isNotNull(
                SettingsController.getSetupChecks(),
                'Asking this org itself whether it may send email never fails the page'
            );
        }
    }

    @IsTest
    static void aSettingNobodyHasSavedShowsItsDefaultNotAnEmptyBox() {
        System.runAs(TestUsers.admin()) {
            SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>{
                effectiveDefaultRow('Test_Digest', 'Error_Digest_Frequency__c', 'Picklist'),
                effectiveDefaultRow('Test_Stale', 'Stale_Record_Years__c', 'Number'),
                effectiveDefaultRow('Test_Membership', 'Household_Membership_Mode__c', 'Picklist'),
                effectiveDefaultRow('Test_Coexistence', 'Coexistence_Mode__c', 'Picklist'),
                effectiveDefaultRow('Test_Pattern', 'Household_Name_Pattern__c', 'Text'),
                optimizerRow(),
                setupValueRow()
            };
            OrgShapeDetector.overrideShape = new OrgShapeDetector.OrgShape();
            SetupValueSelector.organizationNameOverride = 'Barn Rescue';
            Assert.isNull(BarnCRM_Settings__c.getOrgDefaults().Id, 'The org has never saved.');

            SettingsController.ConsoleModel model = SettingsController.getConsoleModel();

            Map<String, String> valueByKey = new Map<String, String>();
            for (SettingsController.SectionModel section : model.sections) {
                for (SettingsController.SettingModel setting : section.settings) {
                    valueByKey.put(setting.key, setting.value);
                }
            }
            Assert.areEqual('Daily', valueByKey.get('Error_Digest_Frequency__c'), 'Default shown');
            Assert.areEqual('5', valueByKey.get('Stale_Record_Years__c'), 'Number default shown');
            Assert.areEqual(
                CoexistenceService.MEMBERSHIP_CONTACT,
                valueByKey.get('Household_Membership_Mode__c'),
                'A blank household choice shows one household per person selected (#570), ' +
                'not the empty value the effective default leaves it as'
            );
            Assert.isTrue(
                String.isBlank(SettingsService.getSettings().Household_Membership_Mode__c),
                'Showing it stores nothing, so detection may still propose the flexible way'
            );
            Assert.areEqual(
                CoexistenceService.MODE_STANDALONE,
                valueByKey.get('Coexistence_Mode__c'),
                'The recommended coexistence mode is selected, not an empty box'
            );
            Assert.areEqual(
                'The {LastName} Family',
                valueByKey.get('Household_Name_Pattern__c'),
                'A text setting shows its shipped pattern'
            );
            Assert.areEqual(
                '90',
                valueByKey.get('Unused_Login_Days__c'),
                'An Org Optimizer threshold shows its default in its own section'
            );
            Assert.areEqual(
                'Barn Rescue',
                valueByKey.get('Name'),
                'A value from Setup is read from Setup, never given a default of BarnCRM'
            );
            Assert.isNull(
                BarnCRM_Settings__c.getOrgDefaults().Id,
                'Opening the page saved nothing'
            );
        }
    }

    private static Map<String, SettingsController.SettingModel> rowsByKey(
        SettingsController.ConsoleModel model
    ) {
        Map<String, SettingsController.SettingModel> rows = new Map<String, SettingsController.SettingModel>();
        for (SettingsController.SectionModel section : model.sections) {
            for (SettingsController.SettingModel setting : section.settings) {
                rows.put(setting.key, setting);
            }
        }
        return rows;
    }

    @IsTest
    static void anUnsavedDefaultIsMarkedAndKeepingItSavesExactlyThatValue() {
        System.runAs(TestUsers.admin()) {
            SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>{
                effectiveDefaultRow('Test_Digest', 'Error_Digest_Frequency__c', 'Picklist'),
                effectiveDefaultRow('Test_Membership', 'Household_Membership_Mode__c', 'Picklist'),
                effectiveDefaultRow('Test_Coexistence', 'Coexistence_Mode__c', 'Picklist'),
                effectiveDefaultRow('Test_Auto_Create', CHECKBOX_KEY, 'Checkbox')
            };
            OrgShapeDetector.overrideShape = new OrgShapeDetector.OrgShape();
            Map<String, SettingsController.SettingModel> before = rowsByKey(
                SettingsController.getConsoleModel()
            );
            Assert.isTrue(before.get('Coexistence_Mode__c').unsavedDefault, 'Mode not saved');
            Assert.isTrue(
                before.get('Household_Membership_Mode__c').unsavedDefault,
                'Membership not saved'
            );
            Assert.isTrue(before.get('Error_Digest_Frequency__c').unsavedDefault, 'Not saved');
            Assert.isFalse(
                before.get(CHECKBOX_KEY).unsavedDefault,
                'A checkbox is never an unsaved default'
            );
            Assert.isFalse(
                before.get('Household_Membership_Mode__c').detectionMayChange,
                'Without Person Accounts detection keeps the simple way, so it may be kept'
            );
            Assert.isFalse(
                before.get('Coexistence_Mode__c').detectionMayChange,
                'The shown mode is the one detection would write'
            );

            Test.startTest();
            Map<String, SettingsController.SettingModel> after = rowsByKey(
                SettingsController.saveSettings(
                    new Map<String, Object>{
                        'Coexistence_Mode__c' => before.get('Coexistence_Mode__c').value,
                        'Household_Membership_Mode__c' => before.get('Household_Membership_Mode__c')
                            .value
                    }
                )
            );
            Test.stopTest();

            Assert.areEqual(
                CoexistenceService.MODE_STANDALONE,
                CoexistenceService.getCurrentMode(),
                'Keeping the shown mode confirms exactly that mode'
            );
            Assert.areEqual(
                CoexistenceService.MEMBERSHIP_CONTACT,
                SettingsService.getSettings().Household_Membership_Mode__c,
                'Keeping the shown household choice stores exactly that choice'
            );
            Assert.areEqual(
                2,
                SettingsController.getRecentChanges(10).size(),
                'Each kept default is in the change history, as a choice by hand would be'
            );
            Assert.isFalse(after.get('Coexistence_Mode__c').unsavedDefault, 'Now saved');
            Assert.isFalse(after.get('Household_Membership_Mode__c').unsavedDefault, 'Saved');
            Assert.isTrue(
                after.get('Error_Digest_Frequency__c').unsavedDefault,
                'A default nobody kept is still offered'
            );
        }
    }

    @IsTest
    static void aHouseholdDefaultDetectionWouldReplaceIsNotOfferedForKeeping() {
        System.runAs(TestUsers.admin()) {
            stubMembershipRows();
            OrgShapeDetector.OrgShape shape = new OrgShapeDetector.OrgShape();
            shape.hasPersonAccounts = true;
            OrgShapeDetector.overrideShape = shape;

            Test.startTest();
            Map<String, SettingsController.SettingModel> rows = rowsByKey(
                SettingsController.getConsoleModel()
            );
            Test.stopTest();

            SettingsController.SettingModel membership = rows.get(
                CoexistenceService.KEY_MEMBERSHIP_MODE
            );
            Assert.areEqual(CoexistenceService.MEMBERSHIP_CONTACT, membership.value, 'Shown');
            Assert.isTrue(membership.unsavedDefault, 'Still a default nobody saved');
            Assert.isTrue(
                membership.detectionMayChange,
                'Detection would choose the flexible way on a Person Account org, so no keep'
            );
            Assert.areEqual(
                CoexistenceService.MEMBERSHIP_JUNCTION,
                CoexistenceService.membershipDetectionWouldChoose(),
                'What detection would write'
            );
            Assert.isFalse(
                rows.get(CoexistenceService.KEY_COEXISTENCE_MODE).detectionMayChange,
                'The coexistence mode shown is what detection writes, so it may be kept'
            );
        }
    }

    @IsTest
    static void keepingTheShownCoexistenceModeWritesNothingElse() {
        System.runAs(TestUsers.admin()) {
            stubMembershipRows();
            OrgShapeDetector.OrgShape shape = new OrgShapeDetector.OrgShape();
            shape.hasPersonAccounts = true;
            OrgShapeDetector.overrideShape = shape;
            String shown = rowsByKey(SettingsController.getConsoleModel())
                .get(CoexistenceService.KEY_COEXISTENCE_MODE)
                .value;

            Test.startTest();
            SettingsController.saveSettings(
                new Map<String, Object>{ CoexistenceService.KEY_COEXISTENCE_MODE => shown }
            );
            Test.stopTest();

            Assert.areEqual(shown, CoexistenceService.getCurrentMode(), 'The shown mode is kept');
            Assert.isFalse(
                CoexistenceService.membershipModeChosen(),
                'The console save writes only the mode, as choosing it by hand does'
            );
            Assert.areEqual(
                1,
                SettingsController.getRecentChanges(10).size(),
                'One change, one history row'
            );
        }
    }

    private static Setting_Definition__mdt optimizerRow() {
        Setting_Definition__mdt row = effectiveDefaultRow(
            'Test_Unused_Login',
            'Unused_Login_Days__c',
            'Number'
        );
        row.Section__c = SettingSections.ORG_OPTIMIZER;
        return row;
    }

    private static Setting_Definition__mdt setupValueRow() {
        return new Setting_Definition__mdt(
            DeveloperName = 'Test_Organization_Name',
            MasterLabel = 'Organization name',
            Setting_Key__c = 'Name',
            Settings_Object__c = 'Organization',
            Section__c = SettingSections.ORGANIZATION,
            Module__c = 'Core',
            Data_Type__c = 'SetupValue',
            Sort_Order__c = 1
        );
    }

    @IsTest
    static void aBlankTextRowSaysWhatItMeansAndOffersCompanyInformation() {
        System.runAs(TestUsers.admin()) {
            Setting_Definition__mdt legalName = effectiveDefaultRow(
                'Test_Legal_Name',
                'Organization_Legal_Name__c',
                'Text'
            );
            legalName.Section__c = SettingSections.ORGANIZATION;
            SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>{
                legalName,
                effectiveDefaultRow('Test_Recipients', 'Error_Digest_Recipients__c', 'Text'),
                effectiveDefaultRow('Test_Pattern', 'Household_Name_Pattern__c', 'Text')
            };
            CompanyInformation.companyOverride = (Organization) JSON.deserialize(
                '{"Name":"Barn Rescue Inc"}',
                Organization.class
            );
            Map<String, SettingsController.SettingModel> blank = rowsByKey(
                SettingsController.getConsoleModel()
            );

            SettingsController.SettingModel name = blank.get('Organization_Legal_Name__c');
            Assert.isTrue(String.isBlank(name.value), 'Nothing is filled in for the admin');
            Assert.areEqual(System.Label.Core_Settings_NotSet, name.defaultText, 'Says Not set');
            Assert.isTrue(name.unsavedDefault, 'Marked Default, as every blank row is');
            Assert.areEqual('Barn Rescue Inc', name.suggestedValue, 'Company Information offered');
            SettingsController.SettingModel recipients = blank.get('Error_Digest_Recipients__c');
            Assert.areEqual(
                System.Label.Core_Settings_DigestRecipientsDefault,
                recipients.defaultText,
                'A blank list sends the digest to every settings administrator, and says so'
            );
            Assert.isNull(recipients.suggestedValue, 'Nothing to suggest for recipients');
            SettingsController.SettingModel pattern = blank.get('Household_Name_Pattern__c');
            Assert.isNull(pattern.defaultText, 'A row with a default value shows that value');

            SettingsService.saveValues(
                new Map<String, Object>{ 'Organization_Legal_Name__c' => 'Barn Rescue Society' }
            );
            SettingsController.SettingModel saved = rowsByKey(SettingsController.getConsoleModel())
                .get('Organization_Legal_Name__c');
            Assert.isNull(saved.defaultText, 'A saved name is shown as itself');
            Assert.isNull(saved.suggestedValue, 'And nothing is offered over it');
            Assert.isFalse(saved.unsavedDefault, 'No longer a default');
        }
    }

    private static Setting_Definition__mdt effectiveDefaultRow(
        String developerName,
        String key,
        String dataType
    ) {
        return new Setting_Definition__mdt(
            DeveloperName = developerName,
            MasterLabel = developerName,
            Setting_Key__c = key,
            Section__c = SettingSections.GENERAL,
            Module__c = 'Core',
            Data_Type__c = dataType,
            Picklist_Values__c = dataType == 'Picklist'
                ? 'Daily:Daily;Weekly:Weekly;Contact:Contact;Junction:Junction;Standalone:Standalone'
                : null,
            Sort_Order__c = 1
        );
    }
}
