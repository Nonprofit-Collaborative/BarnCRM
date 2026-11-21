/**
 * The last full Health Check result, kept so BarnCRM Home can show it instead of running every
 * check on each load (ADMIN-7, ADR-0106 health-check-on-home-shows-the-last-result).
 *
 * The one place that records and reads it. A page that wants "last result plus Run now" sets
 * the panel's lastResultFirst property; nothing else needs to know how the result is kept.
 *
 * The run record is package owned bookkeeping saved through OrgSettingsSystemWriter without an
 * audit row, like the other run stamps (ADR-0021). Only a run by someone with Manage BarnCRM
 * Settings is kept, because anyone else's run skips the access checks.
 */
public with sharing class HealthCheckLastRun {
	/** What the panel shows before anyone clicks Run now. */
	public class Summary {
		/** When Health Check last ran in full, or null when it never has. */
		@AuraEnabled
		public Datetime ranAt;
		/** The counts as a sentence in the reader's language, or null when it never ran. */
		@AuraEnabled
		public String result;
		@AuraEnabled
		public Integer errors;
		@AuraEnabled
		public Integer warnings;
		@AuraEnabled
		public Integer infos;
	}

	/** Records the report's time and counts, when it ran for someone who sees every check. */
	public static void record(HealthCheckService.Report report) {
		if (report == null || report.getCanManageSettings() != true) {
			return;
		}
		List<Integer> counts = counts(report.getFindings());
		save(counts[0], counts[1], counts[2]);
	}

	/**
	 * Adds a Run Remaining Checks result to the stored one (D-208, N-07): its findings count,
	 * and the earlier run's Not Checked warning no longer does, since those checks have now run
	 * (a run that stops early again brings its own).
	 */
	public static void addRemaining(HealthCheckService.Report remaining) {
		if (remaining == null || remaining.getCanManageSettings() != true) {
			return;
		}
		Summary stored = read();
		if (stored.ranAt == null) {
			return;
		}
		List<Integer> counts = counts(remaining.getFindings());
		save(stored.errors + counts[0], Math.max(0, stored.warnings - 1) + counts[1], stored.infos + counts[2]);
	}

	/** Errors, warnings and the rest, in that order. */
	private static List<Integer> counts(List<HealthCheckService.Finding> findings) {
		List<Integer> counts = new List<Integer>{ 0, 0, 0 };
		for (HealthCheckService.Finding finding : findings) {
			if (HealthCheckService.SEVERITY_ERROR.equals(finding.getSeverity())) {
				counts[0]++;
			} else if (HealthCheckService.SEVERITY_WARNING.equals(finding.getSeverity())) {
				counts[1]++;
			} else {
				counts[2]++;
			}
		}
		return counts;
	}

	private static void save(Integer errors, Integer warnings, Integer infos) {
		OrgSettingsSystemWriter.save(
			new Map<Schema.SObjectField, Object>{
				BarnCRM_Settings__c.Health_Check_Last_Run__c => Datetime.now(),
				BarnCRM_Settings__c.Health_Check_Last_Result__c => HealthCheckResult.text(errors, warnings, infos)
			}
		);
	}

	/**
	 * The last recorded result (Core's HealthCheckResult reads it); every field is null when
	 * Health Check has never run or the stored value cannot be read, which the next run fixes.
	 */
	public static Summary read() {
		HealthCheckResult.Counts counts = HealthCheckResult.read();
		Summary summary = new Summary();
		if (counts.ranAt == null) {
			return summary;
		}
		summary.ranAt = counts.ranAt;
		summary.errors = counts.errors;
		summary.warnings = counts.warnings;
		summary.infos = counts.infos;
		summary.result = String.format(
			BarnHelp.text('Core', 'Core_HealthCheck_LastResult'),
			new List<Object>{ summary.errors, summary.warnings, summary.infos }
		);
		return summary;
	}
}
