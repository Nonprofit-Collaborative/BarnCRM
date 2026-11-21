/**
 * Runs one Health Check fix by its key (C-21, ADR-0048, ADR-0125): Core's own fixes and any
 * module's, through `HealthCheckFixExtension`. It stays in Core with the vocabulary
 * (`HealthCheckService`) so a module's fix, and the module's tests that press it, work without
 * the Org Optimizer module, which holds the panel and its controller (ADR-0233
 * `0233-org-optimizer-and-sample-data-modules.md`). The controller runs a fix here, then the
 * whole report again.
 *
 * The panel sends back the fix scope of the finding the administrator confirmed. The fix runs
 * only when what it would change now is exactly that: otherwise something changed since Health
 * Check last ran, and the fix is refused with a sentence rather than creating something she has
 * not read (ADR-0048 condition 5). Everything runs inside one savepoint, so a failure leaves the
 * org as it was, and a fix that ran is recorded in the settings change history like any other
 * change made on the console. Acting on a finding needs Manage BarnCRM Settings, checked here.
 */
@NamespaceAccessible
public with sharing class HealthCheckFixes {
	/** What a fix is recorded under in the settings change history, before its button label. */
	private static final String CHANGE_PREFIX = 'Health Check: ';

	/** Set by a test to make a fix fail after it has written, so the rollback can be seen. */
	private static Boolean failAfterFix = false;

	/**
	 * Has the next fix fail after it has written, for a test that shows the rollback, including
	 * a module's test where `@TestVisible` does not reach. Does nothing outside a test.
	 */
	@NamespaceAccessible
	public static void failAfterFixForTest(Boolean fail) {
		if (Test.isRunningTest()) {
			failAfterFix = fail;
		}
	}

	/**
	 * Runs the fix and returns the sentence that says what it did.
	 *
	 * @param fixKey which fix, one of the FIX_KEY constants on HealthCheckService or a module's
	 * @param expectedScope the fix scope the confirmed finding carried
	 */
	@NamespaceAccessible
	public static String apply(String fixKey, List<String> expectedScope) {
		requireManageSettings();
		String fixLabel = fixLabel(fixKey);
		if (fixLabel == null) {
			throw UserErrors.message(BarnHelp.text('Core', 'Core_HealthCheck_FixUnknown'));
		}
		Savepoint beforeFix = Database.setSavepoint();
		try {
			List<String> scope = HealthCheckService.fixScope(fixKey);
			if (scope.isEmpty() || !sameScope(scope, expectedScope)) {
				throw UserErrors.message(BarnHelp.text('Core', 'Core_HealthCheck_FixStale'));
			}
			String outcome = runFix(fixKey, scope);
			SettingsService.logChange(
				CHANGE_PREFIX + fixLabel,
				'',
				String.join(scope, HealthCheckService.JOB_SEPARATOR)
			);
			if (failAfterFix) {
				throw new HealthCheckFixException('A failure after the fix had written.');
			}
			return outcome;
		} catch (AuraHandledException e) {
			Database.rollback(beforeFix);
			throw e;
		} catch (Exception e) {
			Database.rollback(beforeFix);
			throw failed(e, e instanceof AsyncStarter.BusyException);
		}
	}

	/**
	 * The same fix, then every installed module's findings read again with what it did: how a
	 * module's test presses its own fix without the Org Optimizer module's full report.
	 */
	@NamespaceAccessible
	public static HealthCheckService.Report applyForModules(String fixKey, List<String> expectedScope) {
		String outcome = apply(fixKey, expectedScope);
		HealthCheckService.Report report = new HealthCheckService.Report();
		report.findings = HealthCheckService.extensionFindings();
		report.fixOutcome = outcome;
		return report;
	}

	/**
	 * The error a failed fix shows: a message written for a person as it is, anything else
	 * logged and replaced by the fix failure text.
	 */
	@NamespaceAccessible
	public static AuraHandledException failed(Exception caught, Boolean shown) {
		return UserErrors.wrap(
			caught,
			shown,
			System.Label.Core_HealthCheck_Title,
			BarnHelp.text('Core', 'Core_HealthCheck_FixFailed')
		);
	}

	/** Refuses anyone without Manage BarnCRM Settings, with a sentence they can act on. */
	@NamespaceAccessible
	public static void requireManageSettings() {
		if (!HealthCheckService.canManageSettings()) {
			throw UserErrors.message(BarnHelp.text('Core', 'Core_HealthCheck_PermissionRequired'));
		}
	}

	/** The button label of a fix, which also names it in the change history; null if unknown. */
	private static String fixLabel(String fixKey) {
		if (HealthCheckService.FIX_KEY_RESTORE_AUTOMATION_SWITCHES.equals(fixKey)) {
			return System.Label.Core_HealthCheck_SwitchesMissingFix;
		}
		if (HealthCheckService.FIX_KEY_RESTORE_IMPORT_TEMPLATES.equals(fixKey)) {
			return System.Label.Core_HealthCheck_TemplatesMissingFix;
		}
		if (HealthCheckService.FIX_KEY_SCHEDULE_NIGHTLY_JOBS.equals(fixKey)) {
			return System.Label.Core_HealthCheck_NightlyJobsFix;
		}
		if (HealthCheckService.FIX_KEY_RESCHEDULE_INACTIVE_OWNER_JOBS.equals(fixKey)) {
			return System.Label.Core_HealthCheck_InactiveOwnerJobsFix;
		}
		if (ModuleSetups.FIX_KEY.equals(fixKey)) {
			return System.Label.Core_ModuleSetup_FinishButton;
		}
		if (HealthCheckService.FIX_KEY_FILL_MATCH_KEYS.equals(fixKey)) {
			return BarnHelp.text('Core', 'Core_HealthCheck_MatchKeysFix');
		}
		HealthCheckFixExtension owner = HealthCheckService.fixOwner(fixKey);
		return owner == null ? null : owner.fixLabel(fixKey);
	}

	/** Runs the fix and returns the sentence that says what it did. */
	private static String runFix(String fixKey, List<String> scope) {
		if (HealthCheckService.FIX_KEY_FILL_MATCH_KEYS.equals(fixKey)) {
			AddressMatchKeyBatch.run();
			return BarnHelp.text('Core', 'Core_HealthCheck_MatchKeysStarted');
		}
		if (ModuleSetups.FIX_KEY.equals(fixKey)) {
			return String.format(
				BarnHelp.text('Core', 'Core_ModuleSetup_FixOutcome'),
				new List<Object>{ String.join(ModuleSetups.finishByLabel(scope), ', ') }
			);
		}
		HealthCheckFixExtension owner = HealthCheckService.fixOwner(fixKey);
		if (owner != null) {
			return owner.runFix(fixKey, scope);
		}
		if (HealthCheckService.FIX_KEY_RESCHEDULE_INACTIVE_OWNER_JOBS.equals(fixKey)) {
			return rescheduled(scope);
		}
		if (HealthCheckService.FIX_KEY_SCHEDULE_NIGHTLY_JOBS.equals(fixKey)) {
			return String.format(
				System.Label.Core_HealthCheck_FixScheduled,
				new List<Object>{ String.join(NightlyJobs.scheduleAll(), HealthCheckService.JOB_SEPARATOR) }
			);
		}
		String outcome = String.format(
			System.Label.Core_HealthCheck_FixCreated,
			new List<Object>{ String.join(scope, ', ') }
		);
		if (HealthCheckService.FIX_KEY_RESTORE_AUTOMATION_SWITCHES.equals(fixKey)) {
			AutomationControl.ensureDefaults();
		} else {
			ImportTemplateService.materializeDefaults();
		}
		return outcome;
	}

	/** Jobs owned by inactive people, scheduled again as the running user, or only stopped. */
	private static String rescheduled(List<String> scope) {
		List<String> stoppedOnly = NightlyJobs.rescheduleAsRunningUser(scope);
		List<String> again = new List<String>();
		for (String name : scope) {
			if (!stoppedOnly.contains(name)) {
				again.add(name);
			}
		}
		String outcome = again.isEmpty()
			? ''
			: String.format(
					System.Label.Core_HealthCheck_FixScheduled,
					new List<Object>{ String.join(again, HealthCheckService.JOB_SEPARATOR) }
			  );
		if (!stoppedOnly.isEmpty()) {
			outcome +=
				(outcome == '' ? '' : ' ') +
				String.format(
					BarnHelp.text('Core', 'Core_HealthCheck_FixStoppedOnly'),
					new List<Object>{ String.join(stoppedOnly, HealthCheckService.JOB_SEPARATOR) }
				);
		}
		return outcome;
	}

	/** Whether two scopes name the same things, in any order. */
	private static Boolean sameScope(List<String> current, List<String> expected) {
		if (expected == null || expected.size() != current.size()) {
			return false;
		}
		List<String> left = current.clone();
		List<String> right = expected.clone();
		left.sort();
		right.sort();
		return left.equals(right);
	}

	private class HealthCheckFixException extends Exception {
	}
}
