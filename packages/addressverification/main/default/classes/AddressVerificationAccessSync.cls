/**
 * Gives Address Verification Admin to everyone holding BarnCRM Admin (ADR-0209
 * `0209-address-verification-module.md`, decision 8; ADR-0131 module access sync by role). The
 * module has no record of its own, so there is no staff or read only set.
 *
 * It only gives, never takes away. It runs at install, and Core asks it when a role is given on
 * the Access page, at each Turn on and with the hourly access check. Core finds it by its name,
 * the module key followed by `AccessSync` (`ModuleAccessSyncs`), so the class keeps this name.
 */
@NamespaceAccessible
public with sharing class AddressVerificationAccessSync extends ModuleAccessSyncBase {
	public static final String ADMIN_SET = 'Address_Verification_Admin';

	@TestVisible
	private static final Map<String, List<String>> BY_SET = new Map<String, List<String>>{
		ADMIN_SET => new List<String>{ 'BarnCRM_Admin' }
	};

	@NamespaceAccessible
	public AddressVerificationAccessSync() {
		// Built by name from Core (ModuleAccessSyncs), so it needs a public constructor.
	}

	/** One slice now. Returns true when more is left. */
	public static Boolean syncOnce() {
		return new AddressVerificationAccessSync().sync();
	}

	public override String moduleName() {
		return AddressVerifier.MODULE;
	}

	public override String logContext() {
		return 'AddressVerificationAccessSync';
	}

	public override Map<String, List<String>> setsByPermissionSet() {
		return BY_SET;
	}

	public override Map<String, List<String>> setsByRole() {
		return new Map<String, List<String>>();
	}

	public override Integer sliceSize() {
		return 9000;
	}
}
