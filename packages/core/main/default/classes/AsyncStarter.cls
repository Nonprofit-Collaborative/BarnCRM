/**
 * The one way BarnCRM starts background work from a button or a nightly step (D-200 P9).
 *
 * Salesforce holds at most 100 batch jobs waiting in the flex queue and allows a set number of
 * queued jobs per request. Past either, starting a job throws, and past the queued job limit
 * it throws a LimitException no try can catch, so the person who pressed a button got an
 * unexpected error and nothing ran. Here every start checks first: fewer than 95 batch jobs
 * waiting, and a queued job still allowed in this request. When the org is busy, or the
 * platform refuses the start anyway, it is written to the Error Log once and the caller gets
 * a BusyException whose message tells the person to try again in a few minutes. ErrorLogger
 * skips that exception, so a caller that logs what it catches does not log it twice.
 *
 * A job that re-queues itself while it runs may keep calling the platform directly: it is
 * already inside the limits this class checks. scripts/ci/check-async-starter.py forbids any
 * other direct call outside its allowlist.
 */
@NamespaceAccessible
public with sharing class AsyncStarter {
	/** The flex queue holds 100; a few are left for Salesforce's own and other packages' jobs. */
	private static final Integer FLEX_QUEUE_ROOM = 95;

	/** Set by a test to act as if the org were busy. */
	@TestVisible
	private static Boolean busyForTest = false;

	/** Raised when background work cannot start now; the message is for the person. */
	@NamespaceAccessible
	public class BusyException extends Exception {
	}

	/**
	 * Starts a batch job, or refuses when the flex queue is nearly full.
	 * @param work the batch
	 * @param scope records per execute
	 * @param context what is starting, for the Error Log
	 * @return the job's id
	 * @throws BusyException when it cannot start now
	 */
	@NamespaceAccessible
	public static Id batch(Database.Batchable<SObject> work, Integer scope, String context) {
		if (busyForTest || flexQueueFull()) {
			throw busy(context, null);
		}
		try {
			return Database.executeBatch(work, scope);
		} catch (AsyncException refused) {
			throw busy(context, refused);
		}
	}

	/**
	 * Queues a job, or refuses when this request may queue no more.
	 * @param work the job
	 * @param context what is starting, for the Error Log
	 * @return the job's id
	 * @throws BusyException when it cannot start now
	 */
	@NamespaceAccessible
	public static Id queue(Queueable work, String context) {
		return queue(work, null, context);
	}

	/**
	 * Queues a job to start after a delay, or refuses as above.
	 * @param work the job
	 * @param delayMinutes minutes to wait, 0 to 10, or null for none
	 * @param context what is starting, for the Error Log
	 * @return the job's id
	 * @throws BusyException when it cannot start now
	 */
	@NamespaceAccessible
	public static Id queue(Queueable work, Integer delayMinutes, String context) {
		if (busyForTest || Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) {
			throw busy(context, null);
		}
		try {
			return delayMinutes == null
				? System.enqueueJob(work)
				: System.enqueueJob(work, delayMinutes);
		} catch (AsyncException refused) {
			throw busy(context, refused);
		}
	}

	private static Boolean flexQueueFull() {
		return [SELECT COUNT() FROM AsyncApexJob WHERE Status = 'Holding' WITH SYSTEM_MODE] >=
			FLEX_QUEUE_ROOM;
	}

	private static BusyException busy(String context, Exception refused) {
		String message = BarnHelp.text('Core', 'Core_AsyncStarter_Busy');
		ErrorLogger.logMessage(
			refused == null ? message : message + ' ' + refused.getMessage(),
			context,
			ErrorLogger.SEVERITY_WARNING
		);
		return new BusyException(message);
	}
}
