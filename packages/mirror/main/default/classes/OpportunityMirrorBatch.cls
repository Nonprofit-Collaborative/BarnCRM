/**
 * A run of the Opportunity mirror (feature X-01, R-OM8), in the shape `MirrorRunBatch` gives both
 * gift mirrors' runs. What it does follows the chosen direction:
 *
 * - Gifts to Opportunities: copies every gift in the totals that has no Opportunity yet, or, from
 *   the reconciliation page, every gift in the totals dated in a range (R-OM11).
 * - Opportunities to Gifts: makes a gift from every won Opportunity closed on or after the start
 *   date that no gift names (R-OM7).
 *
 * Refusals are written when the run ends, one Warning per distinct reason (R-OM6), so a nightly
 * run over a refused rule writes one entry rather than one per gift, and none per chunk. A chunk
 * is left when the direction changed since the run started.
 */
public with sharing class OpportunityMirrorBatch extends MirrorRunBatch {
	public static final String CLASS_NAME = 'OpportunityMirrorBatch';
	/** Smaller than Campaign sync's: the org's own Opportunity automation runs on each chunk. */
	@TestVisible
	private static final Integer CHUNK_SIZE = 100;
	private static final String LOG_CONTEXT = 'Opportunity mirror: run';

	private final String direction;
	private final OpportunityMirrorService.Result totals = new OpportunityMirrorService.Result();

	@TestVisible
	private OpportunityMirrorBatch(String direction, Date fromDate, Date toDate) {
		super(fromDate, toDate);
		this.direction = direction;
	}

	/** Starts a run in the chosen direction and returns its job id, or null when it is off. */
	public static Id run() {
		String direction = OpportunityMirrorService.direction();
		if (direction == OpportunityMirrorService.OFF || !OpportunityMirrorService.isAvailable()) {
			return null;
		}
		return AsyncStarter.batch(
			new OpportunityMirrorBatch(direction, null, null),
			CHUNK_SIZE,
			'OpportunityMirrorBatch'
		);
	}

	/** Copies again every gift in the totals dated in the range (Gifts to Opportunities only). */
	public static Id runRange(Date fromDate, Date toDate) {
		return AsyncStarter.batch(
			new OpportunityMirrorBatch(
				OpportunityMirrorService.GIFTS_TO_OPPORTUNITIES,
				fromDate,
				toDate
			),
			CHUNK_SIZE,
			'OpportunityMirrorBatch'
		);
	}

	protected override String automationName() {
		return OpportunityMirrorService.AUTOMATION_NAME;
	}

	protected override String logContext() {
		return LOG_CONTEXT;
	}

	protected override String pausedText() {
		return BarnHelp.text('Mirror', 'Mirror_OpportunityMirror_RunPaused');
	}

	protected override String switchedOffText() {
		return BarnHelp.text('Mirror', 'Mirror_OpportunityMirror_RunSwitchedOff');
	}

	protected override MirrorSync.Result runTotals() {
		return totals;
	}

	protected override Boolean stillOn() {
		// The direction may have changed since the run started; a run never works against it.
		return OpportunityMirrorService.direction() == direction;
	}

	private Boolean makesGifts() {
		return direction == OpportunityMirrorService.OPPORTUNITIES_TO_GIFTS;
	}

	protected override Database.QueryLocator locator() {
		if (makesGifts()) {
			return wonOpportunities();
		}
		Datetime lastRun = Mirror_Settings__c.getOrgDefaults()?.Opportunity_Mirror_Last_Run__c;
		return Database.getQueryLocatorWithBinds(
			OpportunityMirrorSelector.giftsToCopyQuery(fromDate != null, lastRun != null),
			new Map<String, Object>{
				'statuses' => OpportunityMirrorService.IN_TOTALS,
				'fromDate' => fromDate,
				'toDate' => toDate,
				'since' => lastRun
			},
			AccessLevel.USER_MODE
		);
	}

	/** Opportunities to Gifts: the won Opportunities closed on or after the start date. */
	private Database.QueryLocator wonOpportunities() {
		Date startDate = OpportunityGiftService.startDate();
		Set<Id> recordTypeIds = OpportunityGiftService.recordTypeIds();
		List<String> unknown = OpportunityGiftService.unknownRecordTypes();
		if (!unknown.isEmpty()) {
			// Once a run: a mistyped name otherwise matches nothing without a word.
			ErrorLogger.logMessage(
				String.format(
					BarnHelp.text('Mirror', 'Mirror_OpportunityMirror_UnknownRecordTypes'),
					new List<Object>{ String.join(unknown, ', ') }
				),
				LOG_CONTEXT,
				ErrorLogger.SEVERITY_WARNING
			);
		}
		if (OpportunityGiftService.listsMasterRecordType()) {
			// Master is a real name, so it is not unknown, yet it matches no Opportunity.
			ErrorLogger.logMessage(
				BarnHelp.text('Mirror', 'Mirror_OpportunityMirror_MasterRecordType'),
				LOG_CONTEXT,
				ErrorLogger.SEVERITY_WARNING
			);
		}
		if (recordTypeIds != null && recordTypeIds.isEmpty()) {
			// Nothing listed exists, and an org without record types has no field to filter.
			return nothing();
		}
		return Database.getQueryLocatorWithBinds(
			OpportunityMirrorSelector.wonOpportunitiesQuery(
				OpportunityMirrorService.opportunityType().getDescribe().getName(),
				OpportunityGiftService.opportunityFields(),
				recordTypeIds != null
			),
			// No start date, no Opportunity: a date no Opportunity closes on or after.
			new Map<String, Object>{
				'startDate' => startDate == null ? Date.newInstance(4000, 12, 31) : startDate,
				'recordTypeIds' => recordTypeIds
			},
			AccessLevel.USER_MODE
		);
	}

	protected override void work(List<SObject> scope) {
		totals.add(
			makesGifts()
				? OpportunityGiftService.makeGifts(scope)
				: OpportunityMirrorService.syncSaved((List<Gift__c>) scope)
		);
	}

	protected override String report() {
		if (makesGifts()) {
			totals.writeOpportunityRefusals();
		} else {
			totals.writeRefusals();
		}
		return String.format(
			makesGifts()
				? BarnHelp.text('Mirror', 'Mirror_OpportunityMirror_LogRunGifts')
				: BarnHelp.text('Mirror', 'Mirror_OpportunityMirror_LogRunOpportunities'),
			new List<Object>{
				totals.created,
				totals.updated,
				totals.unchanged,
				totals.failed,
				totals.skipped
			}
		);
	}

	protected override void recordRun(Datetime startedAt, String summary) {
		MirrorSettingsWriter.recordOpportunityMirrorRun(startedAt, summary);
	}
}
