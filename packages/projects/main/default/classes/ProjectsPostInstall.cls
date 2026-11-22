/**
 * What the BarnCRM Project Management module does at install and at every upgrade (ADR-0208
 * `0208-project-management-module.md`). Each step is safe to run twice and none can abort an
 * install, since every failure is written to the Error Log instead:
 *
 * 1. Queue `ModuleAccessSyncs`, which gives Projects Admin to every BarnCRM Admin holder (the
 *    installer among them, given BarnCRM Admin by Core's own install) and the other sets to
 *    BarnCRM's roles. Queued, since a permission set assignment is a setup object write.
 * 2. Start `ProjectCostSync`, which fills each project's stored Actual Cost (a project saved
 *    before the field existed has none until then).
 *
 * The settings need no step: an unsaved setting reads its shipped default from its Setting
 * Definition, and Invoice payment return page reads the org's My Domain address while blank
 * (ADR-0238 settings as custom metadata). The steps are `runSetup`, which also adds the module
 * to Core's setup marker and is what Finish Setup runs for a module copied into an org by hand
 * (`ModuleSetups`).
 */
@NamespaceAccessible
public with sharing class ProjectsPostInstall implements InstallHandler, ModuleSetup {
	public static final String MODULE_KEY = 'Projects';

	@NamespaceAccessible
	public ProjectsPostInstall() {
		// Built by name from Core (`ModuleSetups`) for Finish Setup, so it needs a public constructor.
	}

	/** Called by the platform after the module is installed or upgraded. */
	public void onInstall(InstallContext context) {
		if (context != null) {
			runSetup(context.installerId());
		}
	}

	/** The install's steps, then the module's key added to the setup marker. Never throws. */
	public void runSetup(Id installerId) {
		ModuleSetups.markRan(MODULE_KEY);
		try {
			ModuleAccessSyncs.requestFor(MODULE_KEY);
		} catch (Exception e) {
			ErrorLogger.log(e, 'ProjectsPostInstall');
		}
		ProjectCostSync.startPass();
	}
}
