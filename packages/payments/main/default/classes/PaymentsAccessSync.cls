/**
 * Gives the Payments permission sets to BarnCRM's roles (ADR-0201 `0201-payments-module.md`,
 * decision 9; ADR-0131 module access sync by role): Payments Admin to everyone holding BarnCRM
 * Admin, Payments Staff to the Team Member role and Giving's Fundraising Staff role, Payments
 * Read Only to the Read Only role.
 *
 * It only gives, never takes away. It runs at install (`PaymentsPostInstall`), and Core asks it
 * when a role is given on the Access page, at each Turn on and with the hourly access check. Core
 * finds it by its name, the module key followed by `AccessSync` (`ModuleAccessSyncs`), so the
 * class keeps this name. It does nothing while the module is turned off.
 */
@NamespaceAccessible
public with sharing class PaymentsAccessSync extends ModuleAccessSyncBase {
	/** The module key in the Module Manager. */
	public static final String MODULE_NAME = 'Payments';
	/** The set the installer and BarnCRM Admin holders get. */
	public static final String ADMIN_SET = 'Payments_Admin';

	@TestVisible
	private static final Map<String, List<String>> BY_SET = new Map<String, List<String>>{
		ADMIN_SET => new List<String>{ 'BarnCRM_Admin' }
	};

	/** Fundraising Staff is Giving's role, named as text: a role not installed is skipped. */
	@TestVisible
	private static final Map<String, List<String>> BY_ROLE = new Map<String, List<String>>{
		'Payments_Staff' => new List<String>{ 'Program_Staff', 'Fundraising_Staff' },
		'Payments_Read_Only' => new List<String>{ 'Read_Only' }
	};

	/** Assignments one run gives per set: all three together stay inside the 10,000 DML rows. */
	private static final Integer ROWS_PER_SET = 3000;

	@NamespaceAccessible
	public PaymentsAccessSync() {
		// Built by name from Core (ModuleAccessSyncs), so it needs a public constructor.
	}

	/** One slice of each set now. Returns true when more is left. */
	public static Boolean syncOnce() {
		return new PaymentsAccessSync().sync();
	}

	public override String moduleName() {
		return MODULE_NAME;
	}

	public override String logContext() {
		return 'PaymentsAccessSync';
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
