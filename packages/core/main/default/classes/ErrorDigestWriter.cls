/**
 * Records what an error digest run did, on the org's run-state rows (C-23, SettingsState).
 *
 * DOCUMENTED EXCEPTION to the user-mode DML rule (plan Section 7.2), of the kind ADR-0027 added
 * under ADR-0021: a scheduled job's record of its own run. The digest runs as whoever scheduled
 * it, and a protected custom setting takes no field permissions, so no user-mode write can be
 * relied on. The permission gate is where the job starts: `ErrorDigestController` requires
 * `Manage_BarnCRM_Settings` before scheduling the job or sending a digest now.
 *
 * The conditions of ADR-0021 that still apply are met: only three package owned keys are
 * written, every value is produced by `ErrorDigestService` about its own run (two times and one
 * sentence built from labels and counts), and nothing else is elevated. The Setting Change
 * audit is not written for these: they are the job's run record, like the seasonal swap's, not
 * a setting anybody changed.
 */
@NamespaceAccessible
public without sharing class ErrorDigestWriter {
	public static void recordRun(Datetime ranAt, String summary, Datetime coveredUntil) {
		// Run state, not settings: kept on state rows (ADR-NEXT settings as custom metadata).
		SettingsState.put(
			new Map<String, Object>{
				LAST_RUN => ranAt,
				LAST_SUMMARY => summary == null ? null : summary.left(255),
				COVERED_UNTIL => coveredUntil
			}
		);
	}

	/** The state key of the last run, which Org Optimizer's Health Check reads. */
	@NamespaceAccessible
	public static final String LAST_RUN = 'Error_Digest_Last_Run__c';
	public static final String LAST_SUMMARY = 'Error_Digest_Last_Run_Summary__c';
	public static final String COVERED_UNTIL = 'Error_Digest_Covered_Until__c';
}
