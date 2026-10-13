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
                Settings_Object__c = 'Volunteer_Settings__c',
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
            Assert.areEqual(ModuleManagerService.STATUS_OFF, off.modules[1].status, 'Off is shown');
            Assert.areEqual(ModuleManagerService.STATUS_ON, backOn.modules[1].status, 'On again');
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
            }
            Test.stopTest();

            Assert.areEqual(2, refused, 'Switching and counting both need the permission');
        }
    }
}
