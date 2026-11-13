/**
 * The class Core finds by name (registered in its catalog row) to add the Volunteers steps to
 * the one nightly run (ADR-0166 nightly-job-dispatcher, ADR-0128): the run that keeps recurring
 * schedules' shifts created to the horizon, the morning shift reminders and nudges, and the
 * thank-you tasks (V-13).
 */
@NamespaceAccessible
public with sharing class VolunteersNightlyJobProvider implements NightlyStepProvider {
	@NamespaceAccessible
	public VolunteersNightlyJobProvider() {
		// Built by name from Core (NightlyJobs), so it needs a public constructor.
	}

	public List<NightlyStep> nightlySteps() {
		return new List<NightlyStep>{
			VolunteersScheduler.step(),
			VolunteerReminderScheduler.step(),
			VolunteerNudgeScheduler.step(),
			VolunteerRecognitionScheduler.step()
		};
	}
}
