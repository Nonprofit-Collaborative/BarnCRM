/**
 * The NPSP Funds, Levels and Recurring Donations kit's rows (MIG-05, canonical model R-MK1),
 * named by the kit `NPSP_Giving_Setup`. A BarnCRM recurring commitment schedules its payments
 * from its start, so a recurring donation starts at NPSP's next payment date when it has one,
 * not at the date it was established years ago (which would make a run of overdue payments).
 * An engagement plan task gets the step order and assignment BarnCRM needs, and the parity step
 * counts NPSP levels and engagement plans against their BarnCRM counterparts.
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
	/** The columns the recurring templates map to Frequency and Status, built from two fields each. */
	@TestVisible
	private static final String FREQUENCY_COLUMN = 'Frequency';
	@TestVisible
	private static final String STATUS_COLUMN = 'Status';

	@NamespaceAccessible
	public NpspGivingKit() {
		// Built by name from the kit's Extension Class; holds no state.
		return;
	}

	@NamespaceAccessible
	public List<Map<String, Object>> rows(String stepKey, List<SObject> records) {
		if (!stepKey.startsWith('recurring') && stepKey != 'planSteps') {
			return null;
		}
		MigrationKitService.Source source = new MigrationKitService.Source(
			MigrationKitService.stepNamed(MigrationKitService.kitNamed(KIT), stepKey)
		);
		List<Map<String, Object>> rows = source.rows(records);
		shapeRows(stepKey, rows);
		return rows;
	}

	/** Each row's computed columns: a plan step's order and assignment, or a recurring one's. */
	@TestVisible
	private static void shapeRows(String stepKey, List<Map<String, Object>> rows) {
		for (Map<String, Object> row : rows) {
			if (stepKey == 'planSteps') {
				planStep(row);
			} else {
				row.put(
					START_COLUMN,
					startOf((String) row.get(NEXT_FIELD), (String) row.get(ESTABLISHED_FIELD))
				);
				row.put(
					FREQUENCY_COLUMN,
					frequencyOf(
						(String) row.get('npe03.Installment_Period__c'),
						(String) row.get('npsp.InstallmentFrequency__c')
					)
				);
				String status = (String) row.get('npsp.Status__c');
				row.put(
					STATUS_COLUMN,
					String.isBlank(status) ? (String) row.get('npe03.Open_Ended_Status__c') : status
				);
			}
		}
	}

	/**
	 * The parity report (MIG-05): how many active NPSP levels and engagement plan templates
	 * there are, and how many have a BarnCRM counterpart (a donor level of the same name, a
	 * stewardship plan template keyed by the NPSP template's ID). Null for every other step.
	 */
	@NamespaceAccessible
	public MigrationCheck verify(String stepKey) {
		if (stepKey != 'parity') {
			return null;
		}
		Set<String> levels = names(
			'SELECT Name FROM npsp~Level__c WHERE npsp~Active__c = true',
			'Name'
		);
		Set<String> plans = names('SELECT Id FROM npsp~Engagement_Plan_Template__c', 'Id');
		Integer done =
			[SELECT COUNT() FROM Donor_Level__c WHERE Name IN :levels WITH USER_MODE] +
			[
				SELECT COUNT()
				FROM Stewardship_Plan_Template__c
				WHERE Plan_Key__c IN :plans
				WITH USER_MODE
			];
		return new MigrationCheck(levels.size() + plans.size(), done);
	}

	/**
	 * An engagement plan task as a stewardship plan step: ordered by its days after the start
	 * (NPSP keeps no other order), assigned to its user when it names one, else to the record
	 * owner.
	 */
	@TestVisible
	private static void planStep(Map<String, Object> row) {
		String days = (String) row.get('npsp.Days_After__c');
		row.put('Order', String.isBlank(days) ? '0' : days);
		row.put(
			'AssignTo',
			String.isBlank((String) row.get('npsp.Assigned_To__c'))
				? 'Record owner'
				: 'Specific user'
		);
	}

	/**
	 * One text field of every NPSP record a query reads, in the user's access; none without
	 * NPSP. The query writes `~` for the namespace separator, built here at run time.
	 */
	@TestVisible
	private static Set<String> names(String written, String field) {
		Set<String> result = new Set<String>();
		String query = written.replace('~', '__');
		String objectName = query.substringAfter(' FROM ').substringBefore(' ').toLowerCase();
		if (!NamespaceUtil.globalDescribe().containsKey(objectName)) {
			return result;
		}
		// NPSP's own names, fixed here; nothing comes from a request.
		for (SObject record : Database.query(query, AccessLevel.USER_MODE)) {
			result.add(String.valueOf(record.get(field)));
		}
		return result;
	}

	/**
	 * NPSP's period and its "every so many" count as one BarnCRM frequency: monthly every 3 is
	 * Quarterly, every 6 Twice a year, every 12 Yearly. Any other count keeps the period.
	 */
	@TestVisible
	private static String frequencyOf(String period, String every) {
		Integer count;
		try {
			count = String.isBlank(every) ? 1 : Decimal.valueOf(every.trim()).intValue();
		} catch (TypeException notANumber) {
			count = 1;
		}
		if (period == 'Monthly') {
			switch on count {
				when 3 {
					return 'Quarterly';
				}
				when 6 {
					return 'Twice a year';
				}
				when 12 {
					return 'Yearly';
				}
			}
		}
		return period;
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
