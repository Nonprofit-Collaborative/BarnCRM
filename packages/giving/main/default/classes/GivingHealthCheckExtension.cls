/**
 * The class Core finds by name (in `HealthCheckExtensions.EXTENSION_CLASSES`) and calls to add
 * Giving's findings to the one Health Check report (G-20 follow-up, ADR-0053, ADR-0057).
 *
 * `@NamespaceAccessible` for the same reason `GiftImportProcessor` is: Core resolves it with
 * `Type.forName` under ADR-0017, so it must be a public type with a public no-argument
 * constructor. The class itself does nothing but hand off to `HealthCheckGivingChecks`, which
 * is where the actual questions and their answers live.
 */
@NamespaceAccessible
public with sharing class GivingHealthCheckExtension implements HealthCheckExtension {
    @NamespaceAccessible
    public GivingHealthCheckExtension() {
        return;
    }

    public List<HealthCheckService.Finding> findings() {
        return HealthCheckGivingChecks.findings();
    }
}
