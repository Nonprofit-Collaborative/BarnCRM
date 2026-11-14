/**
 * A run of the Gift Transaction mirror (feature X-07, R-GT6), in the shape `MirrorRunBatch` gives
 * both gift mirrors' runs. It copies every gift of R-GT3 that has no Gift Transaction yet, and
 * every linked one changed since the last completed run started, or, from the reconciliation
 * page, every gift of R-GT3 dated in a range. Refusals are written when the run ends (R-GT7).
 *
 * Besides a pause or the switch, a run does nothing, and says so in one Warning, while the mirror
 * is unavailable (R-GT1), while its paid status or start date is missing or unknown (R-GT2), or
 * while the person running it lacks the access it needs. Each chunk also checks the headroom it
 * needs. A run that left or failed a gift is not recorded.
 */
public with sharing class GiftTransactionMirrorBatch extends MirrorRunBatch {
	public static final String CLASS_NAME = 'GiftTransactionMirrorBatch';
	/** Nonprofit Cloud's own fundraising automation runs on each chunk. */
	@TestVisible
	private static final Integer CHUNK_SIZE = 100;
	public static final String LOG_CONTEXT = 'Gift Transaction mirror: run';

	/**
	 * What one chunk costs at most: four reads (the linked records, the designations already
	 * there, the allocations, the time zone) and five writes (insert, update, links, clean-up,
	 * designations), with the shares of the limits left for the org's own automation.
	 */
	private static final Integer QUERIES_NEEDED = 4;
	private static final Integer DML_STATEMENTS_NEEDED = 5;
	private static final Decimal CPU_SHARE_NEEDED = 0.4;
	private static final Decimal LIMIT_SHARE_NEEDED = 0.5;

	@TestVisible
	private final GiftTransactionMirrorService.Result totals = new GiftTransactionMirrorService.Result();
	private Boolean noHeadroom = false;

	@TestVisible
	private GiftTransactionMirrorBatch(Date fromDate, Date toDate) {
		super(fromDate, toDate);
	}

	/** Starts a run and returns its job id, or null when the mirror is off. */
	public static Id run() {
		if (!GiftTransactionMirrorService.isOn()) {
			return null;
		}
		return AsyncStarter.batch(
			new GiftTransactionMirrorBatch(null, null),
			CHUNK_SIZE,
			'GiftTransactionMirrorBatch'
		);
	}

	/** Copies again every gift of R-GT3 dated in the range. */
	public static Id runRange(Date fromDate, Date toDate) {
		return AsyncStarter.batch(
			new GiftTransactionMirrorBatch(fromDate, toDate),
			CHUNK_SIZE,
			'GiftTransactionMirrorBatch'
		);
	}

	protected override String automationName() {
		return GiftTransactionMirrorService.AUTOMATION_NAME;
	}

	protected override String logContext() {
		return LOG_CONTEXT;
	}

	protected override String pausedText() {
		return BarnHelp.text('Mirror', 'Mirror_GiftTransactionMirror_RunPaused');
	}

	protected override String switchedOffText() {
		return BarnHelp.text('Mirror', 'Mirror_GiftTransactionMirror_RunSwitchedOff');
	}

	protected override MirrorSync.Result runTotals() {
		return totals;
	}

	protected override Boolean stillOn() {
		return GiftTransactionMirrorService.isOn();
	}

	protected override String notReadyReason() {
		if (!GiftTransactionMirrorService.isAvailable()) {
			return BarnHelp.text('Mirror', 'Mirror_GiftTransactionMirror_Unavailable');
		}
		String notReady = GiftTransactionMirrorService.notReadyReason();
		if (notReady == null && !GiftTransactionMirrorService.canRun()) {
			notReady = BarnHelp.text('Mirror', 'Mirror_GiftTransactionMirror_NoAccess');
		}
		return notReady == null
			? null
			: String.format(
					BarnHelp.text('Mirror', 'Mirror_GiftTransactionMirror_RunNotReady'),
					new List<Object>{ notReady }
			  );
	}

	protected override Database.QueryLocator locator() {
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

	protected override void work(List<SObject> scope) {
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

	protected override String report() {
		totals.writeRefusals();
		if (noHeadroom) {
			ErrorLogger.logMessage(
				BarnHelp.text('Mirror', 'Mirror_GiftTransactionMirror_LogNoHeadroom'),
				LOG_CONTEXT,
				ErrorLogger.SEVERITY_WARNING
			);
		}
		return summaryOf(totals);
	}

	/**
	 * A run that left or failed a gift is not recorded, so the next run reads that gift again
	 * (only gifts changed since the last recorded run are reread).
	 */
	protected override Boolean recorded() {
		return totals.skipped == 0 && totals.failed == 0;
	}

	protected override void recordRun(Datetime startedAt, String summary) {
		MirrorSettingsWriter.recordGiftTransactionMirrorRun(startedAt, summary);
	}

	/** The run's summary line, with its designation counts (R-GT5). */
	@TestVisible
	private static String summaryOf(GiftTransactionMirrorService.Result totals) {
		String summary = String.format(
			BarnHelp.text('Mirror', 'Mirror_GiftTransactionMirror_LogRun'),
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
			? summary +
			  ' ' +
			  BarnHelp.text('Mirror', 'Mirror_GiftTransactionMirror_DesignationsUnavailable')
			: summary;
	}
}
