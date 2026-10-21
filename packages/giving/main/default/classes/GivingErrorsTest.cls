@IsTest
private class GivingErrorsTest {
    private static final String FALLBACK = Label.Giving_Gift_UnexpectedError;

    @IsTest
    static void aBarnCrmExceptionIsShownAsWritten() {
        Exception known = new GiftService.GiftServiceException('Choose a gift first.');

        AuraHandledException surfaced = GivingErrors.userError(known, FALLBACK);

        Assert.areEqual('Choose a gift first.', surfaced.getMessage(), 'Known message');
    }

    @IsTest
    static void aFailedSaveShowsOnlyTheRowMessage() {
        String message;
        try {
            insert new Gift__c();
        } catch (DmlException failed) {
            message = GivingErrors.userError(failed, FALLBACK).getMessage();
            Assert.areEqual(failed.getDmlMessage(0), message, 'The row message only');
            Assert.isFalse(message.contains('Insert failed'), 'No DML wrapper');
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

        AuraHandledException surfaced = GivingErrors.userError(raw, FALLBACK);

        Assert.areEqual(FALLBACK, surfaced.getMessage(), 'Label shown');
    }

    @IsTest
    static void aRefundOfAnUnknownGiftNeverShowsRawText() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Id notAGift = FakeIds.of(Account.SObjectType, 1);
            String message;
            try {
                GiftController.refund(notAGift, 5, 'Wrong object');
            } catch (AuraHandledException refused) {
                message = refused.getMessage();
            }
            Assert.isNotNull(message, 'Refused');
            Assert.isFalse(message.contains('Exception'), 'No raw exception text');
            Assert.isFalse(message.contains('Insert failed'), 'No DML text');
        }
    }
}
