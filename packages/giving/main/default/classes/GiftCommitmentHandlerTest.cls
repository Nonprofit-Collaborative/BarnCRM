/**
 * Tests for the Gift handler that applies a gift to the payment it fulfills.
 */
@IsTest(testFor='ApexClass:GiftCommitmentHandler')
private class GiftCommitmentHandlerTest {
    /**
     * A gift saves only when there is a default fund to allocate it to (R-GA2).
     */
    @TestSetup
    static void makeData() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            GivingTestDataFactory.ensureDefaultFund();
        }
    }

    private static Contact donor() {
        Contact person = new Contact(FirstName = 'Sarah', LastName = 'Nguyen');
        insert person;
        return person;
    }

    /**
     * The schedule starts today, so its first payment is never past due (and so never
     * Overdue) on whatever day the tests run.
     */
    private static Commitment__c pledgeWithSchedule(Id donorId) {
        Commitment__c pledge = new Commitment__c(
            Type__c = 'Pledge',
            Status__c = 'Active',
            Donor_Contact__c = donorId,
            Amount__c = 100,
            Frequency__c = 'Monthly',
            Start_Date__c = Date.today(),
            Expected_Total__c = 300,
            Installments_Planned__c = 3
        );
        insert pledge;
        CommitmentService.generateInstallments(new Set<Id>{ pledge.Id });
        return pledge;
    }

    private static Gift__c giftFor(Id donorId, Id commitmentId, Id installmentId, Decimal amount) {
        return new Gift__c(
            Donor_Contact__c = donorId,
            Gift_Date__c = Date.today(),
            Amount__c = amount,
            Type__c = 'Check',
            Status__c = 'Received',
            Commitment__c = commitmentId,
            Installment__c = installmentId
        );
    }

    @IsTest
    static void appliesGiftsOnInsert() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact person = donor();
            Commitment__c pledge = pledgeWithSchedule(person.Id);
            Installment__c first = [
                SELECT Id
                FROM Installment__c
                WHERE Commitment__c = :pledge.Id
                ORDER BY Sequence__c
                LIMIT 1
            ];
            Gift__c gift = giftFor(person.Id, pledge.Id, first.Id, 100);
            insert gift;

            Test.startTest();
            new GiftCommitmentHandler().onAfterInsert(new List<Gift__c>{ gift });
            Test.stopTest();

            Assert.areEqual(
                'Paid',
                [SELECT Status__c FROM Installment__c WHERE Id = :first.Id].Status__c,
                'A received gift pays the payment it names.'
            );
        }
    }

    /**
     * A refund is a negative gift on the payment the original paid (R-G3): part of it back leaves
     * the payment partly paid, and the rest back leaves it unpaid.
     */
    @IsTest
    static void recalculatesWhenAGiftIsRefunded() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact person = donor();
            Commitment__c pledge = pledgeWithSchedule(person.Id);
            Installment__c first = [
                SELECT Id
                FROM Installment__c
                WHERE Commitment__c = :pledge.Id
                ORDER BY Sequence__c
                LIMIT 1
            ];
            Gift__c gift = giftFor(person.Id, pledge.Id, first.Id, 100);
            insert gift;

            Test.startTest();
            Id partial = GiftService.refund(gift.Id, 40, 'Part of it back');
            String afterPartial = [SELECT Status__c FROM Installment__c WHERE Id = :first.Id]
            .Status__c;
            GiftService.refund(gift.Id, 60, 'The rest back');
            Test.stopTest();

            Gift__c reversal = [
                SELECT Commitment__c, Installment__c
                FROM Gift__c
                WHERE Id = :partial
            ];
            Assert.areEqual(pledge.Id, reversal.Commitment__c, 'The refund names the pledge.');
            Assert.areEqual(first.Id, reversal.Installment__c, 'And the payment it takes from.');
            Assert.areEqual(
                'Partially paid',
                afterPartial,
                'Forty of the hundred went back, so sixty still pays the payment.'
            );
            Assert.areEqual(
                'Scheduled',
                [SELECT Status__c FROM Installment__c WHERE Id = :first.Id].Status__c,
                'All of it went back, so nothing pays the payment any more.'
            );
        }
    }

    /**
     * A negative gift never takes from the next open payment: it belongs to the payment its
     * original paid, or to none.
     */
    @IsTest
    static void aRefundIsNotLinkedToTheNextOpenPayment() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact person = donor();
            Commitment__c pledge = pledgeWithSchedule(person.Id);
            Gift__c gift = giftFor(person.Id, pledge.Id, null, 100);
            insert gift;
            Gift__c reversal = giftFor(person.Id, pledge.Id, null, -100);
            reversal.Original_Gift__c = gift.Id;
            reversal.Refund_Reason__c = 'Returned';

            Test.startTest();
            insert reversal;
            Test.stopTest();

            Assert.isNotNull(
                [SELECT Installment__c FROM Gift__c WHERE Id = :gift.Id].Installment__c,
                'The payment itself was linked to the first open payment.'
            );
            Assert.isNull(
                [SELECT Installment__c FROM Gift__c WHERE Id = :reversal.Id].Installment__c,
                'The refund was not linked to another one.'
            );
        }
    }

    @IsTest
    static void recalculatesTheInstallmentAGiftLeaves() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact person = donor();
            Commitment__c pledge = pledgeWithSchedule(person.Id);
            List<Installment__c> schedule = [
                SELECT Id
                FROM Installment__c
                WHERE Commitment__c = :pledge.Id
                ORDER BY Sequence__c
            ];
            Gift__c gift = giftFor(person.Id, pledge.Id, schedule[0].Id, 100);
            insert gift;
            CommitmentService.applyGift(new List<Gift__c>{ gift });

            Map<Id, Gift__c> oldMap = new Map<Id, Gift__c>{ gift.Id => gift.clone(true, true) };
            gift.Installment__c = schedule[1].Id;
            update gift;

            Test.startTest();
            new GiftCommitmentHandler().onAfterUpdate(new List<Gift__c>{ gift }, oldMap);
            Test.stopTest();

            Map<Id, Installment__c> byId = new Map<Id, Installment__c>(
                [SELECT Id, Status__c FROM Installment__c WHERE Commitment__c = :pledge.Id]
            );
            Assert.areEqual(
                'Scheduled',
                byId.get(schedule[0].Id).Status__c,
                'The payment the gift left goes back to Scheduled.'
            );
            Assert.areEqual(
                'Paid',
                byId.get(schedule[1].Id).Status__c,
                'The payment the gift moved to is now paid.'
            );
        }
    }

    private static String statusOf(Id recordId) {
        return recordId.getSObjectType() == Commitment__c.SObjectType
            ? [SELECT Status__c FROM Commitment__c WHERE Id = :recordId WITH SYSTEM_MODE].Status__c
            : [SELECT Status__c FROM Installment__c WHERE Id = :recordId WITH SYSTEM_MODE]
              .Status__c;
    }

    @IsTest
    static void aDeletedGiftReopensItsPaymentAndThePledgeItCompleted() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact person = donor();
            Commitment__c pledge = pledgeWithSchedule(person.Id);
            List<Gift__c> gifts = new List<Gift__c>();
            for (Installment__c payment : [
                SELECT Id
                FROM Installment__c
                WHERE Commitment__c = :pledge.Id
                ORDER BY Sequence__c
            ]) {
                gifts.add(giftFor(person.Id, pledge.Id, payment.Id, 100));
            }
            insert gifts;
            Assert.areEqual('Completed', statusOf(pledge.Id), 'Paid in full, so completed.');

            Test.startTest();
            delete gifts[2];
            Test.stopTest();

            Assert.areEqual(
                'Scheduled',
                statusOf(gifts[2].Installment__c),
                'The payment the deleted gift paid is open again.'
            );
            Assert.areEqual('Active', statusOf(pledge.Id), 'And so is the pledge it completed.');

            undelete gifts[2];

            Assert.areEqual('Paid', statusOf(gifts[2].Installment__c), 'Restored, it pays again.');
            Assert.areEqual('Completed', statusOf(pledge.Id), 'And completes the pledge again.');
        }
    }

    @IsTest
    static void aPledgeStaffCompletedShortOfItsTotalStaysCompleted() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact person = donor();
            Commitment__c pledge = pledgeWithSchedule(person.Id);
            Installment__c first = [
                SELECT Id
                FROM Installment__c
                WHERE Commitment__c = :pledge.Id
                ORDER BY Sequence__c
                LIMIT 1
            ];
            Gift__c gift = giftFor(person.Id, pledge.Id, first.Id, 100);
            insert gift;
            CommitmentService.complete(new Set<Id>{ pledge.Id });

            Test.startTest();
            delete gift;
            Test.stopTest();

            Assert.areEqual('Scheduled', statusOf(first.Id), 'The payment is open again.');
            Assert.areEqual(
                'Completed',
                statusOf(pledge.Id),
                'The deleted gift did not complete it, so staff\'s decision stands.'
            );
        }
    }

    @IsTest
    static void ignoresAGiftThatHasNothingToDoWithACommitment() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact person = donor();
            Gift__c gift = giftFor(person.Id, null, null, 100);
            insert gift;

            Test.startTest();
            new GiftCommitmentHandler().onAfterInsert(new List<Gift__c>{ gift });
            Test.stopTest();

            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Installment__c],
                'A one off gift creates and changes nothing here.'
            );
        }
    }
}
