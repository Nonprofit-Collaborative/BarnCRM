/**
 * Reads the org-level record of a settings object the running package does not know at
 * compile time.
 *
 * Each package owns its own protected hierarchy custom setting (ADR-0017), so Core cannot
 * name a module's settings object statically. The query is built from describe results and
 * bound parameters only.
 *
 * It runs in system mode, the same access `BarnCRM_Settings__c.getOrgDefaults()` gives Core's
 * own settings. A setting is org configuration that package code reads on behalf of whoever is
 * saving (a fundraiser's gift save asks whether household members are credited), and a
 * protected custom setting cannot be granted to a subscriber user, so a user mode read failed
 * that save for every user without field access to the whole object. Changing a value is still
 * gated on the custom permission inside `SettingsWriter`.
 */
public with sharing class SettingsRecordSelector {
    public static SObject getOrgDefault(Schema.SObjectType type) {
        return orgDefault(type, false);
    }

    /**
     * The same record, locked until the transaction ends, or null when the org has never saved
     * one. A system mode writer reads through this so that two runs writing the same record at
     * the same moment (a scheduled job and a button) take turns instead of both acting on what
     * they read before the other wrote (OrgSettingsSystemWriter).
     */
    public static SObject lockOrgDefault(Schema.SObjectType type) {
        return orgDefault(type, true);
    }

    private static SObject orgDefault(Schema.SObjectType type, Boolean lock) {
        Schema.DescribeSObjectResult describe = type.getDescribe(SObjectDescribeOptions.DEFERRED);
        List<String> fields = new List<String>();
        for (Schema.SObjectField token : describe.fields.getMap().values()) {
            fields.add(token.getDescribe().getName());
        }
        String soql =
            'SELECT ' +
            String.join(fields, ', ') +
            ' FROM ' +
            describe.getName() +
            ' WHERE SetupOwnerId = :ownerId LIMIT 1' +
            (lock ? ' FOR UPDATE' : '');
        List<SObject> records = Database.queryWithBinds(
            soql,
            new Map<String, Object>{ 'ownerId' => UserInfo.getOrganizationId() },
            AccessLevel.SYSTEM_MODE
        );
        return records.isEmpty() ? null : records[0];
    }
}
