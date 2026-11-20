/**
 * Health Check: what this org looks like, whether BarnCRM is set up to match, who can
 * get in, and what is currently in the way (plan Section 4.8, feature C-11).
 *
 * This class is the seam Health Check's checks are written against: the vocabulary every check
 * shares (the Finding, the severities, the categories, the fix targets), the report the panel
 * receives, the limit guard, and the isolated run of every installed module's extension. The
 * runner itself, Core's own checks in reading order, the fixes and the panel are the Org
 * Optimizer module's (`HealthCheckRunner`, ADR-NEXT
 * `NEXT-org-optimizer-and-sample-data-modules.md`), so a module's checks and Core's own check
 * contributors (`BrandShareJob`, `FieldHistoryService`, `ModuleSetups`, `AddressMatchKeyHandler`)
 * compile without it. `runInstalled()` reaches the runner by name when the module is installed.
 *
 * A dependent package that owns data Core may not name (a gift, a receipt, an accounting
 * period) adds its own findings through `HealthCheckExtension`, found by `HealthCheckExtensions` with
 * `Type.forName` (G-20 follow-up, ADR-0053, ADR-0057), never by Core learning what a gift is.
 *
 * Every check is isolated. A check that throws becomes a finding of its own and is written
 * to the Error Log; the other checks still run, because a report that hides eight answers
 * because the ninth failed is worse than no report. A package extension's findings are
 * isolated the same way.
 *
 * Every string an administrator reads comes from a Custom Label.
 *
 * `@NamespaceAccessible` on the members `HealthCheckGivingChecks` actually reaches (ADR-0017):
 * the class itself, `Finding` with its constructor, `withFix` and `withLinks`, `Link` with its
 * constructor, the vocabulary constants Giving's findings use (`SEVERITY_INFO`,
 * `SEVERITY_WARNING`, `CATEGORY_ACCESS`, `CATEGORY_SETTINGS`, `FIX_CUSTOM_PERMISSIONS_URL`),
 * `canManageSettings()`, and `extensionFindings()`, which `GivingHealthCheckExtensionTest`
 * calls directly to prove Core reaches the installed extension. A severity, category or method a
 * future extension needs and this one does not gets annotated when that extension is built, not
 * ahead of it.
 *
 * `Finding`'s own fields (`key`, `title`, `severity`, `category`, `fixLabel`, `fixTarget`,
 * `links`) carry `@AuraEnabled` and nothing else: the platform rejects `@NamespaceAccessible` on
 * a field that is already `@AuraEnabled` (a compile error, not a style choice). Whether another
 * package can read such a field is unproven until a namespaced build, so another package reads
 * one only through a `@NamespaceAccessible` getter (`getKey`, `getDetail`, `getSeverity`,
 * `getFixTarget`, `getFixScope`, and `Report.getFindings`, `getFixOutcome`) or through JSON,
 * as `GivingHealthCheckExtensionTest` does. A getter is added for a field when another package
 * first needs it; `check-cross-package-visibility.py` fails on a direct read.
 */
@NamespaceAccessible
public with sharing class HealthCheckService {
	@NamespaceAccessible
	public static final String SEVERITY_INFO = 'Info';
	@NamespaceAccessible
	public static final String SEVERITY_WARNING = 'Warning';
	@NamespaceAccessible
	public static final String SEVERITY_ERROR = 'Error';

	@NamespaceAccessible
	public static final String CATEGORY_ORG_SHAPE = 'OrgShape';
	@NamespaceAccessible
	public static final String CATEGORY_LICENSES = 'Licenses';
	@NamespaceAccessible
	public static final String CATEGORY_ACCESS = 'Access';
	@NamespaceAccessible
	public static final String CATEGORY_SETTINGS = 'Settings';

	/**
	 * A fix target is one of three things, and the component tells them apart by shape:
	 * a value starting with "action:" is a method on the controller, a value starting with
	 * "/" is a relative URL to navigate to, and anything else names a section of the
	 * settings console. Null means there is nothing to click.
	 */
	@NamespaceAccessible
	public static final String FIX_ACTION_PREFIX = 'action:';
	@NamespaceAccessible
	public static final String FIX_APPLY_RECOMMENDED_MODE = 'action:applyRecommendedMode';
	@NamespaceAccessible
	public static final String FIX_APPLY_JUNCTION_MEMBERSHIP = 'action:applyJunctionMembership';
	@NamespaceAccessible
	public static final String FIX_ENABLE_AUTOMATIC_HOUSEHOLDS = 'action:enableAutomaticHouseholds';

	/**
	 * The fixes HealthCheckController.applyFix runs (C-21, ADR-0048). Each one only creates
	 * what is missing or schedules what is not scheduled, so pressing it twice is pressing it
	 * once. The key is what follows the action prefix in the fix target. A dependent package's
	 * fixes are its own keys, answered by its `HealthCheckFixExtension` (ADR-0125).
	 */
	@NamespaceAccessible
	public static final String FIX_KEY_RESTORE_AUTOMATION_SWITCHES = 'restoreAutomationSwitches';
	@NamespaceAccessible
	public static final String FIX_KEY_RESTORE_IMPORT_TEMPLATES = 'restoreImportTemplates';
	@NamespaceAccessible
	public static final String FIX_KEY_SCHEDULE_NIGHTLY_JOBS = 'scheduleNightlyJobs';
	@NamespaceAccessible
	public static final String FIX_KEY_RESCHEDULE_INACTIVE_OWNER_JOBS = 'rescheduleInactiveOwnerJobs';
	public static final String FIX_KEY_FILL_MATCH_KEYS = 'fillMatchKeys';

	/**
	 * What a finding puts between the job names it lists. A job name can hold a comma
	 * ("Installment top up, 1:15 AM"), so a comma between them would run two jobs together.
	 */
	@NamespaceAccessible
	public static final String JOB_SEPARATOR = '; ';

	/**
	 * A finding's words for a count: `one` when the count is exactly 1, so it never reads
	 * "1 households have", and `many` otherwise, a count past a cap included.
	 */
	@NamespaceAccessible
	public static String forCount(Integer count, String one, String many, List<Object> values) {
		return String.format(count == 1 ? one : many, values);
	}

	/**
	 * What one of those fixes would change if it ran now: the names of the rows it would create,
	 * or the names of the jobs it would schedule. Empty when it would change nothing, null for a
	 * key that is not one of them.
	 *
	 * The finding carries this list, the panel sends it back with the fix request, and the
	 * controller refuses to run when the list it computes then is different. So the fix creates
	 * exactly what the administrator read in the confirm box, never what changed since
	 * (ADR-0048 condition 5).
	 */
	@NamespaceAccessible
	public static List<String> fixScope(String fixKey) {
		if (FIX_KEY_RESTORE_AUTOMATION_SWITCHES.equals(fixKey)) {
			return AutomationControl.missingDefaultNames();
		}
		if (FIX_KEY_RESTORE_IMPORT_TEMPLATES.equals(fixKey)) {
			return ImportTemplateService.missingDefaultNames();
		}
		if (FIX_KEY_SCHEDULE_NIGHTLY_JOBS.equals(fixKey)) {
			return NightlyJobs.unscheduledLabels();
		}
		if (FIX_KEY_RESCHEDULE_INACTIVE_OWNER_JOBS.equals(fixKey)) {
			return ScheduledJobSelector.namesOwnedByInactiveUsers();
		}
		if (FIX_KEY_FILL_MATCH_KEYS.equals(fixKey)) {
			return AddressMatchKeyHandler.unfilledScope();
		}
		if (ModuleSetups.FIX_KEY.equals(fixKey)) {
			return ModuleSetups.pendingLabels();
		}
		HealthCheckFixExtension owner = fixOwner(fixKey);
		return owner == null ? null : owner.fixScope(fixKey);
	}

	/**
	 * The installed extension that owns this fix key, or null when none does. Core's own keys
	 * never reach here (ADR-0125).
	 */
	public static HealthCheckFixExtension fixOwner(String fixKey) {
		if (String.isBlank(fixKey)) {
			return null;
		}
		for (HealthCheckFixExtension fixer : HealthCheckExtensions.fixExtensions()) {
			if (fixer.fixLabel(fixKey) != null) {
				return fixer;
			}
		}
		return null;
	}

	/** The settings console tab that hosts every section a fix can point at. */
	public static final String SETTINGS_TAB = 'BarnCRM_Settings';

	/** The page state parameter that tells the console which section to open. */
	public static final String SECTION_STATE_PARAMETER = 'section';

	@NamespaceAccessible
	public static final String SECTION_GENERAL = 'General';
	/** The People box of People and Households, where the way of belonging lives (P1). */
	@NamespaceAccessible
	public static final String SECTION_PEOPLE = SettingSections.PEOPLE;
	@NamespaceAccessible
	public static final String SECTION_ACCESS = 'Access';
	@NamespaceAccessible
	public static final String SECTION_AUTOMATION = 'Automation';

	/**
	 * The developer names of the packaged permission set groups (the roles the Access page
	 * assigns) that mean "this person uses BarnCRM", and the permission set that means
	 * "this person administers it". See packages/core/integration/c-07-c-11.permissions.md.
	 */
	@NamespaceAccessible
	public static final String GROUP_ADMIN = 'BarnCRM_Admin_Group';
	@NamespaceAccessible
	public static final String PERMISSION_SET_ADMIN = 'BarnCRM_Admin';
	@NamespaceAccessible
	public static final Set<String> BARNCRM_GROUPS = new Set<String>{
		GROUP_ADMIN,
		'Fundraising_Staff',
		'Program_Staff',
		'Read_Only'
	};

	/**
	 * The packaged permission sets themselves. An administrator who assigned one of these
	 * directly, rather than through a role, has still given that person the app.
	 */
	@NamespaceAccessible
	public static final Set<String> BARNCRM_PERMISSION_SETS = new Set<String>{
		PERMISSION_SET_ADMIN,
		'BarnCRM_Staff',
		'BarnCRM_Read_Only'
	};

	/**
	 * Where Setup lists custom permissions: the fix for a custom permission a module reports
	 * as held (Giving's receipt lock override, ADR-0024, is kept out of the console on purpose).
	 */
	@NamespaceAccessible
	public static final String FIX_CUSTOM_PERMISSIONS_URL = '/lightning/setup/CustomPermissions/home';

	/** The custom permission that gates changing settings and reading who else is in the org. */
	public static final String MANAGE_SETTINGS = BarnCRMPermissions.MANAGE_SETTINGS;

	/**
	 * Test injection point, null in every real transaction: an exception for the Error Log call
	 * to throw. It proves that a logger that is itself broken still leaves the rest of the
	 * report standing.
	 */
	@NamespaceAccessible
	@TestVisible
	public static Exception loggerFault;

	/**
	 * Past these, the remaining checks are left for another run (D-200 P7): about 80 of the
	 * 100 queries, 7 of the 10 seconds of CPU, 40,000 of the 50,000 query rows. A test
	 * lowers them.
	 */
	@NamespaceAccessible
	@TestVisible
	public static Integer queryBudget = 80;
	@TestVisible
	private static Integer cpuBudget = 7000;
	@TestVisible
	private static Integer rowBudget = 40000;

	/** One thing Health Check has to say about this org. */
	@NamespaceAccessible
	public class Finding {
		@AuraEnabled
		public String key;
		@AuraEnabled
		public String title;
		@AuraEnabled
		public String detail;
		@AuraEnabled
		public String severity;
		@AuraEnabled
		public String fixLabel;
		@AuraEnabled
		public String fixTarget;
		@AuraEnabled
		public String category;
		/** What the fix would change, as fixScope computed it for this report. */
		@AuraEnabled
		public List<String> fixScope;
		/** Records the finding is about, to open one by one. Never a fix. */
		@AuraEnabled
		public List<Link> links;

		@NamespaceAccessible
		public Finding(String key, String title, String detail, String severity, String category) {
			this.key = key;
			this.title = title;
			this.detail = detail;
			this.severity = severity;
			this.category = category;
		}

		@NamespaceAccessible
		public Finding withFix(String fixLabel, String fixTarget) {
			this.fixLabel = fixLabel;
			this.fixTarget = fixTarget;
			return this;
		}

		@NamespaceAccessible
		public Finding withScope(List<String> fixScope) {
			this.fixScope = fixScope;
			return this;
		}

		@NamespaceAccessible
		public Finding withLinks(List<Link> links) {
			this.links = links;
			return this;
		}

		@NamespaceAccessible
		public String getKey() {
			return key;
		}

		@NamespaceAccessible
		public String getDetail() {
			return detail;
		}

		@NamespaceAccessible
		public String getSeverity() {
			return severity;
		}

		@NamespaceAccessible
		public String getFixTarget() {
			return fixTarget;
		}

		@NamespaceAccessible
		public List<String> getFixScope() {
			return fixScope;
		}

		@NamespaceAccessible
		public String getTitle() {
			return title;
		}

		@NamespaceAccessible
		public String getCategory() {
			return category;
		}

		@NamespaceAccessible
		public List<Link> getLinks() {
			return links;
		}
	}

	/** One record a finding names, with where to open it. */
	@NamespaceAccessible
	public class Link {
		@AuraEnabled
		public String label;
		@AuraEnabled
		public String url;

		@NamespaceAccessible
		public Link(SObject record) {
			this.label = String.valueOf(record.get('Name'));
			this.url = '/lightning/r/' + record.getSObjectType().getDescribe().getName() + '/' + record.Id + '/view';
		}

		@NamespaceAccessible
		public String getLabel() {
			return label;
		}

		@NamespaceAccessible
		public String getUrl() {
			return url;
		}
	}

	/** Everything the panel needs in one round trip. */
	@NamespaceAccessible
	public class Report {
		@AuraEnabled
		public List<Finding> findings;
		@AuraEnabled
		public OrgShapeDetector.OrgShape orgShape;
		@AuraEnabled
		public String orgShapeSummary;
		@AuraEnabled
		public String currentMode;
		@AuraEnabled
		public String currentModeLabel;
		@AuraEnabled
		public String recommendedMode;
		@AuraEnabled
		public String recommendedModeLabel;
		@AuraEnabled
		public Boolean modeNeedsAttention;
		@AuraEnabled
		public Boolean canManageSettings;

		/**
		 * The API name of the settings console tab, and the page state key a section fix has
		 * to use, both carrying whatever namespace this org runs under. The component never
		 * builds these itself (see docs/contributor-guide/environment.md, "Namespace
		 * registration").
		 */
		@AuraEnabled
		public String settingsTabApiName;
		@AuraEnabled
		public String sectionStateKey;
		/** After a fix: what it created or scheduled, and what it left out. Null otherwise. */
		@AuraEnabled
		public String fixOutcome;
		/**
		 * The keys of the checks this run left because it stopped early to stay inside the
		 * limits, for Run Remaining Checks; empty when every check ran (D-208, N-07).
		 */
		@AuraEnabled
		public List<String> skippedChecks;

		@NamespaceAccessible
		public Report() {
			this.findings = new List<Finding>();
			this.skippedChecks = new List<String>();
			this.modeNeedsAttention = false;
			this.canManageSettings = false;
			this.settingsTabApiName = NamespaceUtil.qualify(SETTINGS_TAB);
			this.sectionStateKey = NamespaceUtil.stateKey(SECTION_STATE_PARAMETER);
		}

		@NamespaceAccessible
		public List<Finding> getFindings() {
			return findings;
		}

		@NamespaceAccessible
		public String getFixOutcome() {
			return fixOutcome;
		}

		@NamespaceAccessible
		public List<String> getSkippedChecks() {
			return skippedChecks;
		}

		@NamespaceAccessible
		public Boolean getCanManageSettings() {
			return canManageSettings;
		}

		@NamespaceAccessible
		public OrgShapeDetector.OrgShape getOrgShape() {
			return orgShape;
		}

		@NamespaceAccessible
		public String getOrgShapeSummary() {
			return orgShapeSummary;
		}

		@NamespaceAccessible
		public String getCurrentMode() {
			return currentMode;
		}

		@NamespaceAccessible
		public String getCurrentModeLabel() {
			return currentModeLabel;
		}

		@NamespaceAccessible
		public String getRecommendedMode() {
			return recommendedMode;
		}

		@NamespaceAccessible
		public String getRecommendedModeLabel() {
			return recommendedModeLabel;
		}

		@NamespaceAccessible
		public Boolean getModeNeedsAttention() {
			return modeNeedsAttention;
		}

		/**
		 * Sets one field by its name, for the Org Optimizer runner that fills the report: an
		 * `@AuraEnabled` field cannot also be `@NamespaceAccessible`.
		 */
		@NamespaceAccessible
		public Report put(String field, Object value) {
			switch on field {
				when 'findings' {
					findings = (List<Finding>) value;
				}
				when 'skippedChecks' {
					skippedChecks = (List<String>) value;
				}
				when 'canManageSettings' {
					canManageSettings = (Boolean) value;
				}
				when 'orgShape' {
					orgShape = (OrgShapeDetector.OrgShape) value;
				}
				when 'orgShapeSummary' {
					orgShapeSummary = (String) value;
				}
				when 'currentMode' {
					currentMode = (String) value;
				}
				when 'currentModeLabel' {
					currentModeLabel = (String) value;
				}
				when 'recommendedMode' {
					recommendedMode = (String) value;
				}
				when 'recommendedModeLabel' {
					recommendedModeLabel = (String) value;
				}
				when 'modeNeedsAttention' {
					modeNeedsAttention = (Boolean) value;
				}
				when 'fixOutcome' {
					fixOutcome = (String) value;
				}
				when else {
					throw new IllegalArgumentException('Unknown Health Check report field: ' + field);
				}
			}
			return this;
		}
	}

	/**
	 * One check. Returning null means there is nothing to report, which is the normal case
	 * for most of them.
	 */
	@NamespaceAccessible
	public interface Check {
		Finding run();
	}

	/**
	 * Every finding of a full Health Check, or null when the Org Optimizer module, which holds
	 * the runner, is not installed (`HealthCheckRun`, ADR-0057). A null is never a clean org: the
	 * caller says Health Check is not available.
	 */
	@NamespaceAccessible
	public static List<Finding> runInstalled() {
		HealthCheckRun runner = (HealthCheckRun) ModuleExtensions.first(HealthCheckRun.class);
		return runner == null ? null : runner.findings();
	}

	/**
	 * Whether the run has used so much of this transaction's limits that the next check could
	 * hit one. A limit exception cannot be caught, so it would lose the whole report rather
	 * than one finding (D-200 P7). Public so an extension can stop between its own checks.
	 */
	@NamespaceAccessible
	public static Boolean nearLimits() {
		return Limits.getQueries() > queryBudget ||
			Limits.getCpuTime() > cpuBudget ||
			Limits.getQueryRows() > rowBudget;
	}

	/** Every installed module's findings, each isolated: how a module's test sees Core reach it. */
	@NamespaceAccessible
	public static List<Finding> extensionFindings() {
		return extensionFindings(new List<String>(), null);
	}

	/**
	 * Findings a dependent package adds through `HealthCheckExtension` (G-20 follow-up,
	 * ADR-0057), isolated the same way a check that throws is: the rest of the report still
	 * stands, and the failure is written to the Error Log rather than shown as this package's
	 * own answer. An extension the run reaches near the limits is added to `skipped` instead;
	 * `only`, when not null, limits the run to those keys.
	 */
	@NamespaceAccessible
	public static List<Finding> extensionFindings(List<String> skipped, Set<String> only) {
		List<Finding> all = new List<Finding>();
		Map<String, HealthCheckExtension> byKey = HealthCheckExtensions.findAll();
		for (String key : byKey.keySet()) {
			if (only != null && !only.contains(key)) {
				continue;
			}
			if (!skipped.isEmpty() || nearLimits()) {
				skipped.add(key);
				continue;
			}
			try {
				List<Finding> extra = byKey.get(key).findings();
				if (extra != null) {
					all.addAll(extra);
				}
			} catch (Exception e) {
				all.add(checkFailed(key, e));
			}
		}
		return all;
	}

	/**
	 * Whether the viewer may change settings, which is also the permission that lets them
	 * see who else is in the org.
	 */
	@NamespaceAccessible
	public static Boolean canManageSettings() {
		return BarnCRMPermissions.canManageSettings();
	}

	/**
	 * The finding that stands in for a check that threw, after writing the failure to the Error
	 * Log. Public so a dependent package's extension can isolate each of its own checks the same
	 * way (C-29, ADR-0059), rather than losing every one of its findings to one failure.
	 */
	@NamespaceAccessible
	public static Finding checkFailed(String checkKey, Exception e) {
		logQuietly(e);
		String detail = String.format(
			BarnHelp.text('Core', 'Core_HealthCheck_CheckFailedDetail'),
			new List<Object>{ checkKey }
		);
		return new Finding(
			'check_failed_' + checkKey,
			System.Label.Core_HealthCheck_CheckFailedTitle,
			detail,
			SEVERITY_WARNING,
			CATEGORY_SETTINGS
		);
	}

	/**
	 * A mode's name as an administrator sees it.
	 */
	@NamespaceAccessible
	public static String modeLabel(String mode) {
		if (CoexistenceService.MODE_NONPROFIT_CLOUD.equals(mode)) {
			return System.Label.Core_CoexistenceMode_NonprofitCloud;
		}
		if (CoexistenceService.MODE_NPSP.equals(mode)) {
			return System.Label.Core_CoexistenceMode_Npsp;
		}
		if (CoexistenceService.MODE_STANDALONE.equals(mode)) {
			return System.Label.Core_CoexistenceMode_Standalone;
		}
		return System.Label.Core_CoexistenceMode_Unset;
	}

	/**
	 * Write one failure to the Error Log without ever letting the writing of it become a
	 * second failure. Canonical model R-E2: a failure to log is swallowed rather than masking
	 * the original error.
	 */
	private static void logQuietly(Exception e) {
		try {
			if (loggerFault != null) {
				throw loggerFault;
			}
			ErrorLogger.log(e, System.Label.Core_HealthCheck_Title);
		} catch (Exception loggingFailed) {
			// Deliberate last resort: ErrorLogger.log itself failed, so the debug log is the only remaining place to note it. Kept intentionally (PMD AvoidDebugStatements finding accepted, not suppressed).
			System.debug(LoggingLevel.ERROR, loggingFailed);
		}
	}
}
