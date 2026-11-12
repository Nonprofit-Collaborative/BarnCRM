/**
 * Gives the Territory Management permission sets to BarnCRM's roles (ADR-0205
 * `0205-territory-management-module.md`, decision 7): Territory Admin to everyone holding BarnCRM
 * Admin, Territory Staff to the Team Member and Fundraising Staff roles, and Territory Read Only
 * to the Read Only role (ADR-0131, D-191).
 *
 * It only gives, never takes away. It runs at install (`TerritoryPostInstall`), and Core asks it
 * when a role is given on the Access page, at each Turn on and with the hourly access check.
 * Core finds it by its name, the module key followed by `AccessSync` (`ModuleAccessSyncs`).
 */
@NamespaceAccessible
public with sharing class TerritoryAccessSync extends ModuleAccessSyncBase {
	public static final String MODULE_NAME = 'Territory';
	public static final String ADMIN_SET = 'Territory_Admin';

	@TestVisible
	private static final Map<String, List<String>> BY_SET = new Map<String, List<String>>{
		ADMIN_SET => new List<String>{ 'BarnCRM_Admin' }
	};

	/** Fundraising Staff is Giving's role, named as text: a role not installed is skipped. */
	@TestVisible
	private static final Map<String, List<String>> BY_ROLE = new Map<String, List<String>>{
		'Territory_Staff' => new List<String>{ 'Program_Staff', 'Fundraising_Staff' },
		'Territory_Read_Only' => new List<String>{ 'Read_Only' }
	};

	@NamespaceAccessible
	public TerritoryAccessSync() {
		// Built by name from Core (ModuleAccessSyncs), so it needs a public constructor.
	}

	/** One slice of each set now. Returns true when more is left. */
	public static Boolean syncOnce() {
		return new TerritoryAccessSync().sync();
	}

	public override String moduleName() {
		return MODULE_NAME;
	}

	public override String logContext() {
		return 'TerritoryAccessSync';
	}

	public override Map<String, List<String>> setsByPermissionSet() {
		return BY_SET;
	}

	public override Map<String, List<String>> setsByRole() {
		return BY_ROLE;
	}

	/** All three sets together stay inside the 10,000 DML rows. */
	public override Integer sliceSize() {
		return 3000;
	}
}
