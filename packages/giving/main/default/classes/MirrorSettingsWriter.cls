/**
 * The last completed run and its summary of the Opportunity mirror (R-OM8, ADR-0038 point 4) and
 * of the Gift Transaction mirror (R-GT6), read by each mirror's page and by Health Check. Run
 * state, not settings (`GivingState`): written synchronously in system mode, so a direction or
 * start date saved meanwhile is never touched. The caller carries the authorization (a run it
 * started); this class adds no permission of its own.
 */
public with sharing class MirrorSettingsWriter {
	public static void recordOpportunityMirrorRun(Datetime ranAt, String summary) {
		GivingState.recordRun(
			GivingState.OPPORTUNITY_MIRROR_LAST_RUN,
			GivingState.OPPORTUNITY_MIRROR_SUMMARY,
			ranAt,
			summary
		);
	}

	/** The Gift Transaction mirror's last completed run and its summary (X-07, R-GT6). */
	public static void recordGiftTransactionMirrorRun(Datetime ranAt, String summary) {
		GivingState.recordRun(
			GivingState.GIFT_TRANSACTION_MIRROR_LAST_RUN,
			GivingState.GIFT_TRANSACTION_MIRROR_SUMMARY,
			ranAt,
			summary
		);
	}
}
