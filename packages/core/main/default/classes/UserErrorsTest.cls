@IsTest(testFor='ApexClass:UserErrors')
private class UserErrorsTest {
    private static final String FALLBACK = 'The feature could not finish. Try again.';

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

    @IsTest
    static void theMessageIsTheTextGiven() {
        System.runAs(TestUsers.admin()) {
            Assert.areEqual('Nope', UserErrors.message('Nope').getMessage(), 'Text kept');
        }
    }

    @IsTest
    static void aShownFailureKeepsItsMessageAndIsNotLogged() {
        System.runAs(TestUsers.admin()) {
            Exception known = new ImportException('Pick a file first.');

            AuraHandledException shown = UserErrors.wrap(
                known,
                true,
                'UserErrorsTest.shown',
                FALLBACK
            );

            Assert.areEqual('Pick a file first.', shown.getMessage(), 'Own message');
            Assert.areEqual(0, [SELECT COUNT() FROM Error_Log__c], 'Nothing logged');
        }
    }

    @IsTest
    static void anyOtherFailureShowsTheFallbackAndIsLoggedWithItsRecord() {
        System.runAs(TestUsers.admin()) {
            Exception other = new ImportException('Internal detail');
            Id recordId = FakeIds.of(Contact.SObjectType, 1);

            Test.startTest();
            AuraHandledException shown = UserErrors.wrap(
                other,
                false,
                'UserErrorsTest.other',
                recordId,
                FALLBACK
            );
            Test.stopTest();

            Assert.areEqual(FALLBACK, shown.getMessage(), 'Fallback label');
            List<Error_Log__c> logged = [
                SELECT Record_Reference__c
                FROM Error_Log__c
                WHERE Context__c = 'UserErrorsTest.other'
            ];
            Assert.areEqual(1, logged.size(), 'Logged once');
            Assert.areEqual(
                String.valueOf(recordId),
                logged[0].Record_Reference__c,
                'With its record'
            );
        }
    }

    @IsTest
    static void wrapShowingDmlKeepsABarnCrmMessage() {
        System.runAs(TestUsers.admin()) {
            Exception known = new ImportException('Choose a gift first.');

            AuraHandledException shown = UserErrors.wrapShowingDml(known, FALLBACK);

            Assert.areEqual('Choose a gift first.', shown.getMessage(), 'Known message');
        }
    }

    @IsTest
    static void wrapShowingDmlShowsOnlyTheRowMessageOfAFailedSave() {
        System.runAs(TestUsers.admin()) {
            String message;
            try {
                insert new Contact();
            } catch (DmlException failed) {
                message = UserErrors.wrapShowingDml(failed, FALLBACK).getMessage();
                Assert.areEqual(failed.getDmlMessage(0), message, 'The row message only');
                Assert.isFalse(message.contains('Insert failed'), 'No DML wrapper');
            }
            Assert.isNotNull(message, 'The insert failed');
            Assert.areEqual(0, [SELECT COUNT() FROM Error_Log__c], 'Nothing logged');
        }
    }

    @IsTest
    static void wrapShowingDmlTurnsAnythingElseIntoTheLabel() {
        System.runAs(TestUsers.admin()) {
            Exception raw;
            try {
                Object nothing = null;
                nothing.toString();
            } catch (NullPointerException failed) {
                raw = failed;
            }

            AuraHandledException shown = UserErrors.wrapShowingDml(raw, FALLBACK);

            Assert.areEqual(FALLBACK, shown.getMessage(), 'Label shown');
        }
    }
}
