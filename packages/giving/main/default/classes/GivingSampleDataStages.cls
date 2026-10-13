/**
 * The Giving sample data load (C-10), as the stages Core's SampleDataStageBatch runs one per
 * transaction. Stage 0 inserts the funds, appeals and commitments; stages 1 and up insert one
 * chunk of gifts each. finish() settles the installments already past due and hands back to
 * Core, so a module that loads after Giving would start there.
 *
 * A batch rather than a chain of queueables, because Developer Edition, trial and scratch orgs
 * stop a chain after five jobs and the gift chunks alone can be more than that.
 *
 * Only the reference key to Id map (about forty entries) is kept between stages. The payload
 * is re-read from the static resource in each stage, so a two hundred kilobyte JSON body is
 * never serialized into the batch state.
 */
public with sharing class GivingSampleDataStages implements SampleDataStages {
    private Map<String, Id> referenceIdsByKey = new Map<String, Id>();

    public String name() {
        return 'GivingSampleDataStages';
    }

    /** The reference data stage and one stage per gift chunk. */
    public Integer stageCount() {
        return GivingSampleDataSet.parse(GivingSampleData.getSampleDataJson()).chunkCount() + 1;
    }

    public void runStage(Integer stage) {
        GivingSampleDataSet data = GivingSampleDataSet.parse(GivingSampleData.getSampleDataJson());
        if (stage == 0) {
            referenceIdsByKey = GivingSampleDataLoader.loadReferenceData(data);
            return;
        }
        GivingSampleDataLoader.loadGiftChunk(data, stage - 1, referenceIdsByKey);
    }

    public void finish() {
        GivingSampleDataLoader.finish();
        SampleDataModules.startAfter(GivingSampleData.MODULE_NAME);
    }
}
