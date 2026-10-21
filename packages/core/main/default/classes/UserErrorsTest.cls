@IsTest(testFor='ApexClass:UserErrors')
private class UserErrorsTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    @IsTest
    static void aBarnCrmExceptionIsShownAsWritten() {
        System.runAs(TestUsers.admin()) {
            Exception known = new ImportException('Pick a file first.');

            AuraHandledException shown = UserErrors.wrap(known, 'UserErrorsTest', false);

            Assert.areEqual('Pick a file first.', shown.getMessage(), 'Known message');
        }
    }

    @IsTest
    static void aPlatformFailureBecomesTheLabelAndIsLogged() {
        System.runAs(TestUsers.admin()) {
            Exception failure;
            try {
                insert new Contact();
            } catch (DmlException failed) {
                failure = failed;
            }
            Assert.isNotNull(failure, 'The insert failed');

            Test.startTest();
            AuraHandledException shown = UserErrors.wrap(failure, 'UserErrorsTest.platform', true);
            Test.stopTest();

            Assert.areEqual(Label.Core_UnexpectedError, shown.getMessage(), 'Label, not raw text');
            Assert.isFalse(
                shown.getMessage().contains('REQUIRED_FIELD_MISSING'),
                'No platform code'
            );
            Integer logged = [
                SELECT COUNT()
                FROM Error_Log__c
                WHERE Context__c = 'UserErrorsTest.platform'
            ];
            Assert.areEqual(1, logged, 'The detail is in the Error Log');
        }
    }

    @IsTest
    static void aCacheableCallCanSkipTheLog() {
        System.runAs(TestUsers.admin()) {
            Exception failure = new NullPointerException();

            AuraHandledException shown = UserErrors.wrap(failure, 'UserErrorsTest.cache', false);

            Assert.areEqual(Label.Core_UnexpectedError, shown.getMessage(), 'Label shown');
            Assert.areEqual(0, [SELECT COUNT() FROM Error_Log__c], 'Nothing logged');
        }
    }
}
