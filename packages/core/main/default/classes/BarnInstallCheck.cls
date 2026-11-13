/**
 * The install and upgrade test's way in (D-199, D-200): what `scripts/org/package-upgrade-test.sh`
 * and `scripts/org/seed-sample-data.sh --namespace` call from anonymous Apex in an org where
 * BarnCRM is installed as managed packages. A subscriber's anonymous Apex sees only `global`
 * code, so these three methods stand in front of the public services that do the work.
 *
 * PERMANENT SURFACE. In a managed package a `global` signature can never be removed or
 * changed once a version is promoted. Keep this class to these methods, return only platform
 * types, and add a key to the summary map rather than a parameter or a method. A method that
 * is no longer wanted is deprecated for one release (`@Deprecated`), never removed
 * (docs/contributor-guide/ci.md, "Global and namespace-accessible API").
 *
 * Each method runs for someone who may run setup (`BarnCRMPermissions.canRunSetup`): the
 * installing admin, or an admin with Customize Application before anyone holds Manage BarnCRM
 * Settings.
 */
global with sharing class BarnInstallCheck {
	/**
	 * Runs every Health Check. Returns `findings` (Integer, how many), `errors` (Integer, how
	 * many have Error severity) and `errorFindings` (List<String>, `key: title` per error).
	 */
	global static Map<String, Object> runHealthCheck() {
		requireSetupAccess();
		List<HealthCheckService.Finding> findings = HealthCheckService.run();
		List<String> errors = new List<String>();
		for (HealthCheckService.Finding finding : findings) {
			if (finding.severity == HealthCheckService.SEVERITY_ERROR) {
				errors.add(finding.key + ': ' + finding.title);
			}
		}
		return new Map<String, Object>{
			'findings' => findings.size(),
			'errors' => errors.size(),
			'errorFindings' => errors
		};
	}

	/** Starts the sample data load (SampleDataLoader.load); throws when it is already loaded. */
	global static void loadSampleData() {
		requireSetupAccess();
		SampleDataLoader.load();
	}

	/**
	 * Finish Setup for one package, as Module Manager runs it: its install's setup steps, safe
	 * to run twice, recorded in the settings change history.
	 *
	 * @param packageKey the package key, such as Core or Giving
	 * @return the names shown of the packages whose steps ran
	 */
	global static List<String> finishSetup(String packageKey) {
		requireSetupAccess();
		List<String> done = ModuleSetups.finish(new List<String>{ packageKey });
		SettingsService.logChange(
			System.Label.Core_ModuleSetup_FinishButton,
			'',
			String.join(done, ', ')
		);
		return done;
	}

	private static void requireSetupAccess() {
		if (!BarnCRMPermissions.canRunSetup()) {
			throw new ModuleManagerService.ModuleManagerException(
				BarnHelp.text('Core', 'Core_Settings_PermissionRequiredError')
			);
		}
	}
}
