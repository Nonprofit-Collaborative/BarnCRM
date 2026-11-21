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

	/** The last run; a value nobody can read reads as never run, and the next run writes it. */
	@NamespaceAccessible
	public static Counts read() {
		BarnCRM_Settings__c settings = SettingsService.getSettings();
		List<String> parts = String.isBlank(settings.Health_Check_Last_Result__c)
			? new List<String>()
			: settings.Health_Check_Last_Result__c.split(',');
		Counts counts = new Counts();
		if (settings.Health_Check_Last_Run__c == null || parts.size() != 3) {
			return counts;
		}
		try {
			counts.errors = Integer.valueOf(parts[0].trim());
			counts.warnings = Integer.valueOf(parts[1].trim());
			counts.infos = Integer.valueOf(parts[2].trim());
		} catch (TypeException unreadable) {
			return new Counts();
		}
		counts.ranAt = settings.Health_Check_Last_Run__c;
		return counts;
	}
}
