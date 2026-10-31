/**
 * What the receipting screens call: the gift page action, and the Receipts panel in the Nonprofit
 * Settings console.
 *
 * Thin on purpose. Every rule lives in `ReceiptService`, `ReceiptNumberSequence` and
 * `ReceiptContentBuilder`, which are testable without a screen; this class turns their exceptions
 * into messages a person can read and their records into shapes a component can render.
 */
public with sharing class ReceiptController {
    /** One receipt, flattened for a component. */
    public class ReceiptView {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String receiptNumber;
        @AuraEnabled
        public String type;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public Decimal amount;
        @AuraEnabled
        public Date issueDate;
        @AuraEnabled
        public String voidReason;
        @AuraEnabled
        public Datetime voidedOn;
        @AuraEnabled
        public String contentDocumentId;
    }

    /** What the gift page needs to decide which buttons to offer. */
    public class GiftReceiptState {
        @AuraEnabled
        public Boolean canIssue;
        @AuraEnabled
        public Boolean alreadyReceipted;
        @AuraEnabled
        public List<ReceiptView> receipts;
    }

    /** One letter, for the console. */
    public class TemplateView {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String type;
        @AuraEnabled
        public String body;
        @AuraEnabled
        public Boolean active;
    }

    /** One run, for the console. */
    public class RunView {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String type;
        @AuraEnabled
        public Integer statementYear;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public Datetime started;
        @AuraEnabled
        public Datetime finished;
        @AuraEnabled
        public Integer donorsProcessed;
        @AuraEnabled
        public Integer receiptsIssued;
        @AuraEnabled
        public Integer errors;
    }

    @AuraEnabled(cacheable=true)
    public static GiftReceiptState getGiftReceiptState(Id giftId) {
        try {
            Gift__c gift = ReceiptSelector.giftForReceipting(giftId);
            GiftReceiptState state = new GiftReceiptState();
            state.canIssue = ReceiptService.canIssueReceipts();
            state.alreadyReceipted = gift != null && String.isNotBlank(gift.Receipt_Number__c);
            state.receipts = viewsOf(ReceiptSelector.forGift(giftId));
            return state;
        } catch (Exception failure) {
            throw asUserError(failure, 'ReceiptController.getGiftReceiptState', giftId);
        }
    }

    /**
     * The failure path rethrows on purpose. A per gift receipt number is accounted for only by the
     * whole transaction rolling back when generation fails, because nothing reconciles that series
     * (see `ReceiptService.issueForGift`). Logging the failure and returning normally would leave
     * a consumed number nothing can explain.
     */
    @AuraEnabled
    public static ReceiptView issue(Id giftId) {
        try {
            return viewOf(ReceiptService.issueForGift(giftId));
        } catch (Exception failure) {
            throw asUserError(failure, 'ReceiptController.issue', giftId);
        }
    }

    @AuraEnabled
    public static ReceiptView voidReceipt(Id receiptId, String reason) {
        try {
            return viewOf(ReceiptService.voidReceipt(receiptId, reason));
        } catch (Exception failure) {
            throw asUserError(failure, 'ReceiptController.voidReceipt', receiptId);
        }
    }

    @AuraEnabled
    public static ReceiptView voidAndReissue(Id receiptId, String reason) {
        try {
            return viewOf(ReceiptService.voidAndReissue(receiptId, reason));
        } catch (Exception failure) {
            throw asUserError(failure, 'ReceiptController.voidAndReissue', receiptId);
        }
    }

    /**
     * The letters, for the console.
     *
     * `cacheable=true` is wanted here and kept: the list is small, it is read on every visit to the
     * page and again after every save through `refreshApex`, and it changes only when somebody on
     * this screen changes it. What it cost was a defect: this method used to materialize the
     * shipped letters when the list came back empty, and **Apex cannot perform DML in a cacheable
     * method**, so on an org that had never issued a receipt the page threw instead of showing the
     * two shipped letters. Creating them is now the post-install script's job (ADR-0029), with
     * `restoreDefaultTemplates` as the recovery path, so this method only reads (ADR-0034).
     */
    @AuraEnabled(cacheable=true)
    public static List<TemplateView> getTemplates() {
        try {
            return viewsOfTemplates(ReceiptSelector.allTemplates());
        } catch (Exception failure) {
            throw asUserError(failure, 'ReceiptController.getTemplates', null);
        }
    }

    /** Whether the running user may edit a letter, so the page can say so before they try. */
    @AuraEnabled(cacheable=true)
    public static Boolean getCanManageTemplates() {
        return ReceiptTemplateService.canManageTemplates();
    }

    /**
     * Creates any shipped letter this org does not have. Not cacheable, because it writes: this is
     * the button an administrator presses when an install left the list empty (ADR-0029 point 3).
     */
    @AuraEnabled
    public static List<TemplateView> restoreDefaultTemplates() {
        try {
            ReceiptTemplateService.restoreDefaults();
            return viewsOfTemplates(ReceiptSelector.allTemplates());
        } catch (Exception failure) {
            throw asUserError(failure, 'ReceiptController.restoreDefaultTemplates', null);
        }
    }

    @AuraEnabled
    public static void saveTemplate(Id templateId, String body) {
        try {
            ReceiptTemplateService.saveBody(templateId, body);
        } catch (Exception failure) {
            throw asUserError(failure, 'ReceiptController.saveTemplate', templateId);
        }
    }

    /**
     * The draft letter filled in for a sample gift. Not cacheable: the draft changes with every
     * edit, and the answer depends on settings that change on another page.
     */
    @AuraEnabled
    public static String previewTemplate(String receiptType, String body) {
        try {
            return ReceiptTemplateService.preview(receiptType, body);
        } catch (Exception failure) {
            throw asUserError(failure, 'ReceiptController.previewTemplate', null);
        }
    }

    @AuraEnabled
    public static void activateTemplate(Id templateId) {
        try {
            ReceiptTemplateService.activate(templateId);
        } catch (Exception failure) {
            throw asUserError(failure, 'ReceiptController.activateTemplate', templateId);
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<RunView> getRuns() {
        try {
            List<RunView> views = new List<RunView>();
            for (Receipt_Run__c run : ReceiptSelector.recentRuns(10)) {
                RunView view = new RunView();
                view.id = run.Id;
                view.name = run.Name;
                view.type = run.Type__c;
                view.statementYear = intOf(run.Statement_Year__c);
                view.status = run.Status__c;
                view.started = run.Started__c;
                view.finished = run.Finished__c;
                view.donorsProcessed = intOf(run.Donors_Processed__c);
                view.receiptsIssued = intOf(run.Receipts_Issued__c);
                view.errors = intOf(run.Errors__c);
                views.add(view);
            }
            return views;
        } catch (Exception failure) {
            throw asUserError(failure, 'ReceiptController.getRuns', null);
        }
    }

    @AuraEnabled(cacheable=true)
    public static Integer getDefaultStatementYear() {
        return ReceiptRunService.defaultStatementYear();
    }

    @AuraEnabled
    public static RunView startStatementRun(Integer statementYear) {
        try {
            Receipt_Run__c run = ReceiptRunService.startStatementRun(statementYear);
            RunView view = new RunView();
            view.id = run.Id;
            view.type = run.Type__c;
            view.statementYear = intOf(run.Statement_Year__c);
            view.status = run.Status__c;
            view.started = run.Started__c;
            view.donorsProcessed = 0;
            view.receiptsIssued = 0;
            view.errors = 0;
            return view;
        } catch (Exception failure) {
            throw asUserError(failure, 'ReceiptController.startStatementRun', null);
        }
    }

    // ----------------------------------------------------------------------- internals

    private static List<TemplateView> viewsOfTemplates(List<Receipt_Template__c> templates) {
        List<TemplateView> views = new List<TemplateView>();
        for (Receipt_Template__c template : templates) {
            TemplateView view = new TemplateView();
            view.id = template.Id;
            view.name = template.Name;
            view.type = template.Type__c;
            view.body = ReceiptTemplateService.letterOf(template.Body__c);
            view.active = template.Active__c;
            views.add(view);
        }
        return views;
    }

    private static List<ReceiptView> viewsOf(List<Receipt__c> receipts) {
        List<ReceiptView> views = new List<ReceiptView>();
        for (Receipt__c receipt : receipts) {
            views.add(viewOf(receipt));
        }
        return views;
    }

    private static ReceiptView viewOf(Receipt__c receipt) {
        ReceiptView view = new ReceiptView();
        view.id = receipt.Id;
        view.receiptNumber = receipt.Receipt_Number__c;
        view.type = receipt.Type__c;
        view.status = receipt.Status__c;
        view.amount = receipt.Total_Amount__c;
        view.issueDate = receipt.Issue_Date__c;
        view.voidReason = receipt.Void_Reason__c;
        view.voidedOn = receipt.Voided_On__c;
        view.contentDocumentId = receipt.Content_Document_Id__c;
        return view;
    }

    private static Integer intOf(Decimal value) {
        return value == null ? 0 : value.intValue();
    }

    /**
     * The Error Log gets the stack; the person gets the sentence. An unexpected failure still
     * says something they can act on rather than a class name and a line number.
     */
    private static AuraHandledException asUserError(
        Exception failure,
        String context,
        Id recordId
    ) {
        ErrorLogger.log(failure, context, recordId);
        return UserErrors.wrapShowingDml(failure, Label.Giving_Receipt_UnexpectedError);
    }
}
