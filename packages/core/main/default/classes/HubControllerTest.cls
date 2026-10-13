/**
 * Maria lands on the Hub home page and is told what to do next. David, without the
 * Manage BarnCRM Settings permission, sees the same page and cannot change anything.
 * Finishing a step belongs to the Setup Assistant's own controller.
 */
@IsTest
private class HubControllerTest {
    @TestSetup
    static void grantPermission() {
        System.runAs(TestUsers.admin()) {
            SettingsTestPermissions.grantTo('C03_Hub_Home_Test', UserInfo.getUserId());
        }
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
        System.runAs(TestUsers.admin()) {
            SetupAssistantTestExtension.useNone();

            Test.startTest();
            HubController.HomeModel model = HubController.getHomeModel();
            Test.stopTest();

            Assert.areEqual(8, model.stepsTotal, 'On Core alone the checklist has eight steps');
            Assert.isNotNull(model.stepsCompleted, 'The page says how many are done');
            Assert.isFalse(model.automationPaused, 'Nothing is paused on a fresh org');
            Assert.areEqual(0, model.newErrorCount, 'A fresh org has nothing to review');
            Assert.isFalse(model.newErrorCountCapped, 'Zero is an exact count');
        }
    }

    @IsTest
    static void aFloodedErrorLogShowsTheCapAndSaysThereAreMore() {
        System.runAs(TestUsers.admin()) {
            SetupAssistantTestExtension.useNone();
            List<Error_Log__c> errors = new List<Error_Log__c>();
            for (Integer i = 0; i < 3; i++) {
                errors.add(
                    new Error_Log__c(
                        Timestamp__c = System.now(),
                        Context__c = 'Hub test',
                        Message__c = 'Something went wrong.',
                        Severity__c = 'Error',
                        Status__c = 'New'
                    )
                );
            }
            insert errors;
            HubController.errorCountCap = 2;
            User maria = HealthCheckTestHelper.mariaWithManageSettings();

            System.runAs(maria) {
                HubController.HomeModel model = HubController.getHomeModel();
                Assert.areEqual(2, model.newErrorCount, 'The tile shows the cap');
                Assert.isTrue(model.newErrorCountCapped, 'and says there are more than that');
                Assert.areEqual(
                    0,
                    model.installProblemCount,
                    'Errors from elsewhere are not install problems, and the count arrives in the same model'
                );
            }

        }
    }

    @IsTest
    static void letsDavidReadTheHomePageWithoutChangingAnything() {
        System.runAs(TestUsers.admin()) {
            SetupAssistantTestExtension.useNone();
            User david = buildDavid();
            System.runAs(new User(Id = UserInfo.getUserId())) {
                insert david;
            }

            Test.startTest();
            System.runAs(david) {
                HubController.HomeModel model = HubController.getHomeModel();
                Assert.isFalse(model.canEdit, 'David may not change anything');
                Assert.areEqual(
                    0,
                    model.stepsTotal,
                    'The checklist is hidden from David, so its steps are not worked out for him'
                );
                Assert.areEqual(0, model.newErrorCount, 'Nor is the administrator error count');
                Assert.isNull(model.installProblemCount, 'Nor the install problem count');
                Assert.isFalse(model.rollupsStale, 'The admin tiles read as quiet, not broken');
                Assert.isFalse(model.seasonalAddressStale, 'Both of them');
                Assert.isNotNull(model.recurringSources, 'What staff do see still arrives');
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void listsTheFilesThatArriveRegularly() {
        System.runAs(TestUsers.admin()) {
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
}
