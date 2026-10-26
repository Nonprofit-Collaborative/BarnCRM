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
        /**
         * A plain notice for each other rollup tool in the org (DLRS, Rollup Helper), said only
         * when a module that calculates totals, Rollup Builder or Giving, is installed (R-R16).
         */
        @AuraEnabled
        public List<String> otherRollupTools;
    }

    /** The modules that calculate totals, so another rollup tool matters to them. */
    private static final Set<String> TOTALLING_MODULES = new Set<String>{ 'Rollups', 'Giving' };

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
        state.otherRollupTools = new List<String>();
        for (ModuleManagerService.ModuleStatus module : state.modules) {
            if (
                TOTALLING_MODULES.contains(module.name) &&
                module.status != ModuleManagerService.STATUS_NOT_INSTALLED
            ) {
                state.otherRollupTools = OtherRollupTools.notices();
                break;
            }
        }
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
