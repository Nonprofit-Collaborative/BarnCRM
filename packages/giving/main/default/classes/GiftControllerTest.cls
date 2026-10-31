/**
 * The screen-facing surface: it returns what a panel needs, and it turns a rule into a message
 * a person can read rather than a stack trace.
 */
@IsTest(testFor='ApexClass:GiftController')
private class GiftControllerTest {
    @TestSetup
    static void makeData() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            GivingTestDataFactory.insertDefaultFund();
            GivingTestDataFactory.insertHouseholdContact('The Nolan Family', 'Ana', 'Nolan');
        }
    }

    private static Gift__c insertGift(Decimal amount) {
        Contact person = [SELECT Id FROM Contact LIMIT 1];
        Gift__c gift = GivingTestDataFactory.buildGift(person.Id, amount);
        insert gift;
        return gift;
    }

    @IsTest
    static void theSummaryAddsUpWhatAScreenWouldOtherwiseWorkOut() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Gift__c gift = insertGift(250);
            GiftService.refund(gift.Id, 100, 'Part back');

            Test.startTest();
            GiftController.GiftSummary summary = GiftController.getGiftSummary(gift.Id);
            Test.stopTest();

            System.assertEquals(250, summary.allocatedAmount, 'The gift is fully allocated.');
            System.assertEquals(100, summary.reversedAmount, 'One hundred has gone back.');
            System.assertEquals(150, summary.remainingAmount, 'One hundred and fifty is left.');
            System.assertEquals(
                false,
                summary.fullyReversed,
                'The gift is not fully refunded yet.'
            );
            System.assertEquals(1, summary.allocations.size(), 'With its one allocation.');
            System.assertEquals(true, summary.canRefund, 'An administrator may record a refund.');
        }
    }

    /**
     * A reader is told in plain words that they cannot record money going back, instead of a
     * refused insert's raw message (testing guide finding C7).
     */
    @IsTest
    static void aReaderIsToldTheyCannotRecordARefund() {
        User reader = TestDataFactory.createUser(
            'Jen',
            new List<String>{ 'BarnCRM_Read_Only', 'Giving_Read_Only' }
        );
        Gift__c gift;
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            gift = insertGift(250);
        }

        String refundMessage;
        String writeOffMessage;
        Test.startTest();
        System.runAs(reader) {
            try {
                GiftController.refund(gift.Id, 100, 'Part back');
            } catch (AuraHandledException refused) {
                refundMessage = refused.getMessage();
            }
            try {
                GiftController.writeOff(gift.Id, 'Will not be paid');
            } catch (AuraHandledException refused) {
                writeOffMessage = refused.getMessage();
            }
        }
        Test.stopTest();

        System.assertEquals(Label.Giving_RefundGift_NoPermission, refundMessage, 'Refund refused.');
        System.assertEquals(
            Label.Giving_RefundGift_NoPermission,
            writeOffMessage,
            'Write-off refused.'
        );
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            System.assertEquals(
                0,
                [SELECT COUNT() FROM Gift__c WHERE Original_Gift__c = :gift.Id],
                'No negative gift was recorded.'
            );
        }
    }

    @IsTest
    static void theSummaryOfAFullyRefundedGiftSaysSo() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Gift__c gift = insertGift(90);
            GiftController.refund(gift.Id, 90, 'All back');

            Test.startTest();
            GiftController.GiftSummary summary = GiftController.getGiftSummary(gift.Id);
            Test.stopTest();

            System.assertEquals(true, summary.fullyReversed, 'Nothing is left of this gift.');
        }
    }

    @IsTest
    static void theWriteOffActionRecordsTheReversal() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Gift__c gift = insertGift(400);

            Test.startTest();
            Id writeOffId = GiftController.writeOff(gift.Id, 'Never paid');
            Test.stopTest();

            System.assertEquals(
                -400,
                [SELECT Amount__c FROM Gift__c WHERE Id = :writeOffId].Amount__c,
                'The write-off reverses what was left.'
            );
        }
    }

    @IsTest
    static void aBadRequestComesBackAsAMessageAScreenCanShow() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            String message = '';

            Test.startTest();
            try {
                GiftController.refund(null, 10, 'No gift');
            } catch (AuraHandledException screenError) {
                message = screenError.getMessage();
            }
            Test.stopTest();

            System.assert(
                String.isNotBlank(message),
                'The screen gets a sentence, not a stack trace: ' + message
            );
        }
    }

    @IsTest
    static void askingForAGiftThatIsNotThereIsHandled() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            String message = '';

            Test.startTest();
            try {
                GiftController.getGiftSummary(null);
            } catch (AuraHandledException missing) {
                message = missing.getMessage();
            }
            Test.stopTest();

            System.assert(String.isNotBlank(message), 'A missing gift is reported, not swallowed.');
        }
    }

    @IsTest
    static void writeOffFailuresAreReportedToTheScreen() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Gift__c gift = insertGift(60);
            GiftController.writeOff(gift.Id, 'Never paid');
            String message = '';

            Test.startTest();
            try {
                GiftController.writeOff(gift.Id, 'Again');
            } catch (AuraHandledException already) {
                message = already.getMessage();
            }
            Test.stopTest();

            System.assert(String.isNotBlank(message), 'The second write-off is refused politely.');
        }
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
