/**
 * Maria finishes first-run setup: the edition and the features she ticked, in one step. David,
 * without Manage BarnCRM Settings, sees the window but cannot finish it (ADR-NEXT).
 */
@IsTest(testFor='ApexClass:FirstRunController')
private class FirstRunControllerTest {
    @TestSetup
    static void createTestUsers() {
        System.runAs(TestUsers.admin()) {
            TestUsers.standardUserWith('Adeyemi', new List<String>{ 'BarnCRM_Read_Only' });
        }
    }

    private static User david() {
        return [
            SELECT Id
            FROM User
            WHERE LastName = 'Adeyemi'
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
    }

    @IsTest
    static void aNewInstallNeedsSetupAndOffersEveryFeature() {
        System.runAs(TestUsers.admin()) {
            FeatureSwitchService.markNewInstall();

            Test.startTest();
            FirstRunController.FirstRunState state = FirstRunController.getState();
            Test.stopTest();

            Assert.isTrue(state.needsSetup, 'No edition is saved yet');
            Assert.isTrue(state.canFinish, 'Maria may finish it');
            Assert.isNotNull(state.recommendedSuite, 'An edition is suggested');
            Assert.areEqual(8, state.features.size(), 'Every feature is offered');
        }
    }

    @IsTest
    static void mariaFinishesWithTheFeaturesSheTicked() {
        System.runAs(TestUsers.admin()) {
            FeatureSwitchService.markNewInstall();

            Test.startTest();
            FirstRunController.FirstRunState state = FirstRunController.finish(
                ModuleDetectionService.SUITE_COMMUNITY,
                new List<String>{
                    FeatureSwitchService.DATA_MANAGER,
                    FeatureSwitchService.RELATIONSHIPS
                }
            );
            Test.stopTest();

            Assert.isFalse(state.needsSetup, 'The window does not show again');
            Assert.areEqual(
                ModuleDetectionService.SUITE_COMMUNITY,
                ModuleDetectionService.chosenSuite(),
                'The edition is saved'
            );
            Assert.isTrue(
                FeatureSwitchService.isOn(FeatureSwitchService.DATA_MANAGER),
                'A ticked feature is on'
            );
            Assert.isTrue(
                FeatureSwitchService.isOn(FeatureSwitchService.RELATIONSHIPS),
                'So is the other'
            );
            Assert.isFalse(
                FeatureSwitchService.isOn(FeatureSwitchService.AFFILIATIONS),
                'An unticked feature stays off'
            );
        }
    }

    @IsTest
    static void anUnknownFeatureKeepsNothing() {
        System.runAs(TestUsers.admin()) {
            FeatureSwitchService.markNewInstall();
            Exception refused;

            Test.startTest();
            try {
                FirstRunController.finish(
                    ModuleDetectionService.SUITE_IMPACT,
                    new List<String>{ 'Rollups' }
                );
            } catch (AuraHandledException e) {
                refused = e;
            }
            Test.stopTest();

            Assert.areEqual(
                System.Label.Core_FirstRun_SaveError,
                refused.getMessage(),
                'Maria sees a message she can act on'
            );
        }
    }

    @IsTest
    static void anUnknownEditionIsRefused() {
        System.runAs(TestUsers.admin()) {
            Exception refused;

            Test.startTest();
            try {
                FirstRunController.finish('Enterprise', new List<String>());
            } catch (AuraHandledException e) {
                refused = e;
            }
            Test.stopTest();

            Assert.areEqual(
                System.Label.Core_SuiteChoice_UnknownSuiteError,
                refused.getMessage(),
                'Only the two editions are accepted'
            );
        }
    }

    @IsTest
    static void davidSeesTheWindowButCannotFinish() {
        System.runAs(david()) {
            Exception refused;

            Test.startTest();
            FirstRunController.FirstRunState state = FirstRunController.getState();
            try {
                FirstRunController.finish(
                    ModuleDetectionService.SUITE_COMMUNITY,
                    new List<String>()
                );
            } catch (AuraHandledException e) {
                refused = e;
            }
            Test.stopTest();

            Assert.isTrue(state.needsSetup, 'The window shows for David too');
            Assert.isFalse(state.canFinish, 'He is told an administrator needs to finish');
            Assert.isTrue(state.features.isEmpty(), 'And is shown no choices');
            Assert.isNotNull(refused, 'Finishing needs Manage BarnCRM Settings');
        }
    }
}
