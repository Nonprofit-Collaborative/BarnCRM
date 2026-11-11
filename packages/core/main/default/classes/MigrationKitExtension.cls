/**
 * The seam a migration kit uses when its JSON steps are not enough (MIG-01, ADR-NEXT
 * migration-assistant decision 3, the shape of ADR-0057). A kit names the class in its Extension
 * Class field; Core finds it by name with `NamespaceUtil.build` and calls it only when it is
 * installed, so Core never depends on the module that ships the kit.
 */
@NamespaceAccessible
public interface MigrationKitExtension {
	/**
	 * The staged rows for one page of an import step's source records, each keyed by the column
	 * names the step's import template maps, or null to stage one row per record as the step's
	 * fields read it. May return more or fewer rows than records.
	 */
	List<Map<String, Object>> rows(String stepKey, List<SObject> records);

	/**
	 * The kit's own check of a step: how many there are to move and how many are moved, or null
	 * when the step has no check of its own.
	 */
	MigrationCheck verify(String stepKey);
}
