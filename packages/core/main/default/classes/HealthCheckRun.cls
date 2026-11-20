/**
 * The seam through which Core runs a whole Health Check without depending on the Org Optimizer
 * module that holds the runner (ADR-NEXT `NEXT-org-optimizer-and-sample-data-modules.md`,
 * ADR-0057). The module names its class on its catalog row (`BarnCRM_Module.OrgOptimizer`,
 * Extensions: `HealthCheckRun: HealthCheckRunner`), and `HealthCheckService.runInstalled()`
 * finds it through `ModuleExtensions`. Where the module is not installed, there is no runner,
 * and Core says so instead of reporting a clean org.
 */
@NamespaceAccessible
public interface HealthCheckRun {
	/** Every finding of a full run, Core's checks and every installed module's, in reading order. */
	List<HealthCheckService.Finding> findings();
}
