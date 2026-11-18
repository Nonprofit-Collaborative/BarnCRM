/**
 * What BarnCRM Mirror does for itself at install and at every upgrade: add the module to Core's
 * setup marker. Mirror registers no automation switch since the gift mirrors moved to BarnCRM
 * Fundraising (ADR-NEXT mirror independence; `GivingPostInstall` creates their switches), and it creates
 * no `Mirror_Settings__c`: Send Cases to a service provider's field default of false already reads
 * as off. The hourly Case check is scheduled by the nightly run's step once that setting is on,
 * never at install, so an org that does not send Cases keeps no scheduled job for it.
 *
 * The step is `runSetup`, which is also what Finish Setup runs for a module copied into an org by
 * hand (FS1, `ModuleSetups`). It never throws.
 */
@NamespaceAccessible
public with sharing class MirrorPostInstall implements InstallHandler, ModuleSetup {
	/** The module's key in the module catalog and the setup marker. */
	private static final String MODULE_KEY = 'Mirror';

	/**
	 * Called by the platform after the package is installed or upgraded.
	 *
	 * @param context what the platform knows about this install, unused here because the
	 *        marker belongs to the org rather than to whoever pressed Install
	 */
	public void onInstall(InstallContext context) {
		runSetup(null);
	}

	/** Built by name from Core (`ModuleSetups`) for Finish Setup, so it needs a public constructor. */
	@NamespaceAccessible
	public MirrorPostInstall() {
		// Nothing to set up: the step runs in runSetup.
	}

	/**
	 * Adds the module's key to the setup marker. Never throws.
	 *
	 * @param installerId unused: the marker belongs to the org, not to a person
	 */
	public void runSetup(Id installerId) {
		ModuleSetups.markRan(MODULE_KEY);
	}
}
