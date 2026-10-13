/**
 * Reads the shipped Setting Definition rows that tell the BarnCRM Settings console
 * what to show, in the order the console shows them.
 *
 * The rows are package-shipped custom metadata holding no organization data, and every save
 * that reads a setting reads them (SettingsService checks a named settings object against
 * them), so they are read as shipped rather than in user mode, as the automation registry
 * is. In user mode, on an org that restricts custom metadata to the users granted it, a
 * fundraiser's gift save failed on this read.
 */
public with sharing class SettingDefinitionSelector {
    /**
     * Rows used instead of the shipped ones. Custom metadata records cannot be created in
     * a test, so tests set this to in-memory rows.
     */
    @TestVisible
    private static List<Setting_Definition__mdt> stubbedRows;

    /** Read once per transaction: the console, the service and the search all ask for the list. */
    private static List<Setting_Definition__mdt> cachedRows;

    public static List<Setting_Definition__mdt> getAll() {
        if (stubbedRows != null) {
            return stubbedRows;
        }
        if (cachedRows != null) {
            return cachedRows;
        }
        cachedRows = [
            SELECT
                DeveloperName,
                MasterLabel,
                Setting_Key__c,
                Settings_Object__c,
                Section__c,
                Module__c,
                Data_Type__c,
                Picklist_Values__c,
                Record_Object__c,
                Component__c,
                Navigation_Target__c,
                Description__c,
                Help_Path__c,
                Required_Permission__c,
                Sort_Order__c,
                Min_Value__c,
                Max_Value__c
            FROM Setting_Definition__mdt
            WITH SYSTEM_MODE
            ORDER BY Section__c, Sort_Order__c, MasterLabel
            LIMIT 500
        ];
        return cachedRows;
    }

    /**
     * The same rows, unordered, with every long text area (Description, Picklist Values) cut to
     * 255 characters, for a reader that needs only the short fields. `getAll()` above selects
     * long text, and a custom metadata query that does so counts against the SOQL limit; this
     * read costs no query at all, because the platform serves it from its own metadata cache
     * across transactions (ADR-0094). A module's gift save that reads
     * one of its settings checks the object here.
     */
    public static List<Setting_Definition__mdt> getAllShortFields() {
        if (stubbedRows != null) {
            return stubbedRows;
        }
        return Setting_Definition__mdt.getAll().values();
    }
}
