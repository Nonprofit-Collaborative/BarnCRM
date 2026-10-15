/**
 * The fixes a dependent package's Health Check findings offer, run by Core's Health Check under
 * every ADR-0048 condition (ADR-0125, `0125-rollup-builder-module.md`). A `HealthCheckExtension`
 * that also implements this interface owns the fix keys it answers for: Core asks it only for a
 * key none of its own fixes has.
 *
 * Core keeps the rest: the permission check, the comparison of the confirmed scope with the scope
 * now, the savepoint, the change history row and the re-run report.
 */
@NamespaceAccessible
public interface HealthCheckFixExtension {
    /**
     * What this fix would change if it ran now, as names the administrator reads in the confirm
     * box. Empty when it would change nothing, null for a key this extension does not own.
     */
    List<String> fixScope(String fixKey);

    /** The button label of this fix, which also names it in the change history; null if unknown. */
    String fixLabel(String fixKey);

    /** Runs the fix on exactly this scope and returns the sentence that says what it did. */
    String runFix(String fixKey, List<String> scope);
}
