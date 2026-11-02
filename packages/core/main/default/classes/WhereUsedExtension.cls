/**
 * The seam a dependent package uses to add its own setup records to Where Used (C-59), without
 * Core depending on it: the same mechanism as `HealthCheckExtension` (ADR-0017, ADR-0057), found
 * by `WhereUsedExtensions` with `Type.forName` (ADR-0159, `0159-where-used-extension.md`).
 *
 * An implementation lists the records of its own that name the target, using the target's
 * `matchesPath`, `matchesFilter` and `isObject` so every package reads a field path the same way.
 * It reads in system mode (the controller has already checked Manage BarnCRM Settings) and
 * returns label text, never keys Core would have to translate.
 */
@NamespaceAccessible
public interface WhereUsedExtension {
    /** Every record of this package that names the target; never null. */
    List<WhereUsedService.Reference> references(WhereUsedService.Target target);
}
