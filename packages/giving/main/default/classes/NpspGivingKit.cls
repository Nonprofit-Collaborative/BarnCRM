/**
 * The NPSP Funds, Levels and Recurring Donations kit's rows (MIG-05, canonical model R-MK1),
 * named by the kit `NPSP_Giving_Setup`. A BarnCRM recurring commitment schedules its payments
 * from its start, so a recurring donation starts at NPSP's next payment date when it has one,
 * not at the date it was established years ago (which would make a run of overdue payments).
 * Every other step keeps the default rows. NPSP is read by describe only: its field names are
 * text here. Core builds this class by name, so it and its constructor are namespace-accessible
 * (ADR-0017).
 */
@NamespaceAccessible
public with sharing class NpspGivingKit implements MigrationKitExtension {
	@TestVisible
	private static final String KIT = 'NPSP_Giving_Setup';
	/** The column the recurring templates map to Start Date, which NPSP has no one field for. */
	@TestVisible
	private static final String START_COLUMN = 'Start';
	/** The recurring steps' columns as the kit writes them, read from the default rows. */
	private static final String NEXT_FIELD = 'npe03.Next_Payment_Date__c';
	private static final String ESTABLISHED_FIELD = 'npe03.Date_Established__c';

	@NamespaceAccessible
	public NpspGivingKit() {
		// Built by name from the kit's Extension Class; holds no state.
		return;
	}

	@NamespaceAccessible
	public List<Map<String, Object>> rows(String stepKey, List<SObject> records) {
		if (!stepKey.startsWith('recurring')) {
			return null;
		}
		MigrationKitService.Source source = new MigrationKitService.Source(
			MigrationKitService.stepNamed(MigrationKitService.kitNamed(KIT), stepKey)
		);
		List<Map<String, Object>> rows = source.rows(records);
		for (Map<String, Object> row : rows) {
			row.put(
				START_COLUMN,
				startOf((String) row.get(NEXT_FIELD), (String) row.get(ESTABLISHED_FIELD))
			);
		}
		return rows;
	}

	@NamespaceAccessible
	public MigrationCheck verify(String stepKey) {
		return null;
	}

	/** The next payment date, else the date established, as a file would hold it. */
	@TestVisible
	private static String startOf(String nextPayment, String established) {
		if (String.isNotBlank(nextPayment)) {
			return nextPayment;
		}
		return String.isBlank(established) ? '' : established;
	}
}
