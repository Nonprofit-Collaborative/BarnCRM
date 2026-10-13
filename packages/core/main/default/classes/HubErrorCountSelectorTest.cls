/**
 * The Hub error tile is a number, and it is zero rather than an error when the Error Log
 * is not part of this package build or the reader cannot see it. It stops counting at the
 * cap, so a flooded Error Log never costs the home page more than that.
 */
@IsTest
private class HubErrorCountSelectorTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static void insertNewErrors(Integer howMany) {
        List<Error_Log__c> errors = new List<Error_Log__c>();
        for (Integer i = 0; i < howMany; i++) {
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
    }

    @IsTest
    static void countsWithoutFailingWhenTheErrorLogIsAbsent() {
        System.runAs(TestUsers.admin()) {
            insertNewErrors(1);
            HubErrorCountSelector.absentForTest = true;

            Test.startTest();
            Integer count = HubErrorCountSelector.countNewErrors();
            Test.stopTest();

            Assert.areEqual(0, count, 'Without an Error Log the tile shows zero, not an error');
        }
    }

    @IsTest
    static void countsNewErrorsTheReaderCanSee() {
        System.runAs(TestUsers.admin()) {
            insertNewErrors(2);
            User maria = HealthCheckTestHelper.mariaWithManageSettings();

            System.runAs(maria) {
                Assert.areEqual(2, HubErrorCountSelector.countNewErrors(), 'Both new errors count');
            }

        }
    }

    @IsTest
    static void stopsOnePastTheCap() {
        System.runAs(TestUsers.admin()) {
            insertNewErrors(4);
            HubErrorCountSelector.countCap = 2;
            User maria = HealthCheckTestHelper.mariaWithManageSettings();

            System.runAs(maria) {
                Assert.areEqual(
                    3,
                    HubErrorCountSelector.countNewErrors(),
                    'The count reads one past the cap, which means "more than the cap"'
                );
            }

        }
    }

    @IsTest
    static void theCountIsBoundedAndFiltersOnStatus() {
        System.runAs(TestUsers.admin()) {
            String query = HubErrorCountSelector.countQuery('Error_Log__c', 'Status__c');

            Assert.isTrue(query.contains('WHERE Status__c = :statusNew'), query);
            Assert.isTrue(query.endsWith('LIMIT :readUpTo'), 'Every count is capped: ' + query);
        }
    }
}
