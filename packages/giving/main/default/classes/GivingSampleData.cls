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

    /**
     * Starts the Giving load. Core calls this from the last stage of its own chain, so the
     * households and people every gift points at already exist.
     */
    public void enqueueLoad() {
        System.enqueueJob(
            new GivingSampleDataQueueable(
                GivingSampleDataQueueable.STAGE_REFERENCE_DATA,
                new Map<String, Id>()
            )
        );
    }

    /**
     * Deletes every Giving sample record, inside Core's remove transaction. Allocations,
     * soft credits, tributes and installments are details of a gift or a commitment, so
     * they go with their master rather than being deleted here.
     */
    public Integer removeAll() {
        return GivingSampleDataLoader.removeAll();
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
}
