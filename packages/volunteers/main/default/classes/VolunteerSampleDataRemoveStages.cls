/**
 * The Volunteers sample data removal (C-10, ADMIN-3), as the stages Core's SampleDataRemoveBatch
 * runs one per transaction. Each stage deletes one chunk through
 * VolunteerSampleDataLoader.removeNext, so the hours, shifts and jobs go before the people and
 * households they point at, which Core removes afterwards. finish() hands on to the module
 * before this one, or to Core's own removal, through SampleDataModules.removeAfter.
 *
 * Nothing is kept between stages: each one reads what is left.
 */
public with sharing class VolunteerSampleDataRemoveStages implements SampleDataStages {
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
        SampleDataModules.removeAfter(ShiftScheduleService.MODULE_NAME);
    }
}
