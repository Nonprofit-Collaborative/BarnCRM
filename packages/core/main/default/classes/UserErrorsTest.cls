@IsTest
private class UserErrorsTest {
    @IsTest
    static void aBarnCrmExceptionIsShownAsWritten() {
        AuraHandledException shown = UserErrors.wrap(
            new ImportException('Pick a file first.'),
            'UserErrorsTest',
            false
        );

        Assert.areEqual('Pick a file first.', shown.getMessage(), 'Known message passes through');
    }

    @IsTest
    static void aPlatformFailureBecomesTheLabelAndIsLogged() {
        String raw;
        Exception failure;
        try {
            insert new Contact();
        } catch (DmlException failed) {
            failure = failed;
            raw = failed.getMessage();
        }
        Assert.isNotNull(raw, 'The insert failed');

        Test.startTest();
        AuraHandledException shown = UserErrors.wrap(failure, 'UserErrorsTest.platform', true);
        Test.stopTest();

        Assert.areEqual(Label.Core_UnexpectedError, shown.getMessage(), 'Label, not raw text');
        Assert.isFalse(shown.getMessage().contains('REQUIRED_FIELD_MISSING'), 'No platform code');
        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Error_Log__c WHERE Context__c = 'UserErrorsTest.platform'],
            'The detail is in the Error Log'
        );
    }

    @IsTest
    static void aCacheableCallCanSkipTheLog() {
        AuraHandledException shown = UserErrors.wrap(
            new NullPointerException(),
            'UserErrorsTest.cacheable',
            false
        );

        Assert.areEqual(Label.Core_UnexpectedError, shown.getMessage(), 'Label shown');
        Assert.areEqual(0, [SELECT COUNT() FROM Error_Log__c], 'Nothing logged');
    }
}
