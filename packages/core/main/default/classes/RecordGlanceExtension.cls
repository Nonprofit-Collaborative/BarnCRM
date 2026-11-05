/**
 * The seam a dependent package uses to add a small card to Core's Contact and Account record
 * pages without Core depending on it (people-14; ADR-NEXT `NEXT-record-glance-extension.md`).
 * Found by `RecordGlanceExtensions` with `NamespaceUtil.resolveType`, the mechanism of
 * `HealthCheckExtensions` (ADR-0057) and `WhereUsedExtensions` (ADR-0159).
 *
 * An implementation reads with the viewing person's own access and returns null when it has
 * nothing to show for the record, or when that person may not see it.
 */
@NamespaceAccessible
public interface RecordGlanceExtension {
    /** The card for one Contact or Account, or null. */
    RecordGlance.Card glance(Id recordId);
}
