/**
 * Core's C-10 sample data removal, as the stages SampleDataRemoveBatch runs one per
 * transaction (ADMIN-3). It runs after every installed module has removed its own records,
 * because a gift points at a person and a household.
 *
 * Each stage deletes one chunk (SampleDataLoader.REMOVE_CHUNK_SIZE records) of the first kind
 * that still has sample records, in this order, so nothing is left pointing at a record that
 * has just gone: connections, affiliations, contacts, then the accounts. The number of stages
 * is the number of chunks each kind needs, counted when the batch starts. Every stage reads
 * its list again, so a record an earlier stage's automation already removed (the other side
 * of a connection, a household that upkeep tidied away) is never asked for a second time, and
 * a stage that finds nothing left does nothing.
 *
 * Everything the loader creates is either flagged itself or a detail of something that is,
 * which is what keeps this to "delete only what the loader created". Records an administrator
 * entered have the box clear and are never in these lists.
 *
 * In junction mode the membership rows the load created go with the households: the Household
 * field on a household member record is a required lookup that cascades, so deleting a
 * household flagged Sample_Data__c takes its own membership rows with it.
 *
 * Nothing is kept between stages: each one reads what is left.
 */
public with sharing class SampleDataRemoveStages implements SampleDataStages {
    public String name() {
        return 'SampleDataRemoveStages';
    }

    /** One stage per chunk of each kind of record, so the whole set is covered. */
    public Integer stageCount() {
        SampleDataSelector selector = new SampleDataSelector();
        return chunksFor(selector.getSampleRelationshipIds().size()) +
            chunksFor(selector.getSampleAffiliationIds().size()) +
            chunksFor(selector.getSampleContactIds().size()) +
            chunksFor(selector.getSampleAccountIds().size());
    }

    public void runStage(Integer stage) {
        removeNextChunk();
    }

    /** Nothing follows Core's records: the card sees the batch end and reports Not loaded. */
    public void finish() {
        return;
    }

    /**
     * Deletes the next chunk of sample records and returns true when it deleted anything.
     * Static and public so the tests drive a stage without a batch.
     */
    public static Boolean removeNextChunk() {
        SampleDataSelector selector = new SampleDataSelector();
        return deleteChunk(selector.getSampleRelationshipIds()) ||
            deleteChunk(selector.getSampleAffiliationIds()) ||
            deleteChunk(selector.getSampleContactIds()) ||
            deleteChunk(selector.getSampleAccountIds());
    }

    private static Integer chunksFor(Integer recordCount) {
        Integer size = SampleDataLoader.REMOVE_CHUNK_SIZE;
        return (recordCount + size - 1) / size;
    }

    /** Deletes up to one chunk of these ids; false when there were none. */
    private static Boolean deleteChunk(List<Id> ids) {
        if (ids.isEmpty()) {
            return false;
        }
        List<Id> chunk = new List<Id>();
        for (Integer i = 0; i < ids.size() && i < SampleDataLoader.REMOVE_CHUNK_SIZE; i++) {
            chunk.add(ids[i]);
        }
        Database.delete(chunk, AccessLevel.USER_MODE);
        return true;
    }
}
