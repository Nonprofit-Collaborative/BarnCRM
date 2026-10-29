/**
 * The Module Manager's Apex surface: Maria reads and switches, David only reads (C-24).
 */
@IsTest(testFor='ApexClass:ModuleManagerController')
private class ModuleManagerControllerTest {
    @TestSetup
    static void grantPermission() {
        System.runAs(TestUsers.admin()) {
            SettingsTestPermissions.grantTo('C24_Module_Controller_Test', UserInfo.getUserId());
        }
    }

    private static void volunteersInstalled() {
        SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>{
            new Setting_Definition__mdt(
                Setting_Key__c = 'Shift_Reminder_Days__c',
                Settings_Object__c = 'Example_Settings__c',
                Section__c = 'Volunteers',
                Module__c = 'Volunteers',
                Data_Type__c = 'Number'
            )
        };
        ModuleDetectionService.givingPresentOverride = false;
        AutomationRegistrySelector.registryOverride = new List<Automation_Registry__mdt>();
        ModuleManagerService.ownedObjects = new Map<String, List<String>>{
            'Volunteers' => new List<String>{ 'Error_Log__c' }
        };
        ModuleManagerService.adminPermissionSets = new Map<String, String>();
    }

    @IsTest
    static void mariaTurnsAModuleOffAndOn() {
        System.runAs(TestUsers.admin()) {
            volunteersInstalled();

            Test.startTest();
            ModuleManagerController.ManagerState opened = ModuleManagerController.getState();
            ModuleManagerController.ManagerState off = ModuleManagerController.turnOff(
                'Volunteers'
            );
            ModuleManagerController.ManagerState backOn = ModuleManagerController.turnOn(
                'Volunteers'
            );
            Boolean granted = ModuleManagerController.grantAdminAccess('Volunteers');
            List<ModuleManagerService.RecordCount> report = ModuleManagerController.uninstallReport(
                'Volunteers'
            );
            Test.stopTest();

            Assert.isTrue(opened.canEdit, 'Maria may switch modules');
            // Core, then BarnCRM Rollup Builder (still shipped in Core), then Volunteers.
            Assert.areEqual(ModuleManagerService.STATUS_OFF, off.modules[2].status, 'Off is shown');
            Assert.areEqual(ModuleManagerService.STATUS_ON, backOn.modules[2].status, 'On again');
            Assert.isFalse(granted, 'No admin set to give for this module');
            Assert.areEqual(1, report.size(), 'The report has a line per object the module owns');
        }
    }

    @IsTest
    static void aModuleThatIsNotHereIsRefusedWithAMessage() {
        System.runAs(TestUsers.admin()) {
            volunteersInstalled();
            String message;

            Test.startTest();
            try {
                ModuleManagerController.turnOff('Funders');
            } catch (AuraHandledException e) {
                message = e.getMessage();
            }
            Test.stopTest();

            Assert.areEqual(System.Label.Core_ModuleManager_UnknownModuleError, message);
        }
    }

    @IsTest
    static void davidReadsTheListAndCannotSwitch() {
        System.runAs(TestUsers.admin()) {
            volunteersInstalled();
            User david = TestUsers.standardUser('Okonkwo');
            Integer refused = 0;

            Test.startTest();
            System.runAs(david) {
                Assert.isFalse(ModuleManagerController.getState().canEdit, 'David may only read');
                try {
                    ModuleManagerController.turnOff('Volunteers');
                } catch (AuraHandledException e) {
                    refused++;
                }
                try {
                    ModuleManagerController.uninstallReport('Volunteers');
                } catch (AuraHandledException e) {
                    refused++;
                }
                try {
                    ModuleManagerController.saveShowNonprofitModules(false);
                } catch (AuraHandledException e) {
                    refused++;
                }
            }
            Test.stopTest();

            Assert.areEqual(
                3,
                refused,
                'Switching, counting and hiding the nonprofit modules all need the permission'
            );
            Assert.isTrue(
                ModuleManagerService.showNonprofitModules(),
                'Nothing was saved, so the nonprofit modules still show'
            );
        }
    }

    @IsTest
    static void nonprofitModulesShowUntilMariaClearsTheCheckboxAndTheChoiceIsSaved() {
        System.runAs(TestUsers.admin()) {
            volunteersInstalled();
            ModuleDetectionService.catalogOverride = new List<BarnCRM_Module__mdt>{
                new BarnCRM_Module__mdt(
                    DeveloperName = 'Volunteers',
                    Editions__c = 'Nonprofit',
                    Package_Folder__c = 'volunteers',
                    Sort_Order__c = 20
                ),
                new BarnCRM_Module__mdt(
                    DeveloperName = 'Rollups',
                    Editions__c = 'Standard;Nonprofit',
                    Package_Folder__c = 'rollups',
                    Sort_Order__c = 10
                )
            };

            Test.startTest();
            ModuleManagerController.ManagerState fresh = ModuleManagerController.getState();
            ModuleManagerController.ManagerState cleared = ModuleManagerController.saveShowNonprofitModules(
                false
            );
            SettingsService.clearCaches();
            Boolean stored = SettingsService.getSettings().Hide_Nonprofit_Modules__c;
            ModuleManagerController.ManagerState shown = ModuleManagerController.saveShowNonprofitModules(
                true
            );
            Test.stopTest();

            Assert.isTrue(fresh.showNonprofitModules, 'Shown until someone clears it');
            Assert.isFalse(cleared.showNonprofitModules, 'Cleared is returned');
            Assert.isTrue(stored, 'Cleared is stored for the whole org as Hide Nonprofit Modules');
            Assert.isTrue(shown.showNonprofitModules, 'Ticked again is returned');
            Map<String, Boolean> nonprofit = new Map<String, Boolean>();
            for (ModuleManagerService.ModuleStatus module : cleared.modules) {
                nonprofit.put(module.name, module.nonprofitOnly);
            }
            Assert.isTrue(
                nonprofit.get('Volunteers'),
                'A module only the Nonprofit Edition offers'
            );
            Assert.isFalse(nonprofit.get('Rollups'), 'A module both editions offer');
            Assert.isFalse(nonprofit.get('Core'), 'Core is never nonprofit only');
            Assert.areEqual(
                2,
                [
                    SELECT COUNT()
                    FROM Setting_Change__c
                    WHERE Setting_Name__c LIKE '%Hide_Nonprofit_Modules__c'
                ],
                'Each change is audited like any other setting'
            );
        }
    }

    @IsTest
    static void anExistingSettingsRowThatNeverSetTheFieldShowsTheNonprofitModules() {
        System.runAs(TestUsers.admin()) {
            volunteersInstalled();
            // An org that saved its settings before this field existed: a row with other keys
            // set and nothing said about hiding.
            insert new BarnCRM_Settings__c(
                SetupOwnerId = UserInfo.getOrganizationId(),
                Suite__c = ModuleDetectionService.SUITE_NONPROFIT
            );
            SettingsService.clearCaches();

            Test.startTest();
            ModuleManagerController.ManagerState state = ModuleManagerController.getState();
            Test.stopTest();

            Assert.isTrue(state.showNonprofitModules, 'A saved row that never hid them shows them');
            Assert.isTrue(ModuleManagerService.showNonprofitModules(), 'The service agrees');
            Assert.isFalse(
                SettingsService.getSettings().Hide_Nonprofit_Modules__c == true,
                'Nothing was hidden'
            );
        }
    }

    @IsTest
    static void dlrsIsMentionedOnlyWhenAModuleThatTotalsIsInstalled() {
        System.runAs(TestUsers.admin()) {
            volunteersInstalled();
            OtherRollupTools.overrideForTest(new Set<String>{ OtherRollupTools.DLRS_NAMESPACE });

            ModuleManagerController.ManagerState volunteersOnly = ModuleManagerController.getState();
            ModuleDetectionService.givingPresentOverride = true;
            ModuleManagerController.ManagerState withGiving = ModuleManagerController.getState();

            // Rollup Builder is found by its own object, so an org that has it is told too.
            Boolean rollupsHere = false;
            for (ModuleManagerService.ModuleStatus module : volunteersOnly.modules) {
                rollupsHere |=
                    module.name == 'Rollups' &&
                    module.status != ModuleManagerService.STATUS_NOT_INSTALLED;
            }
            Assert.areEqual(
                rollupsHere ? 1 : 0,
                volunteersOnly.otherRollupTools.size(),
                'Volunteers calculates no totals, so DLRS is mentioned only beside Rollup Builder'
            );
            Assert.areEqual(
                new List<String>{ System.Label.Core_OtherRollupTools_Dlrs },
                withGiving.otherRollupTools,
                'With Giving installed, the page says DLRS is a separate tool'
            );
        }
    }

    @IsTest
    static void noOtherToolMeansNoNotice() {
        System.runAs(TestUsers.admin()) {
            volunteersInstalled();
            ModuleDetectionService.givingPresentOverride = true;
            OtherRollupTools.overrideForTest(new Set<String>());

            ModuleManagerController.ManagerState state = ModuleManagerController.getState();

            Assert.isTrue(state.otherRollupTools.isEmpty(), 'Nothing to say without DLRS');
        }
    }
}
