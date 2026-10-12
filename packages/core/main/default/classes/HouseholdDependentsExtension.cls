/**
 * The seam a dependent package uses to keep a household the empty household tidy-up would
 * otherwise delete (R-H12, ADR-NEXT `NEXT-empty-household-tidy-up-keeps-households-with-gifts.md`),
 * under the cross-package mechanism ADR-0017 settled and in the shape of `HealthCheckExtension`.
 *
 * Core is neutral and may not know what the dependent package's records are. It looks up an
 * implementation by name (`HouseholdDependentsExtensions`) and asks it before deleting; where
 * none is installed, nothing is asked.
 */
@NamespaceAccessible
public interface HouseholdDependentsExtension {
    /**
     * Of these household identifiers, the ones this package still credits records to, read
     * in system mode so that a record the running user cannot see still counts. Never null;
     * an empty set means none.
     */
    Set<Id> householdsWithDependents(Set<Id> householdIds);
}
