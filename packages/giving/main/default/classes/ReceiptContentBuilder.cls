/**
 * Composes the HTML of a receipt or a year end statement.
 *
 * **The tax content is code, not template prose (ADR-0016, R-RC7).** An administrator writes the
 * letter around the sentences below and can neither edit nor delete them: whatever the template
 * says, this class appends what IRS Publication 1771 requires. That is deliberate. A template is
 * the thing an organization changes in a hurry in January, and a receipt that has lost its
 * substantiation language is not a receipt, it is a thank you note that a donor will find out about
 * from their accountant.
 *
 * Nothing here renders a PDF. It produces HTML restricted to what the Visualforce PDF rendering
 * service supports: no web fonts, no JavaScript, no `data:` URI images, and page furniture only
 * through `@page` margin boxes.
 *
 * The organization's branding is printed the same way, and for the same reason (R-RC13): the legal
 * name and the address go above the letter when the template did not place them itself, so an
 * administrator cannot produce a document with no organization on it. The logo is optional and
 * comes from `ReceiptLogoSource`, whose delivery route is **unverified in an org**: ADR-0016's
 * second spike is open, and a receipt with no images at all is a valid receipt.
 */
public with sharing class ReceiptContentBuilder {
    /**
     * The payment above which IRS Publication 1771 requires a written quid pro quo disclosure.
     * A statutory number, so it is a constant and not a setting: an administrator who could lower
     * it could put an organization on the wrong side of a rule they did not know they were
     * changing.
     *
     * The package discloses a recorded benefit whatever the amount, which is stricter than the
     * statute and never states that no goods or services were provided when some were.
     */
    public static final Decimal QUID_PRO_QUO_THRESHOLD = 75;

    public static final String SENTENCE_NO_GOODS = 'No goods or services were provided in exchange for this contribution.';
    public static final String SENTENCE_INTANGIBLE_RELIGIOUS = 'The only goods or services provided in exchange for this contribution were intangible religious benefits.';

    /**
     * What an in-kind gift puts where the template asked for an amount (R-RC12). A currency figure
     * there reads as a cash contribution of that amount, which is the one thing a document for
     * donated property must not say.
     */
    public static final String IN_KIND_AMOUNT_PHRASE = 'the goods or services described below';

    /**
     * What every document states in place of a figure, for a gift of goods (G-18, ADR-0030,
     * R-RC12). Printing the zero a cash field would carry reads as a receipt for nothing, and
     * printing the fair market value the organization recorded is the one thing ADR-0016 forbids.
     * So the document says what is true: the organization has not stated a value.
     */
    public static final String AMOUNT_NOT_STATED = 'No value stated (gift of goods or services)';

    /** What an in-kind gift puts in the amount column of a statement (R-RC12). */
    public static final String IN_KIND_LINE_AMOUNT = 'Not valued';

    /** Why a statement's total is smaller than the sum of the lines above it (R-RC12). */
    public static final String SENTENCE_IN_KIND_NOT_IN_TOTAL = 'Gifts of goods or services are listed above without a value and are not part of the total, because determining the value of donated property is the donor\'s responsibility.';

    private static final String IN_KIND = 'In-kind';
    private static final String TOKEN_OPEN = '{{';
    private static final String TOKEN_CLOSE = '}}';
    private static final Set<String> RAW_TOKENS = new Set<String>{ 'GiftLines' };

    public class ReceiptContentException extends Exception {
    }

    /** The organization's identity as it is printed, read once and passed down. */
    public class OrganizationDetails {
        public String legalName;
        public String taxId;
        public String address;
        public String placeOfIssue;
        public String signerName;
        public String signerTitle;
    }

    /**
     * The organization's identity from settings. The legal name is the one value a receipt cannot
     * be produced without, so its absence is an error with a readable message rather than a
     * document with a blank at the top.
     */
    public static OrganizationDetails organizationDetails() {
        Nonprofit_Settings__c core = Nonprofit_Settings__c.getOrgDefaults();
        Giving_Settings__c giving = Giving_Settings__c.getOrgDefaults();
        if (String.isBlank(core.Organization_Legal_Name__c)) {
            throw new ReceiptContentException(Label.Giving_Receipt_OrganizationIncomplete);
        }
        OrganizationDetails details = new OrganizationDetails();
        details.legalName = core.Organization_Legal_Name__c;
        details.taxId = giving.Organization_EIN__c;
        details.address = core.Organization_Address__c;
        details.placeOfIssue = giving.Receipt_Place_Of_Issue__c;
        details.signerName = giving.Receipt_Signer_Name__c;
        details.signerTitle = giving.Receipt_Signer_Title__c;
        return details;
    }

    // -------------------------------------------------------------- the tax sentences

    /**
     * What this gift's receipt must say about goods and services, in order (R-RC7).
     *
     * An in-kind gift contributes its own sentence first: the donor's description of what they
     * gave, and **never a value the organization asserts**, because in the United States valuing
     * donated property is the donor's responsibility and an organization that puts a number on it
     * has handed the donor a problem.
     */
    public static List<String> taxSentencesFor(Gift__c gift) {
        List<String> sentences = new List<String>();

        if (isInKind(gift)) {
            String described = String.isBlank(gift.In_Kind_Description__c)
                ? 'goods or services, described to us by the donor'
                : gift.In_Kind_Description__c.trim();
            sentences.add(
                'You gave the following goods or services: ' +
                    described +
                    '. This organization has not placed a value on your gift; determining the value of donated property is the donor\'s responsibility.'
            );
        }

        if (gift.Intangible_Religious_Benefits__c == true) {
            sentences.add(SENTENCE_INTANGIBLE_RELIGIOUS);
            return sentences;
        }

        if (hasRecordedBenefit(gift)) {
            sentences.add(quidProQuoSentence(gift));
            return sentences;
        }

        sentences.add(SENTENCE_NO_GOODS);
        return sentences;
    }

    /**
     * The quid pro quo disclosure: what the donor received, the organization's good faith estimate
     * of its value, and the amount that is deductible, which is the payment less that estimate.
     *
     * The deductible amount is computed here rather than stored on the gift, because a stored copy
     * of a subtraction is a second place for it to be wrong.
     */
    private static String quidProQuoSentence(Gift__c gift) {
        Decimal paid = gift.Amount__c == null ? 0 : gift.Amount__c;
        Decimal benefit = gift.Benefit_Value__c == null ? 0 : gift.Benefit_Value__c;
        Decimal deductible = paid - benefit;
        if (deductible < 0) {
            deductible = 0;
        }
        String described = String.isBlank(gift.Benefit_Description__c)
            ? 'goods or services'
            : gift.Benefit_Description__c.trim();
        return 'In exchange for this contribution you received ' +
            described +
            '. Our good faith estimate of the value of those goods or services is ' +
            money(benefit) +
            '. The amount of your contribution that is deductible for federal income tax purposes is limited to the excess of the amount contributed over that value, which is ' +
            money(deductible) +
            '.';
    }

    /**
     * A benefit is disclosed when the organization recorded one: a description, a value, or both.
     * A value of zero with a description is still a benefit worth naming, and a description with
     * no value is a benefit whose estimate an administrator has not typed yet, which the receipt
     * says plainly rather than hiding.
     */
    private static Boolean hasRecordedBenefit(Gift__c gift) {
        return String.isNotBlank(gift.Benefit_Description__c) || gift.Benefit_Value__c != null;
    }

    // ------------------------------------------------------------------- the documents

    /** One gift's receipt. */
    public static String forGift(
        Gift__c gift,
        String donorName,
        String receiptNumber,
        Date issueDate,
        String templateBody
    ) {
        OrganizationDetails details = organizationDetails();
        Map<String, String> tokens = baseTokens(details, donorName, receiptNumber, issueDate);
        Date giftDate = gift.Gift_Date__c == null ? issueDate : gift.Gift_Date__c;
        tokens.put('StatementYear', String.valueOf(giftDate.year()));
        tokens.put('Amount', amountText(gift));
        tokens.put('GiftDate', formatDate(giftDate));
        tokens.put('GiftType', String.isBlank(gift.Type__c) ? '' : gift.Type__c);
        tokens.put('GiftLines', '');

        String body = mergeTokens(templateBody, tokens);
        return document(
            'Receipt ' + receiptNumber,
            brandingBlock(details, templateBody) +
                body +
                amountNote(isInKind(gift)) +
                taxBlock(taxSentencesFor(gift)) +
                signatureBlock(details)
        );
    }

    /**
     * A donor's year end statement. Every gift is a line, and **every line carries its own
     * status** (R-RC8): a footer saying "some of these were refunded" is not something a reader can
     * act on, and a statement that quietly dropped a refunded gift would not reconcile with what
     * the donor believes they gave.
     */
    public static String forStatement(
        String donorName,
        List<Gift__c> gifts,
        String receiptNumber,
        Integer statementYear,
        Date issueDate,
        String templateBody
    ) {
        OrganizationDetails details = organizationDetails();
        Map<String, String> tokens = baseTokens(details, donorName, receiptNumber, issueDate);
        tokens.put('StatementYear', String.valueOf(statementYear));
        tokens.put('Amount', money(cashTotalOf(gifts)));
        tokens.put('GiftDate', '');
        tokens.put('GiftType', '');
        tokens.put('GiftLines', giftLines(gifts));

        Set<String> sentences = new Set<String>();
        List<String> ordered = new List<String>();
        Boolean anyInKind = false;
        for (Gift__c gift : gifts) {
            anyInKind = anyInKind || isInKind(gift);
            for (String sentence : taxSentencesFor(gift)) {
                if (sentences.add(sentence)) {
                    ordered.add(sentence);
                }
            }
        }
        if (anyInKind) {
            ordered.add(SENTENCE_IN_KIND_NOT_IN_TOTAL);
        }

        // The lines go where the template asked for them, and after the letter when it did not
        // ask: a statement with no lines on it is not a statement.
        Boolean templatePlacedLines =
            templateBody != null && templateBody.contains('{{GiftLines}}');
        String body = mergeTokens(templateBody, tokens);
        return document(
            'Statement ' + receiptNumber,
            brandingBlock(details, templateBody) +
                body +
                (templatePlacedLines ? '' : giftLines(gifts)) +
                amountNote(anyInKind) +
                taxBlock(ordered) +
                signatureBlock(details)
        );
    }

    /**
     * The total a statement states, which is the total of the amounts it actually prints: money
     * only, because an in-kind gift is listed without a value and left out of the total (R-RC12).
     * The goods are listed as lines of their own, visibly outside the money the statement totals,
     * and the fair market value the organization recorded stays on the gift (R-G12). The receipt
     * record carries this same number, so the record and the document agree.
     */
    public static Decimal cashTotalOf(List<Gift__c> gifts) {
        Decimal total = 0;
        for (Gift__c gift : gifts) {
            total += statedAmountOf(gift);
        }
        return total;
    }

    /**
     * The amount a document states for one gift: its amount, or nothing at all for a gift of goods
     * or services (R-RC12). The value the organization recorded stays on the gift (R-G12).
     */
    public static Decimal statedAmountOf(Gift__c gift) {
        if (isInKind(gift) || gift.Amount__c == null) {
            return 0;
        }
        return gift.Amount__c;
    }

    /**
     * What one gift's amount reads as where the letter asked for a figure: the money, or, for a
     * gift of goods, the phrase that points at the description instead (R-RC12). The fair market
     * value is never consulted here, and there is a test that asserts it never reaches the
     * rendered document.
     */
    @TestVisible
    private static String amountText(Gift__c gift) {
        return isInKind(gift) ? IN_KIND_AMOUNT_PHRASE : money(gift.Amount__c);
    }

    private static Boolean isInKind(Gift__c gift) {
        return IN_KIND.equalsIgnoreCase(gift.Type__c);
    }

    // ----------------------------------------------------------------------- internals

    private static Map<String, String> baseTokens(
        OrganizationDetails details,
        String donorName,
        String receiptNumber,
        Date issueDate
    ) {
        Map<String, String> tokens = new Map<String, String>();
        tokens.put('OrganizationName', details.legalName);
        tokens.put('OrganizationTaxId', blankToEmpty(details.taxId));
        tokens.put('OrganizationAddress', blankToEmpty(details.address));
        tokens.put('PlaceOfIssue', blankToEmpty(details.placeOfIssue));
        tokens.put('SignerName', blankToEmpty(details.signerName));
        tokens.put('SignerTitle', blankToEmpty(details.signerTitle));
        tokens.put('DonorName', blankToEmpty(donorName));
        tokens.put('ReceiptNumber', receiptNumber);
        tokens.put('IssueDate', formatDate(issueDate));
        return tokens;
    }

    /**
     * Replaces the tokens the package documents and leaves anything else exactly as typed (R-RT2).
     * A typo is then visible on the proof rather than invisible on the donor's copy.
     */
    @TestVisible
    private static String mergeTokens(String templateBody, Map<String, String> tokens) {
        if (String.isBlank(templateBody)) {
            throw new ReceiptContentException(Label.Giving_Receipt_NoActiveTemplate);
        }
        String merged = templateBody;
        for (String name : tokens.keySet()) {
            // Everything a person typed is escaped on the way in. The gift lines are the one
            // exception, because the package built that markup itself, and it escaped every
            // value it put in it.
            String value = RAW_TOKENS.contains(name) ? tokens.get(name) : escape(tokens.get(name));
            merged = merged.replace(TOKEN_OPEN + name + TOKEN_CLOSE, value);
        }
        return merged;
    }

    /** One row per gift, each stating its own status. */
    private static String giftLines(List<Gift__c> gifts) {
        String rows = '';
        for (Gift__c gift : gifts) {
            rows +=
                '<tr>' +
                '<td>' +
                escape(formatDate(gift.Gift_Date__c)) +
                '</td>' +
                '<td>' +
                escape(blankToEmpty(gift.Type__c)) +
                '</td>' +
                '<td class="status">' +
                escape(blankToEmpty(gift.Status__c)) +
                '</td>' +
                '<td class="amount">' +
                escape(isInKind(gift) ? IN_KIND_LINE_AMOUNT : money(gift.Amount__c)) +
                '</td>' +
                '</tr>';
        }
        return '<table class="gifts"><thead><tr><th>Date</th><th>Type</th><th>Status</th>' +
            '<th class="amount">Amount</th></tr></thead><tbody>' +
            rows +
            '</tbody></table>';
    }

    /**
     * The letterhead the package prints above the letter (R-RC13): the logo, when the organization
     * has one and has left it turned on, and the organization's name and address when the template
     * did not place them itself.
     *
     * The template test is the one already used for the gift lines: an administrator who deleted
     * the letterhead out of their template has not thereby issued a document with no organization
     * on it, and one that kept it does not get the name twice.
     */
    private static String brandingBlock(OrganizationDetails details, String templateBody) {
        String logo = ReceiptLogoSource.imageTag();
        Boolean templateNamedOrganization =
            templateBody != null && templateBody.contains('{{OrganizationName}}');
        if (String.isBlank(logo) && templateNamedOrganization) {
            return '';
        }
        String block = '<div class="branding">' + logo;
        if (!templateNamedOrganization) {
            block += '<p class="orgname">' + escape(details.legalName) + '</p>';
            if (String.isNotBlank(details.address)) {
                block +=
                    '<p class="orgaddress">' +
                    escape(details.address).replace('\n', '<br/>') +
                    '</p>';
            }
        }
        return block + '</div>';
    }

    /**
     * The line that states, in the document's own words, that no value has been placed on a gift
     * of goods (G-18, ADR-0030, R-RC12). The letter's own amount slot reads as a phrase pointing
     * at the description, and a statement's amount column reads as `Not valued`, but neither of
     * those says outright that the organization has stated no value, and a donor reading the
     * document is owed that in plain words. Nothing is printed for a document with no gift of
     * goods on it.
     */
    private static String amountNote(Boolean anyInKind) {
        return anyInKind == true
            ? '<p class="amountnote">' + escape(AMOUNT_NOT_STATED) + '</p>'
            : '';
    }

    private static String taxBlock(List<String> sentences) {
        String block = '<div class="tax">';
        for (String sentence : sentences) {
            block += '<p>' + escape(sentence) + '</p>';
        }
        return block + '</div>';
    }

    private static String signatureBlock(OrganizationDetails details) {
        String block = '<div class="signature">';
        if (String.isNotBlank(details.placeOfIssue)) {
            block += '<p>Issued at ' + escape(details.placeOfIssue) + '</p>';
        }
        if (String.isNotBlank(details.signerName)) {
            block += '<p>' + escape(details.signerName);
            if (String.isNotBlank(details.signerTitle)) {
                block += ', ' + escape(details.signerTitle);
            }
            block += '</p>';
        }
        if (String.isNotBlank(details.taxId)) {
            block += '<p>Tax identification number ' + escape(details.taxId) + '</p>';
        }
        return block + '</div>';
    }

    /**
     * The page furniture. `@page` margin boxes are the only way the rendering service accepts a
     * running header or footer, and the style sheet is inline because an external one would be a
     * request the renderer will not make.
     */
    private static String document(String title, String body) {
        return '<!DOCTYPE html><html><head><meta charset="UTF-8"/><title>' +
            escape(title) +
            '</title><style>' +
            'body { font-family: Arial Unicode MS, Arial, sans-serif; font-size: 11pt; color: #000; }' +
            '@page { margin: 20mm 18mm; }' +
            'table.gifts { width: 100%; border-collapse: collapse; margin: 12pt 0; }' +
            'table.gifts th, table.gifts td { border-bottom: 1px solid #999; padding: 4pt; text-align: left; }' +
            'table.gifts .amount { text-align: right; }' +
            'div.branding { margin-bottom: 12pt; }' +
            'div.branding img.logo { display: block; margin-bottom: 6pt; }' +
            'div.branding p.orgname { font-size: 14pt; font-weight: bold; margin: 0; }' +
            'div.branding p.orgaddress { margin: 2pt 0 0 0; }' +
            'p.amountnote { margin: 6pt 0; font-style: italic; }' +
            'div.tax p { margin: 6pt 0; }' +
            'div.signature { margin-top: 18pt; }' +
            '</style></head><body>' +
            body +
            '</body></html>';
    }

    private static String escape(String value) {
        return value == null ? '' : value.escapeHtml4();
    }

    private static String blankToEmpty(String value) {
        return value == null ? '' : value;
    }

    /**
     * A dollar amount as a United States receipt prints it: two decimal places and a comma
     * between thousands, whoever is running the issue. `Decimal.format()` is not used because it
     * drops trailing zeros (250.00 prints as 250) and follows the running user's locale, so the
     * same receipt would read differently depending on who issued it.
     */
    @TestVisible
    private static String money(Decimal value) {
        Decimal amount = (value == null ? 0 : value).setScale(2, System.RoundingMode.HALF_UP);
        String digits = amount.abs().toPlainString();
        String whole = digits.substringBefore('.');
        String grouped = '';
        while (whole.length() > 3) {
            grouped = ',' + whole.right(3) + grouped;
            whole = whole.left(whole.length() - 3);
        }
        return (amount < 0 ? '-' : '') + '$' + whole + grouped + '.' + digits.substringAfter('.');
    }

    private static String formatDate(Date value) {
        return value == null
            ? ''
            : Datetime.newInstance(value, Time.newInstance(0, 0, 0, 0)).format('d MMMM yyyy');
    }
}
