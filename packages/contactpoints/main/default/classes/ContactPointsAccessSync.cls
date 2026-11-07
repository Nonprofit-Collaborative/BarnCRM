/**
 * Gives Contact Point Sync Admin to everyone holding BarnCRM Admin, directly or through a role
 * (ADR-NEXT contact point sync module, decision 12; ADR-0131 module access sync by role). Staff
 * need nothing: the copy runs in system mode as upkeep (decision 9).
 *
 * It only gives, never takes away. It runs at install (`ContactPointsPostInstall`), and Core asks
 * it at each Turn on and with the hourly access check. Core finds it by its name, the module key
 * followed by `AccessSync` (`ModuleAccessSyncs`), so the class keeps this name. It does nothing
 * while the module is turned off.
 */
@NamespaceAccessible
public with sharing class ContactPointsAccessSync extends ModuleAccessSyncBase {
	/** The module key in the Module Manager. */
	public static final String MODULE_NAME = 'ContactPoints';
	/** The set the installer and BarnCRM Admin holders get. */
	public static final String ADMIN_SET = 'Contact_Point_Sync_Admin';

	@TestVisible
	private static final Map<String, List<String>> BY_SET = new Map<String, List<String>>{
		ADMIN_SET => new List<String>{ 'BarnCRM_Admin' }
	};

	/** Assignments one run gives: well inside the 10,000 DML rows. */
	private static final Integer ROWS_PER_SET = 5000;

	@NamespaceAccessible
	public ContactPointsAccessSync() {
		// Built by name from Core (ModuleAccessSyncs), so it needs a public constructor.
	}

	/** One slice now. Returns true when more is left. */
	public static Boolean syncOnce() {
		return new ContactPointsAccessSync().sync();
	}

	public override String moduleName() {
		return MODULE_NAME;
	}

	public override String logContext() {
		return 'ContactPointsAccessSync';
	}

	public override Map<String, List<String>> setsByPermissionSet() {
		return BY_SET;
	}

	public override Map<String, List<String>> setsByRole() {
		return new Map<String, List<String>>();
	}

	public override Integer sliceSize() {
		return ROWS_PER_SET;
	}
}
