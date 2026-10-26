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
    static void listsTheSevenPackagesAndSaysWhichAreHere() {
        System.runAs(TestUsers.admin()) {
            SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>();
            ModuleDetectionService.givingPresentOverride = true;
            chooseSuite(ModuleDetectionService.SUITE_IMPACT);

            Test.startTest();
            List<ModuleDetectionService.ModuleInfo> modules = ModuleDetectionService.getModules();
            Test.stopTest();

            Assert.areEqual(7, modules.size(), 'The Nonprofit Edition is offered all seven');
            Assert.areEqual('Core', modules[0].name, 'Core comes first and is always here');
            Assert.isTrue(modules[0].present, 'Core is the package this code is in');
            for (Integer i = 1; i < modules.size(); i++) {
                Assert.isTrue(
                    modules[i].label.startsWith('BarnCRM '),
                    'Every module is shown as BarnCRM and its name: ' + modules[i].label
                );
            }
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
    static void offersOnlyEveryEditionModulesBeforeAnEditionIsChosen() {
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
            assertListed(
                new List<String>{ 'Core', 'Rollups' },
                names,
                'No nonprofit module is shown until the Nonprofit Edition is chosen'
            );
            Assert.isTrue(
                modules[1].present,
                'Rollup Builder counts as installed while its objects ship in Core'
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

            Map<String, ModuleDetectionService.ModuleInfo> byName = new Map<String, ModuleDetectionService.ModuleInfo>();
            for (ModuleDetectionService.ModuleInfo module : modules) {
                byName.put(module.name, module);
            }
            Set<String> expected = installedModules();
            expected.add('Programs');
            Assert.areEqual(
                3 + expected.size() - 1,
                modules.size(),
                'Core, Rollup Builder, the announcing module and any module whose objects are here'
            );
            Assert.isTrue(byName.containsKey('Programs'), 'An installed module is never hidden');
            Assert.isTrue(byName.get('Programs').present, 'And it is shown as here');
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
                7,
                modules.size(),
                'Any org that chose the Nonprofit Edition is offered all seven, before Giving is here'
            );
            Assert.areEqual('Giving', modules[2].name, 'Giving follows Rollup Builder');
            Assert.isFalse(modules[2].present, 'And Giving is still shown as not installed');
            Assert.isNull(modules[2].appUrl, 'A module that is not here has no app to open');
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
                2 + installedModules().size(),
                modules.size(),
                'Core and Rollup Builder, any module whose objects are here, and no other nonprofit module'
            );
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

            assertListed(
                new List<String>{ 'Core', 'Rollups', 'Giving' },
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
            ModuleDetectionService.catalogOverride = new List<BarnCRM_Module__mdt>{
                catalogRow('Giving', 'Impact', FakeIds.ofPrefix('04t', 1), 10),
                catalogRow('Volunteers', 'Impact', 'not a version id', 20),
                catalogRow('Programs', 'Impact', null, 30)
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
            BarnCRM_Module__mdt row = catalogRow(
                'Giving',
                'Impact',
                FakeIds.ofPrefix('04t', 1),
                10
            );
            row.App_Name__c = 'Fundraising';
            ModuleDetectionService.catalogOverride = new List<BarnCRM_Module__mdt>{ row };
            String appId = FakeIds.ofPrefix('06m', 1);
            ModuleDetectionService.appIdsOverride = new Map<String, String>{
                'Fundraising' => appId
            };

            Test.startTest();
            ModuleDetectionService.ModuleInfo giving = ModuleDetectionService.givingModule();
            Test.stopTest();

            Assert.isTrue(giving.present, 'Giving is here');
            Assert.isNull(giving.installUrl, 'So the step offers no installer');
            Assert.areEqual(
                '/lightning/app/' + appId,
                giving.appUrl,
                'An installed module links to its own app by Id, where its Settings tab lives'
            );
            Assert.isTrue(
                giving.docsUrl.endsWith('/giving/README.md'),
                'Its description is linked'
            );
        }
    }

    @IsTest
    static void appLinkFallsBackToTheCustomAppFormWithNoNamespace() {
        System.runAs(TestUsers.admin()) {
            SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>();
            ModuleDetectionService.givingPresentOverride = true;
            BarnCRM_Module__mdt row = catalogRow('Giving', 'Impact', null, 10);
            row.App_Name__c = 'Fundraising';
            ModuleDetectionService.catalogOverride = new List<BarnCRM_Module__mdt>{ row };
            ModuleDetectionService.appIdsOverride = new Map<String, String>();
            NamespaceUtil.cachedPrefix = '';

            Test.startTest();
            ModuleDetectionService.ModuleInfo giving = ModuleDetectionService.givingModule();
            Test.stopTest();

            Assert.areEqual(
                '/lightning/app/c__Fundraising',
                giving.appUrl,
                'An app not found is addressed as an unmanaged custom app'
            );
        }
    }

    @IsTest
    static void appLinkFallsBackToTheNamespaceWhenThereIsOne() {
        System.runAs(TestUsers.admin()) {
            SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>();
            ModuleDetectionService.givingPresentOverride = true;
            BarnCRM_Module__mdt row = catalogRow('Giving', 'Impact', null, 10);
            row.App_Name__c = 'Fundraising';
            ModuleDetectionService.catalogOverride = new List<BarnCRM_Module__mdt>{ row };
            ModuleDetectionService.appIdsOverride = new Map<String, String>();
            NamespaceUtil.cachedPrefix = 'barn__';

            Test.startTest();
            ModuleDetectionService.ModuleInfo giving = ModuleDetectionService.givingModule();
            Test.stopTest();

            Assert.areEqual(
                '/lightning/app/barn__Fundraising',
                giving.appUrl,
                'An app not found is addressed by its namespace'
            );
        }
    }

    @IsTest
    static void appLinkUsesTheOrgsOwnAppMenuWhenNothingIsStubbed() {
        System.runAs(TestUsers.admin()) {
            SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>();
            ModuleDetectionService.givingPresentOverride = true;
            BarnCRM_Module__mdt row = catalogRow('Giving', 'Impact', null, 10);
            row.App_Name__c = 'NoSuchBarnCrmApp';
            ModuleDetectionService.catalogOverride = new List<BarnCRM_Module__mdt>{ row };
            NamespaceUtil.cachedPrefix = '';

            Test.startTest();
            ModuleDetectionService.ModuleInfo giving = ModuleDetectionService.givingModule();
            Test.stopTest();

            Assert.areEqual(
                '/lightning/app/c__NoSuchBarnCrmApp',
                giving.appUrl,
                'The real query finds nothing for an unknown app, so the name form is used'
            );
        }
    }

    @IsTest
    static void anInstalledModuleListsTheTabsToAddToTheBarnCrmApps() {
        System.runAs(TestUsers.admin()) {
            SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>();
            ModuleDetectionService.givingPresentOverride = true;
            BarnCRM_Module__mdt here = catalogRow('Giving', 'Impact', null, 10);
            here.Staff_Tabs__c = 'Gift__c; Commitment__c';
            here.Admin_Tabs__c = 'Giving_Nightly_Jobs;Donor_Levels:Donor Level Ladder';
            BarnCRM_Module__mdt notHere = catalogRow('Events', 'Community;Impact', null, 5);
            notHere.Staff_Tabs__c = 'Event__c';
            ModuleDetectionService.catalogOverride = new List<BarnCRM_Module__mdt>{ here, notHere };
            ModuleDetectionService.tabLabelsOverride = new Map<String, String>{
                'Gift__c' => 'Gifts'
            };

            Map<String, ModuleDetectionService.ModuleInfo> byName = new Map<String, ModuleDetectionService.ModuleInfo>();
            for (ModuleDetectionService.ModuleInfo info : ModuleDetectionService.getModules()) {
                byName.put(info.name, info);
            }

            ModuleDetectionService.ModuleInfo giving = byName.get('Giving');
            Assert.areEqual('Gifts, Commitment', giving.staffTabs, 'By label, else by name');
            Assert.areEqual(
                'Giving Nightly Jobs, Donor Level Ladder',
                giving.adminTabs,
                'The admin tools too, by the label an entry carries'
            );
            Assert.isNull(byName.get('Events').staffTabs, 'A module not here lists nothing');
        }
    }

    @IsTest
    static void aTabTheOrgDoesNotHaveIsNamedWithoutError() {
        System.runAs(TestUsers.admin()) {
            SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>();
            ModuleDetectionService.givingPresentOverride = true;
            BarnCRM_Module__mdt row = catalogRow('Giving', 'Impact', null, 10);
            row.Admin_Tabs__c = 'No_Such_BarnCRM_Tab';
            ModuleDetectionService.catalogOverride = new List<BarnCRM_Module__mdt>{ row };

            Test.startTest();
            List<ModuleDetectionService.ModuleInfo> modules = ModuleDetectionService.getModules();
            Test.stopTest();

            Assert.areEqual(
                'No Such BarnCRM Tab',
                modules[modules.size() - 1].adminTabs,
                'A page tab has no object to label it, so its name stands in for the label'
            );
        }
    }

    @IsTest
    static void anAppThatIsNotInTheOrgYetFallsBackToTheNameFormWithoutError() {
        System.runAs(TestUsers.admin()) {
            SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>();
            ModuleDetectionService.givingPresentOverride = true;
            BarnCRM_Module__mdt row = catalogRow('Giving', 'Impact', null, 10);
            row.App_Name__c = 'BarnCRM_Volunteers';
            ModuleDetectionService.catalogOverride = new List<BarnCRM_Module__mdt>{ row };
            NamespaceUtil.cachedPrefix = '';

            ModuleDetectionService.ModuleInfo info = ModuleDetectionService.givingModule();

            Assert.areEqual(
                '/lightning/app/c__BarnCRM_Volunteers',
                info.appUrl,
                'Volunteers ships no app yet, so its link uses the name form'
            );
        }
    }

    @IsTest
    static void aModuleIsNonprofitOnlyWhenItsEditionsLeaveOutTheStandardEdition() {
        System.runAs(TestUsers.admin()) {
            SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>();
            ModuleDetectionService.givingPresentOverride = false;
            ModuleDetectionService.catalogOverride = new List<BarnCRM_Module__mdt>{
                catalogRow('Giving', 'Impact', null, 10),
                catalogRow('Events', 'Community; Impact', null, 5),
                catalogRow('Mailings', 'impact', null, 6),
                catalogRow('Everywhere', 'Community', null, 7)
            };
            chooseSuite(ModuleDetectionService.SUITE_IMPACT);

            Test.startTest();
            Map<String, ModuleDetectionService.ModuleInfo> modules = byName();
            // A Standard-only module is not listed while the Nonprofit Edition is chosen, so it is
            // checked on its row.
            Boolean standardOnly = ModuleDetectionService.isNonprofitOnly(
                catalogRow('Everywhere', 'Community', null, 7)
            );
            Boolean blank = ModuleDetectionService.isNonprofitOnly(catalogRow('X', null, null, 1));
            Boolean missing = ModuleDetectionService.isNonprofitOnly(null);
            Test.stopTest();

            Assert.isFalse(modules.get('Core').nonprofitOnly, 'Core is offered by every edition');
            Assert.isTrue(modules.get('Giving').nonprofitOnly, 'Only the Nonprofit Edition');
            Assert.isTrue(
                modules.get('Mailings').nonprofitOnly,
                'The edition value is not case sensitive'
            );
            Assert.isFalse(modules.get('Events').nonprofitOnly, 'Both editions offer it');
            Assert.isFalse(
                modules.containsKey('Everywhere'),
                'Not offered by the Nonprofit Edition'
            );
            Assert.isFalse(standardOnly, 'The Standard Edition offers it');
            Assert.isFalse(blank, 'A row that names no edition is not nonprofit only');
            Assert.isFalse(missing, 'No row is not nonprofit only');
        }
    }

    @IsTest
    static void aModuleBothEditionsOfferNeedsOnlyACatalogRow() {
        System.runAs(TestUsers.admin()) {
            SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>();
            ModuleDetectionService.givingPresentOverride = false;
            ModuleDetectionService.catalogOverride = new List<BarnCRM_Module__mdt>{
                catalogRow('Giving', 'Impact', null, 10),
                catalogRow('Events', 'Community; Impact', null, 5)
            };
            chooseSuite(ModuleDetectionService.SUITE_COMMUNITY);

            Test.startTest();
            List<String> names = new List<String>();
            for (ModuleDetectionService.ModuleInfo module : ModuleDetectionService.getModules()) {
                names.add(module.name);
            }
            Boolean eventsOffered = ModuleDetectionService.isOffered('Events');
            Boolean givingOffered = ModuleDetectionService.isOffered('Giving');
            Test.stopTest();

            Assert.areEqual(
                new List<String>{ 'Core', 'Events' },
                names,
                'The Standard Edition lists the module its row names, in Sort Order, and not Giving'
            );
            Assert.isTrue(eventsOffered, 'Offered to the Standard Edition');
            Assert.isFalse(givingOffered, 'Giving is for the Nonprofit Edition only');
        }
    }

    @IsTest
    static void shipsANonprofitOnlyRowForEveryKnownModule() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            Map<String, BarnCRM_Module__mdt> shipped = BarnCRM_Module__mdt.getAll();
            Test.stopTest();

            List<String> modules = new List<String>{
                'Giving',
                'Volunteers',
                'Programs',
                'Funders',
                'Mirror'
            };
            for (String name : modules) {
                Assert.isTrue(shipped.containsKey(name), name + ' has a catalog row');
                Assert.areEqual(
                    'Impact',
                    shipped.get(name).Editions__c,
                    name + ' is nonprofit only'
                );
            }
            Assert.isTrue(
                ModuleDetectionService.offeredIn(
                    shipped.get('Rollups'),
                    ModuleDetectionService.SUITE_COMMUNITY
                ) &&
                ModuleDetectionService.offeredIn(
                    shipped.get('Rollups'),
                    ModuleDetectionService.SUITE_IMPACT
                ),
                'BarnCRM Rollup Builder is offered to both editions'
            );
            BarnCRM_Module__mdt rollups = shipped.get('Rollups');
            Assert.areEqual('rollups', rollups.Package_Folder__c, 'Its own package folder');
            Assert.isNull(rollups.App_Name__c, 'No app of its own: its tool is in the admin apps');
            Assert.areEqual('Rollup_Builder', rollups.Admin_Tabs__c, 'The Rollup Builder tab');
            Assert.areEqual(5, rollups.Sort_Order__c.intValue(), 'Listed before Giving');
            Assert.areEqual('Rollups', shipped.get('Giving').Requires__c, 'Giving needs it');
            BarnCRM_Module__mdt volunteers = shipped.get('Volunteers');
            Assert.areEqual('Rollups', volunteers.Requires__c, 'Volunteers needs it too');
            Assert.areEqual('BarnCRM_Volunteers', volunteers.App_Name__c, 'Its own app');
            Assert.areEqual(
                'Volunteer_Shift__c;Volunteer_Hours__c',
                volunteers.Staff_Tabs__c,
                'Its everyday tabs for the BarnCRM apps'
            );
            Assert.areEqual('Volunteer_Hours__c', volunteers.Probe_Object__c, 'Its probe object');
        }
    }

    @IsTest
    static void saysWhichModulesToInstallFirst() {
        System.runAs(TestUsers.admin()) {
            SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>();
            ModuleDetectionService.givingPresentOverride = false;
            BarnCRM_Module__mdt rollups = catalogRow('Rollups', 'Community;Impact', null, 5);
            rollups.MasterLabel = 'BarnCRM Rollup Builder';
            rollups.Probe_Object__c = 'No_Such_Object__c';
            BarnCRM_Module__mdt giving = catalogRow('Giving', 'Impact', null, 10);
            giving.MasterLabel = 'BarnCRM Giving';
            giving.Requires__c = 'Rollups';
            BarnCRM_Module__mdt funders = catalogRow('Funders', 'Impact', null, 40);
            funders.Requires__c = 'Rollups; Giving;Elsewhere';
            BarnCRM_Module__mdt programs = catalogRow('Programs', 'Impact', null, 30);
            ModuleDetectionService.catalogOverride = new List<BarnCRM_Module__mdt>{
                rollups,
                giving,
                funders,
                programs
            };
            chooseSuite(ModuleDetectionService.SUITE_IMPACT);

            Test.startTest();
            Map<String, ModuleDetectionService.ModuleInfo> before = byName();
            // Core's own object stands in for the Rollup Builder's, so it counts as installed.
            rollups.Probe_Object__c = 'Error_Log__c';
            Map<String, ModuleDetectionService.ModuleInfo> after = byName();
            Test.stopTest();

            Assert.areEqual(
                'BarnCRM Rollup Builder',
                before.get('Giving').installFirst,
                'Giving says to install the Rollup Builder first'
            );
            Assert.areEqual(
                'BarnCRM Rollup Builder, BarnCRM Giving, Elsewhere',
                before.get('Funders').installFirst,
                'Every missing module, in install order, by name shown'
            );
            Assert.isNull(before.get('Programs').installFirst, 'A module needing none says none');
            Assert.isNull(
                after.get('Giving').installFirst,
                'Once the Rollup Builder is installed Giving needs nothing first'
            );
            Assert.areEqual(
                'BarnCRM Giving, Elsewhere',
                after.get('Funders').installFirst,
                'Only what is still missing'
            );
            Assert.isNull(after.get('Rollups').installFirst, 'An installed module needs nothing');
        }
    }

    private static Map<String, ModuleDetectionService.ModuleInfo> byName() {
        Map<String, ModuleDetectionService.ModuleInfo> modules = new Map<String, ModuleDetectionService.ModuleInfo>();
        for (ModuleDetectionService.ModuleInfo module : ModuleDetectionService.getModules()) {
            modules.put(module.name, module);
        }
        return modules;
    }

    private static BarnCRM_Module__mdt catalogRow(
        String name,
        String editions,
        String versionId,
        Integer sortOrder
    ) {
        return new BarnCRM_Module__mdt(
            DeveloperName = name,
            Editions__c = editions,
            Package_Folder__c = name.toLowerCase(),
            Install_Version_Id__c = versionId,
            Sort_Order__c = sortOrder
        );
    }

    /**
     * The modules other than Core, Rollup Builder and Giving whose probe object is in this org.
     * Detection lists an installed module in any edition, so a test that expects a short list
     * adds these to it and holds whether or not such a package is installed beside Core.
     */
    private static Set<String> installedModules() {
        Set<String> names = new Set<String>();
        for (BarnCRM_Module__mdt row : BarnCRM_Module__mdt.getAll().values()) {
            if (
                row.DeveloperName != 'Rollups' &&
                row.DeveloperName != 'Giving' &&
                String.isNotBlank(row.Probe_Object__c) &&
                ModuleDetectionService.resolveObject(row.Probe_Object__c.trim()) != null
            ) {
                names.add(row.DeveloperName);
            }
        }
        return names;
    }

    /** The expected modules first, then exactly the installed ones this org also has. */
    private static void assertListed(List<String> expected, List<String> actual, String message) {
        Assert.areEqual(expected.size() + installedModules().size(), actual.size(), message);
        for (Integer i = 0; i < expected.size(); i++) {
            Assert.areEqual(expected[i], actual[i], message);
        }
        Set<String> rest = new Set<String>(actual);
        rest.removeAll(new Set<String>(expected));
        Assert.areEqual(installedModules(), rest, message);
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
