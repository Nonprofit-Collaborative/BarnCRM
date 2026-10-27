/**
 * The Module Manager's Apex surface (C-24). Reading the list is open to anyone who can open
 * BarnCRM Settings; turning a module on or off, granting its admin access and counting what an
 * uninstall would delete each check `Manage_BarnCRM_Settings` first, log what went wrong, and
 * return a message Maria can act on.
 */
public with sharing class ModuleManagerController {
    private static final String ERROR_CONTEXT = 'Module Manager';

    /** Everything the Module Manager draws. */
    public class ManagerState {
        @AuraEnabled
        public Boolean canEdit;
        @AuraEnabled
        public List<ModuleManagerService.ModuleStatus> modules;
        /** The Show Nonprofit Modules checkbox: false hides the nonprofit modules. */
        @AuraEnabled
        public Boolean showNonprofitModules;
    }

    @AuraEnabled
    public static ManagerState getState() {
        try {
            return buildState();
        } catch (Exception e) {
            throw logged(e, System.Label.Core_ModuleManager_LoadErrorMessage);
        }
    }

    /** Saves the Show Nonprofit Modules checkbox for the whole org; it hides rows and changes nothing else. */
    @AuraEnabled
    public static ManagerState saveShowNonprofitModules(Boolean show) {
        requireEdit();
        try {
            ModuleManagerService.setShowNonprofitModules(show);
            return buildState();
        } catch (Exception e) {
            throw logged(e, System.Label.Core_ModuleManager_SaveErrorMessage);
        }
    }

    @AuraEnabled
    public static ManagerState turnOff(String moduleName) {
        requireEdit();
        try {
            ModuleManagerService.turnOff(moduleName);
            return buildState();
        } catch (Exception e) {
            throw logged(e, System.Label.Core_ModuleManager_SaveErrorMessage);
        }
    }

    /** The page follows this with grantAdminAccess, which cannot share its transaction. */
    @AuraEnabled
    public static ManagerState turnOn(String moduleName) {
        requireEdit();
        try {
            ModuleManagerService.turnOn(moduleName);
            return buildState();
        } catch (Exception e) {
            throw logged(e, System.Label.Core_ModuleManager_SaveErrorMessage);
        }
    }

    /**
     * Finish Setup (FS1): runs the setup steps an install of this package runs, for one copied
     * into the org by hand. Safe to run twice; recorded in the settings change history.
     */
    @AuraEnabled
    public static ManagerState finishSetup(String moduleName) {
        requireEdit();
        try {
            List<String> done = ModuleSetups.finish(new List<String>{ moduleName });
            SettingsService.logChange(
                System.Label.Core_ModuleSetup_FinishButton,
                '',
                String.join(done, ', ')
            );
            return buildState();
        } catch (Exception e) {
            throw logged(e, System.Label.Core_ModuleManager_SaveErrorMessage);
        }
    }

    @AuraEnabled
    public static Boolean grantAdminAccess(String moduleName) {
        requireEdit();
        try {
            return ModuleManagerService.grantAdminAccess(moduleName);
        } catch (Exception e) {
            throw logged(e, System.Label.Core_ModuleManager_AccessErrorMessage);
        }
    }

    @AuraEnabled
    public static List<ModuleManagerService.RecordCount> uninstallReport(String moduleName) {
        requireEdit();
        try {
            return ModuleManagerService.uninstallReport(moduleName);
        } catch (Exception e) {
            throw logged(e, System.Label.Core_ModuleManager_LoadErrorMessage);
        }
    }

    private static ManagerState buildState() {
        ManagerState state = new ManagerState();
        state.canEdit = BarnCRMPermissions.canManageSettings();
        state.modules = ModuleManagerService.getModules();
        state.showNonprofitModules = ModuleManagerService.showNonprofitModules();
        return state;
    }

    private static AuraHandledException logged(Exception e, String fallback) {
        ErrorLogger.log(e, ERROR_CONTEXT);
        return asAuraException(
            e instanceof ModuleManagerService.ModuleManagerException ? e.getMessage() : fallback
        );
    }

    private static void requireEdit() {
        if (!BarnCRMPermissions.canManageSettings()) {
            throw asAuraException(System.Label.Core_Settings_PermissionRequiredError);
        }
    }

    private static AuraHandledException asAuraException(String message) {
        AuraHandledException error = new AuraHandledException(message);
        error.setMessage(message);
        return error;
    }
}
