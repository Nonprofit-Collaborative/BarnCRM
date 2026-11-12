/**
 * Gives the Scholarships permission sets to BarnCRM's roles (ADR-0204
 * `0204-scholarships-outbound-grants-module.md`, decision 13): Scholarships Admin to everyone
 * holding BarnCRM Admin, directly or through a role, Scholarships Staff to the Team Member and
 * Fundraising Staff roles, and Scholarships Read Only to the Read Only role (ADR-0131, D-191).
 *
 * It only gives, never takes away. It runs at install (`ScholarshipsPostInstall`), and Core asks
 * it when a role is given on the Access page, at each Turn on and with the hourly access check.
 * Core finds it by its name, the module key followed by `AccessSync` (`ModuleAccessSyncs`).
 */
@NamespaceAccessible
public with sharing class ScholarshipsAccessSync extends ModuleAccessSyncBase {
	/** The module key in the Module Manager. */
	public static final String MODULE_NAME = 'Scholarships';
	/** The set BarnCRM Admin holders get. */
	public static final String ADMIN_SET = 'Scholarships_Admin';

	@TestVisible
	private static final Map<String, List<String>> BY_SET = new Map<String, List<String>>{
		ADMIN_SET => new List<String>{ 'BarnCRM_Admin' }
	};

	/** Fundraising Staff is Giving's role, named as text: a role not installed is skipped. */
	@TestVisible
	private static final Map<String, List<String>> BY_ROLE = new Map<String, List<String>>{
		'Scholarships_Staff' => new List<String>{ 'Program_Staff', 'Fundraising_Staff' },
		'Scholarships_Read_Only' => new List<String>{ 'Read_Only' }
	};

	@NamespaceAccessible
	public ScholarshipsAccessSync() {
		// Built by name from Core (ModuleAccessSyncs), so it needs a public constructor.
	}

	public override String moduleName() {
		return MODULE_NAME;
	}

	public override String logContext() {
		return 'ScholarshipsAccessSync';
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
