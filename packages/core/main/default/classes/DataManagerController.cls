/**
 * The Data Manager tab's import mappings card (ADR-0103 org-optimizer-and-data-manager-pages,
 * admin guide data-manager.md).
 *
 * The rest of the page needs no Apex of its own: its tool cards are gated by custom permission
 * imports in the browser, and its job history reads the import, bulk update and bulk delete
 * controllers directly. The mappings are read in user mode, and only for a holder of Manage
 * BarnCRM Settings, the permission the Import tab itself requires.
 */
public with sharing class DataManagerController {
    private static final String PERMISSION = 'Manage_BarnCRM_Settings';

    @TestVisible
    private static Boolean permissionOverride;

    /** One import mapping, as the card lists it. */
    public class Mapping {
        @AuraEnabled
        public String id;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String description;
        /** The object a one-object mapping loads; blank for a people mapping. */
        @AuraEnabled
        public String targetObject;
        @AuraEnabled
        public Boolean isRecurring;
        @AuraEnabled
        public String sourceName;
        @AuraEnabled
        public Date lastImportDate;
        /**
         * What the mapping loads, as the Loads column says it: the object's label for a
         * one-object mapping, Gifts for a people file with gift columns, else people and
         * organizations. Never an API name.
         */
        @AuraEnabled
        public String loads;
    }

    /** The row entity a gift file's columns name (Core stages it, a module loads it, R-IR6). */
    private static final String GIFT_ENTITY = 'Gift';

    /** The active import mappings, by name; none for a person who cannot import. */
    @AuraEnabled(cacheable=true)
    public static List<Mapping> getMappings() {
        List<Mapping> result = new List<Mapping>();
        if (!canImport()) {
            return result;
        }
        try {
            for (Import_Template__c template : ImportTemplateSelector.selectActive()) {
                Mapping mapping = new Mapping();
                mapping.id = template.Id;
                mapping.name = template.Name;
                mapping.description = template.Description__c;
                mapping.targetObject = template.Target_Object__c;
                mapping.isRecurring = template.Is_Recurring__c == true;
                mapping.sourceName = template.Source_Name__c;
                mapping.lastImportDate = template.Last_Import_Date__c;
                mapping.loads = loadsOf(template);
                result.add(mapping);
            }
            return result;
        } catch (Exception caught) {
            // Cacheable call: the platform refuses the Error Log insert, so nothing is logged.
            throw UserErrors.wrap(caught, 'DataManagerController.getMappings', false);
        }
    }

    /**
     * The page state key that tells Find which bulk tool a card or the Bulk Update page opened
     * it for (D-135): `c__tool` here, the namespace's own prefix inside a managed package.
     */
    @AuraEnabled(cacheable=true)
    public static String findToolStateKey() {
        return NamespaceUtil.stateKey('tool');
    }

    /**
     * The Loads column for one mapping. A one-object mapping names its object by its plural
     * label from describe (the API name only when the object is not in this org); a people
     * file whose columns load gifts reads Gifts, as the import wizard's Gifts choice does.
     */
    @TestVisible
    private static String loadsOf(Import_Template__c template) {
        if (ImportObjectSchema.loadsOneObject(template)) {
            Schema.SObjectType type = ImportObjectSchema.typeOf(template);
            return type == null
                ? template.Target_Object__c
                : type.getDescribe(SObjectDescribeOptions.DEFERRED).getLabelPlural();
        }
        Boolean loadsGifts = ImportMapping.parse(template.Column_Mapping_JSON__c)
            .mappedEntities()
            .contains(GIFT_ENTITY);
        return loadsGifts
            ? System.Label.Core_DataManager_LoadsGifts
            : System.Label.Core_DataManager_LoadsPeople;
    }

    private static Boolean canImport() {
        if (permissionOverride != null) {
            return permissionOverride;
        }
        return FeatureManagement.checkPermission(PERMISSION);
    }
}
