/**
 * Maria lands on the Hub home page and is told what to do next. David, without the
 * Manage Nonprofit Settings permission, sees the same page and cannot change anything.
 * Finishing a step belongs to the Setup Assistant's own controller.
 */
@IsTest
private class HubControllerTest {
    @TestSetup
    static void grantPermission() {
        SettingsTestPermissions.grantTo('C03_Hub_Home_Test', UserInfo.getUserId());
    }

    private static User buildDavid() {
        Profile standard = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        return new User(
            FirstName = 'David',
            LastName = 'Okonkwo',
            Alias = 'davidh',
            Email = 'david.hub@example.com',
            Username = 'david.hub.' + DateTime.now().getTime() + '@example.com',
            ProfileId = standard.Id,
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
    }

    @IsTest
    static void tellsMariaWhatToDoNext() {
        SetupAssistantTestExtension.useNone();

        Test.startTest();
        HubController.HomeModel model = HubController.getHomeModel();
        Test.stopTest();

        Assert.areEqual(7, model.stepsTotal, 'On Core alone the checklist has seven steps');
        Assert.isNotNull(model.stepsCompleted, 'The page says how many are done');
        Assert.isFalse(model.automationPaused, 'Nothing is paused on a fresh org');
        Assert.areEqual(0, model.newErrorCount, 'A fresh org has nothing to review');
    }

    @IsTest
    static void letsDavidReadTheHomePageWithoutChangingAnything() {
        SetupAssistantTestExtension.useNone();
        User david = buildDavid();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert david;
        }

        Test.startTest();
        System.runAs(david) {
            HubController.HomeModel model = HubController.getHomeModel();
            Assert.areEqual(7, model.stepsTotal, 'David sees the same seven steps counted');
            Assert.isFalse(model.canEdit, 'David may not change anything');
        }
        Test.stopTest();
    }

    @IsTest
    static void listsTheFilesThatArriveRegularly() {
        TestDataFactory.defaultSettings();
        Import_Template__c template = ImportTestDataFactory.template(
            ImportTestDataFactory.donorMapping(),
            ImportTemplateService.RULE_EMAIL
        );
        ImportTemplateService.saveRecurring(template.Id, true, 'Monthly processor export');

        Test.startTest();
        HubController.HomeModel model = HubController.getHomeModel();
        Test.stopTest();

        Assert.areEqual(1, model.recurringSources.size(), 'The recurring source is listed.');
        Assert.areEqual(
            'Monthly processor export',
            model.recurringSources[0].sourceName,
            'By the name Maria gave it.'
        );
        Assert.isNull(model.recurringSources[0].lastImportDate, 'Never imported yet.');
    }
}
