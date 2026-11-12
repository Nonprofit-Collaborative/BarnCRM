/**
 * Gives Giving Admin to everyone holding BarnCRM Admin, directly or through the BarnCRM Admin
 * role, as every other module gives its Admin set (ADR-0194, simpler permission sets, D2).
 * Giving Staff and Giving Read Only stay per person on the Access page, except Giving Staff inside
 * the Fundraising Staff role: donor amounts, receipts and tax statements are given deliberately.
 *
 * It only gives, never takes away. It runs at install and upgrade (`GivingPostInstall`), and Core
 * asks it when a role is given on the Access page, at each Turn on and with the hourly access
 * check. Core finds it by its name, the module key followed by `AccessSync` (`ModuleAccessSyncs`),
 * so the class keeps this name. It does nothing while the module is turned off.
 */
@NamespaceAccessible
public with sharing class GivingAccessSync extends ModuleAccessSyncBase {
	/** The module key in the Module Manager. */
	public static final String MODULE_NAME = 'Giving';
	/** The set BarnCRM Admin holders get. */
	public static final String ADMIN_SET = 'Giving_Admin';

	/** The Admin set, and the Core permission set whose holders get it. */
	@TestVisible
	private static final Map<String, List<String>> BY_SET = new Map<String, List<String>>{
		ADMIN_SET => new List<String>{ 'BarnCRM_Admin' }
	};

	/** Assignments one run gives: one set, well inside the 10,000 DML rows. */
	private static final Integer ROWS_PER_SET = 5000;

	@NamespaceAccessible
	public GivingAccessSync() {
		// Built by name from Core (ModuleAccessSyncs), so it needs a public constructor.
	}

	/** One slice now. Returns true when more is left. */
	public static Boolean syncOnce() {
		return new GivingAccessSync().sync();
	}

	public override String moduleName() {
		return MODULE_NAME;
	}

	public override String logContext() {
		return 'GivingAccessSync';
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
