/**
 * The Volunteers half of the C-10 sample data set: Core finds this class by name
 * (`SampleDataModules.MODULE_CLASS_NAMES`), so the same Load Sample Data action in BarnCRM
 * Settings fills an org that has Volunteers with jobs, a recurring schedule, shifts, sign-ups,
 * hours in each status, skills and requirements, and the same Remove Sample Data action takes
 * them away again (ADR-0017, SampleDataModule).
 *
 * No letter is generated: a letter is a file, and the shipped Hours letter template can be used
 * on any sample volunteer once the load has finished. See docs/admin-guide/sample-data.md.
 *
 * `@NamespaceAccessible`, public, with a public no-argument constructor, because Core resolves it
 * with `Type.forName` under ADR-0017.
 */
@NamespaceAccessible
public with sharing class VolunteersSampleData implements SampleDataModule {
    @NamespaceAccessible
    public VolunteersSampleData() {
        // Built by name from Core (SampleDataModules), so it needs a public constructor.
    }

    public String moduleName() {
        return ShiftScheduleService.MODULE_NAME;
    }

    public String countLabel() {
        return System.Label.Volunteers_SampleData_CountLabel;
    }

    /** The number the status card shows for Volunteers: sample hours entries. */
    public Integer countLoaded() {
        return new VolunteerSampleDataSelector().countSampleHours();
    }

    /**
     * Whether a sample job or skill is still here, including those removal kept because real
     * records point at them; every other sample record hangs off one or off a sample person.
     * While one is, Core keeps Remove sample data offered so the admin can finish.
     */
    public Boolean hasSampleRecords() {
        return new VolunteerSampleDataSelector().hasSampleJobsOrSkills();
    }

    /** Starts the Volunteers load, after Core's people and households exist. */
    public void enqueueLoad() {
        SampleDataStageBatch.start(new LoadStages());
    }

    /** Starts the Volunteers removal, before Core removes the people the records point at. */
    public void enqueueRemove() {
        SampleDataRemoveBatch.startRemoval(new RemoveStages());
    }

    /**
     * The Volunteers sample data load (C-10), as the stages Core's SampleDataStageBatch runs one per
     * transaction: stage 0 the skills, jobs, schedule and shifts; stage 1 the sign-ups, hours,
     * skills and requirements of Core's sample people; stage 2 the hours' statuses, set with the
     * approval verbs once the hours exist. finish() hands on to the module after Volunteers, or ends
     * the load. Nothing is kept between stages: each one reads what it needs.
     */
    public with sharing class LoadStages implements SampleDataStages {
        public String name() {
            return 'VolunteerSampleDataStages';
        }

        public Integer stageCount() {
            return 3;
        }

        public void runStage(Integer stage) {
            if (stage == 0) {
                VolunteerSampleDataLoader.loadJobs();
            } else if (stage == 1) {
                VolunteerSampleDataLoader.loadPeople();
            } else {
                VolunteerSampleDataLoader.decideHours();
            }
        }

        public void finish() {
            SampleDataModules.startAfter(ShiftScheduleService.MODULE_NAME);
        }
    }

    /**
     * The Volunteers sample data removal (C-10, ADMIN-3), as the stages Core's SampleDataRemoveBatch
     * runs one per transaction. Each stage deletes one chunk through
     * VolunteerSampleDataLoader.removeNext, so the hours, shifts and jobs go before the people and
     * households they point at, which Core removes afterwards. finish() logs one Warning naming the
     * sample records real records kept, then hands on to the module before this one, or to Core's
     * own removal, through SampleDataModules.removeAfter, so a kept record never stops the rest.
     *
     * Nothing is kept between stages: each one reads what is left.
     */
    public with sharing class RemoveStages implements SampleDataStages {
        public String name() {
            return 'VolunteerSampleDataRemoveStages';
        }

        public Integer stageCount() {
            return VolunteerSampleDataLoader.removeStageCount();
        }

        public void runStage(Integer stage) {
            VolunteerSampleDataLoader.removeNext();
        }

        public void finish() {
            try {
                VolunteerSampleDataLoader.logWhatWasKept();
            } catch (Exception notNamed) {
                // Naming what was kept is a courtesy; the rest of the removal still runs.
                ErrorLogger.log(notNamed, name());
            }
            SampleDataModules.removeAfter(ShiftScheduleService.MODULE_NAME);
        }
    }
}
