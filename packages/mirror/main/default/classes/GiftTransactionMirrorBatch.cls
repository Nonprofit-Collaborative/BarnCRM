/**
 * A run of the Gift Transaction mirror (feature X-07, R-GT6), as the person who started or
 * scheduled it, in chunks. It copies every gift of R-GT3 that has no Gift Transaction yet, and
 * every linked one changed since the last completed run started, or, from the reconciliation
 * page, every gift of R-GT3 dated in a range.
 *
 * Refusals are gathered across the chunks and written when the run ends, one Warning per distinct
 * reason, with a summary at Info (R-GT7).
 *
 * A run does nothing, and says so in one entry, while the mirror is unavailable (R-GT1), while its
 * paid status or start date is missing or unknown (R-GT2), while the person running it lacks the
 * access it needs, or while automation is paused or the Gift Transaction mirror is switched off on
 * the Automation page. The pause and the switch are checked again for each chunk, and so is the
 * headroom a chunk needs. A run that is not a range records when it started and its summary on
 * Mirror Settings, for the page, for Health Check, and as the point from which the next run
 * rechecks linked gifts changed since.
 */
public with sharing class GiftTransactionMirrorBatch implements Database.Batchable<SObject>, Database.Stateful {
	public static final String CLASS_NAME = 'GiftTransactionMirrorBatch';
	/** Nonprofit Cloud's own fundraising automation runs on each chunk. */
	@TestVisible
	private static final Integer CHUNK_SIZE = 100;
	public static final String LOG_CONTEXT = 'Gift Transaction mirror: run';
	// Core's constant for this severity is not namespace accessible, so its value is repeated.
	private static final String SEVERITY_INFO = 'Info';

	/**
	 * What one chunk costs at most: four reads (the linked records, the designations already
	 * there, the allocations, the time zone) and five writes (insert, update, links, clean-up,
	 * designations), with the shares of the limits left for the org's own automation.
	 */
	private static final Integer QUERIES_NEEDED = 4;
	private static final Integer DML_STATEMENTS_NEEDED = 5;
	private static final Decimal CPU_SHARE_NEEDED = 0.4;
	private static final Decimal LIMIT_SHARE_NEEDED = 0.5;

	private final Date fromDate;
	private final Date toDate;
	@TestVisible
	private final GiftTransactionMirrorService.Result totals = new GiftTransactionMirrorService.Result();
	private Datetime startedAt;
	/** Why chunks were left, when automation was paused or switched off during the run. */
	private String skipReason;
	private Boolean skippedAtStart = false;
	private String skipSeverity = SEVERITY_INFO;
	private Boolean noHeadroom = false;

	@TestVisible
	private GiftTransactionMirrorBatch(Date fromDate, Date toDate) {
		this.fromDate = fromDate;
		this.toDate = toDate;
	}

	/** Starts a run and returns its job id, or null when the mirror is off. */
	public static Id run() {
		if (!GiftTransactionMirrorService.isOn()) {
			return null;
		}
		return Database.executeBatch(new GiftTransactionMirrorBatch(null, null), CHUNK_SIZE);
	}

	/** Copies again every gift of R-GT3 dated in the range. */
	public static Id runRange(Date fromDate, Date toDate) {
		return Database.executeBatch(new GiftTransactionMirrorBatch(fromDate, toDate), CHUNK_SIZE);
	}

	/** Why a chunk must not work now, or null when it may. */
	private static String pauseReason() {
		if (AutomationControl.isPaused()) {
			return Label.Mirror_GiftTransactionMirror_RunPaused;
		}
		if (!AutomationControl.isEnabled(GiftTransactionMirrorService.AUTOMATION_NAME)) {
			return Label.Mirror_GiftTransactionMirror_RunSwitchedOff;
		}
		return null;
	}

	/** Why the run cannot copy anything at all, or null when it can. */
	private String notReadyReason() {
		if (!GiftTransactionMirrorService.isAvailable()) {
			return Label.Mirror_GiftTransactionMirror_Unavailable;
		}
		String notReady = GiftTransactionMirrorService.notReadyReason();
		if (notReady == null && !GiftTransactionMirrorService.canRun()) {
			notReady = Label.Mirror_GiftTransactionMirror_NoAccess;
		}
		return notReady == null
			? null
			: String.format(
					Label.Mirror_GiftTransactionMirror_RunNotReady,
					new List<Object>{ notReady }
			  );
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
		Datetime lastRun = Mirror_Settings__c.getOrgDefaults()?.Gift_Transaction_Mirror_Last_Run__c;
		return Database.getQueryLocatorWithBinds(
			GiftTransactionMirrorSelector.giftsToCopyQuery(fromDate != null, lastRun != null),
			new Map<String, Object>{
				'statuses' => GiftTransactionMirrorService.MIRRORED_STATUSES,
				'inKind' => GiftTransactionMirrorService.TYPE_IN_KIND,
				'startDate' => GiftTransactionMirrorService.startDate(),
				'fromDate' => fromDate,
				'toDate' => toDate,
				'since' => lastRun
			},
			AccessLevel.USER_MODE
		);
	}

	private static Database.QueryLocator nothing() {
		return Database.getQueryLocator([SELECT Id FROM Gift__c WHERE Id = NULL WITH USER_MODE]);
	}

	public void execute(Database.BatchableContext context, List<SObject> scope) {
		// The direction may have changed since the run started; a run never works against it.
		String reason = pauseReason();
		if (reason != null || !GiftTransactionMirrorService.isOn()) {
			totals.skipped += scope.size();
			skipReason = skipReason == null ? reason : skipReason;
			return;
		}
		if (!hasHeadroom(scope.size())) {
			totals.skipped += scope.size();
			noHeadroom = true;
			return;
		}
		totals.add(GiftTransactionMirrorService.copyGifts((List<Gift__c>) scope));
	}

	/**
	 * Whether this chunk still has room: a gift can cost a write, its link, a clean-up and a
	 * designation per allocation.
	 */
	@TestVisible
	private static Boolean hasHeadroom(Integer records) {
		return MirrorSync.hasHeadroom(
			QUERIES_NEEDED,
			DML_STATEMENTS_NEEDED,
			4 * records,
			CPU_SHARE_NEEDED,
			LIMIT_SHARE_NEEDED
		);
	}

	public void finish(Database.BatchableContext context) {
		if (skippedAtStart) {
			ErrorLogger.logMessage(skipReason, LOG_CONTEXT, skipSeverity);
			return;
		}
		totals.writeRefusals();
		if (noHeadroom) {
			ErrorLogger.logMessage(
				Label.Mirror_GiftTransactionMirror_LogNoHeadroom,
				LOG_CONTEXT,
				ErrorLogger.SEVERITY_WARNING
			);
		}
		String summary = summaryOf(totals);
		ErrorLogger.logMessage(
			skipReason == null ? summary : summary + ' ' + skipReason,
			LOG_CONTEXT,
			SEVERITY_INFO
		);
		// A run that left or failed a gift is not recorded, so the next run reads that gift again
		// (only gifts changed since the last recorded run are reread).
		if (fromDate == null && skipReason == null && totals.skipped == 0 && totals.failed == 0) {
			MirrorSettingsWriter.recordGiftTransactionMirrorRun(startedAt, summary);
		}
	}

	/** The run's summary line, with its designation counts (R-GT5). */
	@TestVisible
	private static String summaryOf(GiftTransactionMirrorService.Result totals) {
		String summary = String.format(
			Label.Mirror_GiftTransactionMirror_LogRun,
			new List<Object>{
				totals.created,
				totals.updated,
				totals.unchanged,
				totals.failed,
				totals.skipped,
				totals.designated,
				totals.undesignated
			}
		);
		return totals.designationsUnavailable
			? summary + ' ' + Label.Mirror_GiftTransactionMirror_DesignationsUnavailable
			: summary;
	}
}
