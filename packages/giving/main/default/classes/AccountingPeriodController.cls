/**
 * The Accounting Periods page of the BarnCRM Settings console (G-20, R-G14, ADR-0053).
 *
 * It holds the one setting that closes the books: `Giving_Settings__c.Books_Closed_Through__c`.
 * The setting has no Setting Definition row naming its key, so the console's generic save cannot
 * reach it; this page is the only way it changes, and it enforces what a close date means:
 *
 * - the date moves forward only, for anyone with Manage BarnCRM Settings;
 * - it is at least two days before today, so a refund or write-off, which is dated today, lands
 *   in an open period. Two, not one: `Date.today()` is the running user's day, and a user whose
 *   time zone is ahead of the org's could otherwise close the org's today;
 * - moving it back or clearing it reopens a period, which needs Override Posting Lock (granted to
 *   nobody by the package) and is written to the Error Log at Warning.
 *
 * Every change is recorded as a Setting Change, as the console records its own.
 */
public with sharing class AccountingPeriodController {
    private static final String EDIT_PERMISSION = 'Manage_BarnCRM_Settings';
    private static final String CONTEXT = 'Accounting periods page';
    private static final String REOPEN_CONTEXT = 'Posting lock override';
    private static final String SETTING_NAME = 'Giving_Settings__c.Books_Closed_Through__c';

    /** Raised with a message the page shows as it is. */
    public class AccountingPeriodException extends Exception {
    }

    /** The page, in one round trip. */
    public class PeriodView {
        @AuraEnabled
        public Date closedThrough;
        @AuraEnabled
        public Date latestAllowed;
        @AuraEnabled
        public Boolean canManage;
        @AuraEnabled
        public Boolean canReopen;
    }

    @AuraEnabled
    public static PeriodView getPeriod() {
        try {
            return currentView();
        } catch (Exception caught) {
            throw asUserError(caught, CONTEXT);
        }
    }

    /**
     * Closes the books through `closeDate`, or reopens every period when it is null. Returns the
     * page as it now stands.
     */
    @AuraEnabled
    public static PeriodView closeThrough(Date closeDate) {
        try {
            if (!canManage()) {
                throw new AccountingPeriodException(Label.Giving_Periods_PermissionRequired);
            }
            // Locked, so whether this save reopens a period, and the audit row's old value, are
            // decided from what is stored, not from a value another person replaced a moment ago.
            Date current = AccountingPeriodWriter.lockedClosedThrough();
            if (closeDate == current) {
                return currentView();
            }
            if (closeDate != null && closeDate > latestAllowed()) {
                throw new AccountingPeriodException(Label.Giving_Periods_NotBeforeToday);
            }
            Boolean reopens = current != null && (closeDate == null || closeDate < current);
            if (reopens && !GiftPostingLock.canOverride()) {
                throw new AccountingPeriodException(Label.Giving_Periods_ReopenNeedsOverride);
            }
            AccountingPeriodWriter.saveClosedThrough(closeDate);
            SettingsService.logChange(SETTING_NAME, asText(current), asText(closeDate));
            if (reopens) {
                ErrorLogger.logMessages(
                    new List<String>{
                        String.format(
                            Label.Giving_Periods_ReopenLogged,
                            new List<String>{
                                asText(current),
                                closeDate == null ? Label.Giving_Periods_NoDate : asText(closeDate)
                            }
                        )
                    },
                    REOPEN_CONTEXT,
                    ErrorLogger.SEVERITY_WARNING
                );
            }
            return currentView();
        } catch (Exception caught) {
            throw asUserError(caught, 'Close an accounting period');
        }
    }

    /** The day before yesterday in the user's time zone, which no time zone has as its today. */
    private static Date latestAllowed() {
        return Date.today().addDays(-2);
    }

    private static PeriodView currentView() {
        PeriodView view = new PeriodView();
        view.closedThrough = GiftPostingLock.closedThrough();
        view.latestAllowed = latestAllowed();
        view.canManage = canManage();
        view.canReopen = view.canManage && GiftPostingLock.canOverride();
        return view;
    }

    private static Boolean canManage() {
        return FeatureManagement.checkPermission(EDIT_PERMISSION);
    }

    /** ISO dates, as the console records every date setting. */
    private static String asText(Date value) {
        return value == null ? '' : String.valueOf(value);
    }

    private static AuraHandledException asUserError(Exception caught, String context) {
        String message = caught.getMessage();
        if (!(caught instanceof AccountingPeriodException)) {
            ErrorLogger.log(caught, context);
            message = Label.Giving_Periods_UnexpectedError;
        }
        AuraHandledException reported = new AuraHandledException(message);
        reported.setMessage(message);
        return reported;
    }
}
