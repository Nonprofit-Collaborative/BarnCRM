/**
 * What the BarnCRM Corporate Hub module does at install and at every upgrade (ADR-0196
 * `0196-corporate-hub-module.md`).
 *
 * Each step is safe to run twice and none can abort an install, since every failure is written
 * to the Error Log instead:
 *
 * 1. Load each shipped template the org has no record for (`HubTemplates`, R-CT1), owned by the
 *    installer: obligations Off, policies Draft. An upgrade adds new templates only.
 * 2. Queue the job that gives the installer Corporate Hub Admin (a permission set assignment is a
 *    setup object write, and this transaction may already have written ordinary records).
 * 3. Give the Corporate Hub sets to BarnCRM's roles (`ModuleAccessSyncs`), queued for the
 *    same reason; the installer's job runs it after its own grant.
 *
 * The steps are `runSetup`, which also adds the module to Core's setup marker and is what Finish
 * Setup runs for a module copied into an org by hand (`ModuleSetups`).
 */
@NamespaceAccessible
public with sharing class CorporateHubPostInstall implements InstallHandler, ModuleSetup {
	public static final String MODULE_KEY = 'CorporateHub';
	private static final String TEMPLATE_CONTEXT = 'CorporateHubPostInstall.loadTemplates';

	/** Called by the platform after the module is installed or upgraded. */
	public void onInstall(InstallContext context) {
		if (context == null) {
			return;
		}
		runSetup(context.installerId());
	}

	/** Built by name from Core (`ModuleSetups`) for Finish Setup, so it needs a public constructor. */
	@NamespaceAccessible
	public CorporateHubPostInstall() {
		// Nothing to set up: every step runs in runSetup.
	}

	/**
	 * The install's steps, with the given person standing in for the installer, then the module's
	 * key added to the setup marker. Never throws.
	 */
	public void runSetup(Id installerId) {
		try {
			HubTemplates.loadMissing(installerId, true);
		} catch (Exception e) {
			ErrorLogger.log(e, TEMPLATE_CONTEXT);
		}
		ModuleSetups.markRan(MODULE_KEY);
		ModuleAccessSyncs.setUp(MODULE_KEY, installerId);
	}
}
