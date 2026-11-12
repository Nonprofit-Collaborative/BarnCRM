/**
 * The Gift Transaction mirror (feature X-07, canonical model Section 29C1, ADR-0157): its
 * settings, the check of a typed link, and the copy of each received gift to a Nonprofit Cloud
 * Gift Transaction with its designations.
 *
 * The copy is made only by runs (R-GT6): `GiftTransactionMirrorBatch` calls `copyGifts` one chunk
 * at a time, as the person who started or scheduled the run. Saving a gift copies nothing; the
 * `Gift_Transaction_Mirror` automation only checks a typed link (R-GT9) and reports the Gift
 * Transactions deleted gifts leave behind (R-GT8), and it reads no Nonprofit Cloud record.
 *
 * The Nonprofit Cloud objects and their fields are reached only through
 * `GiftTransactionMirrorSchema` and SObject generics, so Mirror installs and this class compiles
 * where Nonprofit Cloud does not exist; there the mirror does nothing (plan Section 4.2, R-GT1).
 *
 * Every write is in user mode with partial success (R-GT7): a Gift Transaction is a record the
 * package does not own, and one the platform refuses is counted and logged, never allowed to stop
 * the run. Refusals are grouped by the platform's message for the run to write once when it ends.
 */
public with sharing class GiftTransactionMirrorService {
	/** The registry name of the automation, used to bypass it while a run stores links. */
	public static final String AUTOMATION_NAME = 'Gift_Transaction_Mirror';
	public static final String OFF = 'Off';
	public static final String GIFTS_TO_GIFT_TRANSACTIONS = 'GiftsToGiftTransactions';
	public static final String CONTEXT = 'Gift Transaction mirror';
	/** The paid status when none is saved: the field's shipped default (R-GT2). */
	public static final String DEFAULT_PAID_STATUS = 'Paid';

	/** R-GT3: the only status copied. A refund or write-off is a negative gift and never is. */
	public static final Set<String> MIRRORED_STATUSES = new Set<String>{ 'Received' };
	/** R-GT3: an in-kind gift carries no money (R-G12) and is not copied. */
	public static final String TYPE_IN_KIND = 'In-kind';

	/** The start date as last read, and the setting it was read from, so a change is seen. */
	private static Date cachedStartDate;
	private static Datetime cachedStartSetting;
	private static String orgTimeZone;

	/** What one call did, for the run summary and the tests. */
	public class Result {
		public Integer created = 0;
		public Integer updated = 0;
		public Integer unchanged = 0;
		public Integer failed = 0;
		public Integer skipped = 0;
		/** Designations written, and allocations left without one (R-GT5). */
		public Integer designated = 0;
		public Integer undesignated = 0;
		/** True when Gift Transactions were created but designations could not be written. */
		public Boolean designationsUnavailable = false;
		/** The refusals, grouped by message; written by the run when it ends (R-GT7). */
		public MirrorSync.Warnings refusals = new MirrorSync.Warnings();
		/** The gifts whose Gift Transaction this call created and linked, for the designations. */
		public List<Gift__c> createdFor = new List<Gift__c>();

		public void add(Result other) {
			created += other.created;
			updated += other.updated;
			unchanged += other.unchanged;
			failed += other.failed;
			skipped += other.skipped;
			designated += other.designated;
			undesignated += other.undesignated;
			designationsUnavailable = designationsUnavailable || other.designationsUnavailable;
			refusals.addAll(other.refusals);
		}

		/** Writes the grouped refusals as Warnings, in one statement. */
		public void writeRefusals() {
			refusals.write(
				CONTEXT,
				BarnHelp.text('Mirror', 'Mirror_GiftTransactionMirror_LogOne'),
				BarnHelp.text('Mirror', 'Mirror_GiftTransactionMirror_LogMany')
			);
		}
	}

	// ------------------------------------------------------------------ settings and the org

	public static Boolean isAvailable() {
		return GiftTransactionMirrorSchema.isAvailable();
	}

	/**
	 * The chosen direction (R-GT1): GiftsToGiftTransactions, or Off for anything else, including
	 * an empty setting and a direction this version does not offer.
	 */
	public static String direction() {
		Mirror_Settings__c settings = Mirror_Settings__c.getOrgDefaults();
		String chosen = settings?.Gift_Transaction_Mirror_Direction__c;
		return chosen != null &&
			chosen.trim() == GIFTS_TO_GIFT_TRANSACTIONS
			? GIFTS_TO_GIFT_TRANSACTIONS
			: OFF;
	}

	/** Whether the mirror copies in this org: it is available and its direction is chosen. */
	public static Boolean isOn() {
		return direction() != OFF && isAvailable();
	}

	/** The Status value that means paid in this org, as set, or the shipped default (R-GT2). */
	public static String paidStatus() {
		String typed = Mirror_Settings__c.getOrgDefaults()?.Gift_Transaction_Mirror_Status__c;
		return String.isBlank(typed) ? DEFAULT_PAID_STATUS : typed.trim();
	}

	/**
	 * The start date (R-GT2), or null while none is set. Read in the org's default time zone, so a
	 * nightly run started by anyone uses the same day, and read once per transaction.
	 */
	public static Date startDate() {
		Datetime start = Mirror_Settings__c.getOrgDefaults()?.Gift_Transaction_Mirror_Start__c;
		if (start == null) {
			return null;
		}
		if (start != cachedStartSetting) {
			if (orgTimeZone == null) {
				orgTimeZone = [SELECT TimeZoneSidKey FROM Organization WITH SYSTEM_MODE LIMIT 1]
				.TimeZoneSidKey;
			}
			cachedStartDate = Date.valueOf(start.format('yyyy-MM-dd', orgTimeZone));
			cachedStartSetting = start;
		}
		return cachedStartDate;
	}

	/**
	 * Why the mirror cannot copy anything yet, in words, or null when the paid status is one of
	 * the org's and the start date is set (R-GT2). Asked only once the mirror is available.
	 */
	public static String notReadyReason() {
		String status = paidStatus();
		if (!GiftTransactionMirrorSchema.isActiveStatus(status)) {
			return String.format(
				BarnHelp.text('Mirror', 'Mirror_GiftTransactionMirror_UnknownStatus'),
				new List<Object>{ status }
			);
		}
		if (startDate() == null) {
			return BarnHelp.text('Mirror', 'Mirror_GiftTransactionMirror_NoStartDate');
		}
		return null;
	}

	/**
	 * Whether a run started by the running person could do its work: read, create and edit Gift
	 * Transactions with the fields R-GT4 needs, and store the link on the gift.
	 */
	public static Boolean canRun() {
		if (!isAvailable()) {
			return false;
		}
		Schema.DescribeFieldResult link = Gift__c.Gift_Transaction_Id__c.getDescribe();
		List<String> compared = GiftTransactionMirrorSchema.compared();
		return GiftTransactionMirrorSchema.canRead(compared) &&
			GiftTransactionMirrorSchema.canCreate(GiftTransactionMirrorSchema.requiredToCreate()) &&
			GiftTransactionMirrorSchema.canUpdate(compared) &&
			link.isAccessible() &&
			link.isUpdateable();
	}

	/** R-GT3: whether a gift is one the mirror copies. */
	public static Boolean isMirrored(Gift__c gift) {
		Date start = startDate();
		return MIRRORED_STATUSES.contains(gift.Status__c) &&
			gift.Amount__c != null &&
			gift.Amount__c > 0 &&
			gift.Type__c != TYPE_IN_KIND &&
			start != null &&
			gift.Gift_Date__c != null &&
			gift.Gift_Date__c >= start;
	}

	// ----------------------------------------------------------------- the automation on Gift

	/**
	 * R-GT9, before insert and update: a typed or changed Gift Transaction ID must be a Gift
	 * Transaction's identifier, and is stored in its 18 character form. Only a changed, non-empty
	 * link is looked at, and only where the saver can see Gift Transactions, so a save that does
	 * not touch the link, or one in an org without Nonprofit Cloud, reads nothing.
	 */
	public static void checkLinks(List<Gift__c> gifts, Map<Id, Gift__c> oldById) {
		if (gifts == null) {
			return;
		}
		for (Gift__c gift : gifts) {
			if (String.isBlank(gift.Gift_Transaction_Id__c)) {
				if (gift.Gift_Transaction_Id__c != null) {
					gift.Gift_Transaction_Id__c = null;
				}
				continue;
			}
			Gift__c old = oldById == null ? null : oldById.get(gift.Id);
			if (
				old != null &&
				MirrorSync.same(old.Gift_Transaction_Id__c, gift.Gift_Transaction_Id__c)
			) {
				continue;
			}
			Schema.SObjectType giftTransaction = GiftTransactionMirrorSchema.objectType();
			if (giftTransaction == null) {
				return;
			}
			Id typed = MirrorSync.idOf(gift.Gift_Transaction_Id__c, giftTransaction);
			if (typed == null) {
				gift.Gift_Transaction_Id__c.addError(
					BarnHelp.text('Mirror', 'Mirror_GiftTransactionMirror_InvalidGiftTransactionId')
				);
			} else {
				gift.Gift_Transaction_Id__c = String.valueOf(typed);
			}
		}
	}

	/**
	 * R-GT8, after delete: the Gift Transaction of a deleted gift is left in place, and one Warning
	 * per message names the gifts and their Gift Transactions.
	 */
	public static void warnDeleted(List<Gift__c> deleted) {
		if (deleted == null || deleted.isEmpty()) {
			return;
		}
		List<Gift__c> linked = new List<Gift__c>();
		for (Gift__c gift : deleted) {
			if (gift.Gift_Transaction_Id__c != null) {
				linked.add(gift);
			}
		}
		if (linked.isEmpty() || !isOn()) {
			return;
		}
		MirrorSync.Warnings warnings = new MirrorSync.Warnings();
		for (Gift__c gift : linked) {
			warnings.add(
				BarnHelp.text('Mirror', 'Mirror_GiftTransactionMirror_DeletedKept'),
				gift.Name + ' (' + gift.Gift_Transaction_Id__c + ')',
				gift.Id
			);
		}
		warnings.write(
			CONTEXT,
			BarnHelp.text('Mirror', 'Mirror_GiftTransactionMirror_LogDeletedOne'),
			BarnHelp.text('Mirror', 'Mirror_GiftTransactionMirror_LogDeletedMany')
		);
	}

	// ----------------------------------------------------------------------------- a chunk

	/**
	 * One chunk of a run (R-GT4 to R-GT7): creates the Gift Transaction of each gift that has
	 * none, updates the linked ones whose copied values differ, stores each new link on its gift,
	 * and gives each new Gift Transaction its designations. Refusals stay on the result for the
	 * run to write once.
	 *
	 * The links are stored with partial success, so one gift that cannot be saved never costs the
	 * rest of the chunk their links; a Gift Transaction made here for such a gift is deleted again
	 * at once (R-GT7). Only a failure that throws rolls the whole chunk back.
	 */
	public static Result copyGifts(List<Gift__c> gifts) {
		Result result = new Result();
		if (gifts == null || gifts.isEmpty() || !isAvailable()) {
			return result;
		}
		Map<Id, String> linkBefore = new Map<Id, String>();
		List<Gift__c> valid = new List<Gift__c>();
		Set<Id> linkedIds = new Set<Id>();
		Schema.SObjectType giftTransaction = GiftTransactionMirrorSchema.objectType();
		for (Gift__c gift : gifts) {
			linkBefore.put(gift.Id, gift.Gift_Transaction_Id__c);
			if (!isMirrored(gift)) {
				// The run's query already leaves these out; a gift changed meanwhile is not copied.
				result.unchanged++;
				continue;
			}
			if (String.isBlank(gift.Gift_Transaction_Id__c)) {
				gift.Gift_Transaction_Id__c = null;
				valid.add(gift);
				continue;
			}
			Id typed = MirrorSync.idOf(gift.Gift_Transaction_Id__c, giftTransaction);
			if (typed == null) {
				result.failed++;
				result.refusals.add(
					BarnHelp.text(
						'Mirror',
						'Mirror_GiftTransactionMirror_InvalidGiftTransactionId'
					),
					gift.Name,
					gift.Id
				);
				continue;
			}
			gift.Gift_Transaction_Id__c = String.valueOf(typed);
			linkedIds.add(typed);
			valid.add(gift);
		}
		if (valid.isEmpty()) {
			return result;
		}
		Savepoint beforeChunk = Database.setSavepoint();
		try {
			Result copied = copy(valid, linkedIds);
			storeLinks(valid, linkBefore, copied);
			writeDesignations(copied);
			result.add(copied);
		} catch (Exception unexpected) {
			Database.rollback(beforeChunk);
			ErrorLogger.log(unexpected, CONTEXT);
			Result undone = new Result();
			undone.failed = gifts.size() - result.unchanged;
			undone.unchanged = result.unchanged;
			undone.refusals = result.refusals;
			result = undone;
		}
		return result;
	}

	/**
	 * The values R-GT4 gives a Gift Transaction for this gift, keeping only the fields in
	 * `writable`: every copied field when `creating`, and only the compared ones otherwise.
	 */
	@TestVisible
	private static Map<String, Object> desiredValues(
		Gift__c gift,
		Boolean creating,
		Set<String> writable
	) {
		GiftTransactionMirrorSchema.Names names = GiftTransactionMirrorSchema.names;
		Map<String, Object> values = new Map<String, Object>();
		values.put(names.donorField, donorOf(gift));
		values.put(names.dateField, gift.Gift_Date__c);
		values.put(names.amountField, gift.Amount__c);
		if (creating) {
			if (names.currentAmountField != null) {
				values.put(names.currentAmountField, gift.Amount__c);
			}
			values.put(names.statusField, paidStatus());
			if (String.isNotBlank(gift.Name)) {
				values.put(names.nameField, gift.Name);
			}
			values.putAll(names.createdAlso);
		}
		for (String field : new List<String>(values.keySet())) {
			if (!writable.contains(field)) {
				values.remove(field);
			}
		}
		return values;
	}

	/** Whether a Gift Transaction as it is differs from what the gift says in a compared field. */
	@TestVisible
	private static Boolean differs(Map<String, Object> desired, SObject existing) {
		String amountField = GiftTransactionMirrorSchema.names.amountField;
		for (String field : desired.keySet()) {
			Object current = existing.get(field);
			if (field == amountField) {
				current = GiftTransactionMirrorSchema.decimalOf(current);
			}
			if (!MirrorSync.same(desired.get(field), current)) {
				return true;
			}
		}
		return false;
	}

	/** The Gift Transaction's donor (R-GT4): the Donor Account, else the gift's Household. */
	@TestVisible
	private static Id donorOf(Gift__c gift) {
		return gift.Donor_Account__c != null ? gift.Donor_Account__c : gift.Household__c;
	}

	/**
	 * Creates or updates the Gift Transaction of each gift, and writes a new one's identifier onto
	 * the gift in memory. Two DML statements at most, whatever the number of gifts.
	 */
	private static Result copy(List<Gift__c> gifts, Set<Id> linkedIds) {
		Result result = new Result();
		Schema.SObjectType giftTransaction = GiftTransactionMirrorSchema.objectType();
		Set<String> creatable = GiftTransactionMirrorSchema.creatable();
		List<String> compared = GiftTransactionMirrorSchema.compared();
		Set<String> updatable = GiftTransactionMirrorSchema.writable(compared, false);
		Map<Id, SObject> current = GiftTransactionMirrorSelector.giftTransactionsById(
			GiftTransactionMirrorSchema.objectName(),
			compared,
			linkedIds
		);

		List<SObject> inserts = new List<SObject>();
		List<Gift__c> insertedFor = new List<Gift__c>();
		List<SObject> updates = new List<SObject>();
		List<Gift__c> updatedFor = new List<Gift__c>();
		for (Gift__c gift : gifts) {
			if (donorOf(gift) == null) {
				result.failed++;
				result.refusals.add(
					BarnHelp.text('Mirror', 'Mirror_GiftTransactionMirror_NoAccount'),
					gift.Name,
					gift.Id
				);
				continue;
			}
			if (gift.Gift_Transaction_Id__c == null) {
				inserts.add(recordOf(giftTransaction, null, desiredValues(gift, true, creatable)));
				insertedFor.add(gift);
				continue;
			}
			SObject existing = current.get(Id.valueOf(gift.Gift_Transaction_Id__c));
			if (existing == null) {
				result.failed++;
				result.refusals.add(
					BarnHelp.text('Mirror', 'Mirror_GiftTransactionMirror_Missing'),
					gift.Name,
					gift.Id
				);
				continue;
			}
			Map<String, Object> desired = desiredValues(gift, false, updatable);
			if (differs(desired, existing)) {
				updates.add(recordOf(giftTransaction, existing.Id, desired));
				updatedFor.add(gift);
			} else {
				result.unchanged++;
			}
		}

		if (!inserts.isEmpty()) {
			List<Database.SaveResult> saved = Database.insert(
				inserts,
				false,
				AccessLevel.USER_MODE
			);
			for (Integer i = 0; i < saved.size(); i++) {
				if (saved[i].isSuccess()) {
					insertedFor[i].Gift_Transaction_Id__c = saved[i].getId();
					result.createdFor.add(insertedFor[i]);
					result.created++;
				} else {
					result.failed++;
					refuse(result, insertedFor[i], saved[i].getErrors());
				}
			}
		}
		if (!updates.isEmpty()) {
			List<Database.SaveResult> saved = Database.update(
				updates,
				false,
				AccessLevel.USER_MODE
			);
			for (Integer i = 0; i < saved.size(); i++) {
				if (saved[i].isSuccess()) {
					result.updated++;
				} else {
					result.failed++;
					refuse(result, updatedFor[i], saved[i].getErrors());
				}
			}
		}
		return result;
	}

	private static SObject recordOf(
		Schema.SObjectType giftTransaction,
		Id recordId,
		Map<String, Object> values
	) {
		SObject record = recordId == null
			? giftTransaction.newSObject(null, true)
			: giftTransaction.newSObject(recordId);
		for (String field : values.keySet()) {
			record.put(field, values.get(field));
		}
		return record;
	}

	/**
	 * Saves each gift whose link changed, with partial success and this automation bypassed. A gift
	 * that is refused is counted as failed, and a Gift Transaction created for it in this call is
	 * deleted again (R-GT7).
	 */
	private static void storeLinks(List<Gift__c> gifts, Map<Id, String> linkBefore, Result result) {
		List<Gift__c> links = new List<Gift__c>();
		List<Gift__c> linkedFor = new List<Gift__c>();
		for (Gift__c gift : gifts) {
			if (!MirrorSync.same(gift.Gift_Transaction_Id__c, linkBefore.get(gift.Id))) {
				links.add(
					new Gift__c(Id = gift.Id, Gift_Transaction_Id__c = gift.Gift_Transaction_Id__c)
				);
				linkedFor.add(gift);
			}
		}
		if (links.isEmpty()) {
			return;
		}
		List<Database.SaveResult> saved;
		AutomationControl.bypass(AUTOMATION_NAME);
		try {
			saved = Database.update(links, false, AccessLevel.USER_MODE);
		} finally {
			AutomationControl.clearBypass(AUTOMATION_NAME);
		}
		List<SObject> orphans = new List<SObject>();
		List<Gift__c> orphanedFor = new List<Gift__c>();
		Set<Id> unlinked = new Set<Id>();
		Schema.SObjectType giftTransaction = GiftTransactionMirrorSchema.objectType();
		for (Integer i = 0; i < saved.size(); i++) {
			if (saved[i].isSuccess()) {
				continue;
			}
			Gift__c gift = linkedFor[i];
			result.failed++;
			refuse(result, gift, saved[i].getErrors());
			if (linkBefore.get(gift.Id) == null) {
				result.created--;
				unlinked.add(gift.Id);
				orphans.add(giftTransaction.newSObject(Id.valueOf(gift.Gift_Transaction_Id__c)));
				orphanedFor.add(gift);
			}
		}
		if (!unlinked.isEmpty()) {
			List<Gift__c> stillLinked = new List<Gift__c>();
			for (Gift__c gift : result.createdFor) {
				if (!unlinked.contains(gift.Id)) {
					stillLinked.add(gift);
				}
			}
			result.createdFor = stillLinked;
		}
		if (orphans.isEmpty()) {
			return;
		}
		List<Database.DeleteResult> deleted = Database.delete(
			orphans,
			false,
			AccessLevel.USER_MODE
		);
		for (Integer i = 0; i < deleted.size(); i++) {
			if (!deleted[i].isSuccess()) {
				result.refusals.add(
					String.format(
						BarnHelp.text('Mirror', 'Mirror_GiftTransactionMirror_LogOrphan'),
						new List<Object>{
							String.valueOf(orphans[i].Id),
							messageOf(deleted[i].getErrors())
						}
					),
					orphanedFor[i].Name,
					orphanedFor[i].Id
				);
			}
		}
	}

	// ------------------------------------------------------------------------- designations

	/**
	 * R-GT5: gives each Gift Transaction this call created, and linked, one designation per
	 * allocation whose fund names a Gift Designation, unless it already has a designation. One
	 * insert, whatever the number of gifts.
	 */
	private static void writeDesignations(Result result) {
		if (result.createdFor.isEmpty()) {
			return;
		}
		if (!GiftTransactionMirrorSchema.canWriteDesignations()) {
			result.designationsUnavailable = true;
			return;
		}
		GiftTransactionMirrorSchema.Names names = GiftTransactionMirrorSchema.names;
		Map<Id, Gift__c> giftById = new Map<Id, Gift__c>(result.createdFor);
		Set<Id> transactionIds = new Set<Id>();
		for (Gift__c gift : result.createdFor) {
			transactionIds.add(Id.valueOf(gift.Gift_Transaction_Id__c));
		}
		Set<Id> designatedAlready = GiftTransactionMirrorSelector.designatedTransactionIds(
			GiftTransactionMirrorSchema.linkObjectName(),
			names.linkTransactionField,
			transactionIds
		);
		Schema.SObjectType designation = GiftTransactionMirrorSchema.designationType();
		Schema.SObjectType link = GiftTransactionMirrorSchema.linkType();
		List<SObject> inserts = new List<SObject>();
		List<Gift__c> insertedFor = new List<Gift__c>();
		for (
			Gift_Allocation__c allocation : GiftTransactionMirrorSelector.allocationsOf(
				giftById.keySet()
			)
		) {
			Gift__c gift = giftById.get(allocation.Gift__c);
			Id transactionId = Id.valueOf(gift.Gift_Transaction_Id__c);
			if (designatedAlready.contains(transactionId)) {
				continue;
			}
			Id designationId = MirrorSync.idOf(
				allocation.Fund__r?.Gift_Designation_Id__c,
				designation
			);
			if (designationId == null) {
				result.undesignated++;
				continue;
			}
			SObject record = link.newSObject(null, true);
			record.put(names.linkTransactionField, transactionId);
			record.put(names.linkDesignationField, designationId);
			record.put(names.linkAmountField, allocation.Amount__c);
			inserts.add(record);
			insertedFor.add(gift);
		}
		if (inserts.isEmpty()) {
			return;
		}
		List<Database.SaveResult> saved = Database.insert(inserts, false, AccessLevel.USER_MODE);
		for (Integer i = 0; i < saved.size(); i++) {
			if (saved[i].isSuccess()) {
				result.designated++;
			} else {
				result.refusals.add(
					String.format(
						BarnHelp.text('Mirror', 'Mirror_GiftTransactionMirror_DesignationRefused'),
						new List<Object>{ messageOf(saved[i].getErrors()) }
					),
					insertedFor[i].Name,
					insertedFor[i].Id
				);
			}
		}
	}

	// ------------------------------------------------------------------------------- helpers

	private static void refuse(Result result, Gift__c gift, List<Database.Error> errors) {
		result.refusals.add(messageOf(errors), gift.Name, gift.Id);
	}

	public static String messageOf(List<Database.Error> errors) {
		List<String> messages = new List<String>();
		for (Database.Error error : errors) {
			messages.add(error.getMessage());
		}
		return String.join(messages, ' ');
	}
}
