/** One vocabulary of section names, so a setup step and a shipped row can agree on one. */
@IsTest(testFor='ApexClass:SettingSections')
private class SettingSectionsTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    @IsTest
    static void namesEverySectionTheConsoleGroupsBy() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            List<String> sections = SettingSections.all();
            Test.stopTest();

            Assert.areEqual(
                15,
                sections.size(),
                'Fifteen section names are agreed across the suite'
            );
            Assert.isTrue(
                SettingSections.isKnown(SettingSections.VOLUNTEERS),
                'Volunteers is a section its module ships rows into, so Core has to know the name'
            );
            Assert.areEqual(
                SettingSections.MODULES,
                sections[1],
                'Modules comes right after General, where the features are'
            );
            Assert.areEqual(
                SettingSections.GENERAL,
                sections[0],
                'General comes first, because it is where a new org starts'
            );
            Assert.isTrue(SettingSections.isKnown('households'), 'The check ignores case');
            Assert.isTrue(
                SettingSections.isKnown(SettingSections.RECEIPTS),
                'Receipts is a section Giving ships rows into, so Core has to know the name'
            );
            Assert.isTrue(SettingSections.isKnown('  Health '), 'The check ignores spacing');
            Assert.isTrue(
                SettingSections.isKnown('Relationships'),
                'A module that has not shipped yet still has its section name reserved'
            );
            Assert.isFalse(
                SettingSections.isKnown('Household names and greetings'),
                'A section name nobody agreed on is not one of ours'
            );
            Assert.isFalse(SettingSections.isKnown(null), 'Nothing is not a section');
        }
    }

    @IsTest
    static void everySetupStepPointsAtASectionThatExists() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            List<SetupAssistantService.Step> steps = SetupAssistantService.getSteps();
            Test.stopTest();

            for (SetupAssistantService.Step step : steps) {
                Assert.isTrue(
                    SettingSections.isKnown(step.target),
                    'Step ' + step.key + ' opens section ' + step.target + ', which has to exist'
                );
            }
        }
    }
}
