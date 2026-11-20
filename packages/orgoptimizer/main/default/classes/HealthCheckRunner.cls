/**
 * Runs Health Check (plan Section 4.8, feature C-11): Core's own checks in reading order, then
 * every installed module's `HealthCheckExtension`, each isolated, and the report the panel
 * receives (ADR-NEXT `NEXT-org-optimizer-and-sample-data-modules.md`).
 *
 * The vocabulary every check shares (the Finding, the severities, the categories, the fix
 * targets) stays in Core's `HealthCheckService`, with the extension seam, so a module's checks
 * and Core's own check contributors (`BrandShareJob`, `FieldHistoryService`, `ModuleSetups`,
 * `AddressMatchKeyHandler`) compile without this package. What each Core check says lives in one
 * of the classes grouped by the question it asks (ADR-0039):
 *
 * - HealthCheckOrgShapeChecks: what is installed, and whether the mode matches it.
 * - HealthCheckAccessChecks: who administers the app and who cannot see it. Only asked of a
 *   viewer who may manage settings.
 * - HealthCheckSettingsChecks: automation, fiscal year, Error Log, and the package defaults and
 *   nightly run a fix button can restore (C-21, ADR-0048).
 * - HealthCheckHouseholdChecks: whether everyone is in a household and every household has
 *   somebody in it. Detection only, with no fix button (C-21, ADR-0048).
 *
 * Every check is isolated. A check that throws becomes a finding of its own and is written to
 * the Error Log; the other checks still run.
 *
 * Core reaches this class by name through the module catalog (`HealthCheckRun`, ADR-0057), for
 * `BarnInstallCheck.runHealthCheck`, so it needs a public constructor.
 */
@NamespaceAccessible
public with sharing class HealthCheckRunner implements HealthCheckRun {
	/** Test injection point, null in every real transaction: a check that always throws. */
	@TestVisible
	private static HealthCheckService.Check faultInjection;

	/**
	 * Where the two access counts come from. Injected in tests so that the findings are
	 * asserted against numbers the test chose, not against whichever people and permission
	 * sets happen to exist in the org the tests run in.
	 */
	@TestVisible
	private static AccessCounts accessCountsOverride;

	/** Built by name from Core (`ModuleExtensions`), so it needs a public constructor. */
	@NamespaceAccessible
	public HealthCheckRunner() {
		// Nothing to set up: every run reads the org afresh.
	}

	/** Every finding, for Core's install check (`HealthCheckRun`). */
	public List<HealthCheckService.Finding> findings() {
		return run();
	}

	/**
	 * How many people administer BarnCRM, and how many active people cannot see it at
	 * all. Both are questions about the whole org, which is why only an administrator is
	 * allowed to ask them.
	 */
	public interface AccessCounts {
		Integer administrators();
		Integer usersWithoutAccess();
	}

	/** The real counts, read from the org. */
	private class OrgAccessCounts implements AccessCounts {
		public Integer administrators() {
			return UserAccessSelector.countActiveAssignees(new Set<String>{ HealthCheckService.GROUP_ADMIN }) +
				UserAccessSelector.countActiveDirectAssignees(
					new Set<String>{ HealthCheckService.PERMISSION_SET_ADMIN }
				);
		}

		public Integer usersWithoutAccess() {
			Set<Id> assigned = UserAccessSelector.getAssignedUserIds(HealthCheckService.BARNCRM_GROUPS);
			assigned.addAll(UserAccessSelector.getPermissionSetAssigneeIds(HealthCheckService.BARNCRM_PERMISSION_SETS));
			return UserAccessSelector.countActiveStandardUsersExcluding(assigned);
		}
	}

	private static AccessCounts accessCounts() {
		return accessCountsOverride == null ? new OrgAccessCounts() : accessCountsOverride;
	}

	/** A check and the key its failure is reported under. */
	private class CheckStep {
		private final String key;
		private final HealthCheckService.Check check;

		private CheckStep(String key, HealthCheckService.Check check) {
			this.key = key;
			this.check = check;
		}
	}

	/**
	 * Every finding, in the order an administrator should read them.
	 *
	 * A check that throws becomes one finding of its own; the rest still run, because a
	 * report that hides eight answers because the ninth failed is worse than no report.
	 */
	@NamespaceAccessible
	public static List<HealthCheckService.Finding> run() {
		return run(null);
	}

	/**
	 * The keys of the checks the last run in this transaction left because it stopped early to
	 * stay inside the limits; empty when every check ran.
	 */
	private static List<String> lastSkipped = new List<String>();

	/**
	 * The same, running only the checks whose keys are given (null for all of them): how
	 * Run Remaining Checks runs just the checks an earlier run left (D-208, N-07).
	 */
	private static List<HealthCheckService.Finding> run(Set<String> only) {
		List<HealthCheckService.Finding> findings = new List<HealthCheckService.Finding>();
		List<String> skipped = new List<String>();

		for (CheckStep step : steps()) {
			if (only != null && !only.contains(step.key)) {
				continue;
			}
			if (!skipped.isEmpty() || HealthCheckService.nearLimits()) {
				skipped.add(step.key);
				continue;
			}
			try {
				HealthCheckService.Finding finding = step.check.run();
				if (finding != null) {
					findings.add(finding);
				}
			} catch (Exception e) {
				findings.add(HealthCheckService.checkFailed(step.key, e));
			}
		}

		findings.addAll(HealthCheckService.extensionFindings(skipped, only));
		if (!skipped.isEmpty()) {
			findings.add(notChecked(skipped));
		}
		lastSkipped = skipped;

		return findings;
	}

	/** One finding naming, as an administrator reads them, the checks left for another run. */
	private static HealthCheckService.Finding notChecked(List<String> keys) {
		Map<String, String> labels = stepLabels();
		List<String> names = new List<String>();
		for (String key : keys) {
			names.add(labels.containsKey(key) ? labels.get(key) : extensionLabel(key));
		}
		return new HealthCheckService.Finding(
			'not_checked',
			BarnHelp.text('Core', 'Core_HealthCheck_NotCheckedTitle'),
			String.format(
				BarnHelp.text('Core', 'Core_HealthCheck_NotCheckedDetail'),
				new List<Object>{ keys.size(), String.join(names, ', ') }
			),
			HealthCheckService.SEVERITY_WARNING,
			HealthCheckService.CATEGORY_SETTINGS
		);
	}

	/** Each of Core's own check steps by the name an administrator reads, keyed by step key. */
	private static Map<String, String> stepLabels() {
		return new Map<String, String>{
			'org_shape' => BarnHelp.text('Core', 'Core_HealthCheck_Step_OrgShape'),
			'coexistence_mode' => BarnHelp.text('Core', 'Core_HealthCheck_Step_CoexistenceMode'),
			'membership_mode' => BarnHelp.text('Core', 'Core_HealthCheck_Step_MembershipMode'),
			'membership_data' => BarnHelp.text('Core', 'Core_HealthCheck_Step_MembershipData'),
			'household_creation' => BarnHelp.text('Core', 'Core_HealthCheck_Step_HouseholdCreation'),
			'npsp_upkeep_overlap' => BarnHelp.text('Core', 'Core_HealthCheck_Step_NpspUpkeepOverlap'),
			'native_households' => BarnHelp.text('Core', 'Core_HealthCheck_Step_NativeHouseholds'),
			'native_household_collision' => BarnHelp.text('Core', 'Core_HealthCheck_Step_NativeHouseholdCollision'),
			'mirror_module' => BarnHelp.text('Core', 'Core_HealthCheck_Step_MirrorModule'),
			'brand_visibility' => BarnHelp.text('Core', 'Core_HealthCheck_Step_BrandVisibility'),
			'multi_currency' => BarnHelp.text('Core', 'Core_HealthCheck_Step_MultiCurrency'),
			'admin_role' => BarnHelp.text('Core', 'Core_HealthCheck_Step_AdminRole'),
			'users_without_access' => BarnHelp.text('Core', 'Core_HealthCheck_Step_UsersWithoutAccess'),
			'access_checks_need_admin' => BarnHelp.text('Core', 'Core_HealthCheck_Step_AccessChecks'),
			'automation' => BarnHelp.text('Core', 'Core_HealthCheck_Step_Automation'),
			'field_history' => BarnHelp.text('Core', 'Core_HealthCheck_Step_FieldHistory'),
			'fiscal_year' => BarnHelp.text('Core', 'Core_HealthCheck_Step_FiscalYear'),
			'organization_record_type' => BarnHelp.text('Core', 'Core_HealthCheck_Step_OrganizationRecordType'),
			'error_log' => BarnHelp.text('Core', 'Core_HealthCheck_Step_ErrorLog'),
			'error_digest' => BarnHelp.text('Core', 'Core_HealthCheck_Step_ErrorDigest'),
			'people_without_household' => BarnHelp.text('Core', 'Core_HealthCheck_Step_PeopleWithoutHousehold'),
			'households_without_members' => BarnHelp.text('Core', 'Core_HealthCheck_Step_HouseholdsWithoutMembers'),
			'household_ownership_skew' => BarnHelp.text('Core', 'Core_HealthCheck_Step_HouseholdOwnershipSkew'),
			'relationships_without_person' => BarnHelp.text('Core', 'Core_HealthCheck_Step_RelationshipsWithoutPerson'),
			'affiliations_without_person' => BarnHelp.text('Core', 'Core_HealthCheck_Step_AffiliationsWithoutPerson'),
			'automation_switches' => BarnHelp.text('Core', 'Core_HealthCheck_Step_AutomationSwitches'),
			'import_templates' => BarnHelp.text('Core', 'Core_HealthCheck_Step_ImportTemplates'),
			'nightly_jobs' => BarnHelp.text('Core', 'Core_HealthCheck_Step_NightlyJobs'),
			'jobs_inactive_owner' => BarnHelp.text('Core', 'Core_HealthCheck_Step_JobsInactiveOwner'),
			'module_setup' => BarnHelp.text('Core', 'Core_HealthCheck_Step_ModuleSetup'),
			'match_keys' => BarnHelp.text('Core', 'Core_HealthCheck_Step_MatchKeys')
		};
	}

	/**
	 * A module extension's checks by the module's name (`addressverification_extension` reads
	 * "Address Verification module checks"), found from the class it is registered under. A key
	 * that is neither is shown as it is.
	 */
	private static String extensionLabel(String key) {
		for (String className : HealthCheckExtensions.EXTENSION_CLASSES) {
			String module = className.removeEnd('HealthCheckExtension');
			if ((module.toLowerCase() + '_extension').equals(key)) {
				return String.format(
					BarnHelp.text('Core', 'Core_HealthCheck_Step_Extension'),
					new List<Object>{ String.join(module.splitByCharacterTypeCamelCase(), ' ') }
				);
			}
		}
		return key;
	}

	/**
	 * The checks to run, in reading order. The access and Error Log counts are only asked
	 * for when the viewer can actually see the answer: a person without the administrator
	 * permission sees their own permission set assignments and nothing else, and a count
	 * taken from that is confidently wrong, which is worse than no count at all. The package
	 * defaults checks are gated the same way, because only that viewer can press their fix,
	 * and so are the household counts, which are read with the viewer's own access.
	 */
	private static List<CheckStep> steps() {
		List<CheckStep> steps = new List<CheckStep>();
		if (faultInjection != null) {
			steps.add(new CheckStep('injected', faultInjection));
		}

		steps.add(new CheckStep('org_shape', new HealthCheckOrgShapeChecks.OrgShapeCheck()));
		steps.add(new CheckStep('coexistence_mode', new HealthCheckOrgShapeChecks.CoexistenceModeCheck()));
		steps.add(new CheckStep('membership_mode', new HealthCheckOrgShapeChecks.MembershipModeCheck()));
		steps.add(new CheckStep('membership_data', new HealthCheckOrgShapeChecks.MembershipDataCheck()));
		steps.add(new CheckStep('household_creation', new HealthCheckOrgShapeChecks.HouseholdCreationCheck()));
		steps.add(new CheckStep('npsp_upkeep_overlap', new HealthCheckOrgShapeChecks.NpspUpkeepOverlapCheck()));
		steps.add(new CheckStep('native_households', new HealthCheckOrgShapeChecks.NativeHouseholdsCheck()));
		steps.add(
			new CheckStep('native_household_collision', new HealthCheckOrgShapeChecks.NativeHouseholdCollisionCheck())
		);
		steps.add(new CheckStep('mirror_module', new HealthCheckOrgShapeChecks.MirrorModuleCheck()));
		steps.add(new CheckStep('brand_visibility', new BrandShareJob.VisibilityCheck()));
		steps.add(new CheckStep('multi_currency', new HealthCheckOrgShapeChecks.MultiCurrencyCheck()));

		if (HealthCheckService.canManageSettings()) {
			steps.add(new CheckStep('admin_role', new HealthCheckAccessChecks.NoAdminCheck(accessCounts())));
			steps.add(
				new CheckStep(
					'users_without_access',
					new HealthCheckAccessChecks.UsersWithoutAccessCheck(accessCounts())
				)
			);
		} else {
			steps.add(new CheckStep('access_checks_need_admin', new HealthCheckAccessChecks.NeedsAdminCheck()));
		}

		steps.add(new CheckStep('automation', new HealthCheckSettingsChecks.AutomationCheck()));
		steps.add(new CheckStep('field_history', new FieldHistoryService.HealthCheck()));
		steps.add(new CheckStep('fiscal_year', new HealthCheckSettingsChecks.FiscalYearCheck()));
		steps.add(
			new CheckStep('organization_record_type', new HealthCheckSettingsChecks.OrganizationRecordTypeCheck())
		);

		if (HealthCheckService.canManageSettings()) {
			steps.add(new CheckStep('error_log', new HealthCheckSettingsChecks.ErrorLogCheck()));
			steps.add(new CheckStep('error_digest', new HealthCheckSettingsChecks.ErrorDigestCheck()));
			steps.add(
				new CheckStep('people_without_household', new HealthCheckHouseholdChecks.PeopleWithoutHouseholdCheck())
			);
			steps.add(
				new CheckStep(
					'households_without_members',
					new HealthCheckHouseholdChecks.HouseholdsWithoutMembersCheck()
				)
			);
			steps.add(new CheckStep('household_ownership_skew', new HealthCheckSkew.HouseholdOwnershipCheck()));
			steps.add(
				new CheckStep(
					'relationships_without_person',
					new HealthCheckHouseholdChecks.RelationshipsWithoutPersonCheck()
				)
			);
			steps.add(
				new CheckStep(
					'affiliations_without_person',
					new HealthCheckHouseholdChecks.AffiliationsWithoutPersonCheck()
				)
			);
			steps.add(new CheckStep('automation_switches', new HealthCheckSettingsChecks.AutomationSwitchesCheck()));
			steps.add(new CheckStep('import_templates', new HealthCheckSettingsChecks.ImportTemplatesCheck()));
			steps.add(new CheckStep('nightly_jobs', new HealthCheckSettingsChecks.NightlyJobsCheck()));
			steps.add(new CheckStep('jobs_inactive_owner', new HealthCheckSettingsChecks.InactiveOwnerJobsCheck()));
			// A package copied in by hand, whose setup never ran (FS1).
			steps.add(new CheckStep('module_setup', new ModuleSetups.SetupCheck()));
			steps.add(new CheckStep('match_keys', new AddressMatchKeyHandler.FilledCheck()));
			// The rollup checks are the Rollup Builder module's (RollupsHealthCheckExtension,
			// ADR-0125), asked with the other extensions after these.
		}

		return steps;
	}

	/**
	 * The findings plus the context the panel shows above them.
	 */
	public static HealthCheckService.Report buildReport() {
		HealthCheckService.Report report = new HealthCheckService.Report();
		report.findings = run();
		report.skippedChecks = lastSkipped;
		report.canManageSettings = HealthCheckService.canManageSettings();

		try {
			report.orgShape = OrgShapeDetector.detect();
			report.orgShapeSummary = detectedSummary(report.orgShape);
			report.recommendedMode = OrgShapeDetector.recommendedCoexistenceMode();
			report.recommendedModeLabel = HealthCheckService.modeLabel(report.recommendedMode);
		} catch (Exception e) {
			logQuietly(e);
		}

		try {
			report.currentMode = CoexistenceService.getCurrentMode();
			report.currentModeLabel = HealthCheckService.modeLabel(report.currentMode);
			report.modeNeedsAttention =
				String.isBlank(report.currentMode) ||
				(report.recommendedMode != null && !report.recommendedMode.equals(report.currentMode));
		} catch (Exception e) {
			logQuietly(e);
		}

		try {
			HealthCheckLastRun.record(report);
		} catch (Exception e) {
			logQuietly(e);
		}

		return report;
	}

	/**
	 * Only the checks an earlier run left (D-208, N-07): their findings, and the keys of any it
	 * had to leave again. The panel merges these into the report it already shows, so the org
	 * shape and modes are not read again. The stored last result gains these findings in place
	 * of the earlier Not Checked warning.
	 */
	public static HealthCheckService.Report buildRemainingReport(List<String> keys) {
		HealthCheckService.Report report = new HealthCheckService.Report();
		report.canManageSettings = HealthCheckService.canManageSettings();
		if (keys == null || keys.isEmpty()) {
			return report;
		}
		report.findings = run(new Set<String>(keys));
		report.skippedChecks = lastSkipped;
		try {
			HealthCheckLastRun.addRemaining(report);
		} catch (Exception e) {
			logQuietly(e);
		}
		return report;
	}

	/**
	 * What was found, as a sentence an administrator can read out loud. The sentence itself
	 * is built next to the org shape checks that also use it.
	 */
	public static String detectedSummary(OrgShapeDetector.OrgShape shape) {
		return HealthCheckOrgShapeChecks.detectedSummary(shape);
	}

	/**
	 * Write one failure to the Error Log without ever letting the writing of it become a
	 * second failure. Canonical model R-E2: a failure to log is swallowed rather than masking
	 * the original error.
	 */
	private static void logQuietly(Exception e) {
		try {
			ErrorLogger.log(e, System.Label.Core_HealthCheck_Title);
		} catch (Exception loggingFailed) {
			// Deliberate last resort: ErrorLogger.log itself failed, so the debug log is the only remaining place to note it. Kept intentionally (PMD AvoidDebugStatements finding accepted, not suppressed).
			System.debug(LoggingLevel.ERROR, loggingFailed);
		}
	}
}
