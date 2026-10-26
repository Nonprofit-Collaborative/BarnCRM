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
                18,
                sections.size(),
                'Eighteen section names are agreed across the suite'
            );
            Assert.isTrue(
                SettingSections.isKnown(SettingSections.INTEGRATIONS),
                'Integrations is the section that lists other products'
            );
            Assert.isTrue(
                SettingSections.isKnown(SettingSections.ORG_OPTIMIZER),
                'Org Optimizer is the section that holds the tool thresholds'
            );
            Integer last = sections.size() - 1;
            Assert.areEqual(SettingSections.HEALTH, sections[last], 'Health is listed last');
            Assert.areEqual(
                SettingSections.INTEGRATIONS,
                sections[last - 1],
                'Integrations, about other products, comes just before Health'
            );
            Assert.areEqual(
                SettingSections.ORG_OPTIMIZER,
                sections[last - 2],
                'Org Optimizer follows Import, with the other data tools'
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
            Assert.areEqual(
                SettingSections.HOUSEHOLDS,
                sections[sections.indexOf(SettingSections.DUPLICATE_MATCHING) - 1],
                'Duplicate Matching follows Households, where its review list used to be'
            );
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
