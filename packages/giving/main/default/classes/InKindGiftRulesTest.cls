/**
 * What an in-kind gift has to say about itself before it is allowed to be saved (R-G12, G-18).
 *
 * A gift of goods with no description gives the receipt nothing to print in place of an amount,
 * a gift of goods carrying an amount puts goods into the money rollups, and a gift of money
 * carrying a fair market value gives the receipt goods to describe that nobody gave. All three
 * are cheap to refuse here and expensive to find later, on a document a donor has filed with a
 * tax return.
 *
 * `GiftInKindTest` covers the same rules from the record's side, including the receipt lock and
 * Quick Gift Entry. This class is the validation rules on their own, asserted through DML.
 *
 * **These tests have not been executed.** No Salesforce org was reachable while this feature was
 * built, so no Apex in this repository has been run and no validation rule has been deployed. They
 * are written to be run against the first org that exists.
 */
@IsTest
private class InKindGiftRulesTest {
    private static final String IN_KIND = 'In-kind';

    @TestSetup
    static void makeData() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            GivingTestDataFactory.insertDefaultFund();
            GivingTestDataFactory.insertHouseholdContact(
                'The Whitfield Family',
                'Sam',
                'Whitfield'
            );
        }
    }

    private static Contact donor() {
        return [SELECT Id FROM Contact LIMIT 1];
    }

    private static Gift__c inKindGift(Decimal value, String description) {
        Gift__c gift = GivingTestDataFactory.buildGift(donor().Id, 0);
        gift.Type__c = IN_KIND;
        gift.Gift_Date__c = Date.today();
        gift.In_Kind_Description__c = description;
        gift.Fair_Market_Value__c = value;
        return gift;
    }

    private static DmlException refusalFrom(Gift__c gift) {
        try {
            insert gift;
            return null;
        } catch (DmlException refused) {
            return refused;
        }
    }

    /** What a correctly recorded gift of goods looks like, so the rest of the class has a control. */
    @IsTest
    static void anInKindGiftWithADescriptionAndNoAmountSaves() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Test.startTest();
            insert inKindGift(900, 'a used upright piano, delivered to the community hall');
            Test.stopTest();

            Gift__c saved = [
                SELECT Id, Type__c, Amount__c, Fair_Market_Value__c, In_Kind_Description__c
                FROM Gift__c
                LIMIT 1
            ];
            Assert.areEqual(
                IN_KIND,
                saved.Type__c,
                'The gift is recorded as goods rather than money.'
            );
            Assert.areEqual(
                0,
                saved.Amount__c,
                'An in-kind gift carries no amount: goods are not money the organization holds (R-G12).'
            );
            Assert.areEqual(
                900,
                saved.Fair_Market_Value__c,
                'What it was worth is on the attribute no money rollup reads.'
            );
        }
    }

    @IsTest
    static void anInKindGiftWithoutADescriptionIsRefused() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Gift__c gift = inKindGift(900, null);

            Test.startTest();
            DmlException refused = refusalFrom(gift);
            Test.stopTest();

            Assert.isNotNull(refused, 'A gift of goods that says nothing about them is refused.');
            Assert.isTrue(
                refused.getMessage().contains('Describe what was given'),
                'The message says what to do: ' + refused.getMessage()
            );
        }
    }

    /**
     * One gift keeps its one number in one place. The branch that built the receipt side of G-18
     * proved this by refusing an amount that disagreed with the fair market value; the rule that
     * landed says it more simply, by refusing any amount at all on a gift of goods.
     */
    @IsTest
    static void anInKindGiftCarryingAnAmountIsRefused() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Gift__c gift = inKindGift(900, 'Two laptops for the homework club');
            gift.Amount__c = 900;

            Test.startTest();
            DmlException refused = refusalFrom(gift);
            Test.stopTest();

            Assert.isNotNull(refused, 'A figure in Amount would put goods into the money rollups.');
            Assert.isTrue(
                refused.getMessage().contains('An in-kind gift has no amount'),
                'The message says where the value goes: ' + refused.getMessage()
            );
        }
    }

    @IsTest
    static void anInKindGiftWithANegativeFairMarketValueIsRefused() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Gift__c gift = inKindGift(-50, 'Twelve cases of tinned food for the pantry');

            Test.startTest();
            DmlException refused = refusalFrom(gift);
            Test.stopTest();

            Assert.isNotNull(
                refused,
                'Goods are worth nothing or something, never less than nothing.'
            );
            Assert.isTrue(
                refused.getMessage().contains('cannot be negative'),
                'The message names the field: ' + refused.getMessage()
            );
        }
    }

    /**
     * The fair market value is genuinely optional, because an organization often receives the
     * goods before anybody has valued them, and a gift that cannot be saved until then is a gift
     * recorded late or not at all.
     */
    @IsTest
    static void anInKindGiftWithNoFairMarketValueYetSaves() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Gift__c gift = inKindGift(null, 'A pallet of school exercise books');

            Test.startTest();
            insert gift;
            Test.stopTest();

            Gift__c saved = [SELECT Id, Fair_Market_Value__c FROM Gift__c WHERE Id = :gift.Id];
            Assert.isNull(
                saved.Fair_Market_Value__c,
                'The value can be added later, and nothing on the receipt depends on it.'
            );
        }
    }

    @IsTest
    static void aGiftOfMoneyCarryingInKindFieldsIsRefused() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Gift__c gift = GivingTestDataFactory.buildGift(donor().Id, 500);
            gift.Type__c = 'Cash';
            gift.In_Kind_Description__c = 'A used minibus in working order';

            Test.startTest();
            DmlException refused = refusalFrom(gift);
            Test.stopTest();

            Assert.isNotNull(refused, 'A cash receipt must not end up describing goods.');
            Assert.isTrue(
                refused.getMessage().contains('belong to a gift of goods or services'),
                'The message offers both ways out: ' + refused.getMessage()
            );
        }
    }
}
