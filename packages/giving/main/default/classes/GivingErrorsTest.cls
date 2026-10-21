@IsTest
private class GivingErrorsTest {
    @IsTest
    static void aBarnCrmExceptionIsShownAsWritten() {
        AuraHandledException surfaced = GivingErrors.userError(
            new GiftService.GiftServiceException('Choose a gift first.'),
            Label.Giving_Gift_UnexpectedError
        );

        Assert.areEqual(
            'Choose a gift first.',
            surfaced.getMessage(),
            'Known message passes through'
        );
    }

    @IsTest
    static void aFailedSaveShowsOnlyTheRowMessage() {
        String message;
        try {
            insert new Gift__c();
        } catch (DmlException failed) {
            message = GivingErrors.userError(failed, Label.Giving_Gift_UnexpectedError)
                .getMessage();
            Assert.areEqual(failed.getDmlMessage(0), message, 'The row message, not the whole text');
            Assert.isFalse(message.contains('Insert failed'), 'No raw DML wrapper: ' + message);
        }
        Assert.isNotNull(message, 'The insert failed');
    }

    @IsTest
    static void anythingElseBecomesTheLabel() {
        Exception raw;
        try {
            Object nothing = null;
            nothing.toString();
        } catch (NullPointerException failed) {
            raw = failed;
        }

        AuraHandledException surfaced = GivingErrors.userError(
            raw,
            Label.Giving_Gift_UnexpectedError
        );

        Assert.areEqual(Label.Giving_Gift_UnexpectedError, surfaced.getMessage(), 'Label shown');
    }

    @IsTest
    static void aRefundOfAnUnknownGiftNeverShowsRawText() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            String message;
            try {
                GiftController.refund(FakeIds.of(Account.SObjectType, 1), 5, 'Wrong object');
            } catch (AuraHandledException refused) {
                message = refused.getMessage();
            }
            Assert.isNotNull(message, 'Refused');
            Assert.isFalse(message.contains('Exception'), 'No raw exception text: ' + message);
            Assert.isFalse(message.contains('Insert failed'), 'No DML text: ' + message);
        }
    }
}
