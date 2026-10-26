/**
 * Cancelled gifts (R-G16, ADR-0054).
 *
 * Ana pledged 40 at the gala and it never came. David cancels it; nothing else is created, it
 * leaves her receipts and frees the installment it was meant to pay. Then the check turns up
 * after all, and he sets it back to Pending.
 */
@IsTest(testFor='ApexClass:GiftStatusRules')
private class GiftStatusRulesTest {
    @TestSetup
    static void makeData() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            GivingTestDataFactory.insertDefaultFund();
            Contact ana = GivingTestDataFactory.insertHouseholdContact(
                'The Nolan Family',
                'Ana',
                'Nolan'
            );
            Gift__c received = GivingTestDataFactory.buildGift(ana.Id, 100);
            Gift__c pending = GivingTestDataFactory.buildGift(ana.Id, 40);
            pending.Status__c = 'Pending';
            insert new List<Gift__c>{ received, pending };
        }
    }

    private static Gift__c giftOf(Decimal amount) {
        return [
            SELECT Id, Name, Status__c, Installment__c, Household__c, Gift_Date__c
            FROM Gift__c
            WHERE Amount__c = :amount
            WITH SYSTEM_MODE
        ];
    }

    private static String refusalOf(Id giftId, String status) {
        try {
            update new Gift__c(Id = giftId, Status__c = status);
            return null;
        } catch (DmlException refused) {
            return refused.getDmlMessage(0);
        }
    }

    private static List<String> logged() {
        List<String> messages = new List<String>();
        for (Error_Log__c entry : [
            SELECT Message__c, Severity__c
            FROM Error_Log__c
            WHERE Context__c = 'Gift cancelled'
            WITH SYSTEM_MODE
            ORDER BY CreatedDate, Id
        ]) {
            Assert.areEqual(ErrorLogger.SEVERITY_INFO, entry.Severity__c);
            messages.add(entry.Message__c);
        }
        return messages;
    }

    @IsTest
    static void aPendingGiftIsCancelledAndSetBackAndBothAreLogged() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Gift__c pending = giftOf(40);
            Integer before = [SELECT COUNT() FROM Gift__c];

            Test.startTest();
            Assert.isNull(refusalOf(pending.Id, 'Cancelled'), 'Pending to Cancelled');
            Assert.areEqual(before, [SELECT COUNT() FROM Gift__c], 'No negative gift');
            Assert.isNull(refusalOf(pending.Id, 'Pending'), 'Cancelled back to Pending');
            Assert.isNull(refusalOf(pending.Id, 'Received'), 'Then to Received when it arrives');
            Test.stopTest();

            Assert.areEqual(
                new List<String>{
                    String.format(
                        Label.Giving_Gift_CancelledLogged,
                        new List<String>{ pending.Name }
                    ),
                    String.format(
                        Label.Giving_Gift_UncancelledLogged,
                        new List<String>{ pending.Name }
                    )
                },
                logged()
            );
        }
    }

    @IsTest
    static void onlyPendingIsCancelledAndCancelledGoesOnlyBackToPending() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Gift__c received = giftOf(100);
            Gift__c pending = giftOf(40);
            update new Gift__c(Id = pending.Id, Status__c = 'Cancelled');

            Test.startTest();
            String receivedRefusal = refusalOf(received.Id, 'Cancelled');
            String toReceived = refusalOf(pending.Id, 'Received');
            String toWrittenOff = refusalOf(pending.Id, 'Written off');
            Test.stopTest();

            Assert.areEqual(Label.Giving_Gift_CancelOnlyPending, receivedRefusal);
            Assert.areEqual(Label.Giving_Gift_CancelledOnlyToPending, toReceived);
            Assert.areEqual(Label.Giving_Gift_CancelledOnlyToPending, toWrittenOff);
            Assert.areEqual('Received', giftOf(100).Status__c);
            Assert.areEqual('Cancelled', giftOf(40).Status__c);
        }
    }

    @IsTest
    static void aPendingGiftIsNeitherWrittenOffNorRefunded() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Gift__c pending = giftOf(40);
            String expected = String.format(
                Label.Giving_Gift_ReverseNeedsReceived,
                new List<String>{ 'Pending' }
            );

            Test.startTest();
            String typed = refusalOf(pending.Id, 'Written off');
            String typedRefund = refusalOf(pending.Id, 'Refunded');
            String writeOff;
            try {
                GiftService.writeOff(pending.Id, 'Never paid');
            } catch (GiftService.GiftServiceException refused) {
                writeOff = refused.getMessage();
            }
            String refund;
            try {
                GiftService.refund(pending.Id, 10, 'Never paid');
            } catch (GiftService.GiftServiceException refused) {
                refund = refused.getMessage();
            }
            Test.stopTest();

            Assert.areEqual(expected, typed, 'The status edit');
            Assert.areEqual(expected, typedRefund, 'The status edit');
            Assert.areEqual(expected, writeOff, 'The action');
            Assert.areEqual(expected, refund, 'The action');
            Assert.areEqual(2, [SELECT COUNT() FROM Gift__c], 'No negative gift');
        }
    }

    /** A three-month pledge from Ana, with its installments. */
    private static Commitment__c pledge() {
        Contact ana = [SELECT Id FROM Contact LIMIT 1];
        Commitment__c pledge = new Commitment__c(
            Type__c = 'Pledge',
            Status__c = 'Active',
            Donor_Contact__c = ana.Id,
            Amount__c = 40,
            Frequency__c = 'Monthly',
            Start_Date__c = Date.today().addMonths(1).toStartOfMonth(),
            Expected_Total__c = 120,
            Installments_Planned__c = 3
        );
        insert pledge;
        CommitmentService.generateInstallments(new Set<Id>{ pledge.Id });
        return pledge;
    }

    private static Installment__c firstInstallment(Id pledgeId) {
        return [
            SELECT Id
            FROM Installment__c
            WHERE Commitment__c = :pledgeId
            WITH SYSTEM_MODE
            ORDER BY Sequence__c
            LIMIT 1
        ];
    }

    @IsTest
    static void cancellingFreesTheInstallmentAsADeleteWould() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Commitment__c pledge = pledge();
            Installment__c first = firstInstallment(pledge.Id);
            Gift__c pending = giftOf(40);
            update new Gift__c(
                Id = pending.Id,
                Commitment__c = pledge.Id,
                Installment__c = first.Id
            );

            Test.startTest();
            update new Gift__c(Id = pending.Id, Status__c = 'Cancelled');
            Test.stopTest();

            Gift__c cancelled = [
                SELECT Installment__c, Commitment__c
                FROM Gift__c
                WHERE Id = :pending.Id
            ];
            Assert.isNull(cancelled.Installment__c, 'The installment is released');
            Assert.areEqual(pledge.Id, cancelled.Commitment__c, 'The pledge link stays as history');
            Assert.isNull(
                new InstallmentSelector().countGifts(new Set<Id>{ first.Id }).get(first.Id),
                'No gift holds the installment'
            );
            Assert.areEqual(
                'Scheduled',
                [SELECT Status__c FROM Installment__c WHERE Id = :first.Id].Status__c,
                'Open for the next gift'
            );
        }
    }

    @IsTest
    static void aCancelledGiftIsOnNoStatement() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Gift__c pending = giftOf(40);
            update new Gift__c(Id = pending.Id, Status__c = 'Cancelled');
            Gift__c kept = giftOf(100);

            Test.startTest();
            List<Gift__c> lines = ReceiptSelector.giftsForReceipting(
                new Set<Id>{ kept.Household__c },
                kept.Gift_Date__c.year()
            );
            Test.stopTest();

            Assert.areEqual(1, lines.size(), 'Only the received gift');
            Assert.areEqual(kept.Id, lines[0].Id);
        }
    }

    @IsTest
    static void goingBackToPendingDoesNotLinkAnInstallmentAgain() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Commitment__c pledge = pledge();
            Gift__c pending = giftOf(40);
            update new Gift__c(
                Id = pending.Id,
                Commitment__c = pledge.Id,
                Installment__c = firstInstallment(pledge.Id).Id
            );
            update new Gift__c(Id = pending.Id, Status__c = 'Cancelled');

            Test.startTest();
            update new Gift__c(Id = pending.Id, Status__c = 'Pending');
            Test.stopTest();

            Gift__c back = [
                SELECT Installment__c, Commitment__c
                FROM Gift__c
                WHERE Id = :pending.Id
            ];
            Assert.isNull(back.Installment__c, 'A person picks the installment, as for a new gift');
            Assert.areEqual(pledge.Id, back.Commitment__c);
        }
    }

    @IsTest
    static void aGiftCreatedCancelledHoldsNoInstallment() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Commitment__c pledge = pledge();
            Installment__c first = firstInstallment(pledge.Id);
            Gift__c cancelled = GivingTestDataFactory.buildGift(
                [SELECT Id FROM Contact LIMIT 1].Id,
                55
            );
            cancelled.Status__c = 'Cancelled';
            cancelled.Commitment__c = pledge.Id;
            cancelled.Installment__c = first.Id;

            Test.startTest();
            insert cancelled;
            Test.stopTest();

            Assert.isNull(
                [SELECT Installment__c FROM Gift__c WHERE Id = :cancelled.Id].Installment__c,
                'A cancelled gift pays no installment'
            );
            Assert.areEqual(
                'Scheduled',
                [SELECT Status__c FROM Installment__c WHERE Id = :first.Id].Status__c
            );
        }
    }
}
