/**
 * The donor-facing receipt sentences live in protected custom labels (audit N12). These tests pin
 * the exact English output so moving the words into labels, or translating them later, cannot
 * silently change what the English receipt says.
 */
// runs-as: deploying user (pure string logic over unsaved records and labels, no DML, SOQL or permission checks)
@IsTest(testFor='ApexClass:ReceiptContentBuilder')
private class ReceiptSentenceLabelsTest {
    @IsTest
    static void constantsReadTheirLabelsWithTheShippedEnglish() {
        System.assertEquals(
            'No goods or services were provided in exchange for this contribution.',
            ReceiptContentBuilder.SENTENCE_NO_GOODS
        );
        System.assertEquals(
            'The only goods or services provided in exchange for this contribution were intangible religious benefits.',
            ReceiptContentBuilder.SENTENCE_INTANGIBLE_RELIGIOUS
        );
        System.assertEquals(
            'the goods or services described below',
            ReceiptContentBuilder.IN_KIND_AMOUNT_PHRASE
        );
        System.assertEquals(
            'No value stated (gift of goods or services)',
            ReceiptContentBuilder.AMOUNT_NOT_STATED
        );
        System.assertEquals('Not valued', ReceiptContentBuilder.IN_KIND_LINE_AMOUNT);
        System.assertEquals(
            'Gifts of goods or services are listed above without a value and are not part of the total, because determining the value of donated property is the donor\'s responsibility.',
            ReceiptContentBuilder.SENTENCE_IN_KIND_NOT_IN_TOTAL
        );
    }

    @IsTest
    static void quidProQuoSentenceFillsItsFormatParameters() {
        Gift__c gift = new Gift__c(
            Amount__c = 1250,
            Benefit_Value__c = 100,
            Benefit_Description__c = ' a dinner '
        );

        List<String> sentences = ReceiptContentBuilder.taxSentencesFor(gift);

        System.assertEquals(1, sentences.size());
        System.assertEquals(
            'In exchange for this contribution you received a dinner. Our good faith estimate of the value of those goods or services is $100.00. The amount of your contribution that is deductible for federal income tax purposes is limited to the excess of the amount contributed over that value, which is $1,150.00.',
            sentences[0]
        );
    }

    @IsTest
    static void quidProQuoSentenceNamesGenericBenefitWhenNoDescription() {
        Gift__c gift = new Gift__c(Amount__c = 50, Benefit_Value__c = 80);

        String sentence = ReceiptContentBuilder.taxSentencesFor(gift)[0];

        System.assert(
            sentence.startsWith(
                'In exchange for this contribution you received goods or services. '
            ),
            sentence
        );
        System.assert(sentence.endsWith('which is $0.00.'), sentence);
    }

    @IsTest
    static void inKindSentenceKeepsItsApostropheAndFillsTheDescription() {
        Gift__c gift = new Gift__c(Type__c = 'In-kind', In_Kind_Description__c = ' two laptops ');

        List<String> sentences = ReceiptContentBuilder.taxSentencesFor(gift);

        System.assertEquals(2, sentences.size());
        System.assertEquals(
            'You gave the following goods or services: two laptops. This organization has not placed a value on your gift; determining the value of donated property is the donor\'s responsibility.',
            sentences[0]
        );
        System.assertEquals(ReceiptContentBuilder.SENTENCE_NO_GOODS, sentences[1]);
    }

    @IsTest
    static void inKindSentenceUsesTheDefaultDescriptionWhenBlank() {
        Gift__c gift = new Gift__c(Type__c = 'In-kind');

        String sentence = ReceiptContentBuilder.taxSentencesFor(gift)[0];

        System.assert(
            sentence.startsWith(
                'You gave the following goods or services: goods or services, described to us by the donor. '
            ),
            sentence
        );
    }
}
