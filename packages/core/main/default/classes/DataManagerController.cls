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
    }

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
                result.add(mapping);
            }
            return result;
        } catch (Exception caught) {
            // Cacheable call: the platform refuses the Error Log insert, so nothing is logged.
            throw UserErrors.wrap(caught, 'DataManagerController.getMappings', false);
        }
    }

    private static Boolean canImport() {
        if (permissionOverride != null) {
            return permissionOverride;
        }
        return FeatureManagement.checkPermission(PERMISSION);
    }
}
