/**
 * The Integrations page's Apex surface: it returns the list, and says plainly when it cannot.
 */
@IsTest(testFor='ApexClass:IntegrationController')
private class IntegrationControllerTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    @IsTest
    static void theListComesBackWithWhatTheCatalogHolds() {
        System.runAs(TestUsers.admin()) {
            IntegrationAppService.catalogOverride = new List<Integration_App__mdt>{
                new Integration_App__mdt(
                    DeveloperName = 'One',
                    MasterLabel = 'One',
                    Category__c = 'Complement',
                    Description__c = 'x',
                    Link_Url__c = 'https://example.invalid',
                    Compatibility__c = 'x'
                )
            };
            IntegrationAppService.objectNamesOverride = new Set<String>();

            Test.startTest();
            List<IntegrationAppService.AppInfo> apps = IntegrationController.getApps();
            Test.stopTest();

            Assert.areEqual(1, apps.size(), 'The one product is listed');
            Assert.areEqual('One', apps[0].key, 'By its key');
        }
    }

    @IsTest
    static void aFailureReadingTheListIsLoggedAndSaidInPlainWords() {
        System.runAs(TestUsers.admin()) {
            // A row the service cannot read: a null row in the catalog.
            IntegrationAppService.catalogOverride = new List<Integration_App__mdt>{ null };

            Test.startTest();
            String message;
            try {
                IntegrationController.getApps();
            } catch (AuraHandledException e) {
                message = e.getMessage();
            }
            Test.stopTest();

            Assert.areEqual(
                System.Label.Core_Integrations_LoadErrorMessage,
                message,
                'The page gets the label, not a stack trace'
            );
        }
    }
}
