/**
 * The chunks of an NPSP household adoption run, and of its undo (X-05, canonical model R-HA3
 * and R-HA4, ADR-0155). Started only by `NpspHouseholdAdoptionService`, which has counted,
 * confirmed and checked the permission.
 *
 * Adopt: the candidates are selected as the person who started the run (user mode), at most
 * the confirmed number, in Id order. Each chunk skips an Account the person cannot edit, writes
 * the record type and the four household fields in system mode through `HouseholdWriter`
 * (ADR-0141), writes one journal row per Account saved in the same savepoint, then runs
 * household upkeep on the adopted households. No NPSP field is written.
 *
 * Undo: reads the run's rows still Adopted and puts each Account back, when it still exists,
 * is still a Household and the person can edit it; every row ends Undone or Not Restored.
 *
 * An NPC run (its id starts `NPC-`, R-HA7) reads Mirror's source and also sets Household Model
 * to Converted, journaling the model it had (R-HA8); its undo puts the model back, and any undo
 * leaves an Account with Household Member rows as it is (R-HA9).
 *
 * The finish writes one Info entry to the Error Log with the counts.
 */
public with sharing class NpspHouseholdAdoptionBatch implements Database.Batchable<SObject>, Database.Stateful {
	/** Accounts per chunk: one read, one write, one journal insert and their upkeep. */
	public static final Integer CHUNK_SIZE = 100;

	/** The four BarnCRM fields an adoption sets and an undo puts back, and no others. */
	@TestVisible
	private static final List<String> SAVED_FIELDS = new List<String>{
		'Custom_Name__c',
		'Household_Formal_Greeting__c',
		'Household_Informal_Greeting__c',
		'Primary_Contact__c'
	};
	/** A fifth, saved and put back for an NPC conversion only (R-HA8, R-HA9). */
	private static final String MODEL_FIELD = 'Household_Model__c';
	/** The Previous Values key listing the membership rows an NPC conversion made (R-HA9). */
	private static final String MEMBERS_KEY = 'members';

	private final String runId;
	private final Boolean undoing;
	private final Boolean keepNames;
	private final Integer runLimit;

	private Integer done = 0;
	private Integer skipped = 0;
	private Integer refused = 0;

	private NpspHouseholdAdoptionBatch(
		String runId,
		Boolean undoing,
		Boolean keepNames,
		Integer runLimit
	) {
		this.runId = runId;
		this.undoing = undoing;
		this.keepNames = keepNames;
		this.runLimit = runLimit;
	}

	public static NpspHouseholdAdoptionBatch adopt(
		String runId,
		Boolean keepNames,
		Integer limitTo
	) {
		return new NpspHouseholdAdoptionBatch(runId, false, keepNames, limitTo);
	}

	public static NpspHouseholdAdoptionBatch undo(String runId) {
		return new NpspHouseholdAdoptionBatch(runId, true, false, null);
	}

	public Database.QueryLocator start(Database.BatchableContext context) {
		if (undoing) {
			return Database.getQueryLocatorWithBinds(
				'SELECT Id, Account_Id__c, Previous_Record_Type_Id__c, Previous_Values__c ' +
					'FROM Household_Adoption__c WHERE Run_Id__c = :runId AND Status__c = :adopted ' +
					'ORDER BY Id',
				new Map<String, Object>{
					'runId' => runId,
					'adopted' => NpspHouseholdAdoptionService.STATUS_ADOPTED
				},
				AccessLevel.SYSTEM_MODE
			);
		}
		NpspHouseholdSource source = NpspHouseholdSource.forKey(
			NpspHouseholdSource.keyOfRun(runId)
		);
		String condition = source != null && source.available() ? source.condition() : '';
		if (String.isBlank(condition)) {
			return Database.getQueryLocatorWithBinds(
				'SELECT Id FROM Account WHERE Id = NULL',
				new Map<String, Object>(),
				AccessLevel.USER_MODE
			);
		}
		Map<String, Object> binds = new Map<String, Object>(source.binds());
		binds.put('runLimit', runLimit);
		return Database.getQueryLocatorWithBinds(
			'SELECT Id FROM Account WHERE ' + condition + ' ORDER BY Id LIMIT :runLimit',
			binds,
			AccessLevel.USER_MODE
		);
	}

	public void execute(Database.BatchableContext context, List<SObject> scope) {
		if (undoing) {
			undoChunk((List<Household_Adoption__c>) scope);
		} else {
			adoptChunk(new Map<Id, SObject>(scope).keySet());
		}
	}

	private void adoptChunk(Set<Id> scopeIds) {
		Id household = HouseholdService.householdRecordTypeId();
		Set<Id> editable = HouseholdSelector.getEditableIds(scopeIds);
		skipped += scopeIds.size() - editable.size();
		String key = NpspHouseholdSource.keyOfRun(runId);
		Boolean converting = key == NpspHouseholdSource.NPC;
		List<NpspHouseholdSource.Household> sources = NpspHouseholdSource.forKey(key)
			.read(editable);

		Set<Id> primaryIds = new Set<Id>();
		for (NpspHouseholdSource.Household source : sources) {
			primaryIds.add(source.primaryContactId);
		}
		primaryIds.remove(null);
		Map<Id, Contact> primaries = new Map<Id, Contact>(
			[SELECT Id, AccountId FROM Contact WHERE Id IN :primaryIds WITH SYSTEM_MODE]
		);
		Map<Id, Account> before = new Map<Id, Account>(
			[
				SELECT
					Id,
					RecordTypeId,
					Custom_Name__c,
					Household_Formal_Greeting__c,
					Household_Informal_Greeting__c,
					Primary_Contact__c,
					Household_Model__c
				FROM Account
				WHERE Id IN :editable
				WITH SYSTEM_MODE
			]
		);

		List<Account> changes = new List<Account>();
		Map<Id, Household_Adoption__c> journal = new Map<Id, Household_Adoption__c>();
		for (NpspHouseholdSource.Household source : sources) {
			Account previous = before.get(source.accountId);
			if (previous == null || previous.RecordTypeId == household) {
				continue;
			}
			Contact primary = primaries.get(source.primaryContactId);
			Account change = new Account(
				Id = source.accountId,
				RecordTypeId = household,
				Custom_Name__c = keepNames || source.customNaming,
				Household_Formal_Greeting__c = source.formalGreeting,
				Household_Informal_Greeting__c = source.informalGreeting,
				Primary_Contact__c = primary != null &&
					primary.AccountId == source.accountId
					? primary.Id
					: null
			);
			Map<String, Object> saved = savedValues(previous);
			if (converting) {
				// R-HA8: BarnCRM owns it now, and the undo puts the model back.
				change.Household_Model__c = HouseholdSelector.MODEL_CONVERTED;
				saved.put(MODEL_FIELD, previous.Household_Model__c);
			}
			changes.add(change);
			journal.put(
				source.accountId,
				new Household_Adoption__c(
					Account_Id__c = source.accountId,
					Run_Id__c = runId,
					Previous_Record_Type_Id__c = previous.RecordTypeId,
					Previous_Values__c = JSON.serialize(saved),
					Status__c = NpspHouseholdAdoptionService.STATUS_ADOPTED
				)
			);
		}
		if (changes.isEmpty()) {
			return;
		}

		Savepoint savepoint = Database.setSavepoint();
		Map<Id, String> refusals = HouseholdWriter.saveAdoptionChanges(changes);
		for (Id refusedId : refusals.keySet()) {
			journal.remove(refusedId);
		}
		try {
			if (converting) {
				joinMembers(sources, journal);
			}
			if (!journal.isEmpty()) {
				Database.insert(journal.values(), true, AccessLevel.SYSTEM_MODE);
			}
		} catch (Exception e) {
			// An Account is never left adopted without the row that undoes it.
			Database.rollback(savepoint);
			ErrorLogger.log(e, Label.Core_NpspAdoption_ErrorContext);
			refused += changes.size();
			return;
		}
		refused += refusals.size();
		done += journal.size();
		HouseholdService.afterMembershipChange(journal.keySet(), false);
	}

	/**
	 * Junction mode only (R-HA8): joins each converted household's members through
	 * `HouseholdService.addMembers` (R-M5), as the person who started the run, then gives each new
	 * membership row the primary flag, role and dates the source holds, and journals the new
	 * rows' ids so the undo removes exactly those. A person already a current member is left as
	 * they are. In Contact mode nobody is moved.
	 */
	private static void joinMembers(
		List<NpspHouseholdSource.Household> sources,
		Map<Id, Household_Adoption__c> journal
	) {
		if (!HouseholdService.isJunctionMode()) {
			return;
		}
		Map<Id, Set<Id>> people = new Map<Id, Set<Id>>();
		Set<Id> contactIds = new Set<Id>();
		for (NpspHouseholdSource.Household source : sources) {
			if (!journal.containsKey(source.accountId) || source.members.isEmpty()) {
				continue;
			}
			people.put(source.accountId, new Set<Id>());
			for (NpspHouseholdSource.Member member : source.members) {
				people.get(source.accountId).add(member.contactId);
				contactIds.add(member.contactId);
			}
		}
		if (people.isEmpty()) {
			return;
		}
		Map<Id, Id> personAccounts = PersonRecordSelector.getAccountsBehindPersonContacts(
			contactIds
		);
		Set<String> held = new Set<String>(memberKeys(people.keySet()).keySet());
		HouseholdService.addMembers(people);
		Map<String, Household_Member__c> now = memberKeys(people.keySet());
		List<Household_Member__c> created = new List<Household_Member__c>();
		Map<Id, List<Id>> createdByHousehold = new Map<Id, List<Id>>();
		for (NpspHouseholdSource.Household source : sources) {
			if (!people.containsKey(source.accountId)) {
				continue;
			}
			createdByHousehold.put(source.accountId, new List<Id>());
			for (NpspHouseholdSource.Member member : source.members) {
				Id person = personAccounts.containsKey(member.contactId)
					? personAccounts.get(member.contactId)
					: member.contactId;
				String key = '' + source.accountId + person;
				Household_Member__c row = now.get(key);
				if (row == null || held.contains(key)) {
					continue;
				}
				held.add(key);
				row.Is_Primary__c = member.isPrimary == true;
				row.Role__c = member.role;
				row.Start_Date__c = member.startDate;
				row.End_Date__c = member.endDate;
				created.add(row);
				createdByHousehold.get(source.accountId).add(row.Id);
			}
		}
		Database.update(created, AccessLevel.USER_MODE);
		for (Id accountId : createdByHousehold.keySet()) {
			Household_Adoption__c row = journal.get(accountId);
			Map<String, Object> saved = (Map<String, Object>) JSON.deserializeUntyped(
				row.Previous_Values__c
			);
			saved.put(MEMBERS_KEY, createdByHousehold.get(accountId));
			row.Previous_Values__c = JSON.serialize(saved);
		}
	}

	/** The membership rows of these households, by household and person. */
	private static Map<String, Household_Member__c> memberKeys(Set<Id> householdIds) {
		Map<String, Household_Member__c> rows = new Map<String, Household_Member__c>();
		for (Household_Member__c row : [
			SELECT Id, Household__c, Contact__c, Account__c
			FROM Household_Member__c
			WHERE Household__c IN :householdIds
			WITH SYSTEM_MODE
		]) {
			rows.put(
				'' + row.Household__c + (row.Contact__c != null ? row.Contact__c : row.Account__c),
				new Household_Member__c(Id = row.Id)
			);
		}
		return rows;
	}

	private void undoChunk(List<Household_Adoption__c> rows) {
		Id household = HouseholdService.householdRecordTypeId();
		Set<Id> accountIds = new Set<Id>();
		for (Household_Adoption__c row : rows) {
			if (String.isNotBlank(row.Account_Id__c)) {
				accountIds.add(Id.valueOf(row.Account_Id__c));
			}
		}
		accountIds.remove(null);
		Map<Id, Account> current = new Map<Id, Account>(
			[SELECT Id, RecordTypeId FROM Account WHERE Id IN :accountIds WITH SYSTEM_MODE]
		);
		Set<Id> editable = HouseholdSelector.getEditableIds(accountIds);
		// R-HA9: the run's own membership rows are removed; a household with any other member
		// cannot stop being one.
		Set<Id> journaled = new Set<Id>();
		for (Household_Adoption__c row : rows) {
			journaled.addAll(journaledMembers(row));
		}
		Set<Id> withMembers = new Set<Id>();
		List<Household_Member__c> ours = new List<Household_Member__c>();
		for (Household_Member__c member : [
			SELECT Id, Household__c
			FROM Household_Member__c
			WHERE Household__c IN :accountIds
			WITH SYSTEM_MODE
		]) {
			if (journaled.contains(member.Id)) {
				ours.add(member);
			} else {
				withMembers.add(member.Household__c);
			}
		}

		List<Account> restores = new List<Account>();
		Map<Id, Household_Adoption__c> rowByAccount = new Map<Id, Household_Adoption__c>();
		for (Household_Adoption__c row : rows) {
			Account account = String.isBlank(row.Account_Id__c)
				? null
				: current.get(Id.valueOf(row.Account_Id__c));
			String note;
			if (account == null) {
				note = BarnHelp.text('Core', 'Core_NpspAdoption_NoteGone');
			} else if (account.RecordTypeId != household) {
				note = BarnHelp.text('Core', 'Core_NpspAdoption_NoteNotHousehold');
			} else if (!editable.contains(account.Id)) {
				note = BarnHelp.text('Core', 'Core_NpspAdoption_NoteNoAccess');
			} else if (withMembers.contains(account.Id)) {
				note = BarnHelp.text('Core', 'Core_NpspAdoption_NoteHasMembers');
			}
			if (note != null) {
				notRestored(row, note);
				continue;
			}
			restores.add(restoreOf(row));
			rowByAccount.put(account.Id, row);
		}
		Map<Id, String> refusals = HouseholdWriter.saveAdoptionChanges(restores);
		// After the record type is back, so removing the last member never tidies the Account.
		List<Household_Member__c> removals = new List<Household_Member__c>();
		for (Household_Member__c member : ours) {
			if (
				rowByAccount.containsKey(member.Household__c) &&
				!refusals.containsKey(member.Household__c)
			) {
				removals.add(member);
			}
		}
		Map<Id, String> kept = deleteFailures(
			removals,
			Database.delete(removals, false, AccessLevel.USER_MODE)
		);
		for (Id accountId : rowByAccount.keySet()) {
			Household_Adoption__c row = rowByAccount.get(accountId);
			if (kept.containsKey(accountId)) {
				notRestored(
					row,
					String.format(
						BarnHelp.text('Core', 'Core_NpspAdoption_NoteMembersKept'),
						new List<Object>{ kept.get(accountId) }
					)
				);
			} else if (refusals.containsKey(accountId)) {
				notRestored(
					row,
					String.format(
						BarnHelp.text('Core', 'Core_NpspAdoption_NoteRefused'),
						new List<Object>{ refusals.get(accountId) }
					)
				);
			} else {
				row.Status__c = NpspHouseholdAdoptionService.STATUS_UNDONE;
				row.Note__c = null;
				done++;
			}
		}
		Database.update(rows, false, AccessLevel.SYSTEM_MODE);
	}

	/** The first delete error per household, for the membership rows whose delete failed. */
	@TestVisible
	private static Map<Id, String> deleteFailures(
		List<Household_Member__c> removals,
		List<Database.DeleteResult> results
	) {
		Map<Id, String> failed = new Map<Id, String>();
		for (Integer i = 0; i < results.size(); i++) {
			if (!results[i].isSuccess() && !failed.containsKey(removals[i].Household__c)) {
				failed.put(removals[i].Household__c, results[i].getErrors()[0].getMessage());
			}
		}
		return failed;
	}

	/** The membership rows an NPC conversion journaled on this row (R-HA9). */
	private static Set<Id> journaledMembers(Household_Adoption__c row) {
		Set<Id> ids = new Set<Id>();
		if (String.isBlank(row.Previous_Values__c)) {
			return ids;
		}
		Object listed = ((Map<String, Object>) JSON.deserializeUntyped(row.Previous_Values__c))
			.get(MEMBERS_KEY);
		if (listed instanceof List<Object>) {
			for (Object memberId : (List<Object>) listed) {
				ids.add(Id.valueOf((String) memberId));
			}
		}
		return ids;
	}

	private void notRestored(Household_Adoption__c row, String note) {
		row.Status__c = NpspHouseholdAdoptionService.STATUS_NOT_RESTORED;
		row.Note__c = note == null ? null : note.left(255);
		refused++;
	}

	/** The Account as it was before adoption: its record type and the four saved fields. */
	@TestVisible
	private static Account restoreOf(Household_Adoption__c row) {
		Account restore = new Account(Id = Id.valueOf(row.Account_Id__c));
		restore.RecordTypeId = String.isBlank(row.Previous_Record_Type_Id__c)
			? null
			: Id.valueOf(row.Previous_Record_Type_Id__c);
		Map<String, Object> values = String.isBlank(row.Previous_Values__c)
			? new Map<String, Object>()
			: (Map<String, Object>) JSON.deserializeUntyped(row.Previous_Values__c);
		restore.Custom_Name__c = values.get('Custom_Name__c') == true;
		restore.Household_Formal_Greeting__c = (String) values.get('Household_Formal_Greeting__c');
		restore.Household_Informal_Greeting__c = (String) values.get(
			'Household_Informal_Greeting__c'
		);
		String primary = (String) values.get('Primary_Contact__c');
		restore.Primary_Contact__c = String.isBlank(primary) ? null : Id.valueOf(primary);
		if (values.containsKey(MODEL_FIELD)) {
			restore.Household_Model__c = (String) values.get(MODEL_FIELD);
		}
		return restore;
	}

	private static Map<String, Object> savedValues(Account previous) {
		Map<String, Object> values = new Map<String, Object>();
		for (String field : SAVED_FIELDS) {
			values.put(field, previous.get(field));
		}
		return values;
	}

	public void finish(Database.BatchableContext context) {
		Boolean npc = NpspHouseholdSource.keyOfRun(runId) == NpspHouseholdSource.NPC;
		String pattern;
		if (undoing) {
			pattern = npc
				? BarnHelp.text('Core', 'Core_NpcConversion_UndoSummary')
				: BarnHelp.text('Core', 'Core_NpspAdoption_UndoSummary');
		} else {
			pattern = npc
				? BarnHelp.text('Core', 'Core_NpcConversion_RunSummary')
				: BarnHelp.text('Core', 'Core_NpspAdoption_RunSummary');
		}
		String summary = String.format(
			pattern,
			undoing ? new List<Object>{ done, refused } : new List<Object>{ done, skipped, refused }
		);
		ErrorLogger.logMessage(
			summary,
			Label.Core_NpspAdoption_ErrorContext,
			ErrorLogger.SEVERITY_INFO
		);
	}
}
