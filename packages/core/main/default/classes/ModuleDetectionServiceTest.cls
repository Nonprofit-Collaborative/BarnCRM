/**
 * Core has to run on an org where no other Open Impact package is installed, so detection
 * answers honestly and nothing static ever names another package's schema.
 */
@IsTest
private class ModuleDetectionServiceTest {
    @IsTest
    static void listsTheSixPackagesAndSaysWhichAreHere() {
        SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>();

        Test.startTest();
        List<ModuleDetectionService.ModuleInfo> modules = ModuleDetectionService.getModules();
        Test.stopTest();

        Assert.areEqual(6, modules.size(), 'Open Impact is six packages');
        Assert.areEqual('Core', modules[0].name, 'Core comes first and is always here');
        Assert.isTrue(modules[0].present, 'Core is the package this code is in');
        for (ModuleDetectionService.ModuleInfo module : modules) {
            Assert.isNotNull(module.docsUrl, 'Every module says where to read what it does');
        }
    }

    @IsTest
    static void countsAModuleThatHasShippedConsoleRows() {
        SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>{
            new Setting_Definition__mdt(
                Setting_Key__c = 'Shift_Reminder_Days__c',
                Settings_Object__c = 'Volunteer_Settings__c',
                Section__c = 'Volunteers',
                Module__c = 'Volunteers',
                Data_Type__c = 'Number'
            )
        };

        Test.startTest();
        List<ModuleDetectionService.ModuleInfo> modules = ModuleDetectionService.getModules();
        Test.stopTest();

        Boolean volunteersPresent = false;
        for (ModuleDetectionService.ModuleInfo module : modules) {
            if (module.name == 'Volunteers') {
                volunteersPresent = module.present;
            }
        }
        Assert.isTrue(
            volunteersPresent,
            'A module announces itself by the settings console rows it ships (ADR-0017)'
        );
    }

    @IsTest
    static void answersHonestlyOnACoreOnlyOrg() {
        Test.startTest();
        Boolean givingPresent = ModuleDetectionService.isGivingPresent();
        Boolean givingListed;
        for (ModuleDetectionService.ModuleInfo module : ModuleDetectionService.getModules()) {
            if (module.name == 'Giving') {
                givingListed = module.present;
            }
        }
        Test.stopTest();

        Assert.areEqual(
            givingPresent,
            givingListed,
            'The module list and the Giving check give the same answer'
        );
    }
}
