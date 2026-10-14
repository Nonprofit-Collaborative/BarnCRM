/**
 * Core has to run on an org where no other BarnCRM package is installed, so detection
 * answers honestly and nothing static ever names another package's schema.
 */
@IsTest(testFor='ApexClass:ModuleDetectionService')
private class ModuleDetectionServiceTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    @IsTest
    static void listsTheSixPackagesAndSaysWhichAreHere() {
        System.runAs(TestUsers.admin()) {
            SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>();
            ModuleDetectionService.givingPresentOverride = true;
            chooseSuite(ModuleDetectionService.SUITE_IMPACT);

            Test.startTest();
            List<ModuleDetectionService.ModuleInfo> modules = ModuleDetectionService.getModules();
            Test.stopTest();

            Assert.areEqual(6, modules.size(), 'The Nonprofit Edition is offered all six packages');
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
    static void offersOnlyCoreBeforeAnEditionIsChosen() {
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
                new List<String>{ 'Core' },
                names,
                'No nonprofit module is shown until the Nonprofit Edition is chosen'
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

            Assert.areEqual(2, modules.size(), 'Core and the module that is installed');
            Assert.areEqual('Programs', modules[1].name, 'An installed module is never hidden');
            Assert.isTrue(modules[1].present, 'And it is shown as here');
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
            Assert.areEqual(1, modules.size(), 'Core, and no nonprofit module');
        }
    }

    @IsTest
    static void givingInstalledInTheStandardEditionShowsGivingAlone() {
        System.runAs(TestUsers.admin()) {
            SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>();
            ModuleDetectionService.givingPresentOverride = true;
            chooseSuite(ModuleDetectionService.SUITE_COMMUNITY);

            Test.startTest();
            List<String> names = new List<String>();
            for (ModuleDetectionService.ModuleInfo module : ModuleDetectionService.getModules()) {
                names.add(module.name);
            }
            Test.stopTest();

            Assert.areEqual(
                new List<String>{ 'Core', 'Giving' },
                names,
                'An installed module stays listed; the others stay hidden in the Standard Edition'
            );
        }
    }

    @IsTest
    static void aValueTypedInSetupCountsOnlyWhenItIsAnEdition() {
        System.runAs(TestUsers.admin()) {
            chooseSuite('impact');
            String lowerCase = ModuleDetectionService.chosenSuite();
            Boolean nonprofit = ModuleDetectionService.isNonprofitEdition();
            BarnCRM_Settings__c settings = BarnCRM_Settings__c.getOrgDefaults();
            settings.Suite__c = 'Standard';
            update settings;
            SettingsService.clearCaches();

            Test.startTest();
            String unknown = ModuleDetectionService.chosenSuite();
            Test.stopTest();

            Assert.areEqual(
                ModuleDetectionService.SUITE_IMPACT,
                lowerCase,
                'Lower case is forgiven'
            );
            Assert.isTrue(nonprofit, 'And it is the Nonprofit Edition');
            Assert.isNull(unknown, 'Anything but Community or Impact is no edition');
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

    @IsTest
    static void anotherPackagesFundAndAppealDoNotLookLikeGiving() {
        System.runAs(TestUsers.admin()) {
            SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>();
            NamespaceUtil.cachedPrefix = '';
            String otherPrefix = 'other__';
            NamespaceUtil.describeOverride = new Map<String, Schema.SObjectType>{
                otherPrefix + 'fund__c' => Account.SObjectType,
                otherPrefix + 'appeal__c' => Contact.SObjectType
            };

            Test.startTest();
            Boolean foreignLooksLikeGiving = ModuleDetectionService.isGivingPresent();
            String foreignFund = ModuleDetectionService.resolveObject('Fund__c');
            NamespaceUtil.describeOverride.put('fund__c', Account.SObjectType);
            NamespaceUtil.describeOverride.put('appeal__c', Contact.SObjectType);
            Boolean ownLooksLikeGiving = ModuleDetectionService.isGivingPresent();
            Test.stopTest();

            Assert.isFalse(
                foreignLooksLikeGiving,
                'Objects of the same name in another namespace are not Giving'
            );
            Assert.isNull(foreignFund, 'Another package\'s Fund__c does not resolve');
            Assert.isTrue(ownLooksLikeGiving, 'The package\'s own objects are found');
            Assert.areEqual(
                'Account',
                ModuleDetectionService.resolveObject('Fund__c'),
                'The real API name of the matching object comes back'
            );
        }
    }

    @IsTest
    static void anObjectIsFoundByItsUnprefixedNameInAnyCase() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            String found = ModuleDetectionService.resolveObject('error_log__c');
            String again = ModuleDetectionService.resolveObject('Error_Log__c');
            String missing = ModuleDetectionService.resolveObject('No_Such_Object__c');
            Test.stopTest();

            Assert.areEqual(
                Error_Log__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getName(),
                found,
                'The real API name comes back, prefix and all once a namespace exists'
            );
            Assert.areEqual(found, again, 'The second ask, from the cache, gives the same answer');
            Assert.isNull(missing, 'An object this org lacks resolves to nothing');
        }
    }
}
