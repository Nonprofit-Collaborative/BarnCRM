/**
 * The Integrations page's list: which other products the catalog names, and whether each one's
 * objects are in the org. The org's objects are injected, so no test depends on what happens to
 * be installed where it runs.
 */
@IsTest(testFor='ApexClass:IntegrationAppService')
private class IntegrationAppServiceTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static Integration_App__mdt product(
        String name,
        String category,
        String detection,
        Decimal order
    ) {
        return new Integration_App__mdt(
            DeveloperName = name,
            MasterLabel = name.replace('_', ' '),
            Category__c = category,
            Description__c = 'What ' + name + ' does',
            Maintainer__c = 'A maintainer',
            License_Cost__c = 'Free',
            Link_Url__c = 'https://example.invalid/' + name,
            Compatibility__c = 'Not tested',
            Detection_Objects__c = detection,
            Sort_Order__c = order
        );
    }

    /** A packaged object's key in the global describe: lower case, joined by two underscores. */
    private static String named(String prefix, String objectName) {
        return (prefix + '__' + objectName).toLowerCase();
    }

    private static AppInfoLookup listed() {
        return new AppInfoLookup(IntegrationAppService.getApps());
    }

    /** The list, found by key. */
    private class AppInfoLookup {
        private final Map<String, IntegrationAppService.AppInfo> byKey = new Map<String, IntegrationAppService.AppInfo>();
        private final List<IntegrationAppService.AppInfo> all;

        private AppInfoLookup(List<IntegrationAppService.AppInfo> apps) {
            this.all = apps;
            for (IntegrationAppService.AppInfo info : apps) {
                byKey.put(info.key, info);
            }
        }

        private IntegrationAppService.AppInfo get(String key) {
            return byKey.get(key);
        }
    }

    @IsTest
    static void aProductIsInstalledWhenOneOfItsObjectsIsInTheOrg() {
        System.runAs(TestUsers.admin()) {
            IntegrationAppService.catalogOverride = new List<Integration_App__mdt>{
                product('Packaged', 'Complement', 'acme.Thing__c', 1),
                product('Plain', 'Complement', 'Plain_Thing__c', 2),
                product('Either', 'Complement', 'nope.One__c;acme.Two__c', 3),
                product('Absent', 'Complement', 'nope.One__c', 4),
                product('Unknowable', 'Complement', null, 5)
            };
            IntegrationAppService.objectNamesOverride = new Set<String>{
                named('acme', 'Thing__c'),
                'plain_thing__c',
                named('acme', 'Two__c')
            };

            Test.startTest();
            AppInfoLookup apps = listed();
            Test.stopTest();

            Assert.isTrue(
                apps.get('Packaged').installed,
                'A packaged object is found by its prefix'
            );
            Assert.isTrue(apps.get('Plain').installed, 'An unpackaged object is found by its name');
            Assert.isTrue(apps.get('Either').installed, 'Any one of the objects is enough');
            Assert.isFalse(apps.get('Absent').installed, 'No object here means not installed');
            Assert.isFalse(
                apps.get('Unknowable').installed,
                'A row naming no object cannot be told'
            );
        }
    }

    @IsTest
    static void aProductMarkedShowOnlyWhenInstalledIsListedOnlyWhenItIs() {
        System.runAs(TestUsers.admin()) {
            Integration_App__mdt overlap = product('Overlap', 'Alternative', 'acme.Job__c', 1);
            overlap.Show_Only_When_Installed__c = true;
            IntegrationAppService.catalogOverride = new List<Integration_App__mdt>{
                overlap,
                product('Always', 'Complement', 'acme.Other__c', 2)
            };

            IntegrationAppService.objectNamesOverride = new Set<String>();
            Test.startTest();
            AppInfoLookup absent = listed();
            IntegrationAppService.objectNamesOverride = new Set<String>{ named('acme', 'Job__c') };
            AppInfoLookup present = listed();
            Test.stopTest();

            Assert.isNull(absent.get('Overlap'), 'Not installed, so it is not mentioned');
            Assert.isNotNull(absent.get('Always'), 'A product without the mark is always listed');
            Assert.isFalse(absent.get('Always').installed, 'It says Not installed');
            Assert.isNotNull(present.get('Overlap'), 'Installed, so it is listed');
            Assert.isTrue(present.get('Overlap').installed, 'And says Installed');
        }
    }

    @IsTest
    static void theListIsInSortOrderAndAnUnknownCategoryIsAComplement() {
        System.runAs(TestUsers.admin()) {
            IntegrationAppService.catalogOverride = new List<Integration_App__mdt>{
                product('Third', 'InDevelopment', null, 30),
                product('First', 'alternative', null, 10),
                product('Second', 'Something_else', null, 20),
                product('Blank', null, null, 40),
                product('Last', 'Complement', null, null)
            };
            IntegrationAppService.objectNamesOverride = new Set<String>();

            Test.startTest();
            AppInfoLookup apps = listed();
            Test.stopTest();

            Assert.areEqual('First', apps.all[0].key, 'Lowest Sort Order first');
            Assert.areEqual('Last', apps.all[4].key, 'A row with no Sort Order comes last');
            Assert.areEqual(
                IntegrationAppService.CATEGORY_ALTERNATIVE,
                apps.get('First').category,
                'The category is matched without regard to case'
            );
            Assert.areEqual(
                IntegrationAppService.CATEGORY_COMPLEMENT,
                apps.get('Second').category,
                'An unknown category is a complement'
            );
            Assert.areEqual(
                IntegrationAppService.CATEGORY_COMPLEMENT,
                apps.get('Blank').category,
                'A blank category is a complement'
            );
            Assert.areEqual(
                IntegrationAppService.CATEGORY_IN_DEVELOPMENT,
                apps.get('Third').category,
                'In development is kept'
            );
        }
    }

    @IsTest
    static void aRowCarriesItsTextAndLinksToThePage() {
        System.runAs(TestUsers.admin()) {
            Integration_App__mdt row = product('Carrier', 'Complement', null, 1);
            row.Install_Url__c = 'https://example.invalid/install';
            row.Related_Module__c = 'BarnCRM Something';
            row.Migration_Path__c = 'Later';
            IntegrationAppService.catalogOverride = new List<Integration_App__mdt>{ row };

            Test.startTest();
            IntegrationAppService.AppInfo info = IntegrationAppService.getApps()[0];
            Test.stopTest();

            Assert.areEqual('Carrier', info.name, 'The label is the name shown');
            Assert.areEqual('A maintainer', info.maintainer, 'Maintainer');
            Assert.areEqual('Free', info.licenseCost, 'Cost and license');
            Assert.areEqual('https://example.invalid/Carrier', info.linkUrl, 'Link');
            Assert.areEqual('https://example.invalid/install', info.installUrl, 'Install link');
            Assert.areEqual('BarnCRM Something', info.relatedModule, 'Related module');
            Assert.areEqual('Not tested', info.compatibility, 'Compatibility note');
            Assert.areEqual('Later', info.migrationPath, 'Migration path');
        }
    }

    @IsTest
    static void everyProductIsInProgressUnlessItsRowSaysAvailable() {
        System.runAs(TestUsers.admin()) {
            Integration_App__mdt done = product('Done', 'Complement', null, 1);
            done.Status__c = 'Available';
            Integration_App__mdt planned = product('Planned', 'Complement', null, 2);
            planned.Status__c = 'InProgress';
            Integration_App__mdt blank = product('Blank', 'Complement', null, 3);
            Integration_App__mdt odd = product('Odd', 'Complement', null, 4);
            odd.Status__c = 'Whatever';
            IntegrationAppService.catalogOverride = new List<Integration_App__mdt>{
                done,
                planned,
                blank,
                odd
            };
            IntegrationAppService.objectNamesOverride = new Set<String>();

            Test.startTest();
            AppInfoLookup apps = listed();
            Test.stopTest();

            Assert.areEqual(
                IntegrationAppService.STATUS_AVAILABLE,
                apps.get('Done').status,
                'Available'
            );
            Assert.areEqual(
                IntegrationAppService.STATUS_IN_PROGRESS,
                apps.get('Planned').status,
                'In progress'
            );
            Assert.areEqual(
                IntegrationAppService.STATUS_IN_PROGRESS,
                apps.get('Blank').status,
                'Blank is in progress'
            );
            Assert.areEqual(
                IntegrationAppService.STATUS_IN_PROGRESS,
                apps.get('Odd').status,
                'Unknown is in progress'
            );
        }
    }

    @IsTest
    static void theShippedCatalogIsAllInProgress() {
        System.runAs(TestUsers.admin()) {
            IntegrationAppService.objectNamesOverride = new Set<String>();

            Test.startTest();
            AppInfoLookup apps = listed();
            Test.stopTest();

            Assert.isFalse(apps.all.isEmpty(), 'The catalog ships products');
            for (IntegrationAppService.AppInfo info : apps.all) {
                Assert.areEqual(
                    IntegrationAppService.STATUS_IN_PROGRESS,
                    info.status,
                    'No integration is built yet: ' + info.name
                );
            }
        }
    }

    @IsTest
    static void theShippedCatalogHidesProductsThatMatchAModuleUntilTheyAreInstalled() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            IntegrationAppService.objectNamesOverride = new Set<String>();
            AppInfoLookup none = listed();
            IntegrationAppService.objectNamesOverride = new Set<String>{
                named('GW_Volunteers', 'Volunteers_Settings__c'),
                named('summit', 'Summit_Events__c')
            };
            AppInfoLookup some = listed();
            Test.stopTest();

            for (IntegrationAppService.AppInfo info : none.all) {
                Assert.areNotEqual(
                    IntegrationAppService.CATEGORY_ALTERNATIVE,
                    info.category,
                    'No alternative to a BarnCRM module is listed when none is installed'
                );
                Assert.isFalse(info.installed, 'Nothing is installed: ' + info.name);
            }
            Assert.isNotNull(none.get('Summit_Events_App'), 'A complement is listed either way');
            Assert.isNotNull(none.get('Memberships_Essentials'), 'So is one in development');
            Assert.isNull(
                none.get('Volunteers_for_Salesforce'),
                'Volunteers for Salesforce is hidden'
            );
            Assert.isNotNull(some.get('Volunteers_for_Salesforce'), 'It is listed once installed');
            Assert.isTrue(some.get('Volunteers_for_Salesforce').installed, 'And says Installed');
            Assert.isTrue(some.get('Summit_Events_App').installed, 'Summit is detected');
            Assert.isNull(some.get('Program_Management_Module'), 'The others stay hidden');
        }
    }

    @IsTest
    static void theOrgsObjectsAreReadFromTheRealDescribeWhenNothingIsInjected() {
        System.runAs(TestUsers.admin()) {
            IntegrationAppService.catalogOverride = new List<Integration_App__mdt>{
                product('Real', 'Complement', 'Account', 1),
                product('Missing', 'Complement', 'zzz.Not_Here__c', 2)
            };

            Test.startTest();
            AppInfoLookup apps = listed();
            Test.stopTest();

            Assert.isTrue(apps.get('Real').installed, 'An object the org has is found by describe');
            Assert.isFalse(apps.get('Missing').installed, 'One it does not have is not');
        }
    }
}
