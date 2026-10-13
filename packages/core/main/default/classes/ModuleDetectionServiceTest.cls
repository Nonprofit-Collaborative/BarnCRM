/**
 * Core has to run on an org where no other BarnCRM package is installed, so detection
 * answers honestly and nothing static ever names another package's schema.
 */
@IsTest(testFor='ApexClass:ModuleDetectionService')
private class ModuleDetectionServiceTest {
    @IsTest
    static void listsTheSixPackagesAndSaysWhichAreHere() {
        System.runAs(TestUsers.admin()) {
            SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>();
            ModuleDetectionService.givingPresentOverride = true;

            Test.startTest();
            List<ModuleDetectionService.ModuleInfo> modules = ModuleDetectionService.getModules();
            Test.stopTest();

            Assert.areEqual(6, modules.size(), 'With Giving here, all six packages are offered');
            Assert.areEqual('Core', modules[0].name, 'Core comes first and is always here');
            Assert.isTrue(modules[0].present, 'Core is the package this code is in');
            for (ModuleDetectionService.ModuleInfo module : modules) {
                Assert.isTrue(
                    module.docsUrl.endsWith('/README.md'),
                    'Every module links to its own README, not to the product plan: ' +
                    module.docsUrl
                );
            }
        }
    }

    @IsTest
    static void offersOnlyCoreAndVolunteersWithoutGiving() {
        System.runAs(TestUsers.admin()) {
            SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>();
            ModuleDetectionService.givingPresentOverride = false;

            Test.startTest();
            List<ModuleDetectionService.ModuleInfo> modules = ModuleDetectionService.getModules();
            Test.stopTest();

            List<String> names = new List<String>();
            for (ModuleDetectionService.ModuleInfo module : modules) {
                names.add(module.name);
            }
            Assert.areEqual(
                new List<String>{ 'Core', 'Volunteers' },
                names,
                'An org without Giving is offered the modules that fit every organization only'
            );
        }
    }

    @IsTest
    static void listsAnInstalledModuleEvenWithoutGiving() {
        System.runAs(TestUsers.admin()) {
            SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>{
                new Setting_Definition__mdt(
                    Setting_Key__c = 'Program_Setting__c',
                    Settings_Object__c = 'Program_Settings__c',
                    Section__c = 'Programs',
                    Module__c = 'Programs',
                    Data_Type__c = 'Text'
                )
            };
            ModuleDetectionService.givingPresentOverride = false;

            Test.startTest();
            List<ModuleDetectionService.ModuleInfo> modules = ModuleDetectionService.getModules();
            Test.stopTest();

            Assert.areEqual(3, modules.size(), 'Core, Volunteers and the module that is installed');
            Assert.areEqual('Programs', modules[2].name, 'An installed module is never hidden');
            Assert.isTrue(modules[2].present, 'And it is shown as here');
        }
    }

    @IsTest
    static void countsAModuleThatHasShippedConsoleRows() {
        System.runAs(TestUsers.admin()) {
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
    }

    @IsTest
    static void offersEveryModuleOnceTheNonprofitEditionIsChosen() {
        System.runAs(TestUsers.admin()) {
            SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>();
            ModuleDetectionService.givingPresentOverride = false;
            chooseSuite(ModuleDetectionService.SUITE_IMPACT);

            Test.startTest();
            List<ModuleDetectionService.ModuleInfo> modules = ModuleDetectionService.getModules();
            Test.stopTest();

            Assert.areEqual(
                6,
                modules.size(),
                'Any org that chose the Nonprofit Edition is offered all six, before Giving is here'
            );
            Assert.isFalse(modules[1].present, 'And Giving is still shown as not installed');
        }
    }

    @IsTest
    static void keepsTheCommunitySuiteToTheModulesThatFitEveryOrg() {
        System.runAs(TestUsers.admin()) {
            SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>();
            ModuleDetectionService.givingPresentOverride = false;
            chooseSuite(ModuleDetectionService.SUITE_COMMUNITY);

            Test.startTest();
            List<ModuleDetectionService.ModuleInfo> modules = ModuleDetectionService.getModules();
            String chosen = ModuleDetectionService.chosenSuite();
            Test.stopTest();

            Assert.areEqual(
                ModuleDetectionService.SUITE_COMMUNITY,
                chosen,
                'The saved choice is read'
            );
            Assert.areEqual(
                2,
                modules.size(),
                'Core and Volunteers, and nothing only for nonprofits'
            );
        }
    }

    @IsTest
    static void linksTheInstallerOnlyForAPublishedModuleThatIsNotHere() {
        System.runAs(TestUsers.admin()) {
            SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>();
            ModuleDetectionService.givingPresentOverride = false;
            ModuleDetectionService.installVersionIds = new Map<String, String>{
                'Giving' => FakeIds.ofPrefix('04t', 1),
                'Volunteers' => 'not a version id'
            };
            chooseSuite(ModuleDetectionService.SUITE_IMPACT);

            Test.startTest();
            Map<String, ModuleDetectionService.ModuleInfo> byName = new Map<String, ModuleDetectionService.ModuleInfo>();
            for (ModuleDetectionService.ModuleInfo module : ModuleDetectionService.getModules()) {
                byName.put(module.name, module);
            }
            ModuleDetectionService.ModuleInfo giving = ModuleDetectionService.givingModule();
            Test.stopTest();

            Assert.areEqual(
                '/packaging/installPackage.apexp?p0=04t000000000001AAA',
                byName.get('Giving').installUrl,
                'A published module that is not here links to Salesforce\'s installer'
            );
            Assert.areEqual(
                byName.get('Giving').installUrl,
                giving.installUrl,
                'The suite step links to the same installer'
            );
            Assert.isNull(
                byName.get('Volunteers').installUrl,
                'Anything but a version Id is no link'
            );
            Assert.isNull(byName.get('Programs').installUrl, 'An unpublished module has no link');
            Assert.isNull(
                byName.get('Core').installUrl,
                'Core is here, so there is nothing to install'
            );
        }
    }

    @IsTest
    static void offersNoInstallerForAModuleThatIsHere() {
        System.runAs(TestUsers.admin()) {
            SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>();
            ModuleDetectionService.givingPresentOverride = true;
            ModuleDetectionService.installVersionIds = new Map<String, String>{
                'Giving' => FakeIds.ofPrefix('04t', 1)
            };

            Test.startTest();
            ModuleDetectionService.ModuleInfo giving = ModuleDetectionService.givingModule();
            Test.stopTest();

            Assert.isTrue(giving.present, 'Giving is here');
            Assert.isNull(giving.installUrl, 'So the step offers no installer');
            Assert.isTrue(
                giving.docsUrl.endsWith('/giving/README.md'),
                'Its description is linked'
            );
        }
    }

    private static void chooseSuite(String suite) {
        insert new BarnCRM_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Suite__c = suite
        );
        SettingsService.clearCaches();
    }

    @IsTest
    static void answersHonestlyOnACoreOnlyOrg() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            Boolean givingPresent = ModuleDetectionService.isGivingPresent();
            Boolean givingListed = false;
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
}
