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

    /** Starts the Volunteers load, after Core's people and households exist. */
    public void enqueueLoad() {
        SampleDataStageBatch.start(new VolunteerSampleDataStages());
    }

    /** Starts the Volunteers removal, before Core removes the people the records point at. */
    public void enqueueRemove() {
        SampleDataRemoveBatch.startRemoval(new VolunteerSampleDataRemoveStages());
    }
}
