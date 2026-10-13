/**
 * The configuration every save reads costs no SOQL query, because the platform already caches
 * it across transactions: the automation registry and the Setting Definition rows through
 * custom metadata `getAll()`, and Core's settings through `getOrgDefaults()`. That is why Core
 * ships no Platform Cache partition (ADR-0094). These tests read with
 * no test override, so they see the shipped rows and measure the real cost.
 */
@IsTest(
    testFor='ApexClass:AutomationRegistrySelector, ApexClass:SettingDefinitionSelector, ApexClass:SettingsService'
)
private class ConfigReadBudgetTest {
    private static final String STAFF = 'BarnCRM_Staff';

    @TestSetup
    static void createTestUsers() {
        TestUsers.withPermissionSets(new List<String>{ STAFF });
        TestUsers.admin();
    }

    @IsTest
    static void dispatcherRegistryReadCostsNoQuery() {
        System.runAs(TestUsers.withPermissionSets(new List<String>{ STAFF })) {
            AutomationRegistrySelector.clearCache();

            Test.startTest();
            Integer before = Limits.getQueries();
            List<Automation_Registry__mdt> forContact = AutomationRegistrySelector.selectForObject(
                'Contact'
            );
            AutomationRegistrySelector.selectForObject('Account');
            AutomationRegistrySelector.selectForFramework();
            Integer used = Limits.getQueries() - before;
            Test.stopTest();

            Assert.areEqual(0, used, 'The trigger framework reads the registry without a query');
            Assert.isFalse(forContact.isEmpty(), 'Core ships automations on Contact');
        }
    }

    @IsTest
    static void frameworkRegistryMatchesTheQueriedRegistry() {
        System.runAs(TestUsers.admin()) {
            AutomationRegistrySelector.clearCache();

            Test.startTest();
            List<Automation_Registry__mdt> queried = AutomationRegistrySelector.selectAll();
            List<Automation_Registry__mdt> framework = AutomationRegistrySelector.selectForFramework();
            Test.stopTest();

            Assert.areEqual(
                namesOf(queried),
                namesOf(framework),
                'The free read returns the same rows as the counted query'
            );
            Map<String, Automation_Registry__mdt> frameworkByName = new Map<String, Automation_Registry__mdt>();
            for (Automation_Registry__mdt entry : framework) {
                frameworkByName.put(entry.DeveloperName, entry);
            }
            for (Automation_Registry__mdt entry : queried) {
                Automation_Registry__mdt free = frameworkByName.get(entry.DeveloperName);
                Assert.areEqual(entry.Object_Name__c, free.Object_Name__c, 'Same object');
                Assert.areEqual(entry.Handler_Class__c, free.Handler_Class__c, 'Same handler');
                Assert.areEqual(entry.Module__c, free.Module__c, 'Same module');
                Assert.areEqual(entry.Always_Runs__c, free.Always_Runs__c, 'Same always runs');
                Assert.areEqual(
                    entry.Execution_Order__c,
                    free.Execution_Order__c,
                    'Same execution order'
                );
            }
        }
    }

    @IsTest
    static void dispatcherKeepsExecutionOrderFromTheUnorderedRead() {
        System.runAs(TestUsers.admin()) {
            AutomationRegistrySelector.clearCache();

            Test.startTest();
            List<Automation_Registry__mdt> forContact = AutomationRegistrySelector.selectForObject(
                'Contact'
            );
            Test.stopTest();

            for (Integer i = 1; i < forContact.size(); i++) {
                Assert.isTrue(
                    orderOf(forContact[i - 1]) <= orderOf(forContact[i]),
                    'Automations run in execution order whatever order getAll() returns'
                );
            }
        }
    }

    @IsTest
    static void testOverrideStillWins() {
        System.runAs(TestUsers.admin()) {
            AutomationRegistrySelector.registryOverride = new List<Automation_Registry__mdt>();
            AutomationRegistrySelector.clearCache();

            Test.startTest();
            List<Automation_Registry__mdt> framework = AutomationRegistrySelector.selectForFramework();
            List<Automation_Registry__mdt> forContact = AutomationRegistrySelector.selectForObject(
                'Contact'
            );
            Test.stopTest();

            Assert.isTrue(framework.isEmpty(), 'A test override replaces the shipped rows');
            Assert.isTrue(forContact.isEmpty(), 'The dispatcher sees the override too');
        }
    }

    @IsTest
    static void settingDefinitionShortReadCostsNoQuery() {
        System.runAs(TestUsers.withPermissionSets(new List<String>{ STAFF })) {
            Test.startTest();
            Integer before = Limits.getQueries();
            List<Setting_Definition__mdt> rows = SettingDefinitionSelector.getAllShortFields();
            Integer used = Limits.getQueries() - before;
            List<Setting_Definition__mdt> queried = SettingDefinitionSelector.getAll();
            Test.stopTest();

            Assert.areEqual(0, used, 'The settings object check reads the rows without a query');
            Set<String> freeNames = new Set<String>();
            for (Setting_Definition__mdt row : rows) {
                freeNames.add(row.DeveloperName + '|' + row.Settings_Object__c);
            }
            Set<String> queriedNames = new Set<String>();
            for (Setting_Definition__mdt row : queried) {
                queriedNames.add(row.DeveloperName + '|' + row.Settings_Object__c);
            }
            Assert.areEqual(queriedNames, freeNames, 'The free read returns the same rows');
        }
    }

    @IsTest
    static void settingDefinitionShortReadHonoursTestRows() {
        System.runAs(TestUsers.admin()) {
            SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>();

            Test.startTest();
            List<Setting_Definition__mdt> rows = SettingDefinitionSelector.getAllShortFields();
            Test.stopTest();

            Assert.isTrue(rows.isEmpty(), 'Rows a test supplies replace the shipped ones');
        }
    }

    @IsTest
    static void coreSettingsReadCostsNoQueryAndSeesAWriteAtOnce() {
        System.runAs(TestUsers.admin()) {
            SettingsService.clearCaches();

            Test.startTest();
            Integer before = Limits.getQueries();
            SettingsService.getSettings();
            SettingsService.clearCaches();
            SettingsService.getSettings();
            Integer used = Limits.getQueries() - before;

            BarnCRM_Settings__c saved = SettingsService.firstSaveRecord();
            saved.Household_Name_Pattern__c = 'Budget test household';
            Database.upsert(saved, AccessLevel.SYSTEM_MODE);
            SettingsService.clearCaches();
            BarnCRM_Settings__c reread = SettingsService.getSettings();
            Test.stopTest();

            Assert.areEqual(0, used, 'Core settings come from the platform cache, not a query');
            Assert.areEqual(
                'Budget test household',
                reread.Household_Name_Pattern__c,
                'With no cross-transaction copy of our own, a read after a save is never stale'
            );
        }
    }

    private static Set<String> namesOf(List<Automation_Registry__mdt> entries) {
        Set<String> names = new Set<String>();
        for (Automation_Registry__mdt entry : entries) {
            names.add(entry.DeveloperName);
        }
        return names;
    }

    private static Decimal orderOf(Automation_Registry__mdt entry) {
        return entry.Execution_Order__c == null ? 999999 : entry.Execution_Order__c;
    }
}
