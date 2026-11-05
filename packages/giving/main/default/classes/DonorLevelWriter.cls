/**
 * The two system mode writes donor levels need, and nothing else (ADR-0021).
 *
 * Both meet that ADR's conditions. The values are computed by package code from a giving total the
 * rollup engine wrote, no user typed text reaches them, and only fields this package owns are
 * written. The reason the writes are elevated is the reason the rollup engine's are: a nightly
 * recalculation must place every donor on the right rung whether or not the user the job happens
 * to run as can see them, and a level that silently stopped being maintained for some records
 * would be worse than no levels at all.
 *
 * Real time assignment is not here. It happens in a before trigger, where the platform writes the
 * values with the save the user already authorized, so it needs no elevation and no second DML.
 */
public without sharing class DonorLevelWriter {
    /** Saves records a recalculation moved between levels. */
    public static void save(List<SObject> moved) {
        if (moved == null || moved.isEmpty()) {
            return;
        }
        Database.update(moved, true, AccessLevel.SYSTEM_MODE);
    }

    /**
     * Saves only the values a recalculation changed (RT-09): each record goes out as its Id and
     * the fields whose value differs from `before` (the record as read), and a record with no
     * change is not written at all, so it costs no DML row and fires no trigger.
     */
    public static Integer saveChanged(List<SObject> recalculated, Map<Id, SObject> before) {
        List<SObject> slim = changedOnly(recalculated, before);
        save(slim);
        return slim.size();
    }

    @TestVisible
    private static List<SObject> changedOnly(List<SObject> recalculated, Map<Id, SObject> before) {
        List<SObject> slim = new List<SObject>();
        if (recalculated == null) {
            return slim;
        }
        for (SObject record : recalculated) {
            SObject original = before == null ? null : before.get(record.Id);
            SObject changes = record.getSObjectType().newSObject(record.Id);
            Boolean anyChange = false;
            Map<String, Object> was = original == null
                ? new Map<String, Object>()
                : original.getPopulatedFieldsAsMap();
            Map<String, Object> now = record.getPopulatedFieldsAsMap();
            for (String field : now.keySet()) {
                Object value = now.get(field);
                if (field == 'Id' || value instanceof SObject || value instanceof List<SObject>) {
                    continue;
                }
                if (original != null && was.get(field) == value) {
                    continue;
                }
                changes.put(field, value);
                anyChange = true;
            }
            if (anyChange) {
                slim.add(changes);
            }
        }
        return slim;
    }

    /**
     * Stamps when a recalculation finished, the freshness promise the rollups make (Principle 2).
     * Only this key is written, on the locked stored record, and a first save keeps the
     * checkboxes that ship on (OrgSettingsSystemWriter).
     */
    public static void stampRecalculation(Datetime completedAt) {
        OrgSettingsSystemWriter.save(
            Giving_Settings__c.SObjectType,
            new Map<Schema.SObjectField, Object>{
                Giving_Settings__c.Donor_Levels_Last_Recalculated__c => completedAt
            }
        );
    }
}
