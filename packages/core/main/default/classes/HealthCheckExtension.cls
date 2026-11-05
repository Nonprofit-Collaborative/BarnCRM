/**
 * The seam a dependent package uses to add its own findings to the one Health Check report,
 * without Core depending on it (G-20 follow-up, ADR-0053, ADR-0057; the same shape as
 * `ImportEntityProcessor`, R-IR6, under the cross-package mechanism ADR-0017 settled).
 *
 * Core is neutral (plan Section 4.1, C-29): it may not know what a gift is or what an
 * accounting period is, so a finding about posting or a closed period cannot be written here.
 * Core never calls into Giving to find this; it looks up an implementation by name with
 * `Type.forName` (`HealthCheckExtensions.findAll()`) and calls it if one is installed. Where none
 * is, `findings()` is never invoked and nothing is missing: an org without Giving has nothing
 * to say about posting.
 */
@NamespaceAccessible
public interface HealthCheckExtension {
	/**
	 * Every finding this package adds to the report, already limited to what the running
	 * viewer may see (Health Check's own rule: only a viewer who may manage settings is asked
	 * a question that only they can be trusted to answer correctly). Never null; an empty
	 * list means nothing to report.
	 */
	List<HealthCheckService.Finding> findings();
}
