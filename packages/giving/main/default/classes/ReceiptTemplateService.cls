/**
 * The letters an administrator writes, and the ones the package ships.
 *
 * ADR-0006 puts structured configuration an administrator manages as a list in a packaged custom
 * object, and package shipped defaults in custom metadata materialized into that object. So the
 * two letters BarnCRM ships live in `Receipt_Template_Default__mdt` and are copied into
 * `Receipt_Template__c` records. An upgrade updates the metadata and never touches what Maria
 * wrote.
 *
 * **Who may reach the copy, and when** (ADR-0034, following ADR-0029):
 *
 * - The Giving post-install script, at install and at every upgrade, which is where a shipped
 *   default is supposed to arrive. There is no running user there and nothing to check.
 * - `Restore the shipped letters` on the Receipts page, after `Manage_Nonprofit_Settings`. It is
 *   the recovery path for an install whose step failed, exactly as the Restore shipped rollups
 *   button is for ADR-0029.
 * - `activeBodyFor`, when an org is issuing a receipt and has no letter of that kind, after
 *   `Issue_Receipts`. A receipt that fails to generate because a bootstrap step did not run is a
 *   worse outcome than a record created on the issuing path.
 *
 * Editing a letter (`saveBody`, `activate`) checks `Manage_Nonprofit_Settings`, like every other
 * write the settings console makes, and the DML stays in user mode on top of that.
 */
public with sharing class ReceiptTemplateService {
    /** Configuring the app. The same permission every other console write checks. */
    public static final String MANAGE_PERMISSION = 'Manage_Nonprofit_Settings';

    private static final String INSTALL_CONTEXT = 'ReceiptTemplateService.installDefaults';

    public class ReceiptTemplateException extends Exception {
    }

    /**
     * The body the renderer merges for one receipt type, materializing the shipped default the
     * first time a type is used so that an organization that has changed nothing still gets a
     * document rather than an error.
     */
    public static String activeBodyFor(String receiptType) {
        Receipt_Template__c template = ReceiptSelector.activeTemplate(receiptType);
        if (template == null) {
            // The only write on the issuing path, and it is authorized by the permission that
            // authorizes the receipt itself. Stated here rather than trusted from the caller,
            // because ADR-0021 asks the writer's doorstep to be the place it is true.
            ReceiptService.requireIssuePermission();
            materializeDefaults();
            template = ReceiptSelector.activeTemplate(receiptType);
        }
        if (template == null || String.isBlank(template.Body__c)) {
            throw new ReceiptTemplateException(Label.Giving_Receipt_NoActiveTemplate);
        }
        return template.Body__c;
    }

    /**
     * The console's Restore the shipped letters action: creates any shipped letter this org does
     * not have, and leaves every letter it does have exactly as it is. Safe to run repeatedly.
     */
    public static List<Receipt_Template__c> restoreDefaults() {
        requireManagePermission();
        return materializeDefaults();
    }

    /**
     * The same work, for the post-install script, and it never throws (ADR-0029 point 2). An
     * install must not fail because a bootstrap step did, and there is no user to tell: the
     * failure goes to the Error Log and the Receipts page still offers the button that fixes it.
     *
     * @param context the calling script, so the Error Log entry names it
     * @return the letters created, empty when there were none to create or the step failed
     */
    public static List<Receipt_Template__c> installDefaultsDuringInstall(String context) {
        try {
            return materializeDefaults();
        } catch (Exception failed) {
            ErrorLogger.log(failed, String.isBlank(context) ? INSTALL_CONTEXT : context);
            return new List<Receipt_Template__c>();
        }
    }

    /** Whether the running user may write to the letters, for a screen deciding what to offer. */
    public static Boolean canManageTemplates() {
        if (managePermission == null) {
            managePermission = FeatureManagement.checkPermission(MANAGE_PERMISSION);
        }
        return managePermission;
    }

    /**
     * R-RT1: one active letter per type. Activating one deactivates the others of its type in the
     * same save, so there is never a moment where two are active or none is.
     */
    public static void activate(Id templateId) {
        requireManagePermission();
        Receipt_Template__c chosen;
        List<Receipt_Template__c> toDeactivate = new List<Receipt_Template__c>();
        for (Receipt_Template__c template : ReceiptSelector.allTemplates()) {
            if (template.Id == templateId) {
                chosen = template;
            }
        }
        if (chosen == null) {
            throw new ReceiptTemplateException(Label.Giving_Receipt_TemplateNotFound);
        }
        for (Receipt_Template__c template : ReceiptSelector.allTemplates()) {
            if (
                template.Id != templateId &&
                template.Type__c == chosen.Type__c &&
                template.Active__c
            ) {
                template.Active__c = false;
                toDeactivate.add(template);
            }
        }
        chosen.Active__c = true;
        toDeactivate.add(chosen);
        Database.update(toDeactivate, true, AccessLevel.USER_MODE);
    }

    /** Saves a body an administrator edited. The letter is theirs; the tax sentences are not. */
    public static void saveBody(Id templateId, String body) {
        requireManagePermission();
        if (String.isBlank(body)) {
            throw new ReceiptTemplateException(Label.Giving_Receipt_EmptyTemplate);
        }
        Database.update(
            new List<Receipt_Template__c>{
                new Receipt_Template__c(Id = templateId, Body__c = body)
            },
            true,
            AccessLevel.USER_MODE
        );
    }

    /**
     * The letter as the editor shows it: the stored body without the letterhead block the
     * shipped letters used to open with (ADR-NEXT point 3). The package prints the letterhead
     * itself now, so the editor never offers it, and the next save stores the letter without it.
     * A body without that block is returned unchanged.
     */
    public static String letterOf(String body) {
        if (
            String.isBlank(body) || !body.contains(ReceiptContentBuilder.LEGACY_LETTERHEAD_MARKER)
        ) {
            return body;
        }
        Matcher found = LEGACY_LETTERHEAD.matcher(body);
        if (!found.find()) {
            return body;
        }
        return (body.substring(0, found.start()) + body.substring(found.end())).trim();
    }

    /**
     * The draft letter filled in for a sample gift, as the page previews it (ADR-NEXT point 5).
     *
     * It goes through the same `ReceiptContentBuilder` path as a real receipt, so the preview
     * shows the letterhead, the tax sentences and the signature the document will carry. It
     * writes nothing, consumes no receipt number and creates no file: the gifts exist only in
     * memory. What comes back is the inside of the document's body, because the page shows it
     * as formatted text rather than as a page of its own.
     */
    public static String preview(String receiptType, String body) {
        if (String.isBlank(body)) {
            throw new ReceiptTemplateException(Label.Giving_Receipt_EmptyTemplate);
        }
        Date today = Date.today();
        String donor = Label.Giving_Receipt_PreviewDonor;
        String sampleNumber = Label.Giving_Receipt_PreviewNumber;
        String html;
        if (ReceiptNumberSequence.TYPE_STATEMENT.equals(receiptType)) {
            html = ReceiptContentBuilder.forStatement(
                donor,
                new List<Gift__c>{ sampleGift(100, today), sampleGift(250, today) },
                sampleNumber,
                today.year(),
                today,
                body
            );
        } else {
            html = ReceiptContentBuilder.forGift(
                sampleGift(100, today),
                donor,
                sampleNumber,
                today,
                body
            );
        }
        return html.substringAfter('<body>').substringBeforeLast('</body>');
    }

    // ----------------------------------------------------------------------- internals

    private static final Pattern LEGACY_LETTERHEAD = Pattern.compile(
        '(?s)<div class="letterhead">.*?</div>\\s*'
    );

    /** A cash gift with nothing given in return, held in memory only. */
    private static Gift__c sampleGift(Decimal amount, Date giftDate) {
        return new Gift__c(
            Amount__c = amount,
            Gift_Date__c = giftDate,
            Type__c = 'Cash',
            Status__c = 'Received'
        );
    }

    /**
     * Read once per transaction: the answer cannot change inside one.
     *
     * Visible to tests for the reason `ReceiptService.issuePermission` is: a custom permission
     * cannot be granted to the user a test runs as without assigning a permission set, which would
     * make every template test a test of permission set assignment.
     */
    @TestVisible
    private static Boolean managePermission = null;

    private static void requireManagePermission() {
        if (!canManageTemplates()) {
            throw new ReceiptTemplateException(Label.Giving_Receipt_NoTemplatePermission);
        }
    }

    /**
     * The copy itself. Private, so that every way in passes one of the three gates above.
     *
     * The insert goes through `ReceiptWriter` in system mode: the post-install user holds no
     * permission set, and the user issuing a receipt holds Read and not Create on
     * `Receipt_Template__c` unless they are also a Giving Admin. Every value written comes from
     * packaged custom metadata (ADR-0021 condition 2).
     */
    private static List<Receipt_Template__c> materializeDefaults() {
        Set<String> typesPresent = new Set<String>();
        for (Receipt_Template__c existing : ReceiptSelector.allTemplates()) {
            typesPresent.add(existing.Type__c);
        }

        List<Receipt_Template__c> created = new List<Receipt_Template__c>();
        for (Receipt_Template_Default__mdt shipped : [
            SELECT Template_Name__c, Receipt_Type__c, Body__c
            FROM Receipt_Template_Default__mdt
            WITH SYSTEM_MODE
            LIMIT 500
        ]) {
            // A long text area cannot be required on custom metadata, so a default with no body
            // is skipped here rather than copied into an active template that could not be sent.
            if (typesPresent.contains(shipped.Receipt_Type__c) || String.isBlank(shipped.Body__c)) {
                continue;
            }
            created.add(
                new Receipt_Template__c(
                    Name = shipped.Template_Name__c,
                    Type__c = shipped.Receipt_Type__c,
                    Body__c = shipped.Body__c,
                    Active__c = true
                )
            );
        }
        ReceiptWriter.insertTemplates(created);
        return created;
    }
}
