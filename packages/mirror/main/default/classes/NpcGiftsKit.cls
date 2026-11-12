/**
 * The Nonprofit Cloud Gifts kit's rows (MIG-04, canonical model R-MK1), named by the kit
 * `NPC_Gifts`. Gift Designations become funds (only those no fund already has, by Gift
 * Designation ID or name), Gift Commitments recurring commitments or pledges, each paid Gift
 * Transaction one gift keyed by its ID, so the Gift Transaction mirror (X-07) never copies it
 * back, and Gift Soft Credits soft credits. A donor or recipient account is named by record Id:
 * a person account's contact, else the account as an organization. Nonprofit Cloud is read by
 * describe only, in the running user's access; its names are text here, and Mirror may name
 * standard objects as text (plan Section 4.2). Core builds this class by name (ADR-0017).
 */
@NamespaceAccessible
public with sharing class NpcGiftsKit implements MigrationKitExtension {
	@TestVisible
	private static final String KIT = 'NPC_Gifts';

	@NamespaceAccessible
	public NpcGiftsKit() {
		// Built by name from the kit's Extension Class; holds no state.
		return;
	}

	@NamespaceAccessible
	public List<Map<String, Object>> rows(String stepKey, List<SObject> records) {
		if (stepKey == 'appeals') {
			return null;
		}
		List<Map<String, Object>> rows = new MigrationKitService.Source(
				MigrationKitService.stepNamed(MigrationKitService.kitNamed(KIT), stepKey)
			)
			.rows(records);
		if (stepKey == 'funds') {
			return newFunds(rows, fundKeys());
		}
		String accountColumn = stepKey == 'credits' ? 'RecipientId' : 'DonorId';
		Map<String, String> people = personContacts(NpspGiftsKit.column(rows, accountColumn));
		Map<String, List<NpspGiftsKit.Part>> splits = stepKey == 'gifts'
			? splits(NpspGiftsKit.column(rows, 'Id'))
			: new Map<String, List<NpspGiftsKit.Part>>();
		Map<String, List<String>> tributes = stepKey == 'gifts'
			? tributes(NpspGiftsKit.column(rows, 'Id'))
			: new Map<String, List<String>>();
		for (Map<String, Object> row : rows) {
			String key = (String) row.get('Id');
			if (stepKey == 'gifts') {
				giftRow(row, people, splits.get(key), tributes.get(key));
			} else if (stepKey == 'commitments') {
				commitmentRow(row, people);
			} else {
				creditRow(row, people);
			}
		}
		return rows;
	}

	/** The funds step's check: designations, and those a fund now has by ID or name. */
	@NamespaceAccessible
	public MigrationCheck verify(String stepKey) {
		if (stepKey != 'funds') {
			return null;
		}
		Set<String> have = fundKeys();
		Integer source = 0;
		Integer done = 0;
		// detection-only: Nonprofit Cloud's GiftDesignation, read after a describe finds it
		String query = 'SELECT Id, Name FROM GiftDesignation LIMIT 50000'; // detection-only: text
		for (SObject designation : read(query, null)) {
			source++;
			done += hasFund(designation.Id, (String) designation.get('Name'), have) ? 1 : 0;
		}
		return new MigrationCheck(source, done);
	}

	/** The designations no fund has yet; a fund of the same name is the one gifts use. */
	@TestVisible
	private static List<Map<String, Object>> newFunds(
		List<Map<String, Object>> rows,
		Set<String> have
	) {
		List<Map<String, Object>> result = new List<Map<String, Object>>();
		for (Map<String, Object> row : rows) {
			if (!hasFund((String) row.get('Id'), (String) row.get('Name'), have)) {
				result.add(row);
			}
		}
		return result;
	}

	private static Boolean hasFund(String designationId, String name, Set<String> have) {
		return have.contains(designationId) ||
			(String.isNotBlank(name) && have.contains(name.trim().toLowerCase()));
	}

	/** Every fund's Gift Designation ID and lowercased name, in the user's access. */
	private static Set<String> fundKeys() {
		Set<String> keys = new Set<String>();
		for (Fund__c fund : [
			SELECT Name, Gift_Designation_Id__c
			FROM Fund__c
			WITH USER_MODE
			LIMIT 50000
		]) {
			keys.add(fund.Name.trim().toLowerCase());
			if (String.isNotBlank(fund.Gift_Designation_Id__c)) {
				keys.add(fund.Gift_Designation_Id__c);
			}
		}
		return keys;
	}

	/**
	 * One paid Gift Transaction's row as a gift: donor, its own ID as the mirror's link, the
	 * designations as the split, and its tribute (type, honoree, notified name, message).
	 */
	@TestVisible
	private static void giftRow(
		Map<String, Object> row,
		Map<String, String> people,
		List<NpspGiftsKit.Part> split,
		List<String> tribute
	) {
		putDonor(row, people, 'ContactId', 'OrganizationId');
		row.put('GiftTransactionId', row.get('Id'));
		NpspGiftsKit.putSplit(row, split, (String) row.get('OriginalAmount'));
		List<String> names = new List<String>{
			'TributeType',
			'HonoreeName',
			'NotifyName',
			'NotifyMessage'
		};
		for (Integer index = 0; index < names.size(); index++) {
			row.put(names[index], tribute == null || tribute[index] == null ? '' : tribute[index]);
		}
	}

	/**
	 * One Gift Commitment's row: donor, Recurring when its schedule type says so (else a
	 * pledge, whose amount is the expected total), and BarnCRM's frequency.
	 */
	@TestVisible
	private static void commitmentRow(Map<String, Object> row, Map<String, String> people) {
		putDonor(row, people, 'DonorContact', 'DonorAccount');
		String schedule = (String) row.get('ScheduleType');
		Boolean recurring = String.isNotBlank(schedule) && schedule.containsIgnoreCase('recurring');
		row.put('Type', recurring ? 'Recurring' : 'Pledge');
		String next = (String) row.get('NextTransactionAmount');
		row.put(
			'Amount',
			recurring && String.isNotBlank(next) ? next : row.get('ExpectedTotalCmtAmount')
		);
		row.put(
			'Frequency',
			frequency(
				(String) row.get('EffectiveTransactionPeriod'),
				(String) row.get('EffectiveTransactionInterval')
			)
		);
	}

	/** BarnCRM's frequency for a period and interval: Monthly when neither is known. */
	@TestVisible
	private static String frequency(String period, String interval) {
		String unit = String.isBlank(period) ? '' : period.trim().toLowerCase();
		Integer every = 1;
		try {
			every = String.isBlank(interval) ? 1 : Decimal.valueOf(interval.trim()).intValue();
		} catch (TypeException notNumber) {
			every = 1;
		}
		if (unit.startsWith('week')) {
			return every == 2 ? 'Every two weeks' : 'Weekly';
		}
		if (unit.startsWith('quarter') || (unit.startsWith('month') && every == 3)) {
			return 'Quarterly';
		}
		if (unit.startsWith('month') && every == 6) {
			return 'Twice a year';
		}
		if (unit.startsWith('year') || unit.startsWith('annual')) {
			return 'Yearly';
		}
		return 'Monthly';
	}

	/** One Gift Soft Credit's row: recipient, BarnCRM's role, and its amount or the gift's. */
	@TestVisible
	private static void creditRow(Map<String, Object> row, Map<String, String> people) {
		String recipient = (String) row.get('RecipientId');
		String contact = people.get(recipient);
		row.put('ContactId', contact == null ? '' : contact);
		row.put('AccountId', contact == null ? recipient : '');
		NpspGiftsKit.putRole(row, (String) row.get('Role'));
		String amount = (String) row.get('SoftCreditAmount');
		row.put(
			'Amount',
			String.isNotBlank(amount) ? amount : row.get('GiftTransaction.OriginalAmount')
		);
	}

	/** The Donor choice and donor Id columns: a person account's contact, else the account. */
	private static void putDonor(
		Map<String, Object> row,
		Map<String, String> people,
		String contactColumn,
		String accountColumn
	) {
		String donor = (String) row.get('DonorId');
		String contact = people.get(donor);
		row.put('Donor', contact == null ? 'Organization' : 'Contact1');
		row.put(contactColumn, contact == null ? '' : contact);
		row.put(accountColumn, contact == null ? donor : '');
	}

	/** Each person account's contact, by account Id; none where person accounts are off. */
	private static Map<String, String> personContacts(Set<String> ids) {
		Map<String, String> result = new Map<String, String>();
		if (
			ids.isEmpty() ||
			!Schema.SObjectType.Account.fields.getMap().containsKey('ispersonaccount')
		) {
			return result;
		}
		for (
			SObject account : Database.queryWithBinds(
				'SELECT Id, PersonContactId FROM Account WHERE Id IN :ids AND IsPersonAccount = true',
				new Map<String, Object>{ 'ids' => ids },
				AccessLevel.USER_MODE
			)
		) {
			result.put(account.Id, (String) account.get('PersonContactId'));
		}
		return result;
	}

	/** Each Gift Transaction's designations, largest first, by its Id. */
	private static Map<String, List<NpspGiftsKit.Part>> splits(Set<String> ids) {
		Map<String, List<NpspGiftsKit.Part>> result = new Map<String, List<NpspGiftsKit.Part>>();
		for (
			SObject link : read(
				// detection-only: the next line is query text, run after a describe finds the object
				'SELECT GiftTransactionId, GiftDesignation.Name, Amount FROM GiftTransactionDesignation' + // detection-only: text
				' WHERE GiftTransactionId IN :ids ORDER BY Amount DESC NULLS LAST',
				ids
			)
		) {
			String key = (String) link.get('GiftTransactionId');
			if (!result.containsKey(key)) {
				result.put(key, new List<NpspGiftsKit.Part>());
			}
			SObject designation = link.getSObject('GiftDesignation');
			result.get(key)
				.add(
					new NpspGiftsKit.Part(
						designation == null ? null : (String) designation.get('Name'),
						(Decimal) link.get('Amount')
					)
				);
		}
		return result;
	}

	/** Each Gift Transaction's first tribute, by its Id. */
	private static Map<String, List<String>> tributes(Set<String> ids) {
		Map<String, List<String>> result = new Map<String, List<String>>();
		for (
			SObject tribute : read(
				'SELECT GiftTransactionId, TributeType, HonoreeName, NotificationContactName,' +
				' NotificationMessage FROM GiftTribute WHERE GiftTransactionId IN :ids', // detection-only: text
				ids
			)
		) {
			String key = (String) tribute.get('GiftTransactionId');
			if (!result.containsKey(key)) {
				result.put(
					key,
					new List<String>{
						String.valueOf(tribute.get('TributeType')),
						(String) tribute.get('HonoreeName'),
						(String) tribute.get('NotificationContactName'),
						(String) tribute.get('NotificationMessage')
					}
				);
			}
		}
		return result;
	}

	/**
	 * The records of a Nonprofit Cloud object, in the user's access; none when the org lacks
	 * the object or the query names a field it does not have.
	 */
	private static List<SObject> read(String query, Set<String> ids) {
		String objectName = query.substringAfter(' FROM ').substringBefore(' ').trim();
		if (
			(ids != null && ids.isEmpty()) ||
			!NamespaceUtil.globalDescribe().containsKey(objectName.toLowerCase())
		) {
			return new List<SObject>();
		}
		try {
			// Every name is Nonprofit Cloud's own, fixed here; the only value is a bind.
			return Database.queryWithBinds(
				query,
				new Map<String, Object>{ 'ids' => ids },
				AccessLevel.USER_MODE
			);
		} catch (QueryException unreadable) {
			ErrorLogger.log(unreadable, 'Nonprofit Cloud Gifts kit');
			return new List<SObject>();
		}
	}
}
