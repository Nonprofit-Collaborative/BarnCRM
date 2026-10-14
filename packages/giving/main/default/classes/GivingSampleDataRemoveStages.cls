/**
 * The Giving sample data removal (C-10, ADMIN-3), as the stages Core's SampleDataRemoveBatch
 * runs one per transaction. Each stage deletes one chunk of Giving sample records through
 * GivingSampleDataLoader.removeNext: refunds and write-offs, then the other gifts (so the
 * gifts go before the people and households they point at, which Core removes afterwards),
 * then commitments, appeals and funds. finish() hands on to the module before this one, or to
 * Core's own removal, through SampleDataModules.removeAfter.
 *
 * Nothing is kept between stages: each one reads what is left.
 */
public with sharing class GivingSampleDataRemoveStages implements SampleDataStages {
    public String name() {
        return 'GivingSampleDataRemoveStages';
    }

    /** One stage per chunk of each kind of Giving sample record. */
    public Integer stageCount() {
        return GivingSampleDataLoader.removeStageCount();
    }

    public void runStage(Integer stage) {
        GivingSampleDataLoader.removeNext();
    }

    public void finish() {
        SampleDataModules.removeAfter(GivingSampleData.MODULE_NAME);
    }
}
