/**
 * What a run of the Opportunity mirror (X-01, R-OM8) and of the Gift Transaction mirror (X-07,
 * R-GT6) share (D-200 S5): a run as the person who started or scheduled it, in chunks, that does
 * nothing and says so in one entry while automation is paused, the mirror is switched off on the
 * Automation page, or the mirror says it is not ready. The pause and the switch are checked again
 * for each chunk. Refusals are gathered across the chunks and written when the run ends, with a
 * summary at Info, and a run that is not a range records when it started and its summary on
 * Mirror Settings, as the point from which the next run rechecks linked gifts changed since.
 */
public abstract with sharing class MirrorRunBatch implements Database.Batchable<SObject>, Database.Stateful {
	// Core's constant for this severity is not namespace accessible, so its value is repeated.
	private static final String SEVERITY_INFO = 'Info';

	protected final Date fromDate;
	protected final Date toDate;
	private Datetime startedAt;
	/** Why chunks were left, when automation was paused or switched off during the run. */
	private String skipReason;
	private Boolean skippedAtStart = false;
	private String skipSeverity = SEVERITY_INFO;

	protected MirrorRunBatch(Date fromDate, Date toDate) {
		this.fromDate = fromDate;
		this.toDate = toDate;
	}

	// ------------------------------------------------------------------- what each mirror says

	/** The mirror's switch on the Automation page. */
	protected abstract String automationName();
	/** The Error Log context of the run. */
	protected abstract String logContext();
	/** The words for a run left because automation is paused. */
	protected abstract String pausedText();
	/** The words for a run left because the mirror is switched off on the Automation page. */
	protected abstract String switchedOffText();
	/** Why the run cannot copy anything at all, logged as a Warning, or null when it can. */
	protected virtual String notReadyReason() {
		return null;
	}
	/** What the run reads. */
	protected abstract Database.QueryLocator locator();
	/** Whether the mirror still works the way the run started, checked for each chunk. */
	protected abstract Boolean stillOn();
	/** The run's totals across the chunks. */
	protected abstract MirrorSync.Result runTotals();
	/** One chunk's work, added to the totals. */
	protected abstract void work(List<SObject> scope);
	/** Writes the refusals and any Warnings of the run, and returns its summary. */
	protected abstract String report();
	/** Whether a finished run that is not a range is recorded. */
	protected virtual Boolean recorded() {
		return true;
	}
	/** Records the run on Mirror Settings. */
	protected abstract void recordRun(Datetime startedAt, String summary);

	// ------------------------------------------------------------------------------- the run

	/** Why a chunk must not work now, or null when it may. */
	private String pauseReason() {
		if (AutomationControl.isPaused()) {
			return pausedText();
		}
		if (!AutomationControl.isEnabled(automationName())) {
			return switchedOffText();
		}
		return null;
	}

	public Database.QueryLocator start(Database.BatchableContext context) {
		startedAt = System.now();
		skipReason = pauseReason();
		if (skipReason == null) {
			skipReason = notReadyReason();
			skipSeverity = skipReason == null ? SEVERITY_INFO : ErrorLogger.SEVERITY_WARNING;
		}
		if (skipReason != null) {
			skippedAtStart = true;
			return nothing();
		}
		return locator();
	}

	/** A locator that reads nothing. */
	protected Database.QueryLocator nothing() {
		return Database.getQueryLocator([SELECT Id FROM Gift__c WHERE Id = NULL WITH USER_MODE]);
	}

	public void execute(Database.BatchableContext context, List<SObject> scope) {
		String reason = pauseReason();
		if (reason != null || !stillOn()) {
			runTotals().skipped += scope.size();
			skipReason = skipReason == null ? reason : skipReason;
			return;
		}
		work(scope);
	}

	public void finish(Database.BatchableContext context) {
		if (skippedAtStart) {
			ErrorLogger.logMessage(skipReason, logContext(), skipSeverity);
			return;
		}
		String summary = report();
		ErrorLogger.logMessage(
			skipReason == null ? summary : summary + ' ' + skipReason,
			logContext(),
			SEVERITY_INFO
		);
		if (fromDate == null && skipReason == null && recorded()) {
			recordRun(startedAt, summary);
		}
	}
}
