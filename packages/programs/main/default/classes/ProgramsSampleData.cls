/**
 * The Programs part of the C-10 sample data set: Core finds this class by name
 * (`SampleDataModules.MODULE_CLASS_NAMES`), so the same Load Sample Data action in BarnCRM
 * Settings fills an org that has Programs with three programs, their services and enrollments of
 * Core's sample people, and the same Remove Sample Data action takes them away again (ADR-0017,
 * SampleDataModule). The records are built and removed by ProgramSampleDataLoader.
 *
 * `@NamespaceAccessible`, public, with a public no-argument constructor, because Core resolves it
 * with `Type.forName` under ADR-0017.
 */
@NamespaceAccessible
public with sharing class ProgramsSampleData implements SampleDataModule {
    @NamespaceAccessible
    public ProgramsSampleData() {
        // Built by name from Core (SampleDataModules), so it needs a public constructor.
    }

    public String moduleName() {
        return ProgramsAccessSync.MODULE_NAME;
    }

    public String countLabel() {
        return System.Label.Programs_SampleData_CountLabel;
    }

    /** The number the status card shows for Programs: sample people's enrollments. */
    public Integer countLoaded() {
        return ProgramSampleDataLoader.countSampleEnrollments();
    }

    /** Whether a sample program is still here, including one removal kept. */
    public Boolean hasSampleRecords() {
        return ProgramSampleDataLoader.hasSamplePrograms();
    }

    /** Starts the Programs load, after Core's people and the modules before it. */
    public void enqueueLoad() {
        SampleDataStageBatch.start(new LoadStages());
    }

    /** Starts the Programs removal, before the modules before it and Core's people. */
    public void enqueueRemove() {
        SampleDataRemoveBatch.startRemoval(new RemoveStages());
    }

    /** The load, one stage per transaction: the programs and services, then the enrollments. */
    public class LoadStages implements SampleDataStages {
        public String name() {
            return 'ProgramsSampleData.LoadStages';
        }

        public Integer stageCount() {
            return 2;
        }

        public void runStage(Integer stage) {
            if (stage == 0) {
                ProgramSampleDataLoader.loadPrograms();
            } else {
                ProgramSampleDataLoader.loadEnrollments();
            }
        }

        public void finish() {
            SampleDataModules.startAfter(ProgramsAccessSync.MODULE_NAME);
        }
    }

    /**
     * The removal, one chunk per stage, then one Warning naming any sample program kept, and on
     * to the module before this one, or to Core's own removal.
     */
    public class RemoveStages implements SampleDataStages {
        public String name() {
            return 'ProgramsSampleData.RemoveStages';
        }

        public Integer stageCount() {
            return ProgramSampleDataLoader.removeStageCount();
        }

        public void runStage(Integer stage) {
            ProgramSampleDataLoader.removeNext();
        }

        public void finish() {
            try {
                ProgramSampleDataLoader.logWhatWasKept();
            } catch (Exception notNamed) {
                // Naming what was kept is a courtesy; the rest of the removal still runs.
                ErrorLogger.log(notNamed, name());
            }
            SampleDataModules.removeAfter(ProgramsAccessSync.MODULE_NAME);
        }
    }
}
