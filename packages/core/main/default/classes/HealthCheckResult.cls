/**
 * The stored last Health Check result (ADR-0106): when it ran and its counts, kept in two
 * settings keys as "errors,warnings,infos". The one owner of that format: the Org Optimizer
 * module writes it through `text` and reads it through `read`, as BarnCRM Home does.
 */
@NamespaceAccessible
public with sharing class HealthCheckResult {
	/** When it last ran in full and its counts; all null when it never ran or cannot be read. */
	@NamespaceAccessible
	public class Counts {
		@NamespaceAccessible
		public Datetime ranAt;
		@NamespaceAccessible
		public Integer errors;
		@NamespaceAccessible
		public Integer warnings;
		@NamespaceAccessible
		public Integer infos;
	}

	/** The stored counts as kept in `Health_Check_Last_Result__c`. */
	@NamespaceAccessible
	public static String text(Integer errors, Integer warnings, Integer infos) {
		return errors + ',' + warnings + ',' + infos;
	}

	private static final String LAST_RUN = 'Health_Check_Last_Run__c';
	private static final String LAST_RESULT = 'Health_Check_Last_Result__c';

	/** Records a run's counts as run state (ADR-0238 settings as custom metadata). */
	@NamespaceAccessible
	public static void write(Integer errors, Integer warnings, Integer infos) {
		SettingsState.put(
			new Map<String, Object>{ LAST_RUN => Datetime.now(), LAST_RESULT => text(errors, warnings, infos) }
		);
	}

	/** The last run; a value nobody can read reads as never run, and the next run writes it. */
	@NamespaceAccessible
	public static Counts read() {
		String result = SettingsState.text(LAST_RESULT);
		Datetime ranAt = SettingsState.moment(LAST_RUN);
		List<String> parts = String.isBlank(result) ? new List<String>() : result.split(',');
		Counts counts = new Counts();
		if (ranAt == null || parts.size() != 3) {
			return counts;
		}
		try {
			counts.errors = Integer.valueOf(parts[0].trim());
			counts.warnings = Integer.valueOf(parts[1].trim());
			counts.infos = Integer.valueOf(parts[2].trim());
		} catch (TypeException unreadable) {
			return new Counts();
		}
		counts.ranAt = ranAt;
		return counts;
	}
}
