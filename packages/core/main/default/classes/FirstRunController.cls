/**
 * First-run setup (ADR-0124): the window in front of BarnCRM Home and BarnCRM Settings until it
 * is finished. It shows while no edition is saved, or while the features list still holds the
 * new install's `None`: an edition typed in Setup, Custom Settings before first-run setup does
 * not skip the feature choice, and the window pre-selects that edition. Finishing always
 * leaves the list off `None` (`NoneChosen` when every feature was unticked), so the window
 * cannot come back; an upgraded org (an empty list) never sees it once an edition is saved.
 * An administrator picks the edition and the features to turn on in one step; anyone else is
 * told an administrator needs to finish. It installs no module.
 */
public with sharing class FirstRunController {
    private static final String ERROR_CONTEXT = 'FirstRunController';

    /** Whether the window shows, who may finish it, and what it offers. */
    public class FirstRunState {
        @AuraEnabled
        public Boolean needsSetup;
        @AuraEnabled
        public Boolean canFinish;
        @AuraEnabled
        public String recommendedSuite;
        @AuraEnabled
        public List<FeatureController.FeatureRow> features;
    }

    /** The window's state. Not cacheable: it changes the moment setup finishes. */
    @AuraEnabled
    public static FirstRunState getState() {
        try {
            return state();
        } catch (Exception e) {
            ErrorLogger.log(e, ERROR_CONTEXT);
            throw asAuraException(System.Label.Core_FirstRun_LoadError);
        }
    }

    /**
     * Saves the edition and turns on the ticked features, in one transaction: if either fails,
     * the thrown error rolls both back and the window stays. A feature already on stays on.
     */
    @AuraEnabled
    public static FirstRunState finish(String suite, List<String> featureKeys) {
        if (!BarnCRMPermissions.canManageSettings()) {
            throw asAuraException(System.Label.Core_Settings_PermissionRequiredError);
        }
        String chosen = knownSuite(suite);
        try {
            SetupAssistantService.ensureStarted();
            SettingsService.saveValues(new Map<String, Object>{ 'Suite__c' => chosen });
            FeatureSwitchService.finishFirstRun(
                featureKeys == null ? new Set<String>() : new Set<String>(featureKeys)
            );
            giveTabsToEveryRole();
            return state();
        } catch (Exception e) {
            ErrorLogger.log(e, ERROR_CONTEXT);
            throw asAuraException(System.Label.Core_FirstRun_SaveError);
        }
    }

    /**
     * Gives the tool tabs of the features now on to everyone holding a BarnCRM role, and starts
     * the hourly tab access check unless it is running. Turning features on queues the sync
     * only when one is newly on, and on an org built from source every feature was already on,
     * so finishing would otherwise leave the tool tabs hidden until somebody changed a role on
     * the Access page. Neither step throws: the sync logs its own failure, and a check that
     * cannot be scheduled is logged and listed by Health Check.
     */
    private static void giveTabsToEveryRole() {
        TabAccessService.requestSync();
        if (Test.isRunningTest() && !startTabCheckInTests) {
            return;
        }
        try {
            TabAccessScheduler.start();
        } catch (Exception e) {
            ErrorLogger.log(e, ERROR_CONTEXT);
        }
    }

    /** Test seam: true lets a test see the hourly tab access check started. */
    @TestVisible
    private static Boolean startTabCheckInTests = false;

    private static FirstRunState state() {
        FirstRunState model = new FirstRunState();
        model.needsSetup =
            ModuleDetectionService.chosenSuite() == null || FeatureSwitchService.awaitingFirstRun();
        model.canFinish = BarnCRMPermissions.canManageSettings();
        if (model.needsSetup && model.canFinish) {
            // The saved edition when there is one (set in Setup), otherwise the suggestion.
            model.recommendedSuite = SetupAssistantService.recommendedSuite();
            model.features = FeatureController.rows();
        } else {
            model.features = new List<FeatureController.FeatureRow>();
        }
        return model;
    }

    private static String knownSuite(String suite) {
        String chosen = suite == null ? '' : suite.trim();
        if (
            chosen != ModuleDetectionService.SUITE_COMMUNITY &&
            chosen != ModuleDetectionService.SUITE_IMPACT
        ) {
            throw asAuraException(System.Label.Core_SuiteChoice_UnknownSuiteError);
        }
        return chosen;
    }

    private static AuraHandledException asAuraException(String message) {
        AuraHandledException error = new AuraHandledException(message);
        error.setMessage(message);
        return error;
    }
}
