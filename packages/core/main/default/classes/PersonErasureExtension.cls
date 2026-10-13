/**
 * The seam a dependent package uses to decide what erasing a person does to its own records
 * (canonical model R-ER8; ADR-NEXT `NEXT-erase-a-person-anonymizes-in-place.md`), in the shape
 * of `HouseholdDependentsExtension` (ADR-0017, ADR-0070). Core is neutral and may not know what
 * a module's records are: it looks implementations up by name (`PersonErasureExtensions`) and
 * asks each one inside the erasure's own transaction.
 */
@NamespaceAccessible
public interface PersonErasureExtension {
    /**
     * Fields of the person's own record (Contact, or Account for a person account) that this
     * package maintains as anonymous aggregates and that the erasure must keep, for example a
     * donor level. Never null; empty means none.
     */
    Set<Schema.SObjectField> fieldsToKeep(Schema.SObjectType personType);

    /**
     * Changes this package's own records about the person, in the caller's transaction and with
     * the user's own access, and answers what it changed and what it kept. Never null. A throw
     * refuses the whole erasure, which is then rolled back. Also called by the preview, whose
     * changes are rolled back.
     */
    List<PersonErasure.Change> erase(Id personId);
}
