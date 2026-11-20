/**
 * The seam a migration kit uses when its JSON steps are not enough (MIG-01, ADR-0197
 * migration-assistant decision 3, the shape of ADR-0057). A kit names the class in its Extension
 * Class field; the Migration Assistant (the Migration package, ADR-0232) finds
 * it by name with `NamespaceUtil.build` and calls it only when it is installed. Core holds only
 * this interface and `MigrationCheck`, so a kit's package needs neither the Assistant nor any
 * other module.
 */
@NamespaceAccessible
public interface MigrationKitExtension {
	/**
	 * One page of an import step's staged rows, reshaped: `rows` holds one row per source record,
	 * keyed by the field names as the step writes them, the values as text. Return the rows to
	 * stage, keyed by the column names the step's import template maps (more or fewer than
	 * given), or null to stage `rows` as they are. Changing `rows` in place and returning them is
	 * fine.
	 */
	List<Map<String, Object>> rows(String stepKey, List<Map<String, Object>> rows);

	/**
	 * The kit's own check of a step: how many there are to move and how many are moved, or null
	 * when the step has no check of its own.
	 */
	MigrationCheck verify(String stepKey);
}
