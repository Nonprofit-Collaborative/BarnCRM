/**
 * The class Core finds by name (in `HealthCheckExtensions.EXTENSION_CLASSES`) and calls to add
 * Mirror's findings to the one Health Check report (ADR-0057).
 *
 * Mirror's finding is the household drift report (MIG-02b): Accounts whose Household Model and
 * Nonprofit Cloud household group disagree. The gift mirrors' findings (a scheduled run that has
 * not completed) are BarnCRM Fundraising's (`GiftMirrorHealthChecks`), so Mirror installs with
 * Core alone (N-09, ADR-NEXT mirror independence).
 *
 * `@NamespaceAccessible` for the reason `GivingHealthCheckExtension` is: Core resolves it with
 * `Type.forName` under ADR-0017.
 */
@NamespaceAccessible
public with sharing class MirrorHealthCheckExtension implements HealthCheckExtension {
	public static final String HOUSEHOLD_DRIFT_KEY = 'household_model_drift';

	@NamespaceAccessible
	public MirrorHealthCheckExtension() {
		return;
	}

	public List<HealthCheckService.Finding> findings() {
		List<HealthCheckService.Finding> found = new List<HealthCheckService.Finding>();
		HealthCheckService.Finding drift = householdDrift();
		if (drift != null) {
			found.add(drift);
		}
		return found;
	}

	/**
	 * The household drift report (MIG-02b, ADR-0217 `0217-npc-household-conversion.md` decision
	 * 8): Accounts whose Household Model and native household group disagree, counted and the
	 * first ten named. A warning that changes nothing; a failed read is reported as such.
	 */
	private static HealthCheckService.Finding householdDrift() {
		if (!HealthCheckService.canManageSettings()) {
			return null;
		}
		try {
			NpcHouseholdSource.Drift drift = NpcHouseholdSource.drift(10);
			return drift.count == 0
				? null
				: new HealthCheckService.Finding(
						HOUSEHOLD_DRIFT_KEY,
						BarnHelp.text('Mirror', 'Mirror_HealthCheck_HouseholdDriftTitle'),
						BarnHelp.text(
							'Mirror',
							'Mirror_HealthCheck_HouseholdDriftDetail',
							new List<Object>{ drift.count, String.join(drift.names, ', ') }
						),
						HealthCheckService.SEVERITY_WARNING,
						HealthCheckService.CATEGORY_SETTINGS
				  );
		} catch (Exception e) {
			return HealthCheckService.checkFailed(HOUSEHOLD_DRIFT_KEY, e);
		}
	}
}
