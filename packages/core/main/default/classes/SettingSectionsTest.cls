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
                17,
                sections.size(),
                'Seventeen section names are agreed across the suite'
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
                SettingSections.PEOPLE_AND_HOUSEHOLDS,
                sections[sections.indexOf(SettingSections.DUPLICATE_MATCHING) - 1],
                'Duplicate Matching follows People and Households, where its review list used to be'
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
                SettingSections.isKnown('Household naming'),
                'A section name nobody agreed on is not one of ours'
            );
            Assert.isFalse(SettingSections.isKnown(null), 'Nothing is not a section');
        }
    }

    /** P1: Households and Relationships are one page, and their old names still land on it. */
    @IsTest
    static void peopleAndHouseholdsIsOnePageThatTheOldNamesLandOn() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            List<String> sections = SettingSections.all();
            String fromHouseholds = SettingSections.pageFor('Households');
            String fromRelationships = SettingSections.pageFor(' relationships ');
            String fromNaming = SettingSections.pageFor(SettingSections.HOUSEHOLD_NAMES);
            String fromPeople = SettingSections.pageFor(SettingSections.PEOPLE);
            Test.stopTest();

            Assert.isTrue(
                sections.contains(SettingSections.PEOPLE_AND_HOUSEHOLDS),
                'People and Households is a page'
            );
            Assert.isFalse(sections.contains('Households'), 'Households is no longer a page');
            Assert.isFalse(sections.contains('Relationships'), 'Relationships is no longer a page');
            Assert.areEqual(
                SettingSections.ORGANIZATION,
                sections[sections.indexOf(SettingSections.PEOPLE_AND_HOUSEHOLDS) - 1],
                'People and Households is where Households was, after Organization'
            );
            for (
                String page : new List<String>{
                    fromHouseholds,
                    fromRelationships,
                    fromNaming,
                    fromPeople
                }
            ) {
                Assert.areEqual(
                    SettingSections.PEOPLE_AND_HOUSEHOLDS,
                    page,
                    'A sub-section, or an old page name, opens People and Households'
                );
            }
            Assert.areEqual(
                SettingSections.GIVING,
                SettingSections.pageFor(SettingSections.GIVING),
                'Any other page is its own'
            );
            Assert.isNull(SettingSections.pageFor(null), 'Nothing stays nothing');
            Assert.isTrue(
                SettingSections.isKnown('household names and greetings'),
                'A link may name a sub-section, so it is a known name'
            );
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
