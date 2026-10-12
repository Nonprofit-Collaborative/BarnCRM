/**
 * The third of the three tests ADR-0016 names: **the IRS language is emitted by code.**
 *
 * An administrator can rewrite every word of the letter. These tests assert what they cannot
 * rewrite, so a template edit that deleted the substantiation language would still produce a valid
 * receipt, and a template edit that tried to assert a value for a gift of goods would not.
 *
 * They compose HTML and read it. PDF bytes are not asserted anywhere, for the reason ADR-0016
 * gives: they cannot be, so the manual visual check is part of the definition of done instead.
 */
@IsTest
private class ReceiptContentRulesTest {
    private static final Date GIFT_DATE = Date.newInstance(2026, 4, 12);

    @TestSetup
    static void setUp() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            ReceiptTestDataFactory.setUpReceipting();
        }
    }

    /**
     * A plain cash gift carries the no goods or services sentence, and states who issued it, how
     * much, and when. Those four are what makes a piece of paper a receipt.
     */
    @IsTest
    static void aPlainCashGiftRendersTheNoGoodsOrServicesSentence() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Gift__c gift = ReceiptTestDataFactory.plainCashGift(null, 250, GIFT_DATE);

            Test.startTest();
            String html = ReceiptContentBuilder.forGift(
                gift,
                'Ana Reyes',
                'HFH-2026-000001',
                Date.newInstance(2027, 1, 15),
                ReceiptTestDataFactory.perGiftTemplateBody()
            );
            Test.stopTest();

            Assert.isTrue(
                html.contains(ReceiptContentBuilder.SENTENCE_NO_GOODS),
                'The no goods or services sentence is on the receipt: ' + html
            );
            Assert.isTrue(
                html.contains('Hope For Homes'),
                'The organization that issued it is named.'
            );
            Assert.isTrue(html.contains('$250.00'), 'The amount is stated.');
            Assert.isTrue(html.contains('12 April 2026'), 'The date of the gift is stated.');
            Assert.isTrue(
                html.contains('HFH-2026-000001'),
                'The receipt number is on the document.'
            );
        }
    }

    /**
     * A gift over the seventy five dollar threshold where the donor received something carries all
     * three parts of the quid pro quo disclosure: what they got, what the organization thinks it
     * was worth, and how much of the payment is deductible.
     */
    @IsTest
    static void aQuidProQuoGiftOverSeventyFiveRendersAllThreeParts() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Gift__c gift = ReceiptTestDataFactory.quidProQuoGift(
                null,
                200,
                40,
                'two tickets to the harvest dinner',
                GIFT_DATE
            );

            Test.startTest();
            String html = ReceiptContentBuilder.forGift(
                gift,
                'Kofi Osei',
                'HFH-2026-000002',
                Date.newInstance(2027, 1, 15),
                ReceiptTestDataFactory.perGiftTemplateBody()
            );
            Test.stopTest();

            Assert.isTrue(
                gift.Amount__c > ReceiptContentBuilder.QUID_PRO_QUO_THRESHOLD,
                'This is the case the disclosure is required for.'
            );
            Assert.isTrue(
                html.contains('two tickets to the harvest dinner'),
                'The benefit is described: ' + html
            );
            Assert.isTrue(
                html.contains('$40.00'),
                'The good faith estimate of its value is stated.'
            );
            Assert.isTrue(
                html.contains('$160.00'),
                'The deductible amount, the payment less the benefit, is stated.'
            );
            Assert.isFalse(
                html.contains(ReceiptContentBuilder.SENTENCE_NO_GOODS),
                'A receipt that discloses a benefit never also says none was provided.'
            );
        }
    }

    /**
     * A gift where the only thing the donor received was an intangible religious benefit carries
     * that sentence, and not a value.
     */
    @IsTest
    static void anIntangibleReligiousBenefitGiftRendersItsOwnSentence() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Gift__c gift = ReceiptTestDataFactory.plainCashGift(null, 500, GIFT_DATE);
            gift.Intangible_Religious_Benefits__c = true;

            Test.startTest();
            String html = ReceiptContentBuilder.forGift(
                gift,
                'Petra Novak',
                'HFH-2026-000003',
                Date.newInstance(2027, 1, 15),
                ReceiptTestDataFactory.perGiftTemplateBody()
            );
            Test.stopTest();

            Assert.isTrue(
                html.contains(ReceiptContentBuilder.SENTENCE_INTANGIBLE_RELIGIOUS),
                'The intangible religious benefits sentence is on the receipt: ' + html
            );
            Assert.isFalse(
                html.contains(ReceiptContentBuilder.SENTENCE_NO_GOODS),
                'It replaces the no goods or services sentence rather than joining it.'
            );
        }
    }

    /**
     * A gift of goods prints the donor's description and **no value the organization asserts**,
     * even though the organization has recorded a fair market value of its own for reporting.
     * Valuing donated property is the donor's responsibility.
     */
    @IsTest
    static void anInKindGiftRendersTheDescriptionAndNoOrganizationAssertedValue() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Gift__c gift = ReceiptTestDataFactory.inKindGift(
                null,
                'a used upright piano, delivered to the community hall',
                GIFT_DATE
            );

            Test.startTest();
            String html = ReceiptContentBuilder.forGift(
                gift,
                'Sam Whitfield',
                'HFH-2026-000004',
                Date.newInstance(2027, 1, 15),
                ReceiptTestDataFactory.perGiftTemplateBody()
            );
            Test.stopTest();

            Assert.isTrue(
                html.contains('a used upright piano, delivered to the community hall'),
                'What the donor gave is described on the receipt: ' + html
            );
            Assert.isFalse(
                html.contains('$900.00'),
                'The fair market value the organization recorded is never printed on the receipt.'
            );
            Assert.isTrue(
                html.contains('has not placed a value'),
                'The receipt says plainly that the organization has not valued the gift.'
            );
        }
    }

    /**
     * The template asked for an amount, and an in-kind gift does not give it one (R-RC12). A
     * currency figure on a receipt for donated property reads as a cash contribution of that
     * amount, which is the one thing the document must not say, so the token renders as a phrase
     * whatever the letter asked for.
     */
    @IsTest
    static void anInKindReceiptPrintsNoAmountWhereTheTemplateAskedForOne() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Gift__c gift = ReceiptTestDataFactory.inKindGift(
                null,
                'a used upright piano, delivered to the community hall',
                1200,
                GIFT_DATE
            );

            Test.startTest();
            String html = ReceiptContentBuilder.forGift(
                gift,
                'Sam Whitfield',
                'HFH-2026-000006',
                Date.newInstance(2027, 1, 15),
                ReceiptTestDataFactory.perGiftTemplateBody()
            );
            Test.stopTest();

            Assert.isFalse(
                html.contains('$1,200.00'),
                'No figure for the goods appears anywhere on the document: ' + html
            );
            Assert.isTrue(
                html.contains(ReceiptContentBuilder.IN_KIND_AMOUNT_PHRASE),
                'The amount token renders as a phrase naming the goods: ' + html
            );
            Assert.areEqual(
                0,
                ReceiptContentBuilder.statedAmountOf(gift),
                'The receipt record states what the document states, which is nothing.'
            );
        }
    }

    /**
     * Where a cash receipt prints an amount, an in-kind receipt says that no value is stated
     * (G-18, ADR-0030). Printing a zero would read as a receipt for nothing, and printing the fair
     * market value the organization recorded is the one thing ADR-0016 forbids, so the document
     * says what is true instead.
     *
     * This proves the same rule as the test above it, from the other end: that one reads the slot
     * the template asked for, this one reads the note the document adds for itself.
     */
    @IsTest
    static void anInKindReceiptStatesNoValueWhereACashReceiptPrintsTheAmount() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Gift__c gift = ReceiptTestDataFactory.inKindGift(
                null,
                'Sixteen folding tables, used',
                GIFT_DATE
            );

            Test.startTest();
            String html = ReceiptContentBuilder.forGift(
                gift,
                'Ines Ferreira',
                'HFH-2026-000011',
                Date.newInstance(2027, 1, 15),
                ReceiptTestDataFactory.perGiftTemplateBody()
            );
            Test.stopTest();

            Assert.isTrue(
                html.contains(ReceiptContentBuilder.AMOUNT_NOT_STATED),
                'The document says no value is stated, rather than printing a figure: ' + html
            );
            Assert.isFalse(
                html.contains('$0.00'),
                'And it does not print a zero, which would read as nothing given.'
            );
            Assert.isFalse(
                html.contains('$900.00'),
                'The fair market value the organization recorded reaches no rendered document.'
            );
            Assert.isTrue(
                html.contains('12 April 2026'),
                'What the receipt does state is the date the goods arrived.'
            );
            Assert.isTrue(
                html.contains('Sixteen folding tables, used'),
                'And what arrived, in the words the donor gave.'
            );
        }
    }

    /**
     * A statement lists a gift of goods without a value and leaves it out of the total, and says
     * why, because a donor who adds the lines up and gets a different number is owed the sentence
     * (R-RC12).
     */
    @IsTest
    static void aStatementListsInKindGiftsWithoutAValueAndOutsideTheTotal() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Gift__c cash = ReceiptTestDataFactory.plainCashGift(
                null,
                100,
                Date.newInstance(2026, 2, 1)
            );
            Gift__c goods = ReceiptTestDataFactory.inKindGift(
                null,
                'Twelve cases of tinned food for the pantry',
                750,
                Date.newInstance(2026, 3, 1)
            );

            Test.startTest();
            String html = ReceiptContentBuilder.forStatement(
                'The Reyes Family',
                new List<Gift__c>{ cash, goods },
                'HFH-2026-000007',
                2026,
                Date.newInstance(2027, 1, 15),
                ReceiptTestDataFactory.statementTemplateBody()
            );
            Test.stopTest();

            Assert.areEqual(
                100,
                ReceiptContentBuilder.cashTotalOf(new List<Gift__c>{ cash, goods }),
                'The stated total is the money, not the money plus a valuation of the goods.'
            );
            Assert.isTrue(
                html.contains('<td class="amount">' + ReceiptContentBuilder.IN_KIND_LINE_AMOUNT),
                'The in-kind line carries no amount: ' + html
            );
            Assert.isFalse(
                html.contains('$750.00'),
                'The value of the goods is nowhere on it: ' + html
            );
            // The sentence says "donor's", and every sentence is HTML escaped on its way into the
            // document, so the document carries the escaped form.
            Assert.isTrue(
                html.contains(ReceiptContentBuilder.SENTENCE_IN_KIND_NOT_IN_TOTAL.escapeHtml4()),
                'The statement explains why the lines do not add up to the total: ' + html
            );
        }
    }

    /**
     * On a year end statement the in-kind line carries no amount either, so the total the
     * statement adds up is the money, and the goods are visibly outside it.
     *
     * The test above proves the same rule with a different statement: this one reads the total
     * through `cashTotalOf` directly, and watches the fair market value stay off the page.
     */
    @IsTest
    static void aStatementLeavesAnInKindLineOutOfTheTotalItStates() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Gift__c cash = ReceiptTestDataFactory.plainCashGift(
                null,
                100,
                Date.newInstance(2026, 2, 1)
            );
            Gift__c goods = ReceiptTestDataFactory.inKindGift(
                null,
                'Two pallets of tinned food',
                Date.newInstance(2026, 11, 3)
            );
            List<Gift__c> gifts = new List<Gift__c>{ cash, goods };

            Test.startTest();
            Decimal total = ReceiptContentBuilder.cashTotalOf(gifts);
            String html = ReceiptContentBuilder.forStatement(
                'Ines Ferreira',
                gifts,
                'HFH-2026-000012',
                2026,
                Date.newInstance(2027, 1, 15),
                ReceiptTestDataFactory.statementTemplateBody()
            );
            Test.stopTest();

            Assert.areEqual(
                100,
                total,
                'The statement totals the money, and the goods add nothing to it.'
            );
            Assert.isTrue(
                html.contains('Two pallets of tinned food'),
                'The gift of goods is still on the statement, where the donor can see it.'
            );
            Assert.isTrue(
                html.contains(ReceiptContentBuilder.AMOUNT_NOT_STATED),
                'The statement states no value for it rather than a figure: ' + html
            );
            Assert.isFalse(
                html.contains('$900.00'),
                'And the fair market value is absent from the statement as well as from the receipt.'
            );
        }
    }

    /**
     * A consolidated statement carries the status of every gift on that gift's own line (R-RC8).
     * A footer saying that some of the year's gifts were refunded is not something a reader can
     * act on.
     */
    @IsTest
    static void aConsolidatedStatementCarriesTheStatusOnEveryLine() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Gift__c received = ReceiptTestDataFactory.plainCashGift(
                null,
                100,
                Date.newInstance(2026, 2, 1)
            );
            Gift__c refunded = ReceiptTestDataFactory.plainCashGift(
                null,
                300,
                Date.newInstance(2026, 6, 1)
            );
            refunded.Status__c = 'Refunded';
            Gift__c writtenOff = ReceiptTestDataFactory.plainCashGift(
                null,
                50,
                Date.newInstance(2026, 9, 1)
            );
            writtenOff.Status__c = 'Written off';

            Test.startTest();
            String html = ReceiptContentBuilder.forStatement(
                'The Reyes Family',
                new List<Gift__c>{ received, refunded, writtenOff },
                'HFH-2026-000005',
                2026,
                Date.newInstance(2027, 1, 15),
                ReceiptTestDataFactory.statementTemplateBody()
            );
            Test.stopTest();

            for (String status : new List<String>{ 'Received', 'Refunded', 'Written off' }) {
                Assert.isTrue(
                    html.contains('<td class="status">' + status + '</td>'),
                    'The status ' + status + ' is on its own line: ' + html
                );
            }
            Assert.areEqual(
                3,
                html.countMatches('<td class="status">'),
                'Every line states a status, and no line is missing one.'
            );
            Assert.isTrue(html.contains('$450.00'), 'The total is the sum of the lines it prints.');
            Assert.isTrue(html.contains('$100.00'), 'The received gift is a line.');
            Assert.isTrue(html.contains('$300.00'), 'The refunded gift is still a line.');
        }
    }
}
