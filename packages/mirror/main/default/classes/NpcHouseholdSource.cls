/**
 * Nonprofit Cloud households as a source of Core's household adoption (MIG-02b, canonical model
 * R-HA7 and R-HA8, ADR-NEXT `NEXT-npc-household-conversion.md`). Core finds this class by name
 * (`NpspHouseholdSource.forKey`, ADR-0057) and runs the same preview, run, journal and undo it
 * runs for NPSP.
 *
 * A candidate is an Account carrying a `PartyRelationshipGroup` of type Household whose record
 * type is not BarnCRM's Household and whose Household Model is neither Converted nor Nonprofit
 * Cloud. Members are `AccountContactRelation` rows; the primary is the one marked
 * `IsPrimaryMember`. Every native name is text resolved through describe at run time (ADR-0013),
 * and every read is in the running user's access, so without the native objects, or without
 * read access to them, nothing is available. Nothing native is ever written.
 */
@NamespaceAccessible
public with sharing class NpcHouseholdSource extends NpspHouseholdSource implements MigrationKitExtension {
	private static final String GROUP_OBJECT = 'partyrelationshipgroup'; // detection-only: describe key of the native household group
	private static final String MEMBER_OBJECT = 'accountcontactrelation'; // detection-only: describe key of native membership
	private static final String PRIMARY_FIELD = 'IsPrimaryMember';
	/** Accounts a native household group of type Household points at. */
	private static final String GROUPED =
		'Id IN (SELECT AccountId FROM PartyRelationshipGroup' + // detection-only: text
		' WHERE Type = \'Household\')';

	@NamespaceAccessible
	public NpcHouseholdSource() {
		// Built by name from Core; holds no state.
		return;
	}

	public override String key() {
		return NpspHouseholdSource.NPC;
	}

	/** True when the org has the native group and membership objects and the user may read them. */
	public override Boolean available() {
		return readable(GROUP_OBJECT) && readable(MEMBER_OBJECT);
	}

	public override String condition() {
		if (!available()) {
			return '';
		}
		return GROUPED +
			' AND RecordTypeId != :barnHousehold' +
			' AND (Household_Model__c = null OR Household_Model__c NOT IN :keptModels)';
	}

	public override Map<String, Object> binds() {
		return new Map<String, Object>{
			'barnHousehold' => HouseholdService.householdRecordTypeId(),
			'keptModels' => new List<String>{
				HouseholdSelector.MODEL_CONVERTED,
				HouseholdSelector.MODEL_NATIVE
			}
		};
	}

	/**
	 * The Accounts with their members and primary member, read as the running user. No
	 * greetings exist natively, so none are read.
	 */
	public override List<NpspHouseholdSource.Household> read(Set<Id> accountIds) {
		List<NpspHouseholdSource.Household> result = new List<NpspHouseholdSource.Household>();
		if (accountIds == null || accountIds.isEmpty()) {
			return result;
		}
		Map<Id, List<NpspHouseholdSource.Member>> members = new Map<Id, List<NpspHouseholdSource.Member>>();
		if (available()) {
			String memberQuery = memberSelect(readableMemberFields());
			if (memberQuery == null) {
				ErrorLogger.logMessage(
					BarnHelp.text('Mirror', 'Mirror_NpcHouseholds_MembersUnreadable'),
					'NpcHouseholdSource',
					ErrorLogger.SEVERITY_WARNING
				);
			} else {
				List<Map<String, Object>> rows = new List<Map<String, Object>>();
				for (
					SObject row : Database.queryWithBinds(
						memberQuery +
						' FROM AccountContactRelation WHERE AccountId IN :accountIds ORDER BY Id', // detection-only: text
						new Map<String, Object>{ 'accountIds' => accountIds },
						AccessLevel.USER_MODE
					)
				) {
					rows.add(row.getPopulatedFieldsAsMap());
				}
				members = members(rows);
			}
		}
		for (Account account : [
			SELECT Id, Name, RecordTypeId
			FROM Account
			WHERE Id IN :accountIds
			WITH USER_MODE
			ORDER BY Id
		]) {
			NpspHouseholdSource.Household household = new NpspHouseholdSource.Household();
			household.accountId = account.Id;
			household.name = account.Name;
			household.recordTypeId = account.RecordTypeId;
			if (members.containsKey(account.Id)) {
				household.members = members.get(account.Id);
				for (NpspHouseholdSource.Member member : household.members) {
					if (member.isPrimary && household.primaryContactId == null) {
						household.primaryContactId = member.contactId;
					}
				}
			}
			result.add(household);
		}
		return result;
	}

	private static final List<String> OPTIONAL_MEMBER_FIELDS = new List<String>{
		PRIMARY_FIELD,
		'Roles',
		'IsActive',
		'StartDate',
		'EndDate'
	};

	/** The membership fields the running user can read, lower case. */
	private static Set<String> readableMemberFields() {
		Set<String> result = new Set<String>();
		Schema.SObjectType type = NamespaceUtil.globalDescribe().get(MEMBER_OBJECT);
		if (type == null) {
			return result;
		}
		Map<String, Schema.SObjectField> fields = type.getDescribe(SObjectDescribeOptions.DEFERRED)
			.fields.getMap();
		for (String field : new List<String>{ 'AccountId', 'ContactId' }) {
			addIfReadable(result, fields, field);
		}
		for (String field : OPTIONAL_MEMBER_FIELDS) {
			addIfReadable(result, fields, field);
		}
		return result;
	}

	private static void addIfReadable(
		Set<String> result,
		Map<String, Schema.SObjectField> fields,
		String field
	) {
		Schema.SObjectField found = fields.get(field.toLowerCase());
		if (found != null && found.getDescribe().isAccessible()) {
			result.add(field.toLowerCase());
		}
	}

	/**
	 * The SELECT list over the readable fields, or null when the Account or Contact of a
	 * membership cannot be read and members cannot be joined. A missing primary flag or role is
	 * dropped, so the members still come across.
	 */
	@TestVisible
	private static String memberSelect(Set<String> readable) {
		if (!readable.contains('accountid') || !readable.contains('contactid')) {
			return null;
		}
		List<String> columns = new List<String>{ 'AccountId', 'ContactId' };
		for (String field : OPTIONAL_MEMBER_FIELDS) {
			if (readable.contains(field.toLowerCase())) {
				columns.add(field);
			}
		}
		return 'SELECT ' + String.join(columns, ', ');
	}

	/**
	 * The count's filter, the one `members` applies: a row inactive with no End Date is not a
	 * member. Only what the user can read is named.
	 */
	@TestVisible
	private static String memberFilter(Set<String> readable) {
		if (!readable.contains('isactive')) {
			return '';
		}
		return readable.contains('enddate')
			? ' AND (IsActive = true OR EndDate != null)'
			: ' AND IsActive = true';
	}

	/** Native roles to Household Member roles (ADR-NEXT conversion decision 4). */
	private static final Map<String, String> ROLES = new Map<String, String>{
		'husband' => 'Spouse or Partner',
		'wife' => 'Spouse or Partner',
		'son' => 'Child',
		'daughter' => 'Child',
		'father' => 'Head',
		'mother' => 'Head',
		'other' => 'Other'
	};

	/**
	 * Each membership row as a member of its Account, in row order. A row inactive with no End
	 * Date is left out: a former member with no date to record. The role is the first of the
	 * row's roles that maps.
	 */
	@TestVisible
	private static Map<Id, List<NpspHouseholdSource.Member>> members(
		List<Map<String, Object>> rows
	) {
		Map<Id, List<NpspHouseholdSource.Member>> result = new Map<Id, List<NpspHouseholdSource.Member>>();
		for (Map<String, Object> row : rows) {
			Id account = (Id) row.get('AccountId');
			Id contact = (Id) row.get('ContactId');
			if (account == null || contact == null) {
				continue;
			}
			if (row.get('IsActive') == false && row.get('EndDate') == null) {
				continue;
			}
			NpspHouseholdSource.Member member = new NpspHouseholdSource.Member();
			member.contactId = contact;
			member.isPrimary = row.get('IsPrimaryMember') == true;
			member.startDate = (Date) row.get('StartDate');
			member.endDate = (Date) row.get('EndDate');
			for (String role : String.valueOf(row.get('Roles') ?? '').split(';')) {
				if (member.role == null && ROLES.containsKey(role.trim().toLowerCase())) {
					member.role = ROLES.get(role.trim().toLowerCase());
				}
			}
			if (!result.containsKey(account)) {
				result.put(account, new List<NpspHouseholdSource.Member>());
			}
			result.get(account).add(member);
		}
		return result;
	}

	/** Members are native membership rows, so the preview counts those. */
	public override Map<Id, Integer> memberCounts(Set<Id> accountIds) {
		Map<Id, Integer> counts = new Map<Id, Integer>();
		if (accountIds == null || accountIds.isEmpty() || !available()) {
			return counts;
		}
		for (
			SObject row : Database.queryWithBinds(
				'SELECT AccountId, COUNT(Id) n FROM AccountContactRelation' + // detection-only: text
					' WHERE AccountId IN :accountIds' +
					memberFilter(readableMemberFields()) +
					' GROUP BY AccountId',
				new Map<String, Object>{ 'accountIds' => accountIds },
				AccessLevel.USER_MODE
			)
		) {
			counts.put((Id) row.get('AccountId'), (Integer) row.get('n'));
		}
		return counts;
	}

	/** Nonprofit Cloud never creates BarnCRM-style households, so upkeep has nothing to wait for. */
	public override Boolean createsHouseholds() {
		return false;
	}

	// ---------------------------------------------------------------------------------------
	// The Migration Assistant kit NPC_Households (one tool step, `households`)
	// ---------------------------------------------------------------------------------------

	/** The kit's only step is a tool step, so there are no rows to shape. */
	@NamespaceAccessible
	public List<Map<String, Object>> rows(String stepKey, List<SObject> records) {
		return null;
	}

	/**
	 * The households step's check: Accounts carrying a native household group, less those an
	 * administrator keeps native, against those converted. Nothing to check without the object.
	 */
	@NamespaceAccessible
	public MigrationCheck verify(String stepKey) {
		if (stepKey != 'households' || (groupedForTest == null && !readable(GROUP_OBJECT))) {
			return new MigrationCheck(0, 0);
		}
		Map<String, Object> binds = drift(new Map<String, Object>());
		Integer wanted = Database.countQueryWithBinds(
			'SELECT COUNT() FROM Account WHERE ' +
				grouped(true) +
				' AND (Household_Model__c = null OR Household_Model__c != :pinned)',
			binds,
			AccessLevel.USER_MODE
		);
		Integer done = Database.countQueryWithBinds(
			'SELECT COUNT() FROM Account WHERE ' +
				grouped(true) +
				' AND Household_Model__c = :converted AND RecordTypeId = :household',
			binds,
			AccessLevel.USER_MODE
		);
		return new MigrationCheck(wanted, done);
	}

	// ---------------------------------------------------------------------------------------
	// The drift report (ADR-NEXT conversion decision 8), shown by MirrorHealthCheckExtension
	// ---------------------------------------------------------------------------------------

	/** Test seam: the Accounts said to carry a native household group, in place of the query. */
	@TestVisible
	private static Set<Id> groupedForTest;
	private static final Integer DRIFT_MOST = 1000;

	/** Accounts whose model and native group disagree: how many, and the first few names. */
	@NamespaceAccessible
	public class Drift {
		@NamespaceAccessible
		public Integer count = 0;
		@NamespaceAccessible
		public List<String> names = new List<String>();
	}

	/**
	 * (a) a BarnCRM household with a native household group not marked Converted, (b) marked
	 * Nonprofit Cloud with no native household group, (c) marked Converted but no longer a
	 * BarnCRM household. Read in the viewer's access; (a) and (b) need the native object. At
	 * most 1,000 of each kind are counted.
	 */
	@NamespaceAccessible
	public static Drift drift(Integer shown) {
		Drift result = new Drift();
		Map<String, Object> binds = drift(new Map<String, Object>());
		List<String> queries = new List<String>{
			'RecordTypeId != :household AND Household_Model__c = :converted'
		};
		if (groupedForTest != null || readable(GROUP_OBJECT)) {
			queries.add(
				'RecordTypeId = :household AND (Household_Model__c = null OR ' +
					'Household_Model__c != :converted) AND ' +
					grouped(true)
			);
			queries.add('Household_Model__c = :pinned AND ' + grouped(false));
		}
		for (String condition : queries) {
			for (
				SObject account : Database.queryWithBinds(
					'SELECT Name FROM Account WHERE ' +
						condition +
						' ORDER BY Name LIMIT ' +
						DRIFT_MOST,
					binds,
					AccessLevel.USER_MODE
				)
			) {
				result.count++;
				if (result.names.size() < shown) {
					result.names.add((String) account.get('Name'));
				}
			}
		}
		return result;
	}

	/** The binds every query above names. */
	private static Map<String, Object> drift(Map<String, Object> binds) {
		binds.put('household', HouseholdService.householdRecordTypeId());
		binds.put('converted', HouseholdSelector.MODEL_CONVERTED);
		binds.put('pinned', HouseholdSelector.MODEL_NATIVE);
		binds.put('groupedForTest', groupedForTest);
		return binds;
	}

	/** The condition "carries (or does not carry) a native household group". */
	private static String grouped(Boolean has) {
		if (groupedForTest != null) {
			return has ? 'Id IN :groupedForTest' : 'Id NOT IN :groupedForTest';
		}
		return has ? GROUPED : GROUPED.replace('Id IN', 'Id NOT IN');
	}

	@TestVisible
	private static Boolean readable(String objectName) {
		Schema.SObjectType type = NamespaceUtil.globalDescribe().get(objectName);
		return type != null && type.getDescribe(SObjectDescribeOptions.DEFERRED).isAccessible();
	}
}
