/**
 * The Volunteers for Salesforce Migration Kit's rows (MIG-03, canonical model R-MK1), named by
 * the kit `V4S_Volunteers`. A V4S shift has a start and a length in hours; a BarnCRM shift has a
 * start and an end, and a status. Every other step keeps the default rows. V4S is read by
 * describe only: its field names are text here, never a compile-time reference. Core builds this
 * class by name, so it and its constructor are namespace-accessible (ADR-0017).
 */
@NamespaceAccessible
public with sharing class V4sMigrationKit implements MigrationKitExtension {
	@TestVisible
	private static final String KIT = 'V4S_Volunteers';
	@TestVisible
	private static final String SHIFTS = 'shifts';
	/** The columns the shifts template maps that V4S has no field for. */
	@TestVisible
	private static final String END_COLUMN = 'End';
	@TestVisible
	private static final String STATUS_COLUMN = 'Status';
	/** The shift step's columns as the kit writes them, read from the default rows. */
	private static final String START_FIELD = 'GW_Volunteers.Start_Date_Time__c';
	private static final String DURATION_FIELD = 'GW_Volunteers.Duration__c';

	@NamespaceAccessible
	public V4sMigrationKit() {
		// Built by name from the kit's Extension Class; holds no state.
		return;
	}

	@NamespaceAccessible
	public List<Map<String, Object>> rows(String stepKey, List<SObject> records) {
		if (stepKey != SHIFTS) {
			return null;
		}
		MigrationKitService.Source source = new MigrationKitService.Source(
			MigrationKitService.stepNamed(MigrationKitService.kitNamed(KIT), stepKey)
		);
		List<Map<String, Object>> rows = source.rows(records);
		shapeShifts(rows);
		return rows;
	}

	/** Each shift row's End and Status columns, from its V4S start and length. */
	@TestVisible
	private static void shapeShifts(List<Map<String, Object>> rows) {
		for (Map<String, Object> row : rows) {
			String startText = (String) row.get(START_FIELD);
			String hoursText = (String) row.get(DURATION_FIELD);
			Datetime starts = String.isBlank(startText)
				? null
				: (Datetime) JSON.deserialize('"' + startText + '"', Datetime.class);
			Decimal hours = String.isBlank(hoursText) ? null : Decimal.valueOf(hoursText);
			row.put(END_COLUMN, endOf(starts, hours));
			row.put(STATUS_COLUMN, statusOf(starts, System.now()));
		}
	}

	@NamespaceAccessible
	public MigrationCheck verify(String stepKey) {
		return null;
	}

	/** The end as a file would hold it: the start plus the length, or one hour when blank. */
	@TestVisible
	private static String endOf(Datetime starts, Decimal hours) {
		if (starts == null) {
			return '';
		}
		Integer minutes = hours == null || hours <= 0 ? 60 : (hours * 60).round().intValue();
		return JSON.serialize(starts.addMinutes(minutes)).remove('"');
	}

	/** A shift already started is Completed (the nightly upkeep would close it anyway). */
	@TestVisible
	private static String statusOf(Datetime starts, Datetime now) {
		return starts != null && starts < now ? 'Completed' : 'Open';
	}
}
