/**
 * That a receipt is raised only for a gift whose money has arrived: Pending and Cancelled gifts are
 * refused, the same two statuses the statement run leaves out (R-RC8, R-G16).
 */
@IsTest(testFor='ApexClass:ReceiptService')
private class ReceiptGiftStatusTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.adminWith('Giving_Admin');
    }

    private static void assertRefused(Id giftId, String why) {
        try {
            ReceiptService.issueForGift(giftId);
            Assert.fail(why);
        } catch (ReceiptService.ReceiptServiceException refused) {
            Assert.areEqual(Label.Giving_Receipt_GiftNotReceived, refused.getMessage(), why);
        }
    }

    @IsTest
    static void aPendingOrCancelledGiftIsNotReceipted() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            System.runAs(ReceiptTestDataFactory.issuer()) {
                ReceiptTestDataFactory.setUpReceipting();
                Contact donor = GivingTestDataFactory.insertHouseholdContact(
                    'The Mbeki Family',
                    'Thandi',
                    'Mbeki'
                );
                Gift__c gift = ReceiptTestDataFactory.plainCashGift(
                    donor.Id,
                    60,
                    Date.newInstance(2026, 2, 3)
                );
                gift.Status__c = 'Pending';
                insert gift;

                Test.startTest();
                assertRefused(gift.Id, 'A pending gift was receipted.');
                gift.Status__c = 'Cancelled';
                update gift;
                assertRefused(gift.Id, 'A cancelled gift was receipted.');
                gift.Status__c = 'Pending';
                update gift;
                gift.Status__c = 'Received';
                update gift;
                Receipt__c issued = ReceiptService.issueForGift(gift.Id);
                Test.stopTest();

                Assert.isNotNull(issued.Id, 'Once received, the gift can be receipted.');
            }
        }
    }
}
