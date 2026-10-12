/**
 * Maria turns a module off and on in the Module Manager and checks what removing it would
 * delete (C-24). No real module is needed: Volunteers is made present by the console row it
 * would ship (ADR-0017), and its automation is a test handler on Contact.
 */
@IsTest
private class ModuleManagerServiceTest {
    private static final String MODULE = 'Volunteers';

    @TestSetup
    static void grantPermission() {
        SettingsTestPermissions.grantTo('C24_Module_Manager_Test', UserInfo.getUserId());
    }

    private static void volunteersInstalled() {
        SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>{
            new Setting_Definition__mdt(
                Setting_Key__c = 'Shift_Reminder_Days__c',
                Settings_Object__c = 'Volunteer_Settings__c',
                Section__c = 'Volunteers',
                Module__c = MODULE,
                Data_Type__c = 'Number'
            )
        };
        ModuleDetectionService.givingPresentOverride = false;
    }

    private static Automation_Registry__mdt volunteerAutomation(Boolean alwaysRuns) {
        Automation_Registry__mdt entry = TestDataFactory.registryEntry('Volunteer_Test', true);
        entry.Handler_Class__c = 'TestRegisteredHandler';
        entry.Object_Name__c = 'Contact';
        entry.Module__c = MODULE;
        entry.Always_Runs__c = alwaysRuns;
        AutomationRegistrySelector.registryOverride = new List<Automation_Registry__mdt>{ entry };
        return entry;
    }

    private static List<Contact> people(Integer howMany, String batch) {
        List<Contact> rows = new List<Contact>();
        for (Integer i = 0; i < howMany; i++) {
            rows.add(new Contact(FirstName = batch, LastName = 'Volunteer ' + i));
        }
        return rows;
    }

    private static ModuleManagerService.ModuleStatus row(String name) {
        for (ModuleManagerService.ModuleStatus status : ModuleManagerService.getModules()) {
            if (status.name == name) {
                return status;
            }
        }
        return null;
    }

    @IsTest
    static void saysWhatEachModuleIsDoing() {
        volunteersInstalled();

        Test.startTest();
        ModuleManagerService.ModuleStatus before = row(MODULE);
        ModuleManagerService.turnOff(MODULE);
        ModuleManagerService.ModuleStatus after = row(MODULE);
        ModuleManagerService.ModuleStatus core = row('Core');
        Test.stopTest();

        Assert.areEqual(ModuleManagerService.STATUS_ON, before.status, 'Installed means on');
        Assert.areEqual(ModuleManagerService.STATUS_OFF, after.status, 'Turned off is shown');
        Assert.isTrue(after.canSwitch, 'An installed module can be switched');
        Assert.areEqual(ModuleManagerService.STATUS_ON, core.status, 'Core is always on');
        Assert.isFalse(core.canSwitch, 'And cannot be switched');
        Assert.isNull(row('Giving'), 'The Community Suite is not offered Giving');
    }

    @IsTest
    static void turningAModuleOffStopsItsAutomationForABulkSave() {
        volunteersInstalled();
        volunteerAutomation(false);
        ModuleManagerService.turnOff(MODULE);
        TestRegisteredHandler.reset();

        Test.startTest();
        insert people(200, 'Off');
        Test.stopTest();

        Assert.areEqual(
            0,
            TestRegisteredHandler.runCount,
            'Nothing of the module ran for 200 people'
        );
        Assert.isFalse(
            AutomationControl.isEnabled('Volunteer_Test'),
            'Its automation reads as off'
        );
    }

    @IsTest
    static void turningItBackOnRestoresItsAutomation() {
        volunteersInstalled();
        volunteerAutomation(false);
        ModuleManagerService.turnOff(MODULE);
        ModuleManagerService.turnOn(MODULE);
        TestRegisteredHandler.reset();

        Test.startTest();
        insert people(200, 'On');
        Test.stopTest();

        Assert.areEqual(200, TestRegisteredHandler.handledIds.size(), 'All 200 were handled');
        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Automation_Setting__c WHERE Automation_Name__c = 'Volunteer_Test'],
            'Turning on creates the switch row a module needs'
        );
        Assert.areEqual(ModuleManagerService.STATUS_ON, row(MODULE).status, 'And it reads as on');
    }

    @IsTest
    static void anAutomationThatAlwaysRunsIgnoresTurningOff() {
        volunteersInstalled();
        volunteerAutomation(true);

        Test.startTest();
        ModuleManagerService.turnOff(MODULE);
        Boolean enabled = AutomationControl.isEnabled('Volunteer_Test');
        Test.stopTest();

        Assert.isTrue(enabled, 'A rule the module enforces keeps running (ADR-0024)');
    }

    @IsTest
    static void refusesCoreAndModulesThatAreNotHere() {
        volunteersInstalled();
        Integer refused = 0;

        Test.startTest();
        for (String name : new List<String>{ 'Core', 'Programs', null }) {
            try {
                ModuleManagerService.turnOff(name);
            } catch (ModuleManagerService.ModuleManagerException e) {
                Assert.areEqual(System.Label.Core_ModuleManager_UnknownModuleError, e.getMessage());
                refused++;
            }
        }
        Test.stopTest();

        Assert.areEqual(3, refused, 'Core, a missing module and no module are all refused');
        Assert.isTrue(ModuleManagerService.turnedOff().isEmpty(), 'And nothing was saved');
    }

    @IsTest
    static void countsWhatAnUninstallWouldDelete() {
        volunteersInstalled();
        ModuleManagerService.ownedObjects = new Map<String, List<String>>{
            MODULE => new List<String>{ 'Error_Log__c', 'No_Such_Object__c' }
        };
        TestDataFactory.insertErrorLogs(200, ErrorLogger.STATUS_NEW);
        Integer stored = [SELECT COUNT() FROM Error_Log__c];

        Test.startTest();
        List<ModuleManagerService.RecordCount> report = ModuleManagerService.uninstallReport(
            MODULE
        );
        ModuleManagerService.countCap = 150;
        List<ModuleManagerService.RecordCount> capped = ModuleManagerService.uninstallReport(
            MODULE
        );
        Test.stopTest();

        Assert.areEqual(1, report.size(), 'An object this org does not have is left out');
        Assert.areEqual(stored, report[0].count, 'Every record is counted');
        Assert.isFalse(report[0].capped, 'Under the cap the count is exact');
        Assert.isNotNull(report[0].objectLabel, 'The kind of record is named as Maria knows it');
        Assert.areEqual(150, capped[0].count, 'A count stops at the cap');
        Assert.isTrue(capped[0].capped, 'And says it stopped');
    }

    @IsTest
    static void givesThePersonWhoTurnedItOnTheModuleAdminSet() {
        volunteersInstalled();
        ModuleManagerService.adminPermissionSets = new Map<String, String>{
            MODULE => 'BarnCRM_Read_Only'
        };

        Test.startTest();
        Boolean first = ModuleManagerService.grantAdminAccess(MODULE);
        Boolean second = ModuleManagerService.grantAdminAccess(MODULE);
        Test.stopTest();

        Assert.isTrue(first && second, 'The set is given, and giving it again changes nothing');
        Assert.areEqual(
            1,
            [
                SELECT COUNT()
                FROM PermissionSetAssignment
                WHERE
                    AssigneeId = :UserInfo.getUserId()
                    AND PermissionSet.Name = 'BarnCRM_Read_Only'
            ],
            'Held once'
        );
    }

    @IsTest
    static void givesNothingForAModuleWithNoAdminSet() {
        volunteersInstalled();
        ModuleManagerService.adminPermissionSets = new Map<String, String>();

        Test.startTest();
        Boolean given = ModuleManagerService.grantAdminAccess(MODULE);
        Test.stopTest();

        Assert.isFalse(given, 'A module that ships no admin set gets none');
    }
}
