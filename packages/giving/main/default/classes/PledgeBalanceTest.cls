/**
 * A pledge's balance, and the pledge balance of its donor and household, through the record
 * save and the refund action, with the shipped rollups running as they do in an org.
 *
 * Two defects found by the final release audit are pinned here. A pledge entered with an amount
 * and a number of installments but no expected total read a balance of zero before anything was
 * paid and a negative one after (R-CM5). And refunding a pledge payment left Paid To Date where it
 * was, because the negative gift did not name the pledge, so every pledge balance stayed too low
 * (R-G3, R-CM4).
 */
@IsTest(testFor='ApexClass:CommitmentService, ApexClass:GiftCommitmentHandler')
private class PledgeBalanceTest {
    @TestSetup
    static void makeData() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            GivingTestDataFactory.insertDefaultFund();
            GivingTestDataFactory.insertHouseholdContact('The Nolan Family', 'Ana', 'Nolan');
            GivingRollupTestData.installShippedRollups();
        }
    }

    private static Contact ana() {
        return [SELECT Id, AccountId FROM Contact WHERE LastName = 'Nolan' LIMIT 1];
    }

    private static Commitment__c pledgeOf(Id donorId, Decimal amount, Integer installments) {
        return new Commitment__c(
            Type__c = 'Pledge',
            Status__c = 'Active',
            Donor_Contact__c = donorId,
            Amount__c = amount,
            Frequency__c = 'Monthly',
            Start_Date__c = Date.today(),
            Installments_Planned__c = installments
        );
    }

    private static Commitment__c reread(Id pledgeId) {
        return [
            SELECT Status__c, Expected_Total__c, Paid_To_Date__c, Balance__c
            FROM Commitment__c
            WHERE Id = :pledgeId
            WITH SYSTEM_MODE
        ];
    }

    private static Installment__c firstPaymentOf(Id pledgeId) {
        return [
            SELECT Id, Status__c, Paid_Amount__c
            FROM Installment__c
            WHERE Commitment__c = :pledgeId
            WITH SYSTEM_MODE
            ORDER BY Sequence__c
            LIMIT 1
        ];
    }

    /** A payment of `amount` against the pledge, linked to its first open payment by the save. */
    private static Gift__c pay(Id donorId, Id pledgeId, Decimal amount) {
        Gift__c gift = GivingTestDataFactory.buildGift(donorId, amount);
        gift.Gift_Date__c = Date.today();
        gift.Commitment__c = pledgeId;
        insert gift;
        GivingRollupTestData.nextSave();
        return gift;
    }

    /**
     * Ana pledges 300 a month for three months and nobody types the total, as the record page
     * allows. The total is 900, the balance 900, and after a payment of 100 the balance is 800 on
     * the pledge, on Ana and on her household.
     */
    @IsTest
    static void aPledgeEnteredWithoutATotalHasTheFullBalance() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact person = ana();
            Commitment__c pledge = pledgeOf(person.Id, 300, 3);
            Database.insert(pledge, AccessLevel.USER_MODE);
            GivingRollupTestData.nextSave();

            Commitment__c saved = reread(pledge.Id);
            Assert.areEqual(900, saved.Expected_Total__c, 'Three payments of 300.');
            Assert.areEqual(900, saved.Balance__c, 'Nothing has been paid yet.');
            Assert.areEqual(
                900,
                GivingRollupTestData.person(person.Id).Pledge_Balance__c,
                'Ana owes the whole pledge.'
            );

            Test.startTest();
            pay(person.Id, pledge.Id, 100);
            Test.stopTest();

            Assert.areEqual(800, reread(pledge.Id).Balance__c, 'The pledge balance.');
            Contact paid = GivingRollupTestData.person(person.Id);
            GivingTestDataFactory.assertRollupWrote(paid.Pledge_Balance__c);
            Assert.areEqual(800, paid.Pledge_Balance__c, 'Ana\'s pledge balance.');
            Assert.areEqual(
                800,
                GivingRollupTestData.account(person.AccountId).Pledge_Balance__c,
                'The household\'s pledge balance.'
            );
        }
    }

    /**
     * Ana pays 100 of a 300 pledge and asks for 40 back. The pledge has been paid 60, so 240 is
     * still owed, and the payment is partly paid.
     */
    @IsTest
    static void aPartialRefundRaisesThePledgeBalance() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact person = ana();
            Commitment__c pledge = pledgeOf(person.Id, 100, 3);
            insert pledge;
            GivingRollupTestData.nextSave();
            Gift__c gift = pay(person.Id, pledge.Id, 100);

            Test.startTest();
            GiftService.refund(gift.Id, 40, 'Donor asked for part of it back');
            Test.stopTest();

            Commitment__c refunded = reread(pledge.Id);
            Assert.areEqual(60, refunded.Paid_To_Date__c, 'Paid to date, net of the refund.');
            Assert.areEqual(240, refunded.Balance__c, 'Still owed.');
            Assert.areEqual('Active', refunded.Status__c, 'The pledge is still running.');
            Installment__c first = firstPaymentOf(pledge.Id);
            Assert.areEqual('Partially paid', first.Status__c, 'Sixty of the hundred is paid.');
            Assert.areEqual(60, first.Paid_Amount__c, 'The payment\'s paid amount.');
            Assert.areEqual(
                240,
                GivingRollupTestData.person(person.Id).Pledge_Balance__c,
                'Ana\'s pledge balance.'
            );
            Assert.areEqual(
                240,
                GivingRollupTestData.account(person.AccountId).Pledge_Balance__c,
                'The household\'s pledge balance.'
            );
        }
    }

    /**
     * Ana pays a pledge of 100 in full, which completes it, and then asks for all of it back. The
     * pledge is open again with the whole 100 owed, and the payment is unpaid.
     */
    @IsTest
    static void aFullRefundReopensTheCompletedPledge() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact person = ana();
            Commitment__c pledge = pledgeOf(person.Id, 100, 1);
            insert pledge;
            GivingRollupTestData.nextSave();
            Gift__c gift = pay(person.Id, pledge.Id, 100);
            Assert.areEqual('Completed', reread(pledge.Id).Status__c, 'Paid in full.');

            Test.startTest();
            GiftService.refund(gift.Id, 100, 'Donor asked for it back');
            Test.stopTest();

            Commitment__c refunded = reread(pledge.Id);
            Assert.areEqual('Active', refunded.Status__c, 'Short of its total again, so open.');
            Assert.areEqual(0, refunded.Paid_To_Date__c, 'Nothing is held against it.');
            Assert.areEqual(100, refunded.Balance__c, 'The whole pledge is owed.');
            Installment__c first = firstPaymentOf(pledge.Id);
            Assert.areEqual('Scheduled', first.Status__c, 'The payment is unpaid again.');
            Assert.areEqual(0, first.Paid_Amount__c, 'The payment\'s paid amount.');
            Assert.areEqual(
                100,
                GivingRollupTestData.person(person.Id).Pledge_Balance__c,
                'Ana\'s pledge balance.'
            );
            Assert.areEqual(
                100,
                GivingRollupTestData.account(person.AccountId).Pledge_Balance__c,
                'The household\'s pledge balance.'
            );
        }
    }
}
