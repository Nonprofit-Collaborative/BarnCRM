/**
 * First-run setup (ADR-NEXT): the window in front of BarnCRM Home and BarnCRM Settings until an
 * edition is saved. An administrator picks the edition and the features to turn on in one
 * step; anyone else is told an administrator needs to finish. It installs no module.
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
            if (featureKeys != null && !featureKeys.isEmpty()) {
                FeatureSwitchService.turnOn(new Set<String>(featureKeys));
            }
            return state();
        } catch (Exception e) {
            ErrorLogger.log(e, ERROR_CONTEXT);
            throw asAuraException(System.Label.Core_FirstRun_SaveError);
        }
    }

    private static FirstRunState state() {
        FirstRunState model = new FirstRunState();
        model.needsSetup = ModuleDetectionService.chosenSuite() == null;
        model.canFinish = BarnCRMPermissions.canManageSettings();
        if (model.needsSetup && model.canFinish) {
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
