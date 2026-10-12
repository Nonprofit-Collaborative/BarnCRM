/**
 * The seam a dependent package uses to add its own steps, fields and wording to the Setup
 * Assistant without Core depending on it (C-29, ADR-0059; the shape of `HealthCheckExtension`,
 * ADR-0057, under the cross-package mechanism ADR-0017 settled).
 *
 * Core is neutral: it asks only what every organization answers. Giving adds the fund and
 * appeal step, the receipt fields of the identity step and the first gift check. Core finds an
 * implementation by name (`SetupAssistantExtensions.findAll()`) and never calls into a
 * package that is not installed.
 */
@NamespaceAccessible
public interface SetupAssistantExtension {
    /**
     * The steps this package contributes. A step whose key is one of Core's adds its fields to
     * that step and, when it carries a label or description, replaces Core's wording; any other
     * key is a new step, placed by its sort order. Never null.
     */
    List<SetupAssistantService.Step> contributions();
}
