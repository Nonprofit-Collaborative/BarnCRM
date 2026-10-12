/**
 * In-kind gifts (G-18, ADR-0030), from the two sides that can go wrong.
 *
 * The first is arithmetic: a gift of goods carries no amount, its worth sits on Fair Market Value,
 * and nothing that adds money up is allowed to see it. The second is the document: the description
 * is printed and the value never is, so the description is locked by the receipt and the value is
 * deliberately not.
 *
 * The receipt content itself is asserted in `ReceiptContentRulesTest`, where the rest of the IRS
 * language lives.
 */
@IsTest
private class GiftInKindTest {
    private static final String RECEIPT_NUMBER = 'R-2026-000318';
    private static final String DESCRIBED = 'A used upright piano, delivered to the community hall';

    @TestSetup
    static void makeData() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            GivingTestDataFactory.insertDefaultFund();
            Contact donor = GivingTestDataFactory.insertHouseholdContact(
                'The Ferreira Family',
                'Ines',
                'Ferreira'
            );
            Gift__c gift = GivingTestDataFactory.buildGift(donor.Id, 0);
            gift.Type__c = 'In-kind';
            gift.Gift_Date__c = Date.newInstance(2026, 5, 4);
            gift.In_Kind_Description__c = DESCRIBED;
            gift.Fair_Market_Value__c = 900;
            insert gift;
            // The number comes from the receipting feature's door, because a person cannot type one
            // onto a gift (ADR-0033).
            GiftService.recordReceiptNumbers(new Map<Id, String>{ gift.Id => RECEIPT_NUMBER });
        }
    }

    private static Gift__c receiptedGift() {
        return [
            SELECT
                Id,
                Amount__c,
                Type__c,
                Gift_Date__c,
                In_Kind_Description__c,
                Fair_Market_Value__c,
                Receipt_Number__c
            FROM Gift__c
            WHERE Receipt_Number__c = :RECEIPT_NUMBER
            LIMIT 1
        ];
    }

    private static String refusalFrom(Gift__c gift) {
        try {
            update gift;
            return null;
        } catch (DmlException refused) {
            return refused.getDmlMessage(0);
        }
    }

    /**
     * The gift as it lands: no amount, the worth on its own attribute, and one allocation for
     * nothing so that R-GA1 still holds and the fund reports are not short of a designation.
     */
    @IsTest
    static void anInKindGiftIsSavedWithNoAmountAndItsWorthOnFairMarketValue() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Gift__c gift = receiptedGift();

            Assert.areEqual(
                0,
                gift.Amount__c,
                'An in-kind gift carries no amount: goods are not money the organization holds.'
            );
            Assert.areEqual(
                900,
                gift.Fair_Market_Value__c,
                'What the goods were worth is recorded, on the attribute no money rollup reads.'
            );
            Assert.areEqual(
                DESCRIBED,
                gift.In_Kind_Description__c,
                'And what arrived is described, because that description is the receipt.'
            );

            List<Gift_Allocation__c> allocations = [
                SELECT Amount__c
                FROM Gift_Allocation__c
                WHERE Gift__c = :gift.Id
            ];
            Assert.areEqual(
                1,
                allocations.size(),
                'A gift with no designation still gets the default one (R-G5), in-kind included.'
            );
            Assert.areEqual(
                0,
                allocations[0].Amount__c,
                'The allocations total the gift, and the gift is zero (R-GA1).'
            );
        }
    }

    /**
     * The description is on the document the donor is holding, so the receipt lock covers it
     * exactly as it covers the amount of a cash gift (R-G4, ADR-0030 item 6).
     */
    @IsTest
    static void theReceiptLockRefusesAChangeToTheDescriptionOfWhatWasGiven() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Gift__c gift = receiptedGift();

            Test.startTest();
            String refusal = refusalFrom(
                new Gift__c(Id = gift.Id, In_Kind_Description__c = 'A grand piano, actually')
            );
            Test.stopTest();

            Assert.isTrue(
                refusal != null && refusal.contains(Label.Giving_Gift_ReceiptLocked),
                'A receipted in-kind gift cannot be re-described: the donor already has the words.'
            );
            Assert.areEqual(
                DESCRIBED,
                receiptedGift().In_Kind_Description__c,
                'So the description still matches the receipt that was issued.'
            );
        }
    }

    /**
     * The fair market value is on no document, so correcting it cannot make the record disagree
     * with the receipt. Locking it would mean voiding a valid receipt to fix an internal
     * reporting figure, which is a worse outcome than letting the figure be corrected.
     */
    @IsTest
    static void theReceiptLockLeavesTheFairMarketValueEditable() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Gift__c gift = receiptedGift();

            Test.startTest();
            String refusal = refusalFrom(new Gift__c(Id = gift.Id, Fair_Market_Value__c = 1200));
            Test.stopTest();

            Assert.isNull(
                refusal,
                'The fair market value appears on no receipt, so no receipt is contradicted by it.'
            );
            Assert.areEqual(
                1200,
                receiptedGift().Fair_Market_Value__c,
                'And the corrected figure is what the organization now reports.'
            );
        }
    }

    /**
     * Quick Gift Entry: choosing In-kind replaces the amount with the two attributes a gift of
     * goods has, and the description is required because it is what the receipt will print.
     */
    @IsTest
    static void quickEntryRefusesAnInKindGiftWithNoDescriptionAndAsksForNoAmount() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            QuickGiftEntryController.GiftInput input = new QuickGiftEntryController.GiftInput();
            input.donorContactId = [SELECT Id FROM Contact LIMIT 1].Id;
            input.giftDate = Date.today();
            input.giftType = 'In-kind';

            Test.startTest();
            List<QuickGiftEntryController.FieldError> errors = input.validate();
            Test.stopTest();

            Map<String, String> byField = new Map<String, String>();
            for (QuickGiftEntryController.FieldError error : errors) {
                byField.put(error.field, error.message);
            }
            Assert.isTrue(
                byField.containsKey('inKindDescription'),
                'A gift of goods with nothing written down cannot be receipted, so it is refused.'
            );
            Assert.areEqual(
                Label.Giving_QuickGiftEntry_ErrorInKindDescriptionRequired,
                byField.get('inKindDescription'),
                'And the message names the description rather than talking about amounts.'
            );
            Assert.isFalse(
                byField.containsKey('amount'),
                'No amount is asked for: an in-kind gift has none, and asking invites the mistake.'
            );
        }
    }

    /** A negative worth is not a worth. */
    @IsTest
    static void quickEntryRefusesANegativeFairMarketValue() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            QuickGiftEntryController.GiftInput input = new QuickGiftEntryController.GiftInput();
            input.donorContactId = [SELECT Id FROM Contact LIMIT 1].Id;
            input.giftDate = Date.today();
            input.giftType = 'In-kind';
            input.inKindDescription = DESCRIBED;
            input.fairMarketValue = -50;

            Test.startTest();
            List<QuickGiftEntryController.FieldError> errors = input.validate();
            Test.stopTest();

            Assert.areEqual(
                1,
                errors.size(),
                'The description is there, so only the value is wrong.'
            );
            Assert.areEqual(
                'fairMarketValue',
                errors[0].field,
                'And the message is shown beside the box that has the negative number in it.'
            );
        }
    }

    /**
     * What Quick Gift Entry builds: zero in the amount whatever the browser sent, the two in-kind
     * attributes filled, and, on a gift that is not in-kind, both of them cleared. A description
     * left behind by somebody switching the type back and forth would otherwise be read later as
     * a gift of goods.
     */
    @IsTest
    static void quickEntryBuildsAnInKindGiftWithNoAmountAndClearsTheFieldsOnACashGift() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Id donorId = [SELECT Id FROM Contact LIMIT 1].Id;

            QuickGiftEntryController.GiftInput goods = new QuickGiftEntryController.GiftInput();
            goods.donorContactId = donorId;
            goods.giftDate = Date.newInstance(2026, 5, 4);
            goods.giftType = 'In-kind';
            goods.amount = 900;
            goods.inKindDescription = DESCRIBED;
            goods.fairMarketValue = 900;

            QuickGiftEntryController.GiftInput cash = new QuickGiftEntryController.GiftInput();
            cash.donorContactId = donorId;
            cash.giftDate = Date.newInstance(2026, 5, 4);
            cash.giftType = 'Check';
            cash.amount = 250;
            cash.inKindDescription = DESCRIBED;
            cash.fairMarketValue = 900;

            Test.startTest();
            Gift__c goodsGift = goods.toGift();
            Gift__c cashGift = cash.toGift();
            Test.stopTest();

            Assert.areEqual(
                0,
                goodsGift.Amount__c,
                'An amount typed before the type was chosen never becomes money on an in-kind gift.'
            );
            Assert.areEqual(
                900,
                goodsGift.Fair_Market_Value__c,
                'The figure that was typed is kept, on the attribute that is reported separately.'
            );
            Assert.areEqual(
                DESCRIBED,
                goodsGift.In_Kind_Description__c,
                'And the description survives to the record, because the receipt will print it.'
            );

            Assert.areEqual(
                250,
                cashGift.Amount__c,
                'A gift of money keeps the amount it was given.'
            );
            Assert.isNull(
                cashGift.In_Kind_Description__c,
                'A gift that is not in-kind carries no in-kind description, whatever was sent.'
            );
            Assert.isNull(
                cashGift.Fair_Market_Value__c,
                'And no fair market value, so it can never be read later as a gift of goods.'
            );
        }
    }
}
