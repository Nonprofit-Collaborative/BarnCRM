/**
 * The one way a system mode writer saves keys on the org-level record of a settings object.
 *
 * ADR-0021 and ADR-0027 name the writers that may write a protected setting in system mode
 * (the console save through `SettingsWriter`, the automation pause, the seasonal swap's run
 * record, the error digest's run record). Each of them used to start from a cached or
 * `getOrgDefaults()` copy and upsert the whole record, which went wrong in three ways this
 * class exists to prevent:
 *
 * 1. On an org that has never saved its settings, `getOrgDefaults()` reads every checkbox as
 *    false, so the first save stored the features that ship on (ADR-0035) as switched off.
 * 2. Creating Core's record fills every text default, which confirms a coexistence mode and a
 *    household membership mode nobody chose (SettingsService.blanksKeptBlank).
 * 3. Upserting the whole record wrote back every other key as this transaction first read it,
 *    so a change another person saved in the meantime could be undone.
 *
 * So: when a record exists it is locked and only the given keys are updated; when none exists
 * one is created from `SettingsService.firstSaveRecord` and, for Core, the blanks are put back.
 * Every value comes from the calling writer, which carries its own authorization (see each
 * writer's header). The class adds no permission of its own and elevates nothing else.
 */
@NamespaceAccessible
public without sharing class OrgSettingsSystemWriter {
    /**
     * Test seam: a record inserted just before this writer's own first insert, as another run
     * that found no record at the same moment would have done. Apex cannot stage two real
     * transactions racing, so this is how a test reaches the duplicate path.
     */
    @TestVisible
    private static SObject competingFirstSaveForTest;

    /** Raised when a caller names something that is not a hierarchy custom setting. */
    @NamespaceAccessible
    public class OrgSettingsException extends Exception {
    }

    /** Saves the given keys on Core's settings record. */
    @NamespaceAccessible
    public static void save(Map<Schema.SObjectField, Object> values) {
        save(BarnCRM_Settings__c.SObjectType, values);
    }

    /** Saves the given keys on the org-level record of the given settings object. */
    @NamespaceAccessible
    public static void save(Schema.SObjectType type, Map<Schema.SObjectField, Object> values) {
        saveOver(type, lockStored(type), values);
    }

    /**
     * The same, for a caller that has already read the stored record through `lockStored(type)`
     * in this transaction to decide what to save. `stored` is that record, or null when the org
     * had none. Passing it saves a second read of a row this transaction already holds.
     */
    @NamespaceAccessible
    public static void saveOver(
        Schema.SObjectType type,
        SObject stored,
        Map<Schema.SObjectField, Object> values
    ) {
        requireSettingsType(type);
        if (values == null || values.isEmpty()) {
            return;
        }
        if (stored != null) {
            updateKeys(type, stored.Id, values);
        } else {
            SObject created = SettingsService.firstSaveRecord(type);
            putAll(created, values);
            if (insertFirst(created)) {
                if (type == BarnCRM_Settings__c.SObjectType) {
                    Database.update(
                        SettingsService.blanksAfterFirstSave(created),
                        AccessLevel.SYSTEM_MODE
                    );
                }
            } else {
                // Another run (the seasonal job and the digest on a new org, say) created the
                // record between this one's read and its insert. Lock theirs and save only these
                // keys on it, so neither run's values are lost.
                updateKeys(type, lockStored(type).Id, values);
            }
        }
        SettingsService.clearCache();
    }

    /**
     * Inserts the org's first settings record. False when one already exists because another
     * run inserted it first; any other failure is thrown.
     */
    private static Boolean insertFirst(SObject created) {
        if (competingFirstSaveForTest != null) {
            Database.insert(competingFirstSaveForTest, AccessLevel.SYSTEM_MODE);
            competingFirstSaveForTest = null;
        }
        try {
            Database.insert(created, AccessLevel.SYSTEM_MODE);
            return true;
        } catch (DmlException collided) {
            if (collided.getDmlType(0) == StatusCode.DUPLICATE_VALUE) {
                return false;
            }
            throw collided;
        }
    }

    private static void updateKeys(
        Schema.SObjectType type,
        Id recordId,
        Map<Schema.SObjectField, Object> values
    ) {
        SObject changes = type.newSObject(recordId);
        putAll(changes, values);
        Database.update(changes, AccessLevel.SYSTEM_MODE);
    }

    /**
     * Core's stored org-level record, locked until the transaction ends, or null when the org
     * has never saved one. Read what a decision depends on through this, then `save`, and a
     * second run waits for the first to finish instead of acting on the same stale value.
     */
    @NamespaceAccessible
    public static BarnCRM_Settings__c lockStored() {
        return (BarnCRM_Settings__c) lockStored(BarnCRM_Settings__c.SObjectType);
    }

    /** The same for any settings object. */
    @NamespaceAccessible
    public static SObject lockStored(Schema.SObjectType type) {
        requireSettingsType(type);
        return SettingsRecordSelector.lockOrgDefault(type);
    }

    /** This class writes hierarchy custom settings and nothing else. */
    private static void requireSettingsType(Schema.SObjectType type) {
        if (type == null || !type.getDescribe(SObjectDescribeOptions.DEFERRED).isCustomSetting()) {
            throw new OrgSettingsException(System.Label.Core_Settings_UnknownKeyError);
        }
    }

    private static void putAll(SObject target, Map<Schema.SObjectField, Object> values) {
        for (Schema.SObjectField field : values.keySet()) {
            target.put(field, values.get(field));
        }
    }
}
