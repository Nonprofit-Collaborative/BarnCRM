/**
 * Core's access sync for every module (ADR-0131 `0131-module-access-sync-by-role.md`, D-200
 * S1): gives each module's permission sets to the holders of the Core permission sets and of
 * the BarnCRM roles (permission set groups) its catalog row names (`ModuleExtensions`), a slice
 * at a time through `TabAccessService`, then runs the module's `ModuleAccessStep` when it
 * registers one. The Module Manager asks for the one module it turns on, and the Access page and
 * the hourly access check (`TabAccessScheduler`) ask for every one. A module's install asks
 * through `setUp`, which first gives the installer the module's admin sets.
 *
 * It only gives, never takes away: a set may also be given by hand. It does nothing while the
 * module is turned off. A permission set assignment is a setup object write, so every pass is
 * queued and never shares a transaction with the record writes of an install or Turn on (mixed
 * DML). Nothing here throws: a failure is logged and the hourly check tries again.
 */
@NamespaceAccessible
public with sharing class ModuleAccessSyncs {
	/** The Core permission set whose holders, and the installer, get a module's admin sets. */
	private static final String CORE_ADMIN_SET = 'BarnCRM_Admin';

	/** Assignments one pass gives across every set, inside the 10,000 DML rows. */
	private static final Integer ROWS_PER_PASS = 9000;

	/** The most one pass gives for one set. */
	private static final Integer MOST_PER_SET = 5000;

	/** The module keys asked for this transaction, for tests. */
	@TestVisible
	private static List<String> requested = new List<String>();

	/** Queues the named module's sync, when its catalog row names sets. Never throws. */
	@NamespaceAccessible
	public static void requestFor(String moduleName) {
		if (String.isBlank(moduleName)) {
			return;
		}
		for (String key : ModuleExtensions.modulesWithAccess()) {
			if (key.equalsIgnoreCase(moduleName)) {
				enqueue(key, null);
			}
		}
	}

	/** Queues every module's sync, where its catalog row names sets. Never throws. */
	@NamespaceAccessible
	public static void requestAll() {
		for (String key : ModuleExtensions.modulesWithAccess()) {
			enqueue(key, null);
		}
	}

	/**
	 * What a module's install runs: gives the installer the module's admin sets (those its
	 * catalog row gives BarnCRM Admin holders), unless they hold them already, then queues the
	 * sync, which then skips the installer. With no installer, only the sync. Never throws.
	 *
	 * @param moduleKey the module's catalog key, for example `Programs`
	 * @param installerId the person to give the admin sets, or null for nobody
	 */
	@NamespaceAccessible
	public static void setUp(String moduleKey, Id installerId) {
		if (installerId == null) {
			requestFor(moduleKey);
		} else if (String.isNotBlank(moduleKey)) {
			enqueue(moduleKey, installerId);
		}
	}

	/**
	 * One slice of each of the module's sets now, then its own step. Returns true when more is
	 * left. Nothing while the module is turned off.
	 */
	@NamespaceAccessible
	public static Boolean syncOnce(String moduleKey) {
		if (ModuleManagerService.turnedOff().contains(moduleKey.toLowerCase())) {
			return false;
		}
		Map<String, List<String>> bySet = ModuleExtensions.setsByPermissionSet(moduleKey);
		Map<String, List<String>> byRole = ModuleExtensions.setsByRole(moduleKey);
		Integer slice = Math.min(
			MOST_PER_SET,
			ROWS_PER_PASS / Math.max(1, bySet.size() + byRole.size())
		);
		String context = moduleKey + 'AccessSync';
		Boolean more = false;
		for (String setName : bySet.keySet()) {
			Boolean left = TabAccessService.giveToHolders(
				setName,
				bySet.get(setName),
				slice,
				context
			);
			more = more || left;
		}
		for (String setName : byRole.keySet()) {
			Boolean left = TabAccessService.giveToGroupHolders(
				setName,
				byRole.get(setName),
				slice,
				context
			);
			more = more || left;
		}
		try {
			ModuleAccessStep step = (ModuleAccessStep) ModuleExtensions.forModule(
				ModuleAccessStep.class,
				moduleKey
			);
			if (step != null) {
				step.afterSync();
			}
		} catch (Exception e) {
			ErrorLogger.log(e, context);
		}
		return more;
	}

	/** The module's admin sets: those its catalog row gives BarnCRM Admin holders. */
	@NamespaceAccessible
	public static List<String> adminSets(String moduleKey) {
		List<String> sets = new List<String>();
		Map<String, List<String>> bySet = ModuleExtensions.setsByPermissionSet(moduleKey);
		for (String setName : bySet.keySet()) {
			if (bySet.get(setName).contains(CORE_ADMIN_SET)) {
				sets.add(setName);
			}
		}
		return sets;
	}

	private static void enqueue(String moduleKey, Id installerId) {
		requested.add(moduleKey);
		try {
			System.enqueueJob(new Job(moduleKey, installerId));
		} catch (Exception e) {
			ErrorLogger.log(e, moduleKey + 'AccessSync');
		}
	}

	/** Gives the installer each admin set they do not hold yet, in system mode. Never throws. */
	private static void giveInstaller(String moduleKey, Id installerId) {
		String context = moduleKey + 'PostInstall.grantInstallerAccess';
		for (String setName : adminSets(moduleKey)) {
			try {
				PermissionSet permissionSet = SetupObjectSelector.permissionSet(setName);
				if (
					permissionSet == null ||
					[
						SELECT COUNT()
						FROM PermissionSetAssignment
						WHERE AssigneeId = :installerId AND PermissionSetId = :permissionSet.Id
						WITH SYSTEM_MODE
					] > 0
				) {
					continue;
				}
				Database.SaveResult saved = Database.insert(
					new PermissionSetAssignment(
						AssigneeId = installerId,
						PermissionSetId = permissionSet.Id
					),
					false,
					AccessLevel.SYSTEM_MODE
				);
				// A duplicate means another job gave it a moment before: what was wanted.
				for (Database.Error error : saved.getErrors()) {
					if (error.getStatusCode() != StatusCode.DUPLICATE_VALUE) {
						ErrorLogger.logMessage(
							error.getMessage(),
							context,
							ErrorLogger.SEVERITY_WARNING
						);
					}
				}
			} catch (Exception e) {
				ErrorLogger.log(e, context);
			}
		}
	}

	/**
	 * One queued pass for a module, giving the installer first when there is one. It queues
	 * itself again while more is left.
	 */
	@NamespaceAccessible
	public with sharing class Job implements Queueable {
		private final String moduleKey;
		private final Id installerId;

		@NamespaceAccessible
		public Job(String moduleKey, Id installerId) {
			this.moduleKey = moduleKey;
			this.installerId = installerId;
		}

		@NamespaceAccessible
		public void execute(QueueableContext jobContext) {
			try {
				if (installerId != null) {
					giveInstaller(moduleKey, installerId);
				}
				// A test cannot chain one queued job from another.
				if (syncOnce(moduleKey) && !Test.isRunningTest()) {
					System.enqueueJob(new Job(moduleKey, null));
				}
			} catch (Exception e) {
				ErrorLogger.log(e, moduleKey + 'AccessSync');
			}
		}
	}
}
