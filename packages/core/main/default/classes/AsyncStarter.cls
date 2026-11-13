/**
 * The one way BarnCRM starts background work from a button or a nightly step (D-200 P9).
 *
 * Salesforce holds at most 100 batch jobs waiting in the flex queue and allows a set number of
 * queued jobs per request. Past either, starting a job throws, and past the queued job limit
 * it throws a LimitException no try can catch, so the person who pressed a button got an
 * unexpected error and nothing ran. Here every start checks first: fewer than 95 batch jobs
 * waiting, and a queued job still allowed in this request. When the org is busy, or the
 * platform refuses the start anyway for want of room, it is written to the Error Log once and
 * the caller gets a BusyException whose message tells the person to try again in a few
 * minutes. ErrorLogger skips that exception, so a caller that logs what it catches does not
 * log it twice. Any other refusal (a start from a batch execute or a future method) is logged
 * as an Error with the platform's message and rethrown as it is.
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

	/** Set by a test: the refusal the platform gives instead of starting the work. */
	@TestVisible
	private static AsyncException refusalForTest;

	/**
	 * Words in a refusal that mean the org has no room now (the flex queue, a queued job or
	 * concurrency limit). Any other refusal, such as starting a batch from a batch execute or a
	 * future method, is a fault in the code, not a busy org.
	 */
	private static final List<String> CAPACITY_WORDS = new List<String>{
		'limit',
		'too many',
		'flex queue',
		'maximum',
		'concurrent'
	};

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
			if (refusalForTest != null) {
				throw refusalForTest;
			}
			return Database.executeBatch(work, scope);
		} catch (AsyncException refused) {
			throw refusal(context, refused);
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
			if (refusalForTest != null) {
				throw refusalForTest;
			}
			return delayMinutes == null
				? System.enqueueJob(work)
				: System.enqueueJob(work, delayMinutes);
		} catch (AsyncException refused) {
			throw refusal(context, refused);
		}
	}

	/**
	 * What a refusal from the platform becomes: the busy message when the org has no room now,
	 * or, for any other refusal (above all starting a batch from a batch execute or a future
	 * method, which Salesforce never allows), the platform's own exception, written to the
	 * Error Log as an Error with its real message, so the fault is not mistaken for a busy org.
	 * A batch's finish may start the next job, so inside a batch or a future method a refusal
	 * is busy only when it names a limit; System.isBatch() cannot tell finish from execute, so
	 * the refusal's own words decide in every context.
	 */
	private static Exception refusal(String context, AsyncException refused) {
		if (isCapacity(refused)) {
			return busy(context, refused);
		}
		ErrorLogger.logMessage(refused.getMessage(), context, ErrorLogger.SEVERITY_ERROR);
		return refused;
	}

	@TestVisible
	private static Boolean isCapacity(AsyncException refused) {
		String message = refused.getMessage() == null ? '' : refused.getMessage().toLowerCase();
		for (String word : CAPACITY_WORDS) {
			if (message.contains(word)) {
				return true;
			}
		}
		return false;
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
