/**
 * The Addresses page's seasonal swap panel, in the BarnCRM Settings console.
 *
 * It answers three questions an administrator has about a nightly job, in this order: is it
 * switched on, when did it last run, and what did it do. It also carries the only two ways the
 * job is ever started, so the `Manage_Nonprofit_Settings` permission checked here is the
 * authorization for everything the run does in system mode afterwards (ADR-0027).
 */
public with sharing class SeasonalAddressController {
    private static final String EDIT_PERMISSION = 'Manage_Nonprofit_Settings';

    /** Raised with a message the panel shows as it is. */
    public class SeasonalAddressException extends Exception {
    }

    /** The panel, in one round trip. */
    public class SwapView {
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
        @AuraEnabled
        public Boolean stale;
    }

    @AuraEnabled(cacheable=true)
    public static SwapView getSwap() {
        try {
            return currentView();
        } catch (Exception caught) {
            throw asUserError(caught, 'Seasonal address swap page');
        }
    }

    /** Starts or stops the nightly swap. */
    @AuraEnabled
    public static SwapView setSchedule(Boolean scheduled) {
        try {
            requirePermission();
            if (scheduled == true) {
                SeasonalAddressScheduler.start();
            } else {
                SeasonalAddressScheduler.stop();
            }
            return currentView();
        } catch (Exception caught) {
            throw asUserError(caught, 'Schedule the seasonal address swap');
        }
    }

    /**
     * Runs the swap now. The view comes back with the schedule and the previous run on it: the
     * run just started is a batch, and the panel refreshes into the new last run once it ends.
     */
    @AuraEnabled
    public static SwapView runNow() {
        try {
            requirePermission();
            SeasonalAddressScheduler.runNow();
            return currentView();
        } catch (Exception caught) {
            throw asUserError(caught, 'Run the seasonal address swap now');
        }
    }

    private static SwapView currentView() {
        SwapView view = new SwapView();
        view.canManage = canManage();
        view.scheduled = SeasonalAddressScheduler.isScheduled();
        view.nextRunAt = SeasonalAddressScheduler.nextRunAt();
        view.lastRun = SeasonalAddressService.lastRun();
        view.lastRunSummary = SeasonalAddressService.lastRunSummary();
        view.stale = SeasonalAddressService.isStale();
        return view;
    }

    private static Boolean canManage() {
        return FeatureManagement.checkPermission(EDIT_PERMISSION);
    }

    private static void requirePermission() {
        if (!canManage()) {
            throw new SeasonalAddressException(
                System.Label.Core_SeasonalAddress_PermissionRequired
            );
        }
    }

    private static AuraHandledException asUserError(Exception caught, String context) {
        String message = caught.getMessage();
        if (!(caught instanceof SeasonalAddressException)) {
            ErrorLogger.log(caught, context);
            message = System.Label.Core_SeasonalAddress_UnexpectedError;
        }
        AuraHandledException reported = new AuraHandledException(message);
        reported.setMessage(message);
        return reported;
    }
}
