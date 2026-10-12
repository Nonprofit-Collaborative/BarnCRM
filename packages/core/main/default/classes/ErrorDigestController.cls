/**
 * The error digest panel on the Error Log page of the BarnCRM Settings console (C-23).
 *
 * It answers what an administrator asks about a job that sends email: is it on, when does it
 * run next, when did it last run and what did it do, and who gets it. It carries the only two
 * ways a digest is ever sent, so the `Manage_Nonprofit_Settings` permission checked here is the
 * authorization for what the job does afterwards (ADR-0027, ADR-0038). Anybody who can open the
 * console can read the panel.
 */
public with sharing class ErrorDigestController {
    private static final String EDIT_PERMISSION = 'Manage_Nonprofit_Settings';

    /** Raised with a message the panel shows as it is. */
    public class ErrorDigestException extends Exception {
    }

    /** The panel, in one round trip. */
    public class DigestView {
        @AuraEnabled
        public Boolean canManage;
        @AuraEnabled
        public Boolean scheduled;
        @AuraEnabled
        public Datetime nextRunAt;
        @AuraEnabled
        public Datetime lastRun;
        @AuraEnabled
        public String lastRunSummary;
        /** The names of the people the next digest goes to. */
        @AuraEnabled
        public List<String> recipients;
        /** True when nobody is listed, so it goes to everyone who administers BarnCRM. */
        @AuraEnabled
        public Boolean toAdministrators;
    }

    @AuraEnabled(cacheable=true)
    public static DigestView getDigest() {
        try {
            return currentView();
        } catch (Exception caught) {
            throw asUserError(caught, 'Error digest page');
        }
    }

    /** Starts or stops the daily digest job. */
    @AuraEnabled
    public static DigestView setSchedule(Boolean scheduled) {
        try {
            requirePermission();
            if (scheduled == true) {
                ErrorDigestScheduler.start();
            } else {
                ErrorDigestScheduler.stop();
            }
            return currentView();
        } catch (Exception caught) {
            throw asUserError(caught, 'Schedule the error digest');
        }
    }

    /** Sends a digest now, whatever the frequency says; nothing is sent when nothing is new. */
    @AuraEnabled
    public static DigestView sendNow() {
        try {
            requirePermission();
            ErrorDigestService.sendNow();
            return currentView();
        } catch (Exception caught) {
            throw asUserError(caught, 'Send the error digest now');
        }
    }

    private static DigestView currentView() {
        Nonprofit_Settings__c settings = SettingsService.getSettings();
        DigestView view = new DigestView();
        view.canManage = canManage();
        view.nextRunAt = ErrorDigestScheduler.nextRunAt();
        view.scheduled = view.nextRunAt != null;
        view.lastRun = settings.Error_Digest_Last_Run__c;
        view.lastRunSummary = settings.Error_Digest_Last_Run_Summary__c;
        view.toAdministrators = String.isBlank(settings.Error_Digest_Recipients__c);
        view.recipients = new List<String>();
        for (User recipient : ErrorDigestRecipients.resolve(settings.Error_Digest_Recipients__c)) {
            view.recipients.add(recipient.Name);
        }
        return view;
    }

    private static Boolean canManage() {
        return FeatureManagement.checkPermission(EDIT_PERMISSION);
    }

    private static void requirePermission() {
        if (!canManage()) {
            throw new ErrorDigestException(System.Label.Core_ErrorDigest_PermissionRequired);
        }
    }

    private static AuraHandledException asUserError(Exception caught, String context) {
        String message = caught.getMessage();
        if (!(caught instanceof ErrorDigestException)) {
            ErrorLogger.log(caught, context);
            message = System.Label.Core_ErrorDigest_UnexpectedError;
        }
        AuraHandledException reported = new AuraHandledException(message);
        reported.setMessage(message);
        return reported;
    }
}
