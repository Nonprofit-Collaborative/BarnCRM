/**
 * The healthCheckPanel component's entry point (feature C-11).
 *
 * Reading the report needs no permission: anyone who can open the BarnCRM app can look at
 * it and tell an administrator what it says. Acting on a finding needs the
 * Manage_BarnCRM_Settings custom permission, checked here rather than trusted from the
 * component. A fix itself runs in Core's `HealthCheckFixes`, which a module's tests call to press
 * a fix the module owns (ADR-0125 `0125-rollup-builder-module.md`).
 */
@NamespaceAccessible
public with sharing class HealthCheckController {
	/**
	 * The whole report: findings, org shape, current and recommended mode.
	 */
	@AuraEnabled
	public static HealthCheckService.Report getReport() {
		try {
			return HealthCheckRunner.buildReport();
		} catch (Exception e) {
			throw loadFailed(e);
		}
	}

	/**
	 * Run Remaining Checks: only the checks an earlier run left when it stopped early to stay
	 * inside the limits (D-208, N-07). Reading needs no permission, as with the whole report.
	 */
	@AuraEnabled
	public static HealthCheckService.Report runRemaining(List<String> checkKeys) {
		try {
			return HealthCheckRunner.buildRemainingReport(checkKeys);
		} catch (Exception e) {
			throw loadFailed(e);
		}
	}

	/**
	 * When Health Check last ran in full and how many findings it had, without running it
	 * (ADMIN-7). The panel shows this first where its lastResultFirst property is set.
	 */
	@AuraEnabled
	public static HealthCheckLastRun.Summary getLastRun() {
		try {
			return HealthCheckLastRun.read();
		} catch (Exception e) {
			throw loadFailed(e);
		}
	}

	/**
	 * Take the recommendation: set the coexistence mode detection proposes, and return the
	 * re-run report so the panel shows the result of what it just did.
	 */
	@AuraEnabled
	public static HealthCheckService.Report applyRecommendedMode() {
		requireManageSettings();
		try {
			CoexistenceService.applyMode(OrgShapeDetector.recommendedCoexistenceMode());
			return HealthCheckRunner.buildReport();
		} catch (Exception e) {
			throw fixFailed(e, e instanceof CoexistenceService.CoexistenceException);
		}
	}

	/**
	 * Move household membership to the junction, which is what a Person Accounts org needs.
	 */
	@AuraEnabled
	public static HealthCheckService.Report applyJunctionMembership() {
		requireManageSettings();
		try {
			CoexistenceService.applyJunctionMembership();
			return HealthCheckRunner.buildReport();
		} catch (Exception e) {
			throw fixFailed(e, e instanceof CoexistenceService.CoexistenceException);
		}
	}

	/**
	 * Turn automatic household creation on, which is what the org needs when household
	 * membership is on the junction and no new person is getting a household (ADR-0037).
	 */
	@AuraEnabled
	public static HealthCheckService.Report enableAutomaticHouseholds() {
		requireManageSettings();
		try {
			HouseholdService.enableAutomaticHouseholds();
			return HealthCheckRunner.buildReport();
		} catch (Exception e) {
			throw fixFailed(e, false);
		}
	}

	/**
	 * Run one of the fixes ADR-0048 allows, by its key (`HealthCheckFixes`, in Core), and return
	 * the re-run report with a sentence saying what the fix did.
	 *
	 * @param fixKey which fix, one of the FIX_KEY constants on HealthCheckService
	 * @param expectedScope the fix scope the confirmed finding carried
	 */
	@AuraEnabled
	public static HealthCheckService.Report applyFix(String fixKey, List<String> expectedScope) {
		String outcome = HealthCheckFixes.apply(fixKey, expectedScope);
		try {
			HealthCheckService.Report report = HealthCheckRunner.buildReport();
			report.fixOutcome = outcome;
			return report;
		} catch (Exception e) {
			throw loadFailed(e);
		}
	}

	/** The error a failed load shows: logged, and replaced by the load failure text. */
	private static AuraHandledException loadFailed(Exception caught) {
		return UserErrors.wrap(
			caught,
			false,
			System.Label.Core_HealthCheck_Title,
			BarnHelp.text('Core', 'Core_HealthCheck_LoadFailed')
		);
	}

	private static AuraHandledException fixFailed(Exception caught, Boolean shown) {
		return HealthCheckFixes.failed(caught, shown);
	}

	private static void requireManageSettings() {
		HealthCheckFixes.requireManageSettings();
	}
}
