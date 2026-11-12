/**
 * The Outbound Funds kit's rows (MIG-11, canonical model R-MK1), named by the kit
 * `Outbound_Funds`. Outbound Funds has no cycles, so each funding program becomes a program and
 * one cycle of it, and an awarded funding request becomes an application and its award. Those
 * steps read the record's own Id twice: once as the row's key, which later steps link to, and
 * once, as the column this class adds, linked to the earlier step's record. Every other step
 * keeps the default rows. Outbound Funds is read by describe only: its names are text in the
 * kit. Core builds this class by name, so it and its constructor are namespace-accessible
 * (ADR-0017).
 */
@NamespaceAccessible
public with sharing class OutboundFundsKit implements MigrationKitExtension {
	@TestVisible
	private static final String KIT = 'Outbound_Funds';
	/** The column a cycle or award links to its program or application by. */
	@TestVisible
	private static final String PARENT_COLUMN = 'Parent';

	@NamespaceAccessible
	public OutboundFundsKit() {
		// Built by name from the kit's Extension Class; holds no state.
		return;
	}

	@NamespaceAccessible
	public List<Map<String, Object>> rows(String stepKey, List<SObject> records) {
		if (stepKey != 'cycles' && stepKey != 'awards') {
			return null;
		}
		List<Map<String, Object>> rows = new MigrationKitService.Source(
				MigrationKitService.stepNamed(MigrationKitService.kitNamed(KIT), stepKey)
			)
			.rows(records);
		linkToParent(rows);
		return rows;
	}

	/** Each row's own Id again, as the column its link to the earlier step reads. */
	@TestVisible
	private static void linkToParent(List<Map<String, Object>> rows) {
		for (Map<String, Object> row : rows) {
			row.put(PARENT_COLUMN, row.get('Id'));
		}
	}

	@NamespaceAccessible
	public MigrationCheck verify(String stepKey) {
		// Every step keeps one row per record, so the Assistant's own counts are the check.
		return null;
	}
}
