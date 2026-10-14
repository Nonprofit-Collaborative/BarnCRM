/**
 * What a module package implements so its own sample records load and remove with Core's
 * (C-10).
 *
 * Core cannot compile against Giving, Volunteers or any other module (ADR-0009), so it
 * cannot insert a gift or count one. It does not need to: a module that ships sample data
 * implements this interface, Core finds the class by name at runtime the way the trigger
 * dispatcher finds a handler (ADR-0017), and asks it these five questions.
 *
 * The contract each implementation has to keep:
 *
 * - `enqueueLoad` starts the module's load asynchronously and returns; it never inserts the
 *   whole set in the calling transaction, because the Core batch that calls it has already
 *   spent part of that transaction's limits. Start it with SampleDataStageBatch.start over
 *   the module's SampleDataStages, not a chain of queueables, which stops after five jobs in
 *   Developer Edition, trial and scratch orgs. Its finish() calls
 *   SampleDataModules.startAfter with the module's name.
 * - `enqueueRemove` starts the module's removal and returns, the same way. Start it with
 *   SampleDataRemoveBatch.startRemoval over the module's SampleDataStages, one chunk of
 *   records per stage. Its finish() calls SampleDataModules.removeAfter with the module's
 *   name, which starts the module before it and then Core's own removal, because Core
 *   deletes the households and people the module's records point at only after that. It
 *   deletes only records the module's own loader created.
 * - `countLoaded` answers cheaply enough to be called from the status card on a poll.
 */
@NamespaceAccessible
public interface SampleDataModule {
    /** The module's stable name, matching the name it announces to module detection, for example 'Giving'. */
    String moduleName();

    /** The module's own label for the number the status card shows, for example 'Gifts'. */
    String countLabel();

    /** How many of the records this number stands for are loaded right now. */
    Integer countLoaded();

    /** Starts this module's load chain. Called once, after Core's own records exist. */
    void enqueueLoad();

    /** Starts this module's removal. Called before Core's own records are removed. */
    void enqueueRemove();
}
