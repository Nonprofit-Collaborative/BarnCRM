/**
 * The class Core finds by name (in `NightlyJobs.PROVIDER_CLASSES`) to have the Volunteers
 * nightly job counted and scheduled by Health Check's "Schedule all nightly jobs" fix (ADR-0075,
 * ADR-0128): the run that keeps recurring schedules' shifts created to the horizon.
 */
@NamespaceAccessible
public with sharing class VolunteersNightlyJobProvider implements NightlyJobProvider {
    @NamespaceAccessible
    public VolunteersNightlyJobProvider() {
        // Built by name from Core (NightlyJobs), so it needs a public constructor.
    }

    public List<NightlyJob> nightlyJobs() {
        return new List<NightlyJob>{ new ScheduleJob() };
    }

    /** The nightly shift schedule run (`VolunteersScheduler`). */
    @NamespaceAccessible
    public class ScheduleJob implements NightlyJob {
        public String label() {
            return System.Label.Volunteers_NightlyJobs_SchedulesName;
        }

        public Boolean isScheduled() {
            return VolunteersScheduler.isScheduled();
        }

        public void schedule() {
            VolunteersScheduler.start();
        }
    }
}
