/**
 * What the BarnCRM Connector module does at install and at every upgrade (CN-01). Safe to run
 * twice; a failure is logged, never raised: the installer gets BarnCRM Connector Admin, then
 * BarnCRM Admin holders do (`ModuleAccessSyncs`), both queued because an assignment is a setup
 * object write. No connection, template or key is created: an org holds only the connections
 * its admin makes (D-216).
 */
@NamespaceAccessible
public with sharing class ConnectorPostInstall implements InstallHandler, ModuleSetup {
	public void onInstall(InstallContext context) {
		if (context != null) {
			runSetup(context.installerId());
		}
	}

	/** Built by name from Core (`ModuleSetups`) for Finish Setup, so it needs a public constructor. */
	@NamespaceAccessible
	public ConnectorPostInstall() {
		// Nothing to set up: every step runs in runSetup.
	}

	public void runSetup(Id installerId) {
		ModuleSetups.markRan(ConnectorConnections.MODULE);
		ModuleAccessSyncs.setUp(ConnectorConnections.MODULE, installerId);
	}
}
