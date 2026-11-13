/**
 * Which BarnCRM packages have run their setup steps, and Finish Setup for any that have not
 * (FS1).
 *
 * BarnCRM is installed as packages. Each package's post-install class runs its setup steps at
 * install and at every upgrade, and `scripts/org/deploy-packages.sh` runs the same steps in a
 * development org. Source copied into an org by hand runs none of them. So each post-install
 * class implements `ModuleSetup` and, at the end of its steps, adds its package's key to
 * `Modules_Setup_Run__c` (`markRan`). A package that is here, ships such a class and is not
 * listed is reported by Health Check and flagged on the Modules page, and Finish Setup runs that
 * class's steps, which are the install's own and safe to run twice.
 *
 * Found by convention, as `ModuleAccessSyncs` finds a module's sync, so Core names no module
 * class: the class named after the package's key (`Core`, or the module catalog's name)
 * followed by `PostInstall`. A package version from before FS1 has no class that implements
 * `ModuleSetup`, so it is never flagged; its next upgrade runs its steps and adds its key. That
 * is the backfill: an org that ran setup before this change keeps a clean report.
 *
 * The marker is per package key and setup revision (D-200, N4): `Giving` means revision 1,
 * `Giving:2` revision 2. A post-install class that gains steps implements `Revisioned` and
 * raises its revision, so an org whose marker holds an older revision (an upgrade whose
 * post-install failed, or source copied in) is flagged again until those steps run. A class
 * that does not implement it is revision 1.
 */
@NamespaceAccessible
public with sharing class ModuleSetups {
	/**
	 * A post-install class whose setup steps have changed since its first version. Raise the
	 * number whenever the steps gain something an existing org needs; never lower it.
	 */
	@NamespaceAccessible
	public interface Revisioned {
		/** The current revision of the setup steps, 2 or more (1 is a class without this). */
		Integer setupRevision();
	}

	private static final String REVISION_SEPARATOR = ':';

	/** The suffix after the package key that names its post-install class. */
	@NamespaceAccessible
	public static final String CLASS_SUFFIX = 'PostInstall';

	/** Core's key, which the module catalog does not list. */
	@NamespaceAccessible
	public static final String CORE = 'Core';

	/** The Health Check fix key of Finish Setup. */
	public static final String FIX_KEY = 'finishModuleSetup';

	private static final String MARKER_KEY = 'Modules_Setup_Run__c';
	/** The Error Log context of a setup step that failed; the Hub counts it as an install problem. */
	public static final String CONTEXT = 'ModuleSetups';

	/** Injected by Core's tests by package key, since no module is there to resolve. */
	@TestVisible
	private static Map<String, ModuleSetup> overrides = new Map<String, ModuleSetup>();

	/** Set by Core's tests to see no setup class beyond those injected. */
	@TestVisible
	private static Boolean noneForTest = false;

	/**
	 * Health Check asks only when a test does: Core's own post-install class is always here and
	 * a test org has run no setup, so every other test's report would carry the finding.
	 */
	@TestVisible
	private static Boolean checkInTests = false;

	/**
	 * Records that a package's setup steps have run. Bookkeeping, with no audit row. Never
	 * throws: an install must not fail over its marker.
	 */
	@NamespaceAccessible
	public static void markRan(String moduleKey) {
		try {
			if (String.isBlank(moduleKey)) {
				return;
			}
			String key = moduleKey.trim();
			Integer revision = revisionOf(key);
			List<String> entries = new List<String>();
			for (String entry : stored()) {
				if (!entry.substringBefore(REVISION_SEPARATOR).equalsIgnoreCase(key)) {
					entries.add(entry);
				} else if (revisionIn(entry) >= revision) {
					return;
				}
			}
			entries.add(revision > 1 ? key + REVISION_SEPARATOR + revision : key);
			SettingsService.saveBookkeeping(
				new Map<String, Object>{ MARKER_KEY => String.join(entries, ',') }
			);
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT);
		}
	}

	/**
	 * The keys of the packages whose setup has run at their current revision, lower case. A key
	 * marked at an older revision than its post-install class now declares is left out.
	 */
	@NamespaceAccessible
	public static Set<String> ran() {
		Set<String> keys = new Set<String>();
		for (String entry : stored()) {
			String key = entry.substringBefore(REVISION_SEPARATOR);
			if (revisionIn(entry) >= revisionOf(key)) {
				keys.add(key.toLowerCase());
			}
		}
		return keys;
	}

	/** The revision a marker entry records: the number after the separator, else 1. */
	private static Integer revisionIn(String entry) {
		String digits = entry.substringAfter(REVISION_SEPARATOR).trim();
		return digits.isNumeric() ? Integer.valueOf(digits) : 1;
	}

	/** The revision the package's setup class declares now, 1 when it declares none. */
	private static Integer revisionOf(String moduleKey) {
		ModuleSetup setup = setupFor(moduleKey);
		Integer revision = setup instanceof Revisioned
			? ((Revisioned) setup).setupRevision()
			: null;
		return revision == null || revision < 1 ? 1 : revision;
	}

	private static List<String> stored() {
		List<String> keys = new List<String>();
		String value = SettingsService.getSettings().Modules_Setup_Run__c;
		for (String part : String.isBlank(value) ? new List<String>() : value.split(',')) {
			if (String.isNotBlank(part)) {
				keys.add(part.trim());
			}
		}
		return keys;
	}

	/**
	 * True when a package that is here never ran its setup: it ships setup steps and its key is
	 * not in `ranKeys` (from `ran()`).
	 */
	public static Boolean isPending(String moduleKey, Set<String> ranKeys) {
		return String.isNotBlank(moduleKey) &&
			!ranKeys.contains(moduleKey.toLowerCase()) &&
			setupFor(moduleKey) != null;
	}

	/** The packages here whose setup never ran, Core first, in the Module Manager's order. */
	public static List<ModuleDetectionService.ModuleInfo> pending() {
		List<ModuleDetectionService.ModuleInfo> found = new List<ModuleDetectionService.ModuleInfo>();
		Set<String> ranKeys = ran();
		for (ModuleDetectionService.ModuleInfo info : ModuleDetectionService.getModules()) {
			if (info.present == true && isPending(info.name, ranKeys)) {
				found.add(info);
			}
		}
		return found;
	}

	/** The names shown of those packages: what the Health Check finding and its fix name. */
	public static List<String> pendingLabels() {
		List<String> labels = new List<String>();
		for (ModuleDetectionService.ModuleInfo info : pending()) {
			labels.add(info.label);
		}
		return labels;
	}

	/**
	 * Finish Setup: runs the setup steps of each named package that is here, Core first, as its
	 * install would, with the person pressing it standing in for the installer, then marks it.
	 * Safe to run twice. A name that is not a package here with setup steps is refused before
	 * anything runs. The caller checks Manage BarnCRM Settings.
	 *
	 * @param moduleKeys package keys, such as Core or Giving
	 * @return the names shown of the packages whose steps ran
	 */
	public static List<String> finish(List<String> moduleKeys) {
		Set<String> wanted = new Set<String>();
		for (String key : moduleKeys == null ? new List<String>() : moduleKeys) {
			if (String.isNotBlank(key)) {
				wanted.add(key.trim());
			}
		}
		List<ModuleDetectionService.ModuleInfo> toRun = new List<ModuleDetectionService.ModuleInfo>();
		for (ModuleDetectionService.ModuleInfo info : ModuleDetectionService.getModules()) {
			if (info.present == true && wanted.contains(info.name) && setupFor(info.name) != null) {
				wanted.remove(info.name);
				toRun.add(info);
			}
		}
		if (!wanted.isEmpty() || toRun.isEmpty()) {
			throw new ModuleManagerService.ModuleManagerException(
				BarnHelp.text('Core', 'Core_ModuleManager_UnknownModuleError')
			);
		}
		List<String> done = new List<String>();
		for (ModuleDetectionService.ModuleInfo info : toRun) {
			setupFor(info.name).runSetup(UserInfo.getUserId());
			markRan(info.name);
			done.add(info.label);
		}
		return done;
	}

	/** Finish Setup from Health Check: the packages named as the finding shows them. */
	public static List<String> finishByLabel(List<String> labels) {
		List<String> keys = new List<String>();
		for (ModuleDetectionService.ModuleInfo info : pending()) {
			if (labels != null && labels.contains(info.label)) {
				keys.add(info.name);
			}
		}
		return finish(keys);
	}

	/** The package's setup, or null when this version of it ships none Core can run. */
	private static ModuleSetup setupFor(String moduleKey) {
		if (overrides.containsKey(moduleKey)) {
			return overrides.get(moduleKey);
		}
		if (noneForTest == true) {
			return null;
		}
		try {
			Type setupType = NamespaceUtil.resolveType(moduleKey + CLASS_SUFFIX);
			if (setupType == null) {
				return null;
			}
			Object candidate = setupType.newInstance();
			return candidate instanceof ModuleSetup ? (ModuleSetup) candidate : null;
		} catch (Exception cannotBuild) {
			ErrorLogger.log(cannotBuild, CONTEXT);
			return null;
		}
	}

	/**
	 * The Health Check finding: packages here whose setup never ran, with Finish Setup as its
	 * fix. Asked only for a viewer who may manage settings, who alone can press it.
	 */
	public class SetupCheck implements HealthCheckService.Check {
		public HealthCheckService.Finding run() {
			if (Test.isRunningTest() && checkInTests != true) {
				return null;
			}
			List<String> names = pendingLabels();
			if (names.isEmpty()) {
				return null;
			}
			List<Object> values = new List<Object>{
				String.valueOf(names.size()),
				String.join(names, ', ')
			};
			return new HealthCheckService.Finding(
					'module_setup_not_run',
					HealthCheckService.forCount(
						names.size(),
						System.Label.Core_ModuleSetup_FindingTitleOne,
						System.Label.Core_ModuleSetup_FindingTitle,
						values
					),
					String.format(BarnHelp.text('Core', 'Core_ModuleSetup_FindingDetail'), values),
					HealthCheckService.SEVERITY_WARNING,
					HealthCheckService.CATEGORY_SETTINGS
				)
				.withScope(names)
				.withFix(
					System.Label.Core_ModuleSetup_FinishButton,
					HealthCheckService.FIX_ACTION_PREFIX + FIX_KEY
				);
		}
	}
}
