/**
 * The Volunteers sample data load (C-10), as the stages Core's SampleDataStageBatch runs one per
 * transaction: stage 0 the skills, jobs, schedule and shifts; stage 1 the sign-ups, hours,
 * skills and requirements of Core's sample people; stage 2 the hours' statuses, set with the
 * approval verbs once the hours exist. finish() hands on to the module after Volunteers, or ends
 * the load. Nothing is kept between stages: each one reads what it needs.
 */
public with sharing class VolunteerSampleDataStages implements SampleDataStages {
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
