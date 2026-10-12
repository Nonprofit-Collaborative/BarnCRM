/**
 * The letter as the Receipts page edits and previews it (ADR-0065,
 * `0065-receipt-letters-are-edited-as-rich-text.md`).
 *
 * Three things are asserted. The editor never shows the old letterhead block, so the next save
 * hands the letterhead to the package. The preview runs the real document path for a sample
 * gift and writes nothing. And a gift lines token on a paragraph of its own, which is how the
 * rich text editor stores it, becomes the table rather than a table inside a paragraph.
 *
 * These tests have not been executed: no Salesforce org exists in this environment.
 */
@IsTest
private class ReceiptLetterEditorTest {
    private static final String LEGACY_BODY =
        '<div class="letterhead">\n  <h1>{{OrganizationName}}</h1>\n  <p>{{OrganizationAddress}}</p>\n</div>\n' +
        '<p>Dear {{DonorName}},</p>';

    @TestSetup
    static void setUp() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            ReceiptTestDataFactory.setUpReceipting();
        }
    }

    @IsTest
    static void theEditorIsGivenTheLetterWithoutTheOldLetterhead() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Assert.areEqual(
                '<p>Dear {{DonorName}},</p>',
                ReceiptTemplateService.letterOf(LEGACY_BODY),
                'The old letterhead block is not offered for editing.'
            );
        }
    }

    @IsTest
    static void aLetterWithoutTheOldLetterheadIsGivenToTheEditorUnchanged() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            String body = '<p>Thank you for supporting {{OrganizationName}}.</p>';
            Assert.areEqual(body, ReceiptTemplateService.letterOf(body), 'Nothing is removed.');
            Assert.isNull(ReceiptTemplateService.letterOf(null), 'An empty body stays empty.');
        }
    }

    @IsTest
    static void theReceiptsPageReadsTheLetterWithoutTheOldLetterhead() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Receipt_Template__c legacy = new Receipt_Template__c(
                Name = 'Saved before the editor',
                Type__c = ReceiptNumberSequence.TYPE_PER_GIFT,
                Body__c = LEGACY_BODY,
                Active__c = false
            );
            insert legacy;

            Test.startTest();
            List<ReceiptController.TemplateView> views = ReceiptController.getTemplates();
            Test.stopTest();

            for (ReceiptController.TemplateView view : views) {
                if (view.id == legacy.Id) {
                    Assert.isFalse(
                        view.body.contains('letterhead'),
                        'The page never offers the old block: ' + view.body
                    );
                    return;
                }
            }
            Assert.fail('The letter saved before the editor was not listed.');
        }
    }

    @IsTest
    static void thePreviewFillsInASampleGiftAndWritesNothing() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Integer dmlBefore = Limits.getDmlStatements();
            Integer receiptsBefore = [SELECT COUNT() FROM Receipt__c];

            Test.startTest();
            String html = ReceiptController.previewTemplate(
                ReceiptNumberSequence.TYPE_PER_GIFT,
                '<p>Dear {{DonorName}}, thank you for {{Amount}}.</p>'
            );
            Test.stopTest();

            Assert.isTrue(
                html.contains(Label.Giving_Receipt_PreviewDonor.escapeHtml4()),
                'The sample donor is named: ' + html
            );
            Assert.isTrue(html.contains('$100.00'), 'The sample amount is filled in: ' + html);
            Assert.isTrue(
                html.contains('class="orgname"'),
                'The letterhead the package prints is in the preview: ' + html
            );
            Assert.isTrue(
                html.contains(ReceiptContentBuilder.SENTENCE_NO_GOODS),
                'So are the tax sentences: ' + html
            );
            Assert.isFalse(html.contains('<body>'), 'Only the inside of the document comes back.');
            Assert.areEqual(dmlBefore, Limits.getDmlStatements(), 'A preview writes nothing.');
            Assert.areEqual(
                receiptsBefore,
                [SELECT COUNT() FROM Receipt__c],
                'And issues no receipt.'
            );
        }
    }

    @IsTest
    static void aStatementPreviewPutsTheGiftLinesWhereTheParagraphTokenIs() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Test.startTest();
            String html = ReceiptController.previewTemplate(
                ReceiptNumberSequence.TYPE_STATEMENT,
                '<p>Dear {{DonorName}},</p><p>{{GiftLines}}</p><p>Thank you.</p>'
            );
            Test.stopTest();

            Assert.isTrue(html.contains('<table class="gifts">'), 'The lines are a table: ' + html);
            Assert.isFalse(
                html.contains('<p><table'),
                'The table replaces the paragraph rather than sitting inside it: ' + html
            );
            Assert.areEqual(
                1,
                html.countMatches('<table class="gifts">'),
                'The lines print once, where the letter put them: ' + html
            );
            Assert.isTrue(
                html.contains('$100.00') && html.contains('$250.00'),
                'Both sample gifts are lines: ' + html
            );
        }
    }

    @IsTest
    static void anEmptyLetterCannotBePreviewed() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Test.startTest();
            try {
                ReceiptController.previewTemplate(ReceiptNumberSequence.TYPE_PER_GIFT, ' ');
                Assert.fail('An empty letter was previewed.');
            } catch (AuraHandledException refused) {
                Assert.areEqual(
                    Label.Giving_Receipt_EmptyTemplate,
                    refused.getMessage(),
                    'It says what to do.'
                );
            }
            Test.stopTest();
        }
    }
}
