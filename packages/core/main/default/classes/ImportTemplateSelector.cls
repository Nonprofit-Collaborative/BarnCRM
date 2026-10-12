/**
 * Every query against import templates and the templates the package ships.
 *
 * Reads that reach an administrator run in user mode. The shipped defaults are custom
 * metadata, which carries no sharing.
 */
@NamespaceAccessible
public with sharing class ImportTemplateSelector {
    /** Active templates, in the order the wizard lists them. */
    @NamespaceAccessible
    public static List<Import_Template__c> selectActive() {
        return [
            SELECT
                Id,
                Name,
                Description__c,
                Template_Key__c,
                Column_Mapping_JSON__c,
                Default_Values_JSON__c,
                Matching_Rule__c,
                Person_Mode__c,
                Is_Package_Default__c,
                Is_Recurring__c,
                Source_Name__c,
                Last_Import_Date__c,
                Active__c,
                Payment_Matching__c,
                Match_Date_Window_Days__c,
                Match_Amount_Tolerance__c
            FROM Import_Template__c
            WHERE Active__c = TRUE
            WITH USER_MODE
            ORDER BY Name ASC
            LIMIT 500
        ];
    }

    /** One template, or null when it is gone or the user cannot see it. */
    @NamespaceAccessible
    public static Import_Template__c selectById(Id templateId) {
        if (templateId == null) {
            return null;
        }
        List<Import_Template__c> found = [
            SELECT
                Id,
                Name,
                Description__c,
                Template_Key__c,
                Column_Mapping_JSON__c,
                Default_Values_JSON__c,
                Matching_Rule__c,
                Person_Mode__c,
                Is_Package_Default__c,
                Is_Recurring__c,
                Source_Name__c,
                Last_Import_Date__c,
                Active__c,
                Payment_Matching__c,
                Match_Date_Window_Days__c,
                Match_Amount_Tolerance__c
            FROM Import_Template__c
            WHERE Id = :templateId
            WITH USER_MODE
            LIMIT 1
        ];
        return found.isEmpty() ? null : found[0];
    }

    /**
     * Existing templates keyed by their template key, for the materialization that must
     * never overwrite an edited template (R-IT4). Runs in system mode because upgrade
     * bookkeeping must see every row, including one a running user cannot.
     */
    @NamespaceAccessible
    public static Map<String, Import_Template__c> selectByKeys(Set<String> keys) {
        Map<String, Import_Template__c> result = new Map<String, Import_Template__c>();
        if (keys == null || keys.isEmpty()) {
            return result;
        }
        List<Import_Template__c> found = Database.queryWithBinds(
            'SELECT Id, Template_Key__c, Is_Package_Default__c FROM Import_Template__c ' +
            'WHERE Template_Key__c IN :keys',
            new Map<String, Object>{ 'keys' => keys },
            AccessLevel.SYSTEM_MODE
        );
        for (Import_Template__c template : found) {
            result.put(template.Template_Key__c, template);
        }
        return result;
    }

    /** The templates the package ships (canonical model Section 13). */
    @NamespaceAccessible
    public static List<Import_Template_Default__mdt> selectShippedDefaults() {
        return [
            SELECT
                DeveloperName,
                MasterLabel,
                Description__c,
                Template_Key__c,
                Column_Mapping_JSON__c,
                Default_Values_JSON__c,
                Matching_Rule__c,
                Person_Mode__c,
                Default_Active__c
            FROM Import_Template_Default__mdt
            WITH SYSTEM_MODE
            ORDER BY MasterLabel ASC
            LIMIT 200
        ];
    }
}
