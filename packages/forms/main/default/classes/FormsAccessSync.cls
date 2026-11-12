/**
 * Gives the Forms permission sets to BarnCRM's roles (ADR-0175 `0175-forms-module.md`, decision
 * 11): Forms Admin to everyone holding BarnCRM Admin, directly or through a role, Forms Staff to
 * the Team Member and Coordinator roles, and Forms Read Only to the Read Only role. The roles are
 * permission set groups, followed through `TabAccessService.giveToGroupHolders` (ADR-0131
 * `0131-module-access-sync-by-role.md`).
 *
 * It only gives, never takes away. It runs at install (`FormsPostInstall`), and Core asks it when
 * a role is given on the Access page, at each Turn on and with the hourly access check. Core finds
 * it by its name, the module key followed by `AccessSync` (`ModuleAccessSyncs`), so the class
 * keeps this name. It does nothing while the module is turned off.
 */
@NamespaceAccessible
public with sharing class FormsAccessSync extends ModuleAccessSyncBase {
	/** The module key in the Module Manager. */
	public static final String MODULE_NAME = 'Forms';
	/** The set the installer and BarnCRM Admin holders get. */
	public static final String ADMIN_SET = 'Forms_Admin';

	/** The Admin set, and the Core permission set whose holders get it. */
	@TestVisible
	private static final Map<String, List<String>> BY_SET = new Map<String, List<String>>{
		ADMIN_SET => new List<String>{ 'BarnCRM_Admin' }
	};

	/**
	 * Each other set, and the BarnCRM roles (permission set groups) whose holders get it. Fundraising
	 * Staff is Giving's role, named as text: a role that is not installed is skipped (ADR-0194 D3).
	 * Coordinator is retired and dropped in the next release (D1).
	 */
	@TestVisible
	private static final Map<String, List<String>> BY_ROLE = new Map<String, List<String>>{
		'Forms_Staff' => new List<String>{
			'Program_Staff',
			'Volunteer_Coordinator',
			'Fundraising_Staff'
		},
		'Forms_Read_Only' => new List<String>{ 'Read_Only' }
	};

	/** Assignments one run gives per set: all three together stay inside the 10,000 DML rows. */
	private static final Integer ROWS_PER_SET = 3000;

	@NamespaceAccessible
	public FormsAccessSync() {
		// Built by name from Core (ModuleAccessSyncs), so it needs a public constructor.
	}

	/** One slice of each set now. Returns true when more is left. */
	public static Boolean syncOnce() {
		return new FormsAccessSync().sync();
	}

	public override String moduleName() {
		return MODULE_NAME;
	}

	public override String logContext() {
		return 'FormsAccessSync';
	}

	public override Map<String, List<String>> setsByPermissionSet() {
		return BY_SET;
	}

	public override Map<String, List<String>> setsByRole() {
		return BY_ROLE;
	}

	public override Integer sliceSize() {
		return ROWS_PER_SET;
	}
}
