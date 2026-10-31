/**
 * What the Pledge Reminders page calls.
 *
 * Thin on purpose. Every rule lives in `PledgeReminderService`, which is testable without a
 * screen; this class turns its exceptions into messages a person can read and its records into
 * shapes a component can render.
 */
public with sharing class PledgeReminderController {
    /** One step, flattened, with the template resolved to the label an administrator knows. */
    public class StepView {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public Decimal days;
        @AuraEnabled
        public String channel;
        @AuraEnabled
        public String template;
        @AuraEnabled
        public String templateLabel;
        @AuraEnabled
        public Boolean templateFound;
        @AuraEnabled
        public Boolean active;
    }

    /** One email template the org has, so a step can name it. */
    public class TemplateView {
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String developerName;
    }

    /** One logged reminder, for the list on the page. */
    public class ReminderView {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String pledgeName;
        @AuraEnabled
        public String installmentName;
        @AuraEnabled
        public String stepName;
        @AuraEnabled
        public String channel;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public Datetime sentOn;
        @AuraEnabled
        public String failureReason;
        @AuraEnabled
        public String fileId;
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
        public Integer emailsDue;
        @AuraEnabled
        public Integer lettersDue;
        @AuraEnabled
        public Integer withoutRecipient;
        @AuraEnabled
        public Integer lettersWaiting;
        @AuraEnabled
        public Integer lettersAwaitingConfirmation;
        @AuraEnabled
        public String lettersFileId;
        @AuraEnabled
        public List<StepView> steps;
        @AuraEnabled
        public List<TemplateView> templates;
        @AuraEnabled
        public List<ReminderView> reminders;
    }

    @AuraEnabled(cacheable=true)
    public static PageView getPage() {
        try {
            return currentView();
        } catch (Exception failure) {
            throw asUserError(failure, 'PledgeReminderController.getPage');
        }
    }

    /** Starts the run now. Refused while reminders are off. */
    @AuraEnabled
    public static PageView sendNow() {
        try {
            PledgeReminderService.startRun();
            return currentView();
        } catch (Exception failure) {
            throw asUserError(failure, 'PledgeReminderController.sendNow');
        }
    }

    /** Writes the merge file for the letters waiting. */
    @AuraEnabled
    public static PageView produceLetters() {
        try {
            PledgeReminderService.produceLetters();
            return currentView();
        } catch (Exception failure) {
            throw asUserError(failure, 'PledgeReminderController.produceLetters');
        }
    }

    /** Says the letters in the file went out. */
    @AuraEnabled
    public static PageView markLettersSent() {
        try {
            PledgeReminderService.markLettersSent();
            return currentView();
        } catch (Exception failure) {
            throw asUserError(failure, 'PledgeReminderController.markLettersSent');
        }
    }

    /** Starts or stops the nightly run. */
    @AuraEnabled
    public static PageView setSchedule(Boolean scheduled) {
        try {
            if (!BarnCRMPermissions.canManageSettings()) {
                throw new PledgeReminderService.PledgeReminderException(
                    Label.Giving_PledgeReminders_NoPermission
                );
            }
            if (scheduled == true) {
                PledgeReminderScheduler.start();
            } else {
                PledgeReminderScheduler.stop();
            }
            return currentView();
        } catch (Exception failure) {
            throw asUserError(failure, 'PledgeReminderController.setSchedule');
        }
    }

    // ------------------------------------------------------------------------------- internals

    @TestVisible
    private static PageView currentView() {
        PageView view = new PageView();
        view.enabled = PledgeReminderService.isEnabled();
        view.canManage = BarnCRMPermissions.canManageSettings();
        view.canSend = AcknowledgmentService.canSend();
        view.scheduled = PledgeReminderScheduler.isScheduled();
        view.nextRunAt = PledgeReminderScheduler.nextRunAt();

        Giving_Settings__c settings = Giving_Settings__c.getOrgDefaults();
        view.lastRun = settings.Pledge_Reminders_Last_Run__c;
        view.lastRunSummary = settings.Pledge_Reminders_Last_Run_Summary__c;

        Map<String, String> templateNames = new Map<String, String>();
        List<TemplateView> templates = new List<TemplateView>();
        for (EmailTemplate template : PledgeReminderSelector.activeTemplates()) {
            TemplateView row = new TemplateView();
            row.label = template.Name;
            row.developerName = template.DeveloperName;
            templates.add(row);
            templateNames.put(template.DeveloperName, template.Name);
        }
        view.templates = templates;
        view.steps = stepViews(templateNames);

        PledgeReminderService.Counts due = PledgeReminderService.preview();
        view.emailsDue = due.emails;
        view.lettersDue = due.letters;
        view.withoutRecipient = due.withoutRecipient;
        view.lettersWaiting = PledgeReminderSelector.lettersWithoutFile(
                PledgeReminderService.LETTER_LIMIT
            )
            .size();
        List<Pledge_Reminder__c> awaiting = PledgeReminderSelector.lettersAwaitingConfirmation();
        view.lettersAwaitingConfirmation = awaiting.size();
        view.lettersFileId = awaiting.isEmpty() ? null : awaiting[0].Letter_File_Document_Id__c;
        view.reminders = reminderViews();
        return view;
    }

    private static List<StepView> stepViews(Map<String, String> templateNames) {
        List<StepView> views = new List<StepView>();
        for (Pledge_Reminder_Step__c step : PledgeReminderSelector.allSteps()) {
            StepView view = new StepView();
            view.id = step.Id;
            view.name = step.Name;
            view.days = step.Days_From_Due__c;
            view.channel = step.Channel__c;
            view.template = step.Email_Template__c;
            String developerName = String.isBlank(step.Email_Template__c)
                ? null
                : step.Email_Template__c.trim();
            view.templateFound = developerName == null || templateNames.containsKey(developerName);
            view.templateLabel = developerName == null ? null : templateNames.get(developerName);
            view.active = step.Active__c;
            views.add(view);
        }
        return views;
    }

    private static List<ReminderView> reminderViews() {
        List<ReminderView> views = new List<ReminderView>();
        for (Pledge_Reminder__c reminder : PledgeReminderSelector.recent(15)) {
            ReminderView view = new ReminderView();
            view.id = reminder.Id;
            view.name = reminder.Name;
            view.pledgeName = reminder.Commitment__r == null ? null : reminder.Commitment__r.Name;
            view.installmentName = reminder.Installment__r == null
                ? null
                : reminder.Installment__r.Name;
            view.stepName = reminder.Step_Name__c;
            view.channel = reminder.Channel__c;
            view.status = reminder.Status__c;
            view.sentOn = reminder.Sent_On__c;
            view.failureReason = reminder.Failure_Reason__c;
            view.fileId = reminder.Letter_File_Document_Id__c;
            views.add(view);
        }
        return views;
    }

    /**
     * A message the page shows as it is when the feature raised it, and a logged entry plus a
     * general apology when something else did. Nothing is swallowed either way.
     */
    private static AuraHandledException asUserError(Exception failure, String context) {
        Boolean ours =
            failure instanceof PledgeReminderService.PledgeReminderException ||
            failure instanceof AcknowledgmentService.AcknowledgmentException;
        String message = failure.getMessage();
        if (!ours) {
            ErrorLogger.log(failure, context);
            message = Label.Giving_PledgeReminders_UnexpectedError;
        }
        AuraHandledException reported = new AuraHandledException(message);
        reported.setMessage(message);
        return reported;
    }
}
