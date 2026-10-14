/**
 * The second of the three tests ADR-0016 names: **ADR-0010 holds end to end.**
 *
 * A receipt is the document a donor files with a tax return. Once it is issued, the number, the
 * amount and the file are facts about the world. This class is the proof that the code treats them
 * that way: nothing here checks that a field can be written, it checks that it cannot.
 */
@IsTest(testFor='ApexClass:ReceiptService')
private class ReceiptVoidReissueTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.adminWith('Giving_Admin');
    }

    /**
     * An issued receipt's number, amount and stored file are all exactly as they were after the
     * receipt is voided, and the void says why and when.
     *
     * The file assertion is the one that matters most. Voiding is not deleting: the donor still
     * holds their copy, so the organization keeps the copy it sent.
     */
    @IsTest
    static void voidingChangesNothingButTheStatusTheReasonAndTheDate() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            System.runAs(ReceiptTestDataFactory.issuer()) {
                ReceiptTestDataFactory.setUpReceipting();
                Contact donor = GivingTestDataFactory.insertHouseholdContact(
                    'The Reyes Family',
                    'Ana',
                    'Reyes'
                );
                Gift__c gift = ReceiptTestDataFactory.plainCashGift(
                    donor.Id,
                    250,
                    Date.newInstance(2026, 3, 4)
                );
                insert gift;

                Receipt__c issued = ReceiptService.issueForGift(gift.Id);
                String numberBefore = issued.Receipt_Number__c;
                Decimal amountBefore = issued.Total_Amount__c;
                Id documentBefore = issued.Content_Document_Id__c;
                Blob bytesBefore = versionDataOf(documentBefore);

                Test.startTest();
                ReceiptService.voidReceipt(issued.Id, 'Donor name was wrong');
                Test.stopTest();

                Receipt__c after = ReceiptSelector.byId(issued.Id);
                Assert.areEqual(
                    numberBefore,
                    after.Receipt_Number__c,
                    'The number does not change.'
                );
                Assert.areEqual(amountBefore, after.Total_Amount__c, 'The amount does not change.');
                Assert.areEqual(
                    documentBefore,
                    after.Content_Document_Id__c,
                    'The receipt still points at the same file.'
                );
                Assert.areEqual(
                    bytesBefore.toString(),
                    versionDataOf(documentBefore).toString(),
                    'The stored document itself is byte for byte what the donor received.'
                );
                Assert.areEqual(ReceiptService.STATUS_VOID, after.Status__c, 'It is void.');
                Assert.areEqual(
                    'Donor name was wrong',
                    after.Void_Reason__c,
                    'The void carries a reason.'
                );
                Assert.isNotNull(after.Voided_On__c, 'The void carries a date.');
            }

        }
    }

    /**
     * A reissue takes the next number, never the voided one, and the two records point at each
     * other so that whoever holds either document can find the other.
     */
    @IsTest
    static void aReissueTakesTheNextNumberAndTheTwoRecordsPointAtEachOther() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            System.runAs(ReceiptTestDataFactory.issuer()) {
                ReceiptTestDataFactory.setUpReceipting();
                Contact donor = GivingTestDataFactory.insertHouseholdContact(
                    'The Osei Family',
                    'Kofi',
                    'Osei'
                );
                Gift__c gift = ReceiptTestDataFactory.plainCashGift(
                    donor.Id,
                    500,
                    Date.newInstance(2026, 5, 9)
                );
                insert gift;
                Receipt__c original = ReceiptService.issueForGift(gift.Id);

                Test.startTest();
                Receipt__c replacement = ReceiptService.voidAndReissue(
                    original.Id,
                    'Amount was keyed wrongly'
                );
                Test.stopTest();

                Assert.areEqual(
                    'HFH-2026-000001',
                    original.Receipt_Number__c,
                    'The first receipt is number one.'
                );
                Assert.areEqual(
                    'HFH-2026-000002',
                    replacement.Receipt_Number__c,
                    'The replacement takes the next number, never the voided one.'
                );

                Receipt__c voided = ReceiptSelector.byId(original.Id);
                Receipt__c reissued = ReceiptSelector.byId(replacement.Id);
                Assert.areEqual(
                    ReceiptService.STATUS_VOID,
                    voided.Status__c,
                    'The original is void.'
                );
                Assert.areEqual(
                    'Amount was keyed wrongly',
                    voided.Void_Reason__c,
                    'The void still carries the reason after the reissue.'
                );
                Assert.areEqual(
                    ReceiptService.STATUS_ISSUED,
                    reissued.Status__c,
                    'The replacement is issued.'
                );
                Assert.areEqual(
                    replacement.Id,
                    voided.Replaced_By__c,
                    'The original names its replacement.'
                );
                Assert.areEqual(
                    original.Id,
                    reissued.Replaces__c,
                    'The replacement names what it replaces.'
                );
                Assert.areEqual(
                    replacement.Receipt_Number__c,
                    [SELECT Receipt_Number__c FROM Gift__c WHERE Id = :gift.Id].Receipt_Number__c,
                    'The gift now carries the live receipt number.'
                );
            }

        }
    }

    /**
     * Changing a receipted gift's amount fails, with a message a person can act on. This is the
     * rule ADR-0010 exists for, enforced by an automation that no switch and no pause reaches
     * (ADR-0024).
     */
    @IsTest
    static void changingAReceiptedGiftsAmountFailsWithAReadableMessage() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            System.runAs(ReceiptTestDataFactory.issuer()) {
                ReceiptTestDataFactory.setUpReceipting();
                Contact donor = GivingTestDataFactory.insertHouseholdContact(
                    'The Novak Family',
                    'Petra',
                    'Novak'
                );
                Gift__c gift = ReceiptTestDataFactory.plainCashGift(
                    donor.Id,
                    120,
                    Date.newInstance(2026, 2, 2)
                );
                insert gift;
                ReceiptService.issueForGift(gift.Id);

                String message;
                Test.startTest();
                try {
                    update new Gift__c(Id = gift.Id, Amount__c = 1200);
                    Assert.fail('A receipted gift accepted a new amount, which ADR-0010 forbids.');
                } catch (DmlException refused) {
                    message = refused.getDmlMessage(0);
                }
                Test.stopTest();

                Assert.areEqual(
                    Label.Giving_Gift_ReceiptLocked,
                    message,
                    'The refusal says what to do instead, in words a person can act on.'
                );
                Assert.areEqual(
                    120,
                    [SELECT Amount__c FROM Gift__c WHERE Id = :gift.Id].Amount__c,
                    'The amount the donor was receipted for is still the amount on the record.'
                );
            }

        }
    }

    private static Blob versionDataOf(Id contentDocumentId) {
        return [
            SELECT VersionData
            FROM ContentVersion
            WHERE ContentDocumentId = :contentDocumentId
            ORDER BY VersionNumber DESC
            LIMIT 1
        ]
        .VersionData;
    }
}
