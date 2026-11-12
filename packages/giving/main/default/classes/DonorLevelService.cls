/**
 * Donor levels: which rung of the organization's ladder a donor is on, and when they moved
 * (feature G-14, canonical model Section 25A, ADR-0028).
 *
 * The one thing to understand here is that this class does no aggregation. A level is a label on
 * a giving total that the rollup engine has already calculated and written to the same record
 * (R-DL1): `Total_Giving__c` by default, or one of the other three totals of Section 26 that a
 * ladder can sensibly be built on. That is what makes a level agree with the number printed next
 * to it, and it is what makes the household membership modes somebody else's problem: the total
 * was calculated through `HouseholdService` when the rollup ran, so nothing is resolved twice
 * here. It also means levels inherit the gift status filter of ADR-0022 by construction rather
 * than by restating it in a second place where it could drift.
 *
 * Assignment mutates records in memory and never saves them. The trigger handler calls it in a
 * before context, where the platform writes the values with the save that is already happening,
 * and the recalculation batch calls it and saves through `DonorLevelWriter`.
 */
public with sharing class DonorLevelService {
	@TestVisible
	private static final String SETTINGS_OBJECT = 'Giving_Settings__c';
	@TestVisible
	private static final String KEY_ENABLED = 'Donor_Levels_Enabled__c';
	@TestVisible
	private static final String KEY_SOURCE = 'Donor_Level_Source_Field__c';

	/** The giving total a ladder is measured on when the organization has not chosen one. */
	public static final String DEFAULT_SOURCE_FIELD = 'Total_Giving__c';

	/**
	 * The totals a ladder may be measured on. Every one of them is a packaged rollup target of
	 * canonical model Section 26 that exists on both Account and Contact, so a setting can never
	 * name a field that is not there. A window we do not ship, a rolling twelve months for
	 * example, needs a rollup definition first, not code here (ADR-0028).
	 */
	public static final Set<String> SOURCE_FIELDS = new Set<String>{
		'Total_Giving__c',
		'Giving_This_Year__c',
		'Giving_Last_Year__c',
		'Largest_Gift__c'
	};

	private static final String FIELD_LEVEL = 'Donor_Level__c';
	private static final String FIELD_PREVIOUS = 'Previous_Donor_Level__c';
	private static final String FIELD_CHANGED = 'Donor_Level_Changed_Date__c';

	private static List<Donor_Level__c> cachedLadder;
	private static Map<String, Map<String, String>> cachedFieldNames = new Map<String, Map<String, String>>();

	/** Whether levels are assigned at all (R-DL7). Off until the organization builds its ladder. */
	public static Boolean isEnabled() {
		Object value = SettingsService.getValue(SETTINGS_OBJECT, KEY_ENABLED);
		if (value == null) {
			return false;
		}
		if (value instanceof Boolean) {
			return (Boolean) value;
		}
		String text = String.valueOf(value).trim();
		return String.isBlank(text) ? false : Boolean.valueOf(text);
	}

	/**
	 * The total the ladder is measured on. A stored value that is not one of the four we ship is
	 * treated as unset rather than obeyed, because assigning every donor from a field that may
	 * not exist is worse than assigning them from the lifetime total.
	 */
	public static String sourceField() {
		Object value = SettingsService.getValue(SETTINGS_OBJECT, KEY_SOURCE);
		String stored = value == null ? null : String.valueOf(value).trim();
		return SOURCE_FIELDS.contains(stored) ? stored : DEFAULT_SOURCE_FIELD;
	}

	/**
	 * The active rungs, lowest first, read once per transaction. In a multi-currency org their
	 * bounds are in the corporate currency, as the totals are compared (`inCorporate`).
	 */
	public static List<Donor_Level__c> ladder() {
		if (cachedLadder == null) {
			List<Donor_Level__c> rungs = DonorLevelSelector.selectActiveLevels();
			cachedLadder = inCorporate(rungs, currencies(rungs));
		}
		return cachedLadder;
	}

	/**
	 * Multi-currency orgs (ADR-0083): a donor's total is in the donor record's currency and a
	 * rung's bounds in the rung's, so both are brought to the corporate currency, at the org's
	 * static rates, before they are compared. A single-currency org reads nothing more and
	 * compares amounts as entered. Rates a test sets in `testRates` stand in for the org's.
	 */
	@TestVisible
	private static Map<String, Decimal> testRates;

	@TestVisible
	private static Decimal toCorporate(Decimal value, String isoCode) {
		if (testRates == null) {
			return RollupCurrency.toCorporate(value, isoCode);
		}
		Decimal rate = testRates.get(isoCode);
		return value == null || rate == null || rate == 0 ? value : value / rate;
	}

	/** These rungs with their bounds in the corporate currency, by each rung's currency. */
	@TestVisible
	private static List<Donor_Level__c> inCorporate(
		List<Donor_Level__c> rungs,
		Map<Id, String> isoById
	) {
		for (Donor_Level__c rung : rungs) {
			String iso = isoById.get(rung.Id);
			if (iso != null) {
				rung.Minimum_Amount__c = toCorporate(rung.Minimum_Amount__c, iso);
				rung.Maximum_Amount__c = toCorporate(rung.Maximum_Amount__c, iso);
			}
		}
		return rungs;
	}

	/**
	 * The currency of each saved record, read in system mode, only in a multi-currency org.
	 * `CurrencyIsoCode` exists only there, so it is named as text, never compiled against.
	 */
	private static Map<Id, String> currencies(List<SObject> records) {
		Map<Id, String> result = new Map<Id, String>();
		Set<Id> ids = new Set<Id>();
		for (SObject record : records) {
			// A record in a save already carries it.
			if (
				record.Id != null &&
				!record.getPopulatedFieldsAsMap().containsKey(RollupCurrency.ISO_FIELD)
			) {
				ids.add(record.Id);
			}
		}
		if (ids.isEmpty() || !RollupCurrency.isMultiCurrency()) {
			return result;
		}
		String query =
			'SELECT Id, ' +
			RollupCurrency.ISO_FIELD +
			' FROM ' +
			records[0].getSObjectType() +
			' WHERE Id IN :ids';
		for (
			SObject row : (List<SObject>) Database.queryWithBinds(
				query,
				new Map<String, Object>{ 'ids' => ids },
				AccessLevel.SYSTEM_MODE
			)
		) {
			result.put(row.Id, (String) row.get(RollupCurrency.ISO_FIELD));
		}
		return result;
	}

	/** A record's currency: as it stands in a save, or as read for a recalculation. */
	private static String currencyOf(SObject record, Map<Id, String> read) {
		Object held = record.getPopulatedFieldsAsMap().get(RollupCurrency.ISO_FIELD);
		return held != null ? (String) held : read.get(record.Id);
	}

	/** Forgets the cached ladder, for a test and for the batch between chunks. */
	public static void clearCache() {
		cachedLadder = null;
	}

	/**
	 * The rung this amount earns (R-DL2): the highest rung whose minimum the amount reaches and
	 * whose maximum it has not, or nothing at all when the amount is empty or below every rung.
	 * Overlapping rungs resolve upward, so a ladder somebody built badly is still deterministic.
	 */
	public static Id levelFor(Decimal amount, List<Donor_Level__c> rungs) {
		if (amount == null || rungs == null) {
			return null;
		}
		Id found = null;
		for (Donor_Level__c rung : rungs) {
			if (rung.Minimum_Amount__c == null || amount < rung.Minimum_Amount__c) {
				continue;
			}
			if (rung.Maximum_Amount__c != null && amount >= rung.Maximum_Amount__c) {
				continue;
			}
			found = rung.Id;
		}
		return found;
	}

	/**
	 * Places one record on the ladder, in memory. Returns true when the record moved, which is
	 * the only case anything is written: an assignment that produces the level already held
	 * leaves Donor Level Changed saying when the donor last moved rather than when the
	 * calculation last ran (R-DL4).
	 */
	public static Boolean assign(SObject record, List<Donor_Level__c> rungs, String source) {
		return assign(record, rungs, source, null);
	}

	/** The same, the record's total being in this currency (null: as the rungs are). */
	@TestVisible
	private static Boolean assign(
		SObject record,
		List<Donor_Level__c> rungs,
		String source,
		String isoCode
	) {
		if (record == null) {
			return false;
		}
		Map<String, String> names = fieldNames(record.getSObjectType());
		if (!names.containsKey(source) || !names.containsKey(FIELD_LEVEL)) {
			// The object does not carry giving totals or levels, so there is nothing to place.
			return false;
		}
		Object raw = record.get(names.get(source));
		Decimal amount = raw == null ? null : toCorporate((Decimal) raw, isoCode);
		Id assigned = levelFor(amount, rungs);
		Id held = (Id) record.get(names.get(FIELD_LEVEL));
		if (assigned == held) {
			return false;
		}
		record.put(names.get(FIELD_PREVIOUS), held);
		record.put(names.get(FIELD_LEVEL), assigned);
		record.put(names.get(FIELD_CHANGED), Date.today());
		return true;
	}

	/**
	 * Places every record in the list, and returns the ones that moved. Does nothing at all when
	 * levels are switched off, including clearing: the levels already assigned stay where they
	 * are, exactly as an inactive rollup definition keeps the values it calculated (R-DL7).
	 */
	public static List<SObject> assignAll(List<SObject> records) {
		List<SObject> moved = new List<SObject>();
		if (records == null || records.isEmpty() || !isEnabled()) {
			return moved;
		}
		List<Donor_Level__c> rungs = ladder();
		String source = sourceField();
		Map<Id, String> read = currencies(records);
		for (SObject record : records) {
			if (assign(record, rungs, source, currencyOf(record, read))) {
				moved.add(record);
			}
		}
		return moved;
	}

	/** Records when a recalculation finished, which is what the Donor Levels page shows. */
	public static void recordRecalculation(Datetime completedAt) {
		DonorLevelWriter.stampRecalculation(completedAt);
	}

	/**
	 * The real API name of each field this class touches on one object, whether or not a
	 * namespace is in front of it. The settings hold a bare field name and a packaged org's
	 * describe keys carry a prefix, which is the same problem `SettingsService.typeByName`
	 * solves for objects.
	 */
	private static Map<String, String> fieldNames(Schema.SObjectType type) {
		String key = String.valueOf(type);
		if (cachedFieldNames.containsKey(key)) {
			return cachedFieldNames.get(key);
		}
		Map<String, String> byLocalName = new Map<String, String>();
		for (
			Schema.SObjectField token : type.getDescribe(SObjectDescribeOptions.DEFERRED)
				.fields.getMap()
				.values()
		) {
			Schema.DescribeFieldResult field = token.getDescribe();
			byLocalName.put(field.getLocalName(), field.getName());
		}
		cachedFieldNames.put(key, byLocalName);
		return byLocalName;
	}
}
