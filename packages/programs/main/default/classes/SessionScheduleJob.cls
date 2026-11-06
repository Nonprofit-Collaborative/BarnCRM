/**
 * The run a session schedule's save queues (R-SS3), so its sessions appear without waiting for
 * the nightly run. Up to a batch chunk of schedules runs here; a larger save (an import, a bulk
 * edit) hands its schedules to `SessionScheduleBatch`. Queuing never fails a save: with no
 * queueable job left, or Programs turned off, the nightly run creates the sessions instead.
 */
public with sharing class SessionScheduleJob implements Queueable {
	private static final String LOG_CONTEXT = 'SessionScheduleJob';

	private final Set<Id> scheduleIds;

	public SessionScheduleJob(Set<Id> scheduleIds) {
		this.scheduleIds = scheduleIds;
	}

	/** Queues one run for these schedules, when there are any and a job can still be queued. */
	public static void queue(Set<Id> scheduleIds) {
		if (
			scheduleIds.isEmpty() ||
			SessionScheduleService.isTurnedOff() ||
			Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()
		) {
			return;
		}
		try {
			System.enqueueJob(new SessionScheduleJob(new Set<Id>(scheduleIds)));
		} catch (Exception notQueued) {
			ErrorLogger.log(notQueued, LOG_CONTEXT);
		}
	}

	public void execute(QueueableContext context) {
		try {
			if (scheduleIds.size() <= SessionScheduleBatch.CHUNK_SIZE) {
				SessionScheduleService.run(scheduleIds);
			} else {
				Database.executeBatch(
					new SessionScheduleBatch(scheduleIds),
					SessionScheduleBatch.CHUNK_SIZE
				);
			}
		} catch (Exception runFailure) {
			// The nightly run tries these schedules again.
			ErrorLogger.log(runFailure, LOG_CONTEXT);
		}
	}
}
