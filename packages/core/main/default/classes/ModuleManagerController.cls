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
    }

    @AuraEnabled
    public static ManagerState getState() {
        try {
            return buildState();
        } catch (Exception e) {
            throw logged(e, System.Label.Core_ModuleManager_LoadErrorMessage);
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
