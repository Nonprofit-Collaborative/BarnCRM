/**
 * The Apex surface of the Settings, Integrations page: the list of other products and whether
 * each is in this org. Anyone who can open BarnCRM Settings can read it, as with the Module
 * Manager's list. Nothing here changes anything.
 */
public with sharing class IntegrationController {
    private static final String ERROR_CONTEXT = 'Integrations';

    /** Not cacheable, so the page's Check again button reads the org again. */
    @AuraEnabled
    public static List<IntegrationAppService.AppInfo> getApps() {
        try {
            return IntegrationAppService.getApps();
        } catch (Exception e) {
            ErrorLogger.log(e, ERROR_CONTEXT);
            AuraHandledException error = new AuraHandledException(
                System.Label.Core_Integrations_LoadErrorMessage
            );
            error.setMessage(System.Label.Core_Integrations_LoadErrorMessage);
            throw error;
        }
    }
}
