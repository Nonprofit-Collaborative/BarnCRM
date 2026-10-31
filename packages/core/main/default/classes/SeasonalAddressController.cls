/**
 * The Addresses page's seasonal swap panel, in the BarnCRM Settings console.
 *
 * It answers three questions an administrator has about a nightly job, in this order: is it
 * switched on, when did it last run, and what did it do. It also carries the only way to run the
 * job by hand, so the `Manage_BarnCRM_Settings` permission checked here is the authorization
 * for everything the run does in system mode afterwards (ADR-0027). The nightly schedule is not
 * set here: the Seasonal Addresses switch in the same section starts and stops it, through the
 * settings save and its permission check.
 */
public with sharing class SeasonalAddressController {
    /** Raised with a message the panel shows as it is. */
    public class SeasonalAddressException extends Exception {
    }

    /** The panel, in one round trip. */
    public class SwapView {
        @AuraEnabled
        public Boolean canManage;
        @AuraEnabled
        public Boolean enabled;
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
        view.enabled = SeasonalAddressScheduler.isEnabled();
        view.scheduled = SeasonalAddressScheduler.isScheduled();
        view.nextRunAt = SeasonalAddressScheduler.nextRunAt();
        view.lastRun = SeasonalAddressService.lastRun();
        view.lastRunSummary = SeasonalAddressService.lastRunSummary();
        view.stale = SeasonalAddressService.isStale(view.scheduled);
        return view;
    }

    private static Boolean canManage() {
        return BarnCRMPermissions.canManageSettings();
    }

    private static void requirePermission() {
        if (!canManage()) {
            throw new SeasonalAddressException(
                System.Label.Core_SeasonalAddress_PermissionRequired
            );
        }
    }

    private static AuraHandledException asUserError(Exception caught, String context) {
        return UserErrors.wrap(
            caught,
            caught instanceof SeasonalAddressException,
            context,
            System.Label.Core_SeasonalAddress_UnexpectedError
        );
    }
}
