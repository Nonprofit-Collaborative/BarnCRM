/**
 * What the Acknowledgments page calls.
 *
 * Thin on purpose. Every rule lives in `AcknowledgmentRuleService`, `AcknowledgmentService` and
 * `AcknowledgmentRunService`, which are testable without a screen; this class turns their
 * exceptions into messages a person can read and their records into shapes a component can
 * render.
 */
public with sharing class AcknowledgmentController {
    private static final String MANAGE_PERMISSION = 'Manage_BarnCRM_Settings';

    /** One rule, flattened, with the template resolved to the label an administrator recognizes. */
    public class RuleView {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public Decimal order;
        @AuraEnabled
        public String channel;
        @AuraEnabled
        public String template;
        @AuraEnabled
        public String templateLabel;
        @AuraEnabled
        public Boolean templateFound;
        @AuraEnabled
        public Decimal minimumAmount;
        @AuraEnabled
        public Decimal maximumAmount;
        @AuraEnabled
        public String giftType;
        @AuraEnabled
        public String appealName;
        @AuraEnabled
        public Boolean firstGiftOnly;
        @AuraEnabled
        public Boolean active;
    }

    /** One email template the org has, so the developer name can be copied into a rule. */
    public class TemplateView {
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String developerName;
    }

    /** One run, for the list on the page. */
    public class RunView {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String channel;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public Datetime started;
        @AuraEnabled
        public Datetime finished;
        @AuraEnabled
        public Integer giftsProcessed;
        @AuraEnabled
        public Integer sent;
        @AuraEnabled
        public Integer errors;
        @AuraEnabled
        public String mergeFileId;
        @AuraEnabled
        public Boolean waitingToBeMarkedSent;
    }

    /** The whole page, in one round trip. */
    public class PageView {
        @AuraEnabled
        public Boolean enabled;
        @AuraEnabled
        public Boolean canManage;
        @AuraEnabled
        public Boolean canSend;
        @AuraEnabled
        public Boolean scheduled;
        @AuraEnabled
        public Datetime nextRunAt;
        @AuraEnabled
        public Datetime lastRun;
        @AuraEnabled
        public String lastRunSummary;
        @AuraEnabled
        public Integer emailQueue;
        @AuraEnabled
        public Integer letterQueue;
        @AuraEnabled
        public Integer unmatchedQueue;
        @AuraEnabled
        public Integer withoutRecipient;
        @AuraEnabled
        public Boolean queueCapped;
        @AuraEnabled
        public List<RuleView> rules;
        @AuraEnabled
        public List<TemplateView> templates;
        @AuraEnabled
        public List<RunView> runs;
    }

    @AuraEnabled(cacheable=true)
    public static PageView getPage() {
        try {
            return currentView();
        } catch (Exception failure) {
            throw asUserError(failure, 'AcknowledgmentController.getPage');
        }
    }

    /** Sends the emails waiting now. */
    @AuraEnabled
    public static PageView sendEmailsNow() {
        try {
            AcknowledgmentRunService.startEmailRun();
            return currentView();
        } catch (Exception failure) {
            throw asUserError(failure, 'AcknowledgmentController.sendEmailsNow');
        }
    }

    /** Produces the letter merge file and returns the page with the new run on it. */
    @AuraEnabled
    public static PageView produceLetters() {
        try {
            AcknowledgmentRunService.runLetterMerge();
            return currentView();
        } catch (Exception failure) {
            throw asUserError(failure, 'AcknowledgmentController.produceLetters');
        }
    }

    /** Says the letters went out. */
    @AuraEnabled
    public static PageView markLettersSent(Id runId) {
        try {
            AcknowledgmentRunService.markLetterRunSent(runId);
            return currentView();
        } catch (Exception failure) {
            throw asUserError(failure, 'AcknowledgmentController.markLettersSent', runId);
        }
    }

    /** Starts or stops the nightly send. */
    @AuraEnabled
    public static PageView setSchedule(Boolean scheduled) {
        try {
            requireManagePermission();
            if (scheduled == true) {
                AcknowledgmentScheduler.start();
            } else {
                AcknowledgmentScheduler.stop();
            }
            return currentView();
        } catch (Exception failure) {
            throw asUserError(failure, 'AcknowledgmentController.setSchedule');
        }
    }

    // ------------------------------------------------------------------------------- internals

    @TestVisible
    private static PageView currentView() {
        PageView view = new PageView();
        view.enabled = AcknowledgmentService.isEnabled();
        view.canManage = FeatureManagement.checkPermission(MANAGE_PERMISSION);
        view.canSend = AcknowledgmentService.canSend();
        view.scheduled = AcknowledgmentScheduler.isScheduled();
        view.nextRunAt = AcknowledgmentScheduler.nextRunAt();

        Giving_Settings__c settings = Giving_Settings__c.getOrgDefaults();
        view.lastRun = settings.Acknowledgments_Last_Run__c;
        view.lastRunSummary = settings.Acknowledgments_Last_Run_Summary__c;

        Map<String, String> templateNames = new Map<String, String>();
        List<TemplateView> templates = new List<TemplateView>();
        for (EmailTemplate template : AcknowledgmentSelector.activeTemplates()) {
            TemplateView row = new TemplateView();
            row.label = template.Name;
            row.developerName = template.DeveloperName;
            templates.add(row);
            templateNames.put(template.DeveloperName, template.Name);
        }
        view.templates = templates;
        view.rules = ruleViews(templateNames);
        view.runs = runViews();
        countQueue(view);
        return view;
    }

    /**
     * The queue, counted by what each waiting gift would actually get.
     *
     * The rules are matched here rather than read from a field on the gift, because that is what
     * a send will do (R-AK3), and a page that counted one thing while the send did another would
     * be worse than a page with no counts on it.
     */
    private static void countQueue(PageView view) {
        List<Gift__c> queued = AcknowledgmentSelector.queuedGifts(
            AcknowledgmentSelector.QUEUE_LIMIT
        );
        view.queueCapped = queued.size() == AcknowledgmentSelector.QUEUE_LIMIT;
        List<Acknowledgment_Rule__c> rules = AcknowledgmentSelector.activeRules();
        Set<String> earlierDonors = AcknowledgmentRuleService.donorsWithEarlierGifts(
            queued,
            new Set<Id>()
        );

        Integer emails = 0;
        Integer letters = 0;
        Integer unmatched = 0;
        Integer unreachable = 0;
        for (Gift__c gift : queued) {
            AcknowledgmentRuleService.RuleMatch match = AcknowledgmentRuleService.matchFor(
                gift,
                rules,
                earlierDonors
            );
            if (match == null) {
                unmatched++;
            } else if (AcknowledgmentRuleService.CHANNEL_LETTER.equals(match.channel)) {
                letters++;
            } else if (AcknowledgmentRuleService.CHANNEL_EMAIL.equals(match.channel)) {
                if (AcknowledgmentService.recipientContactIdFor(gift) == null) {
                    unreachable++;
                } else {
                    emails++;
                }
            }
        }
        view.emailQueue = emails;
        view.letterQueue = letters;
        view.unmatchedQueue = unmatched;
        view.withoutRecipient = unreachable;
    }

    /**
     * The rules, each with its template shown by the name an administrator recognizes rather
     * than the developer name the rule stores (ADR-0032).
     */
    private static List<RuleView> ruleViews(Map<String, String> templateNames) {
        List<RuleView> views = new List<RuleView>();
        for (Acknowledgment_Rule__c rule : AcknowledgmentSelector.allRules()) {
            RuleView view = new RuleView();
            view.id = rule.Id;
            view.name = rule.Name;
            view.order = rule.Order__c;
            view.channel = rule.Channel__c;
            view.template = rule.Email_Template__c;
            String developerName = String.isBlank(rule.Email_Template__c)
                ? null
                : rule.Email_Template__c.trim();
            view.templateFound = developerName == null || templateNames.containsKey(developerName);
            view.templateLabel = developerName == null ? null : templateNames.get(developerName);
            view.minimumAmount = rule.Minimum_Amount__c;
            view.maximumAmount = rule.Maximum_Amount__c;
            view.giftType = rule.Gift_Type__c;
            view.appealName = rule.Appeal__r == null ? null : rule.Appeal__r.Name;
            view.firstGiftOnly = rule.First_Gift_Only__c;
            view.active = rule.Active__c;
            views.add(view);
        }
        return views;
    }

    private static List<RunView> runViews() {
        List<RunView> views = new List<RunView>();
        for (Acknowledgment_Run__c run : AcknowledgmentSelector.recentRuns(5)) {
            RunView view = new RunView();
            view.id = run.Id;
            view.name = run.Name;
            view.channel = run.Channel__c;
            view.status = run.Status__c;
            view.started = run.Started__c;
            view.finished = run.Finished__c;
            view.giftsProcessed = intOf(run.Gifts_Processed__c);
            view.sent = intOf(run.Acknowledgments_Sent__c);
            view.errors = intOf(run.Errors__c);
            view.mergeFileId = run.Merge_File_Document_Id__c;
            view.waitingToBeMarkedSent = AcknowledgmentRunService.STATUS_READY_TO_MERGE.equals(
                run.Status__c
            );
            views.add(view);
        }
        return views;
    }

    private static Integer intOf(Decimal value) {
        return value == null ? 0 : value.intValue();
    }

    private static void requireManagePermission() {
        if (!FeatureManagement.checkPermission(MANAGE_PERMISSION)) {
            throw new AcknowledgmentService.AcknowledgmentException(
                Label.Giving_Acknowledgment_NoPermission
            );
        }
    }

    private static AuraHandledException asUserError(Exception failure, String context) {
        return asUserError(failure, context, null);
    }

    /**
     * A message the page shows as it is when the feature raised it, and a logged entry plus a
     * general apology when something else did. Nothing is swallowed either way.
     */
    private static AuraHandledException asUserError(
        Exception failure,
        String context,
        Id recordId
    ) {
        Boolean ours =
            failure instanceof AcknowledgmentService.AcknowledgmentException ||
            failure instanceof AcknowledgmentRunService.AcknowledgmentRunException;
        String message = failure.getMessage();
        if (!ours) {
            ErrorLogger.log(failure, context, recordId);
            message = Label.Giving_Acknowledgment_UnexpectedError;
        }
        AuraHandledException reported = new AuraHandledException(message);
        reported.setMessage(message);
        return reported;
    }
}
