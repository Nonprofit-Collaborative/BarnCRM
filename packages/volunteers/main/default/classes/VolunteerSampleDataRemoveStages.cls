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
        try {
            VolunteerSampleDataLoader.logWhatWasKept();
        } catch (Exception notNamed) {
            // Naming what was kept is a courtesy; the rest of the removal still runs.
            ErrorLogger.log(notNamed, name());
        }
        SampleDataModules.removeAfter(ShiftScheduleService.MODULE_NAME);
    }
}
