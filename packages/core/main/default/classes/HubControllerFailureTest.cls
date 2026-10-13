/**
 * What the BarnCRM home page does when it cannot be built: the page gets a readable message
 * rather than an unexplained error. The optional tiles
 * are covered by HubControllerTest.
 */
@IsTest(testFor='ApexClass:HubController')
private class HubControllerFailureTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    /** A module whose step is malformed, so that reading the checklist throws. */
    private class BrokenModule implements SetupAssistantExtension {
        public List<SetupAssistantService.Step> contributions() {
            SetupAssistantService.Step broken = new SetupAssistantService.Step(
                'brokenmodule',
                25,
                'A step with no fields list',
                'Reading this step fails.'
            );
            broken.fields = null;
            return new List<SetupAssistantService.Step>{ broken };
        }
    }

    @IsTest
    static void aChecklistThatCannotBeReadGivesThePageAReadableMessage() {
        System.runAs(TestUsers.admin()) {
            SetupAssistantExtensions.overrides = new List<SetupAssistantExtension>{
                new BrokenModule()
            };
            String message;
            HubController.HomeModel model;

            Test.startTest();
            try {
                model = HubController.getHomeModel();
            } catch (AuraHandledException failure) {
                message = failure.getMessage();
            }
            Test.stopTest();

            Assert.isNull(model, 'No half built page is handed back');
            Assert.areEqual(
                System.Label.Core_HubHome_LoadErrorMessage,
                message,
                'The page is told what happened in the words the label gives'
            );
        }
    }

    @IsTest
    static void aRepeatCallAfterTheFaultIsFixedBuildsThePage() {
        System.runAs(TestUsers.admin()) {
            SetupAssistantExtensions.overrides = new List<SetupAssistantExtension>{
                new BrokenModule()
            };
            try {
                HubController.getHomeModel();
                Assert.fail('The broken module should have stopped the page');
            } catch (AuraHandledException expected) {
                Assert.isNotNull(expected.getMessage(), 'The first call fails readably');
            }

            SetupAssistantTestExtension.useNone();
            HubController.HomeModel model = HubController.getHomeModel();

            Assert.areEqual(
                8,
                model.stepsTotal,
                'Once the module is gone Core\'s eight steps show'
            );
        }
    }
}
