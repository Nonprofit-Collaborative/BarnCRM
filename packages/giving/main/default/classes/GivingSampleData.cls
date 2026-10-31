/**
 * The Giving half of the C-10 sample data set: Core finds this class by name, so the same
 * Load Sample Data action in the BarnCRM Settings console fills an org that has Giving
 * with funds, appeals, three years of gifts, pledges, soft credits and tributes, and the
 * same Remove Sample Data action takes them away again (ADR-0017, SampleDataModule).
 *
 * Nothing here is receipted. A receipt number locks a gift against deletion (ADR-0024), and
 * a sample set that cannot be removed is worse than no sample set, so receipting is left to
 * the receipting feature and every sample gift arrives without a receipt number.
 *
 * See docs/admin-guide/sample-data.md for what the set contains and data/sample/README.md
 * for the payload format.
 */
@NamespaceAccessible
public with sharing class GivingSampleData implements SampleDataModule {
    /** The name Core knows this module by, matching module detection. */
    public static final String MODULE_NAME = 'Giving';

    /**
     * Gifts inserted per chunk. One hundred gifts brings roughly a hundred and ten
     * allocations, the household soft credits the automatic rule writes for each one, and
     * the tributes on a few of them: about three hundred rows and their triggers, which is
     * the same order of magnitude as the hundred contacts Core's own chunk inserts, and
     * well inside one asynchronous transaction.
     */
    public static final Integer GIFT_CHUNK_SIZE = 100;

    /** Prefix on every sample gift's external id, so a reversal can find its original. */
    public static final String EXTERNAL_ID_PREFIX = 'SAMPLE-';

    /** Injected by the tests in place of the static resource body. Null in production. */
    @TestVisible
    private static String jsonOverride;

    public class SampleDataException extends Exception {
    }

    @NamespaceAccessible
    public GivingSampleData() {
        return;
    }

    public String moduleName() {
        return MODULE_NAME;
    }

    public String countLabel() {
        return System.Label.Giving_SampleData_GiftsLabel;
    }

    /**
     * The number the status card shows for Giving: sample gifts. Gifts are the record an
     * administrator is looking for, and one query answers whether the Giving half loaded.
     */
    public Integer countLoaded() {
        return new GivingSampleDataSelector().countSampleGifts();
    }

    /** Giving's removal keeps nothing, so its gifts answer whether any of its set is left. */
    public Boolean hasSampleRecords() {
        return countLoaded() > 0;
    }

    /**
     * Starts the Giving load. Core calls this when its own load has finished, so the
     * households and people every gift points at already exist.
     */
    public void enqueueLoad() {
        SampleDataStageBatch.start(new LoadStages());
    }

    /**
     * Starts the Giving removal. Core calls this before it removes its own records, so the
     * gifts go before the people and households they point at. Allocations, soft credits,
     * tributes and installments are details of a gift or a commitment, so they go with their
     * master rather than being deleted on their own.
     */
    public void enqueueRemove() {
        SampleDataRemoveBatch.startRemoval(new RemoveStages());
    }

    /** The Giving sample data JSON body, from the injected override or the static resource. */
    public static String getSampleDataJson() {
        if (jsonOverride != null) {
            return jsonOverride;
        }
        StaticResource resource = new GivingSampleDataSelector().getSampleDataResource();
        if (resource == null) {
            throw new SampleDataException(System.Label.Giving_SampleData_ResourceMissing);
        }
        return resource.Body.toString();
    }

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
    public with sharing class LoadStages implements SampleDataStages {
        private Map<String, Id> referenceIdsByKey = new Map<String, Id>();

        public String name() {
            return 'GivingSampleDataStages';
        }

        /** The reference data stage and one stage per gift chunk. */
        public Integer stageCount() {
            return GivingSampleDataSet.parse(GivingSampleData.getSampleDataJson()).chunkCount() + 1;
        }

        public void runStage(Integer stage) {
            GivingSampleDataSet data = GivingSampleDataSet.parse(
                GivingSampleData.getSampleDataJson()
            );
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
    public with sharing class RemoveStages implements SampleDataStages {
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
}
