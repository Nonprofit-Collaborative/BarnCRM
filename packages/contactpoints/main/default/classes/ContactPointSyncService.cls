/**
 * Keeps a person's Salesforce Contact Points in step with their BarnCRM email, phone and address
 * values (C-45; ADR-0176 contact point sync module; canonical model 29ZZ).
 *
 * One way: `ContactPointPlan` says what the person's copies should be, and this class makes the
 * managed Contact Points match, creating, adopting, updating and deleting them and their Contact
 * Point Links. A Contact Point with no link is never changed.
 *
 * The three Contact Point objects and the Individual object are reached only through describe and
 * dynamic Apex (decision 11), so the module installs in any org, and a kind whose object is
 * missing is skipped and explained on the settings page.
 *
 * Without sharing, in system mode: the copy is upkeep of data the person saving was allowed to
 * change (ADR-0021, decision 9), so it is made even for someone with no Contact Point access. A
 * refused row is logged and never fails the save (decision 8).
 */
public without sharing class ContactPointSyncService {
	public static final String CONTEXT = 'Contact Point Sync';
	public static final String SETTINGS_OBJECT = 'Contact_Point_Sync_Settings__c';

	private static final Map<String, String> OBJECT_BY_KIND = new Map<String, String>{
		ContactPointPlan.EMAIL => 'ContactPointEmail',
		ContactPointPlan.PHONE => 'ContactPointPhone',
		ContactPointPlan.ADDRESS => 'ContactPointAddress'
	};
	private static final Map<String, String> SETTING_BY_KIND = new Map<String, String>{
		ContactPointPlan.EMAIL => 'Sync_Emails__c',
		ContactPointPlan.PHONE => 'Sync_Phones__c',
		ContactPointPlan.ADDRESS => 'Sync_Addresses__c'
	};
	/** The Contact Point fields each kind writes, where the org's object has them. */
	private static final Map<String, List<String>> FIELDS_BY_KIND = new Map<String, List<String>>{
		// Email and phone Names are set by Salesforce and cannot be written.
		ContactPointPlan.EMAIL => new List<String>{ 'EmailAddress', 'IsPrimary' },
		ContactPointPlan.PHONE => new List<String>{ 'TelephoneNumber', 'IsPrimary', 'PhoneType' },
		ContactPointPlan.ADDRESS => new List<String>{
			'Street',
			'City',
			'State',
			'PostalCode',
			'Country',
			'IsDefault',
			'IsPrimary',
			'Name'
		}
	};
	private static final String INDIVIDUAL = 'Individual';
	private static final String INDIVIDUAL_LINK = 'IndividualId';
	private static final String PARENT = 'ParentId';

	/** True while a sync writes, so the person handler ignores the Individual link it sets. */
	public static Boolean running = false;

	/**
	 * The Individuals this module created in this transaction. Every Contact Point on one of
	 * them was made by a sync and is linked, so none is offered for adoption, and asking costs
	 * a query for each kind on every save of a new person (an import chunk saves several times).
	 */
	private static final Set<Id> INDIVIDUALS_CREATED_HERE = new Set<Id>();

	/** Kinds a test treats as missing from the org, to prove they are skipped and explained. */
	@TestVisible
	private static Set<String> missingForTest = new Set<String>();

	/** What one sync or backfill did. */
	public class Result {
		public Integer created = 0;
		public Integer updated = 0;
		public Integer deleted = 0;
		public Integer failed = 0;

		public void add(Result other) {
			created += other.created;
			updated += other.updated;
			deleted += other.deleted;
			failed += other.failed;
		}
	}

	// ------------------------------------------------------------------ what this org can do

	/** The Contact Point object of a kind, or null where the org does not have it. */
	public static Schema.SObjectType typeOf(String kind) {
		if (missingForTest.contains(kind) || !OBJECT_BY_KIND.containsKey(kind)) {
			return null;
		}
		return Schema.getGlobalDescribe().get(OBJECT_BY_KIND.get(kind));
	}

	/** Whether the org has the Individual object and the person's link to it. */
	public static Boolean individualsAvailable() {
		return !missingForTest.contains(INDIVIDUAL) &&
			Schema.getGlobalDescribe().get(INDIVIDUAL) != null &&
			Schema.SObjectType.Contact.fields.getMap().containsKey(INDIVIDUAL_LINK.toLowerCase());
	}

	/** Whether the admin left this kind on (Sync Emails, Sync Phones, Sync Addresses). */
	public static Boolean switchedOn(String kind) {
		Object stored;
		try {
			stored = SettingsService.getValue(SETTINGS_OBJECT, SETTING_BY_KIND.get(kind));
		} catch (Exception unreadable) {
			stored = null;
		}
		return stored == null || stored == true || String.valueOf(stored) == 'true';
	}

	/** The kinds kept in step now: switched on, and the org has their object and Individual. */
	public static Set<String> activeKinds() {
		Set<String> result = new Set<String>();
		if (!individualsAvailable()) {
			return result;
		}
		for (String kind : OBJECT_BY_KIND.keySet()) {
			if (switchedOn(kind) && typeOf(kind) != null) {
				result.add(kind);
			}
		}
		return result;
	}

	public static List<String> kinds() {
		return new List<String>(OBJECT_BY_KIND.keySet());
	}

	// ------------------------------------------------------------------------ entry points

	/** The kinds a sync in this transaction has already made match, by contact id. */
	private static final Map<Id, Set<String>> KINDS_SYNCED_HERE = new Map<Id, Set<String>>();

	/**
	 * Syncs people just inserted, after every handler of their insert has run. A kind a sync
	 * already made match during that insert is not read again: Core saves a new person's
	 * mailing address as an address inside the insert, whose own sync copies it moments before
	 * this, and a person's values cannot change between the two without a save of its own.
	 * Never throws.
	 */
	public static void syncInserted(Set<Id> personIds) {
		if (personIds == null || personIds.isEmpty()) {
			return;
		}
		Map<String, Set<Id>> peopleByKinds = new Map<String, Set<Id>>();
		Map<String, Set<String>> kindsByKey = new Map<String, Set<String>>();
		for (Id personId : personIds) {
			Set<String> remaining = new Set<String>(OBJECT_BY_KIND.keySet());
			if (KINDS_SYNCED_HERE.containsKey(personId)) {
				remaining.removeAll(KINDS_SYNCED_HERE.get(personId));
			}
			if (remaining.isEmpty()) {
				continue;
			}
			List<String> sorted = new List<String>(remaining);
			sorted.sort();
			String key = String.join(sorted, ';');
			if (!peopleByKinds.containsKey(key)) {
				peopleByKinds.put(key, new Set<Id>());
				kindsByKey.put(key, remaining);
			}
			peopleByKinds.get(key).add(personId);
		}
		for (String key : peopleByKinds.keySet()) {
			Set<String> kinds = kindsByKey.get(key);
			syncOrQueue(
				peopleByKinds.get(key),
				kinds.size() == OBJECT_BY_KIND.size() ? null : kinds
			);
		}
	}

	/**
	 * Syncs these people now when the transaction has room, or queues the work when it does not.
	 * Never throws.
	 */
	public static void syncOrQueue(Set<Id> personIds, Set<String> onlyKinds) {
		if (personIds == null || personIds.isEmpty()) {
			return;
		}
		Boolean roomy =
			Limits.getLimitQueries() - Limits.getQueries() > 25 &&
			Limits.getLimitDmlStatements() - Limits.getDmlStatements() > 12;
		if (roomy) {
			syncPeople(personIds, onlyKinds);
			return;
		}
		try {
			System.enqueueJob(new Job(personIds, onlyKinds));
		} catch (Exception notQueued) {
			ErrorLogger.logMessage(
				BarnHelp.text(
					'ContactPoints',
					'ContactPoints_Log_NotQueued',
					new List<Object>{ personIds.size() }
				),
				CONTEXT,
				ErrorLogger.SEVERITY_WARNING
			);
		}
	}

	/** The queued sync, for a save that had too little room left. */
	public without sharing class Job implements Queueable {
		private final Set<Id> personIds;
		private final Set<String> onlyKinds;

		public Job(Set<Id> personIds, Set<String> onlyKinds) {
			this.personIds = personIds;
			this.onlyKinds = onlyKinds;
		}

		public void execute(QueueableContext context) {
			syncPeople(personIds, onlyKinds);
		}
	}

	/**
	 * Makes these people's managed Contact Points match their BarnCRM values, for the kinds
	 * given (all when null). Never throws: a failure is logged and counted.
	 */
	public static Result syncPeople(Set<Id> personIds, Set<String> onlyKinds) {
		Result result = new Result();
		Set<String> kinds = activeKinds();
		if (onlyKinds != null) {
			kinds.retainAll(onlyKinds);
		}
		Set<Id> contactIds = contactsOnly(personIds);
		if (kinds.isEmpty() || contactIds.isEmpty()) {
			return result;
		}
		Boolean wasRunning = running;
		running = true;
		try {
			new Run(kinds, contactIds, result).go();
		} catch (Exception unexpected) {
			ErrorLogger.log(unexpected, CONTEXT);
			result.failed += 1;
		} finally {
			running = wasRunning;
		}
		return result;
	}

	/**
	 * Deletes the managed Contact Points of people about to be deleted (R-CPL4); their links go
	 * with them. Every kind, switched on or not, so a deleted person leaves no copy behind.
	 */
	public static void deleteCopiesOf(Set<Id> personIds) {
		Set<Id> contactIds = contactsOnly(personIds);
		if (contactIds.isEmpty()) {
			return;
		}
		try {
			List<Id> copies = new List<Id>();
			for (Contact_Point_Link__c link : [
				SELECT Contact_Point_Id__c
				FROM Contact_Point_Link__c
				WHERE Contact__c IN :contactIds AND Contact_Point_Id__c != NULL
				WITH SYSTEM_MODE
				ORDER BY Contact_Point_Id__c
			]) {
				// Ordered, so the IDs of each object come together (at most ten runs a save).
				copies.add(Id.valueOf(link.Contact_Point_Id__c));
			}
			if (!copies.isEmpty()) {
				Database.delete(copies, false, AccessLevel.SYSTEM_MODE);
			}
		} catch (Exception unexpected) {
			ErrorLogger.log(unexpected, CONTEXT);
		}
	}

	/**
	 * Gives people about to be saved an Individual when they have something to copy and none
	 * yet, so the copy after the save needs no second save of the person. Before insert and
	 * before update only. Never throws.
	 */
	public static void linkIndividualsBeforeSave(List<Contact> people) {
		Set<String> kinds = activeKinds();
		if (people == null || people.isEmpty() || kinds.isEmpty()) {
			return;
		}
		List<SObject> needing = new List<SObject>();
		for (Contact person : people) {
			if (person.get(INDIVIDUAL_LINK) == null && hasEmailOrPhone(person, kinds)) {
				needing.add(person);
			}
		}
		try {
			giveIndividuals(needing, false);
		} catch (Exception unexpected) {
			ErrorLogger.log(unexpected, CONTEXT);
		}
	}

	private static Boolean hasEmailOrPhone(Contact person, Set<String> kinds) {
		Set<String> onlyValues = kinds.clone();
		onlyValues.remove(ContactPointPlan.ADDRESS);
		return !ContactPointPlan.plan(person.getPopulatedFieldsAsMap(), null, onlyValues).isEmpty();
	}

	/**
	 * Creates an Individual named as each person and links it. With `save`, the people are
	 * updated with the link; without, the link is only set on the records in memory (before a
	 * save). People whose Individual is refused are logged and left without one.
	 */
	private static void giveIndividuals(List<SObject> people, Boolean save) {
		if (people.isEmpty()) {
			return;
		}
		Schema.SObjectType individualType = Schema.getGlobalDescribe().get(INDIVIDUAL);
		List<SObject> individuals = new List<SObject>();
		for (SObject person : people) {
			SObject record = individualType.newSObject();
			record.put('FirstName', person.get('FirstName'));
			String lastName = (String) person.get('LastName');
			record.put('LastName', String.isBlank(lastName) ? '-' : lastName);
			individuals.add(record);
		}
		List<Database.SaveResult> saved = Database.insert(
			individuals,
			false,
			AccessLevel.SYSTEM_MODE
		);
		List<SObject> links = new List<SObject>();
		List<SObject> linkedPeople = new List<SObject>();
		List<String> problems = new List<String>();
		for (Integer i = 0; i < saved.size(); i++) {
			SObject person = people[i];
			if (!saved[i].isSuccess()) {
				problems.add(refusal('Individual', person.Id, saved[i].getErrors()));
				continue;
			}
			person.put(INDIVIDUAL_LINK, saved[i].getId());
			INDIVIDUALS_CREATED_HERE.add(saved[i].getId());
			if (save) {
				SObject link = Contact.SObjectType.newSObject(person.Id);
				link.put(INDIVIDUAL_LINK, saved[i].getId());
				links.add(link);
				linkedPeople.add(person);
			}
		}
		if (!links.isEmpty()) {
			List<Database.SaveResult> linked = Database.update(
				links,
				false,
				AccessLevel.SYSTEM_MODE
			);
			for (Integer i = 0; i < linked.size(); i++) {
				if (!linked[i].isSuccess()) {
					problems.add(refusal('Individual', links[i].Id, linked[i].getErrors()));
					linkedPeople[i].put(INDIVIDUAL_LINK, null);
				}
			}
		}
		logProblems(problems);
	}

	// ------------------------------------------------------------------------------ the run

	/** One sync of a set of people: read, plan, write. */
	private without sharing class Run {
		private final Set<String> kinds;
		private final Set<Id> contactIds;
		private final Result result;
		private final List<String> problems = new List<String>();

		private Map<Id, SObject> people;
		private final Map<Id, List<ContactPointPlan.Desired>> wantedByPerson = new Map<Id, List<ContactPointPlan.Desired>>();
		private final Map<Id, SObject> existing = new Map<Id, SObject>();
		/** Unlinked Contact Points by parent, kind and match key, offered for adoption. */
		private final Map<String, List<SObject>> adoptable = new Map<String, List<SObject>>();

		// What to write.
		private final List<SObject> toCreate = new List<SObject>();
		private final List<Contact_Point_Link__c> linksForCreated = new List<Contact_Point_Link__c>();
		private final List<SObject> toUpdate = new List<SObject>();
		private final Set<Id> toDelete = new Set<Id>();
		private final List<Contact_Point_Link__c> linksToSave = new List<Contact_Point_Link__c>();
		private final List<Contact_Point_Link__c> linksToDelete = new List<Contact_Point_Link__c>();

		Run(Set<String> kinds, Set<Id> contactIds, Result result) {
			this.kinds = kinds;
			this.contactIds = contactIds;
			this.result = result;
		}

		void go() {
			people = readPeople();
			if (people.isEmpty()) {
				return;
			}
			Map<Id, List<Map<String, Object>>> addresses = kinds.contains(ContactPointPlan.ADDRESS)
				? readAddresses(people.keySet())
				: new Map<Id, List<Map<String, Object>>>();
			List<SObject> needingIndividual = new List<SObject>();
			for (SObject person : people.values()) {
				List<ContactPointPlan.Desired> wanted = ContactPointPlan.plan(
					person.getPopulatedFieldsAsMap(),
					addresses.get(person.Id),
					kinds
				);
				wantedByPerson.put(person.Id, wanted);
				if (!wanted.isEmpty() && person.get(INDIVIDUAL_LINK) == null) {
					needingIndividual.add(person);
				}
			}
			giveIndividuals(needingIndividual, true);
			Map<Id, List<Contact_Point_Link__c>> linksByPerson = readLinks();
			readAdoptable();
			for (SObject person : people.values()) {
				planPerson(
					person,
					linksByPerson.containsKey(person.Id)
						? linksByPerson.get(person.Id)
						: new List<Contact_Point_Link__c>()
				);
			}
			write();
			logProblems(problems);
			for (Id personId : people.keySet()) {
				if (!KINDS_SYNCED_HERE.containsKey(personId)) {
					KINDS_SYNCED_HERE.put(personId, new Set<String>());
				}
				KINDS_SYNCED_HERE.get(personId).addAll(kinds);
			}
		}

		private Map<Id, SObject> readPeople() {
			Set<Id> ids = contactIds.clone();
			// Field names come from this module's own constants, never from a caller; escaped regardless.
			String soql = String.escapeSingleQuotes(
				'SELECT Id, FirstName, LastName, ' +
					INDIVIDUAL_LINK +
					', ' +
					String.join(ContactPointPlan.personFields(), ', ') +
					' FROM Contact WHERE Id IN :ids'
			);
			return new Map<Id, SObject>(Database.query(soql, AccessLevel.SYSTEM_MODE));
		}

		/** Each person's current addresses: their own and their household's. */
		private Map<Id, List<Map<String, Object>>> readAddresses(Set<Id> personIds) {
			// A person account belongs to households, and owns addresses, by its account (decision 14).
			Map<Id, Id> accountByContact = PersonRecordSelector.getAccountsBehindPersonContacts(
				personIds
			);
			Map<Id, Id> contactByAccount = new Map<Id, Id>();
			for (Id contactId : accountByContact.keySet()) {
				contactByAccount.put(accountByContact.get(contactId), contactId);
			}
			Set<Id> askedAbout = new Set<Id>();
			for (Id personId : personIds) {
				askedAbout.add(
					accountByContact.containsKey(personId)
						? accountByContact.get(personId)
						: personId
				);
			}
			Map<Id, Id> householdByPerson = HouseholdService.getHouseholdIdsFor(askedAbout);
			Set<Id> householdIds = new Set<Id>(householdByPerson.values());
			householdIds.remove(null);
			Set<Id> ownerAccounts = contactByAccount.keySet();
			Map<Id, Set<Id>> peopleByHousehold = new Map<Id, Set<Id>>();
			for (Id askedId : householdByPerson.keySet()) {
				Id householdId = householdByPerson.get(askedId);
				if (householdId != null) {
					if (!peopleByHousehold.containsKey(householdId)) {
						peopleByHousehold.put(householdId, new Set<Id>());
					}
					peopleByHousehold
						.get(householdId)
						.add(
							contactByAccount.containsKey(askedId)
								? contactByAccount.get(askedId)
								: askedId
						);
				}
			}
			Map<Id, List<Map<String, Object>>> result = new Map<Id, List<Map<String, Object>>>();
			for (Address__c address : [
				SELECT
					Id,
					Contact__c,
					Account__c,
					Person_Account__c,
					Street__c,
					City__c,
					State__c,
					Postal_Code__c,
					Country__c,
					Is_Default__c,
					Type__c,
					Status__c
				FROM Address__c
				WHERE
					(Contact__c IN :personIds
					OR Account__c IN :householdIds
					OR Person_Account__c IN :ownerAccounts)
					AND (Status__c = 'Current'
					OR Status__c = NULL)
				WITH SYSTEM_MODE
				ORDER BY CreatedDate, Id
			]) {
				Set<Id> owners = new Set<Id>();
				if (address.Contact__c != null) {
					owners.add(address.Contact__c);
				} else if (address.Person_Account__c != null) {
					if (contactByAccount.containsKey(address.Person_Account__c)) {
						owners.add(contactByAccount.get(address.Person_Account__c));
					}
				} else if (peopleByHousehold.containsKey(address.Account__c)) {
					owners.addAll(peopleByHousehold.get(address.Account__c));
				}
				for (Id owner : owners) {
					if (!result.containsKey(owner)) {
						result.put(owner, new List<Map<String, Object>>());
					}
					result.get(owner).add(address.getPopulatedFieldsAsMap());
				}
			}
			return result;
		}

		/** The people's links for the kinds in this run, oldest first, and the copies they name. */
		private Map<Id, List<Contact_Point_Link__c>> readLinks() {
			Map<Id, List<Contact_Point_Link__c>> result = new Map<Id, List<Contact_Point_Link__c>>();
			Set<Id> personIds = people.keySet();
			Map<String, Set<Id>> copyIdsByKind = new Map<String, Set<Id>>();
			for (Contact_Point_Link__c link : [
				SELECT Id, Contact__c, Kind__c, Source__c, Contact_Point_Id__c
				FROM Contact_Point_Link__c
				WHERE Contact__c IN :personIds AND Kind__c IN :kinds
				WITH SYSTEM_MODE
				ORDER BY CreatedDate, Id
			]) {
				if (!result.containsKey(link.Contact__c)) {
					result.put(link.Contact__c, new List<Contact_Point_Link__c>());
				}
				result.get(link.Contact__c).add(link);
				if (link.Contact_Point_Id__c != null) {
					if (!copyIdsByKind.containsKey(link.Kind__c)) {
						copyIdsByKind.put(link.Kind__c, new Set<Id>());
					}
					copyIdsByKind.get(link.Kind__c).add(Id.valueOf(link.Contact_Point_Id__c));
				}
			}
			for (String kind : copyIdsByKind.keySet()) {
				Set<Id> ids = copyIdsByKind.get(kind);
				existing.putAll(
					Database.query(selectOf(kind, ' WHERE Id IN :ids'), AccessLevel.SYSTEM_MODE)
				);
			}
			return result;
		}

		/** Contact Points on the people's Individuals that no link names. */
		private void readAdoptable() {
			Set<Id> parents = new Set<Id>();
			for (SObject person : people.values()) {
				Id individual = (Id) person.get(INDIVIDUAL_LINK);
				if (individual != null && !INDIVIDUALS_CREATED_HERE.contains(individual)) {
					parents.add(individual);
				}
			}
			if (parents.isEmpty()) {
				return;
			}
			Map<Id, SObject> unlinked = new Map<Id, SObject>();
			Map<Id, String> kindById = new Map<Id, String>();
			for (String kind : kinds) {
				for (
					SObject row : Database.query(
						selectOf(kind, ' WHERE ParentId IN :parents ORDER BY CreatedDate'),
						AccessLevel.SYSTEM_MODE
					)
				) {
					if (!existing.containsKey(row.Id)) {
						unlinked.put(row.Id, row);
						kindById.put(row.Id, kind);
					}
				}
			}
			if (unlinked.isEmpty()) {
				return;
			}
			Set<String> candidateIds = new Set<String>();
			for (Id rowId : unlinked.keySet()) {
				candidateIds.add(String.valueOf(rowId));
			}
			for (Contact_Point_Link__c other : [
				SELECT Contact_Point_Id__c
				FROM Contact_Point_Link__c
				WHERE Contact_Point_Id__c IN :candidateIds
				WITH SYSTEM_MODE
			]) {
				unlinked.remove(Id.valueOf(other.Contact_Point_Id__c));
			}
			for (SObject row : unlinked.values()) {
				String kind = kindById.get(row.Id);
				String key = adoptKey(
					(Id) row.get(PARENT),
					kind,
					ContactPointPlan.matchKey(kind, row.getPopulatedFieldsAsMap())
				);
				if (!adoptable.containsKey(key)) {
					adoptable.put(key, new List<SObject>());
				}
				adoptable.get(key).add(row);
			}
		}

		/** What to write for one person. */
		private void planPerson(SObject person, List<Contact_Point_Link__c> links) {
			// Not "parent": Apex names ignore case, so that would hide the PARENT field constant.
			Id parentId = (Id) person.get(INDIVIDUAL_LINK);
			Map<String, List<Contact_Point_Link__c>> linksByKey = new Map<String, List<Contact_Point_Link__c>>();
			for (Contact_Point_Link__c link : links) {
				String key = ContactPointPlan.keyOf(link.Kind__c, link.Source__c);
				if (!linksByKey.containsKey(key)) {
					linksByKey.put(key, new List<Contact_Point_Link__c>());
				}
				linksByKey.get(key).add(link);
			}
			for (ContactPointPlan.Desired wanted : wantedByPerson.get(person.Id)) {
				List<Contact_Point_Link__c> sameKey = linksByKey.get(wanted.key());
				Contact_Point_Link__c link = sameKey == null || sameKey.isEmpty()
					? null
					: sameKey.remove(0);
				if (parentId == null) {
					// No Individual to hang a copy from: leave what is there.
					continue;
				}
				planOne(person.Id, parentId, wanted, link);
			}
			// Links left over name a value the person no longer has, or are a second link to
			// the same source after a merge (R-CPL3).
			for (List<Contact_Point_Link__c> leftover : linksByKey.values()) {
				for (Contact_Point_Link__c link : leftover) {
					if (parentId == null && wantedSourceStill(person.Id, link)) {
						continue;
					}
					if (link.Contact_Point_Id__c != null) {
						toDelete.add(Id.valueOf(link.Contact_Point_Id__c));
					}
					linksToDelete.add(link);
				}
			}
		}

		private Boolean wantedSourceStill(Id personId, Contact_Point_Link__c link) {
			for (ContactPointPlan.Desired wanted : wantedByPerson.get(personId)) {
				if (wanted.key() == ContactPointPlan.keyOf(link.Kind__c, link.Source__c)) {
					return true;
				}
			}
			return false;
		}

		private void planOne(
			Id personId,
			Id parentId,
			ContactPointPlan.Desired wanted,
			Contact_Point_Link__c link
		) {
			SObject current = link == null ||
				link.Contact_Point_Id__c == null
				? null
				: existing.get(Id.valueOf(link.Contact_Point_Id__c));
			if (current != null && (Id) current.get(PARENT) != parentId) {
				// The person now has another Individual: the copy moves with them.
				toDelete.add(current.Id);
				current = null;
			}
			if (current == null && link == null) {
				current = adopt(parentId, wanted);
			}
			if (link == null) {
				link = new Contact_Point_Link__c(
					Contact__c = personId,
					Kind__c = wanted.kind,
					Source__c = wanted.source
				);
			}
			if (current == null) {
				SObject created = typeOf(wanted.kind).newSObject();
				created.put(PARENT, parentId);
				putValues(created, wanted, wanted.values.keySet());
				toCreate.add(created);
				linksForCreated.add(link);
				return;
			}
			Set<String> changed = ContactPointPlan.differences(
				writable(wanted),
				current.getPopulatedFieldsAsMap()
			);
			if (!changed.isEmpty()) {
				SObject changes = typeOf(wanted.kind).newSObject(current.Id);
				putValues(changes, wanted, changed);
				toUpdate.add(changes);
			}
			if (link.Id == null || link.Contact_Point_Id__c != String.valueOf(current.Id)) {
				link.Contact_Point_Id__c = current.Id;
				linksToSave.add(link);
			}
		}

		private SObject adopt(Id parentId, ContactPointPlan.Desired wanted) {
			List<SObject> pool = adoptable.get(adoptKey(parentId, wanted.kind, wanted.matchKey()));
			return pool == null || pool.isEmpty() ? null : pool.remove(0);
		}

		private void write() {
			if (!toDelete.isEmpty()) {
				// Sorted, so the IDs of each object come together (at most ten runs a save).
				List<Id> deleteIds = new List<Id>(toDelete);
				deleteIds.sort();
				List<Database.DeleteResult> deleted = Database.delete(
					deleteIds,
					false,
					AccessLevel.SYSTEM_MODE
				);
				for (Database.DeleteResult outcome : deleted) {
					if (outcome.isSuccess()) {
						result.deleted += 1;
					}
				}
			}
			groupByType();
			Database.DMLOptions options = new Database.DMLOptions();
			options.optAllOrNone = false;
			options.allowFieldTruncation = true;
			if (!toCreate.isEmpty()) {
				List<Database.SaveResult> saved = Database.insert(
					toCreate,
					options,
					AccessLevel.SYSTEM_MODE
				);
				for (Integer i = 0; i < saved.size(); i++) {
					Contact_Point_Link__c link = linksForCreated[i];
					if (saved[i].isSuccess()) {
						result.created += 1;
						link.Contact_Point_Id__c = saved[i].getId();
						linksToSave.add(link);
					} else {
						result.failed += 1;
						problems.add(refusal(link.Kind__c, link.Contact__c, saved[i].getErrors()));
					}
				}
			}
			if (!toUpdate.isEmpty()) {
				List<Database.SaveResult> saved = Database.update(
					toUpdate,
					options,
					AccessLevel.SYSTEM_MODE
				);
				for (Integer i = 0; i < saved.size(); i++) {
					if (saved[i].isSuccess()) {
						result.updated += 1;
					} else {
						result.failed += 1;
						problems.add(
							refusal('Contact Point', toUpdate[i].Id, saved[i].getErrors())
						);
					}
				}
			}
			saveLinks();
		}

		/**
		 * One save takes at most ten runs of a type, so the rows are grouped by kind (each
		 * created row keeps its link at the same index).
		 */
		private void groupByType() {
			List<SObject> created = new List<SObject>();
			List<Contact_Point_Link__c> createdLinks = new List<Contact_Point_Link__c>();
			List<SObject> updated = new List<SObject>();
			for (String kind : OBJECT_BY_KIND.keySet()) {
				Schema.SObjectType type = typeOf(kind);
				for (Integer i = 0; i < toCreate.size(); i++) {
					if (linksForCreated[i].Kind__c == kind) {
						created.add(toCreate[i]);
						createdLinks.add(linksForCreated[i]);
					}
				}
				for (SObject row : toUpdate) {
					if (type != null && row.getSObjectType() == type) {
						updated.add(row);
					}
				}
			}
			toCreate.clear();
			toCreate.addAll(created);
			linksForCreated.clear();
			linksForCreated.addAll(createdLinks);
			toUpdate.clear();
			toUpdate.addAll(updated);
		}

		private void saveLinks() {
			if (!linksToSave.isEmpty()) {
				List<Database.UpsertResult> saved = Database.upsert(
					linksToSave,
					false,
					AccessLevel.SYSTEM_MODE
				);
				for (Integer i = 0; i < saved.size(); i++) {
					if (!saved[i].isSuccess()) {
						problems.add(
							refusal(
								'Contact Point Link',
								linksToSave[i].Contact__c,
								saved[i].getErrors()
							)
						);
					}
				}
			}
			if (!linksToDelete.isEmpty()) {
				Database.delete(linksToDelete, false, AccessLevel.SYSTEM_MODE);
			}
		}
	}

	// ------------------------------------------------------------------------------ helpers

	/**
	 * The contacts behind these people. A person stored as a contact is itself; a person
	 * account is the contact the platform keeps behind it (decision 14), found only where the
	 * org has person accounts. Any other id is left out.
	 */
	private static Set<Id> contactsOnly(Set<Id> personIds) {
		Set<Id> result = new Set<Id>();
		if (personIds == null) {
			return result;
		}
		Set<Id> accounts = new Set<Id>();
		for (Id personId : personIds) {
			if (personId == null) {
				continue;
			}
			if (personId.getSObjectType() == Contact.SObjectType) {
				result.add(personId);
			} else if (personId.getSObjectType() == Account.SObjectType) {
				accounts.add(personId);
			}
		}
		if (!accounts.isEmpty() && HouseholdService.isPersonAccountOrg()) {
			result.addAll(PersonRecordSelector.getPersonContactIds(accounts).values());
		}
		return result;
	}

	private static String adoptKey(Id parentId, String kind, String matchKey) {
		return parentId + '|' + kind + '|' + matchKey;
	}

	/** The fields of a kind this org's object has and a save may set. */
	private static Set<String> writableFields(String kind) {
		Set<String> result = new Set<String>();
		Map<String, Schema.SObjectField> fieldMap = typeOf(kind).getDescribe().fields.getMap();
		for (String name : FIELDS_BY_KIND.get(kind)) {
			Schema.SObjectField field = fieldMap.get(name.toLowerCase());
			if (field == null) {
				continue;
			}
			Schema.DescribeFieldResult described = field.getDescribe();
			if (!described.isAutoNumber() && !described.isCalculated()) {
				result.add(name);
			}
		}
		return result;
	}

	private static Map<String, Set<String>> writableByKind = new Map<String, Set<String>>();

	private static Set<String> cachedWritable(String kind) {
		if (!writableByKind.containsKey(kind)) {
			writableByKind.put(kind, writableFields(kind));
		}
		return writableByKind.get(kind);
	}

	/** The wanted values this org can hold: fields it has, and a phone type its picklist lists. */
	private static Map<String, Object> writable(ContactPointPlan.Desired wanted) {
		Map<String, Object> result = new Map<String, Object>();
		Set<String> fields = cachedWritable(wanted.kind);
		for (String field : wanted.values.keySet()) {
			if (
				fields.contains(field) && allowedValue(wanted.kind, field, wanted.values.get(field))
			) {
				result.put(field, wanted.values.get(field));
			}
		}
		return result;
	}

	private static Map<String, Set<String>> picklistByField = new Map<String, Set<String>>();

	private static Boolean allowedValue(String kind, String field, Object value) {
		if (field != 'PhoneType' || value == null) {
			return true;
		}
		String key = kind + '.' + field;
		if (!picklistByField.containsKey(key)) {
			Set<String> values = new Set<String>();
			for (
				Schema.PicklistEntry entry : typeOf(kind)
					.getDescribe()
					.fields.getMap()
					.get(field.toLowerCase())
					.getDescribe()
					.getPicklistValues()
			) {
				if (entry.isActive()) {
					values.add(entry.getValue());
				}
			}
			picklistByField.put(key, values);
		}
		return picklistByField.get(key).contains(String.valueOf(value));
	}

	private static void putValues(
		SObject target,
		ContactPointPlan.Desired wanted,
		Set<String> only
	) {
		Map<String, Object> values = writable(wanted);
		for (String field : values.keySet()) {
			if (only.contains(field)) {
				target.put(field, values.get(field));
			}
		}
	}

	/** The query of a kind's Contact Points with every field this module compares. */
	/** Object and field names come from this class's maps and describe, never from a caller. */
	private static String selectOf(String kind, String filter) {
		List<String> fields = new List<String>{ 'Id', PARENT };
		fields.addAll(cachedWritable(kind));
		return String.escapeSingleQuotes(
			'SELECT ' + String.join(fields, ', ') + ' FROM ' + OBJECT_BY_KIND.get(kind) + filter
		);
	}

	private static String refusal(String what, Id recordId, List<Database.Error> errors) {
		List<String> messages = new List<String>();
		for (Database.Error error : errors) {
			messages.add(error.getMessage());
		}
		return BarnHelp.text(
			'ContactPoints',
			'ContactPoints_Log_Refused',
			new List<Object>{ what, recordId, String.join(messages, '; ') }
		);
	}

	private static void logProblems(List<String> problems) {
		if (!problems.isEmpty()) {
			ErrorLogger.logMessages(problems, CONTEXT, ErrorLogger.SEVERITY_WARNING);
		}
	}
}
