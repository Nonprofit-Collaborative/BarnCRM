/**
 * Giving's part of Core's importer (features G-23 and G-24, canonical model Section 25N): the
 * `ImportEntityProcessor` Core finds by this class name (R-IR6, ADR-0017) and offers each
 * chunk after it has resolved the people, households and organizations.
 *
 * A row's gift is created only through Giving's own path, the one gift batch entry uses:
 * a user-mode insert with Status Received, then the chosen fund applied with
 * `GiftService.applyChosenFunds`, or a split saved with the default allocation suppressed
 * (R-GI4). A row's gift is saved whole or not at all (R-GI7), and every gift carries the
 * import's tag so an undo can remove it (R-IB3).
 */
@NamespaceAccessible
public with sharing class GiftImportProcessor implements ImportEntityProcessor {
	private static final String STATUS_RECEIVED = 'Received';

	@NamespaceAccessible
	public GiftImportProcessor() {
		// Built by name through Type.forName, which needs a constructor it can reach.
	}

	// -------------------------------------------------------------------------------------
	// The column picker
	// -------------------------------------------------------------------------------------

	/** The columns this processor loads, in the order the picker offers them. */
	public List<ImportMapping.Target> targets() {
		List<ImportMapping.Target> result = new List<ImportMapping.Target>{
			target('Gift.Amount__c', Label.Giving_Import_TargetAmount),
			target('Gift.Gift_Date__c', Label.Giving_Import_TargetDate),
			target('Gift.Type__c', Label.Giving_Import_TargetType),
			target('Gift.Payment_Reference__c', Label.Giving_Import_TargetPaymentReference),
			target('Gift.External_Id__c', Label.Giving_Import_TargetExternalId),
			target('Gift.Appeal', Label.Giving_Import_TargetAppeal),
			target('Gift.Donor', Label.Giving_Import_TargetDonor),
			target('Gift.In_Kind_Description__c', Label.Giving_Import_TargetInKindDescription),
			target('Gift.Fair_Market_Value__c', Label.Giving_Import_TargetFairMarketValue),
			target('Gift.Benefit_Description__c', Label.Giving_Import_TargetBenefitDescription),
			target('Allocation.Fund', Label.Giving_Import_TargetFund),
			target('SoftCredit.Role__c', Label.Giving_Import_TargetSoftCreditRole),
			target('SoftCredit.Custom_Role__c', Label.Giving_Import_TargetSoftCreditCustomRole),
			target('SoftCredit.Amount__c', Label.Giving_Import_TargetSoftCreditAmount),
			target('SoftCredit.Party', Label.Giving_Import_TargetSoftCreditParty),
			target('Tribute.Type__c', Label.Giving_Import_TargetTributeType),
			target('Tribute.Honoree_Name__c', Label.Giving_Import_TargetTributeHonoree),
			target(
				'Tribute.Notification_Recipient_Name__c',
				Label.Giving_Import_TargetTributeNotify
			),
			target('Tribute.Message__c', Label.Giving_Import_TargetTributeMessage)
		};
		if (BrandService.isEnabled()) {
			// C-47d, after Gift: appeal; offered only while brands are on (R-BR2).
			result.add(
				6,
				target('Gift.Brand', BarnHelp.text('Giving', 'Giving_Import_TargetBrand'))
			);
		}
		for (Integer index = 1; index <= GiftImportRow.MAX_PARTS; index++) {
			List<String> partNumber = new List<String>{ String.valueOf(index) };
			result.add(
				target(
					'Allocation.Fund' + index,
					String.format(Label.Giving_Import_TargetFundPart, partNumber)
				)
			);
			result.add(
				target(
					'Allocation.Amount' + index,
					String.format(Label.Giving_Import_TargetAmountPart, partNumber)
				)
			);
			result.add(
				target(
					'Allocation.Percent' + index,
					String.format(Label.Giving_Import_TargetPercentPart, partNumber)
				)
			);
		}
		return result;
	}

	private static ImportMapping.Target target(String value, String label) {
		return new ImportMapping.Target(value, label);
	}

	// -------------------------------------------------------------------------------------
	// One chunk
	// -------------------------------------------------------------------------------------

	/**
	 * Reads, checks and (unless a dry run) saves each row's gift, and reports on each row
	 * (R-IR7). Nothing is thrown: a failure belongs on the row it came from.
	 */
	public ImportEntityResult resolve(
		Import_Batch__c batch,
		Import_Template__c template,
		List<Import_Row__c> rows,
		Map<Id, Map<String, Map<String, String>>> entitiesByRowId,
		Boolean dryRun
	) {
		Decimal fileAmount;
		Set<String> notLoaded = new Set<String>();
		List<GiftImportRow> gifts = new List<GiftImportRow>();
		for (Import_Row__c row : rows) {
			GiftImportRow read = new GiftImportRow(row, entitiesByRowId.get(row.Id));
			if (read.readableAmount != null) {
				// Every readable amount counts, rejected rows too: the control total asks
				// whether this is the file on paper (R-GI8, R-IB10).
				fileAmount = (fileAmount == null ? 0 : fileAmount) + read.readableAmount;
			}
			if (!read.carriesGift || ImportRowProcessor.STATUS_REJECTED.equals(row.Status__c)) {
				continue;
			}
			notLoaded.addAll(read.notLoaded);
			gifts.add(read);
		}
		List<String> notes = new List<String>();
		if (!gifts.isEmpty() && !Schema.SObjectType.Gift__c.isDeletable()) {
			// A row is saved whole or not at all, which means deleting a gift whose credit or
			// tribute was refused. Without that right a half-saved gift would stay behind, so
			// the import is refused before anything is written, in the dry run too.
			refuseAll(gifts, BarnHelp.text('Giving', 'Giving_Import_ErrorCannotDeleteGifts'));
			notes.add(BarnHelp.text('Giving', 'Giving_Import_ErrorCannotDeleteGifts'));
		}
		Integer paying = 0;
		// Taken on every chunk, rows with gifts or not, so a dry run records what the commit
		// is held to even when its first gift is in a later chunk (R-DM7).
		DonationMatcher matcher = DonationMatcher.forRun(batch, template, dryRun);
		if (!gifts.isEmpty()) {
			matchExternalIds(pending(gifts), batch, dryRun);
			matcher.refuseExistingUnderNeverMatch(gifts);
			refuseClosedPeriod(pending(gifts));
			GiftImportCredits.read(pending(gifts));
			resolveDonors(pending(gifts), dryRun);
			GiftImportCredits.resolveParties(pending(gifts), dryRun);
			GiftImportReferences.resolve(pending(gifts));
			matcher.match(pending(gifts));
			if (!dryRun) {
				save(batch, pending(gifts));
			}
			// A repeat of an earlier row shares its outcome, in the dry run as in the commit.
			shareWithEarlierRows(gifts);
			paying = matcher.carryClaims(gifts);
			if (dryRun) {
				rememberExternalIds(gifts);
			}
			report(gifts);
		}
		if (paying > 0) {
			notes.add(
				String.format(
					BarnHelp.text('Giving', 'Giving_Import_LogPaymentsMatched'),
					new List<String>{ String.valueOf(paying) }
				)
			);
		}
		if (!notLoaded.isEmpty()) {
			notes.add(
				String.format(
					BarnHelp.text('Giving', 'Giving_Import_LogAttributesNotLoaded'),
					new List<String>{ String.join(new List<String>(notLoaded), ', ') }
				)
			);
		}
		ImportEntityResult result = new ImportEntityResult(
			notes.isEmpty() ? null : String.join(notes, ' '),
			fileAmount
		);
		result.settings = dryRun ? matcher.record() : null;
		return result;
	}

	/**
	 * The external IDs a dry run's chunk would load, for a later chunk to match (R-DM1), since
	 * the dry run saves no gift for it to find: each such row keeps a digest of its own as its
	 * Processor Key, which Core saves with the row. A commit needs none of this: the gift is
	 * there, stamped with the batch. A refused row is not remembered: its repeat is loaded on
	 * its own, in the dry run as in the commit.
	 */
	private static void rememberExternalIds(List<GiftImportRow> gifts) {
		for (GiftImportRow item : gifts) {
			if (item.error == null && !item.matchedExisting && item.externalId != null) {
				item.row.Processor_Key__c = GiftImportRunState.key(item.externalId);
			}
		}
	}

	/**
	 * A row that would add a gift to the books in a closed accounting period is refused before
	 * anything is written, in the dry run as in the commit, with the sentence the gift's own
	 * save would give (R-G14, ADR-0053). A row matched to an existing gift adds nothing and is
	 * not asked. In-kind gifts are not in the books.
	 */
	private static void refuseClosedPeriod(List<GiftImportRow> gifts) {
		Date closed = GiftPostingLock.closedThrough();
		if (closed == null || GiftPostingLock.canOverride()) {
			return;
		}
		String reason = String.format(
			BarnHelp.text('Giving', 'Giving_Posting_ClosedPeriodNewGift'),
			new List<String>{ closed.format() }
		);
		for (GiftImportRow item : gifts) {
			if (
				GiftPostingLock.isInClosedPeriod(item.giftDate, closed) &&
				item.values.get(Gift__c.Type__c) != GiftPostingLock.TYPE_IN_KIND
			) {
				item.error = reason;
			}
		}
	}

	private static void refuseAll(List<GiftImportRow> gifts, String reason) {
		for (GiftImportRow item : gifts) {
			if (item.error == null) {
				item.error = reason;
			}
		}
	}

	/** The rows still on their way to a gift: not refused, and not matched to one. */
	private static List<GiftImportRow> pending(List<GiftImportRow> gifts) {
		List<GiftImportRow> result = new List<GiftImportRow>();
		for (GiftImportRow item : gifts) {
			if (item.error == null && !item.matchedExisting) {
				result.add(item);
			}
		}
		return result;
	}

	/** Writes each row's outcome where Core reads it (R-IR7). */
	private static void report(List<GiftImportRow> gifts) {
		for (GiftImportRow item : gifts) {
			if (item.error != null) {
				item.row.Status__c = ImportRowProcessor.STATUS_REJECTED;
				item.row.Error_Message__c = item.error.abbreviate(4000);
			} else {
				item.row.Status__c = item.matchedExisting
					? ImportRowProcessor.STATUS_MATCHED
					: ImportRowProcessor.STATUS_CREATED;
				item.row.Gift_Id__c = item.giftId;
			}
		}
	}

	// -------------------------------------------------------------------------------------
	// The donor (R-GI2)
	// -------------------------------------------------------------------------------------

	/**
	 * The row's first person gives the gift, or else its organization, unless `Gift.Donor`
	 * says otherwise. In a dry run a donor Core would create has no identifier yet; the row
	 * still counts as a gift that would be created.
	 */
	private static void resolveDonors(List<GiftImportRow> gifts, Boolean dryRun) {
		for (GiftImportRow item : gifts) {
			if (item.error != null) {
				continue;
			}
			Import_Row__c row = item.row;
			Id person = row.Contact_1__c != null ? row.Contact_1__c : row.Person_1_Account__c;
			Boolean personComing =
				dryRun &&
				person == null &&
				item.names(ImportMapping.ENTITY_CONTACT_1);
			Boolean organizationComing =
				dryRun &&
				row.Organization__c == null &&
				item.names(ImportMapping.ENTITY_ORGANIZATION);
			String choice = item.donorChoice;
			if (choice == null) {
				choice = person != null || personComing
					? GiftImportRow.DONOR_CONTACT_1
					: row.Organization__c != null || organizationComing
							? GiftImportRow.DONOR_ORGANIZATION
							: null;
			}
			if (choice == null) {
				item.error = BarnHelp.text('Giving', 'Giving_Import_ErrorNoDonor');
			} else if (choice == GiftImportRow.DONOR_CONTACT_1) {
				if (row.Contact_1__c != null) {
					item.donorContactId = row.Contact_1__c;
				} else if (row.Person_1_Account__c != null) {
					item.donorAccountId = row.Person_1_Account__c;
				} else if (!personComing) {
					item.error = BarnHelp.text('Giving', 'Giving_Import_ErrorDonorPersonMissing');
				}
			} else if (choice == GiftImportRow.DONOR_ORGANIZATION) {
				item.donorAccountId = row.Organization__c;
				if (row.Organization__c == null && !organizationComing) {
					item.error = BarnHelp.text(
						'Giving',
						'Giving_Import_ErrorDonorOrganizationMissing'
					);
				}
			} else {
				item.donorAccountId = row.Household__c;
				if (row.Household__c == null && !personComing) {
					item.error = BarnHelp.text(
						'Giving',
						'Giving_Import_ErrorDonorHouseholdMissing'
					);
				}
			}
		}
	}

	// -------------------------------------------------------------------------------------
	// Gifts already loaded (R-DM1)
	// -------------------------------------------------------------------------------------

	/**
	 * A row whose external ID names a gift already in the org, or one an earlier row of this
	 * chunk makes, is that gift: the row is Matched and the gift is not changed.
	 */
	private static void matchExternalIds(
		List<GiftImportRow> gifts,
		Import_Batch__c batch,
		Boolean dryRun
	) {
		Id batchId = batch.Id;
		Set<String> externalIds = new Set<String>();
		for (GiftImportRow item : gifts) {
			if (item.externalId != null) {
				externalIds.add(item.externalId);
			}
		}
		if (externalIds.isEmpty()) {
			return;
		}
		Map<String, Id> existing = new Map<String, Id>();
		Set<String> madeByThisRun = new Set<String>();
		for (Gift__c gift : GiftImportIntegritySelector.selectByExternalIds(externalIds)) {
			existing.put(gift.External_Id__c.toLowerCase(), gift.Id);
			if (gift.Created_By_Import_Batch__c == batchId) {
				madeByThisRun.add(gift.External_Id__c.toLowerCase());
			}
		}
		// A dry run asks the rows earlier chunks wrote, for this chunk's external IDs only.
		Set<String> loadedEarlier = new Set<String>();
		if (dryRun) {
			Set<String> digests = new Set<String>();
			for (String externalId : externalIds) {
				digests.add(GiftImportRunState.key(externalId));
			}
			loadedEarlier = ImportRowSelector.processorDigestsWrittenEarlier(batch, digests);
		}
		Map<String, GiftImportRow> firstInChunk = new Map<String, GiftImportRow>();
		for (GiftImportRow item : gifts) {
			if (item.externalId == null) {
				continue;
			}
			String key = item.externalId.toLowerCase();
			// A commit finds the gift an earlier chunk made; a dry run saved none, so it asks
			// what the earlier chunks carried.
			item.repeatsEarlierChunk =
				madeByThisRun.contains(key) || loadedEarlier.contains(GiftImportRunState.key(key));
			if (existing.containsKey(key)) {
				item.matchedExisting = true;
				item.giftId = existing.get(key);
			} else if (item.repeatsEarlierChunk) {
				// A dry run saved nothing, but the commit's earlier chunk will have made it.
				item.matchedExisting = true;
			} else if (firstInChunk.containsKey(key)) {
				item.matchedExisting = true;
				item.sameAs = firstInChunk.get(key);
			} else {
				firstInChunk.put(key, item);
			}
		}
	}

	// -------------------------------------------------------------------------------------
	// Saving (R-GI4, R-GI7)
	// -------------------------------------------------------------------------------------

	/**
	 * Creates the gifts: those with a split with the default allocation suppressed, the
	 * others with it, then the chosen fund or the split's parts. A row whose gift was saved but
	 * whose allocations were not has its gift deleted, so it never leaves half a gift.
	 */
	private static void save(Import_Batch__c batch, List<GiftImportRow> gifts) {
		List<GiftImportRow> whole = new List<GiftImportRow>();
		List<GiftImportRow> split = new List<GiftImportRow>();
		for (GiftImportRow item : gifts) {
			if (item.isSplit()) {
				split.add(item);
			} else {
				whole.add(item);
			}
		}
		insertGifts(batch, whole, false);
		insertGifts(batch, split, true);
		applyFunds(saved(whole));
		insertParts(saved(split));
		GiftImportCredits.save(gifts);
		undoTheUnfinished(gifts);
	}

	/** A row repeating an earlier row's external ID shares that row's gift, or its refusal. */
	private static void shareWithEarlierRows(List<GiftImportRow> gifts) {
		for (GiftImportRow item : gifts) {
			if (item.sameAs != null && item.error == null) {
				item.giftId = item.sameAs.giftId;
				item.error = item.sameAs.error;
			}
		}
	}

	private static List<GiftImportRow> saved(List<GiftImportRow> gifts) {
		List<GiftImportRow> result = new List<GiftImportRow>();
		for (GiftImportRow item : gifts) {
			if (item.error == null && item.giftId != null) {
				result.add(item);
			}
		}
		return result;
	}

	private static void insertGifts(
		Import_Batch__c batch,
		List<GiftImportRow> gifts,
		Boolean split
	) {
		if (gifts.isEmpty()) {
			return;
		}
		List<Gift__c> records = new List<Gift__c>();
		for (GiftImportRow item : gifts) {
			records.add(build(batch, item));
		}
		Boolean callerSuppression = GiftService.suppressDefaultAllocations;
		List<Database.SaveResult> results;
		try {
			GiftService.suppressDefaultAllocations = split || callerSuppression;
			results = Database.insert(records, false, AccessLevel.USER_MODE);
		} finally {
			GiftService.suppressDefaultAllocations = callerSuppression;
		}
		for (Integer index = 0; index < results.size(); index++) {
			if (results[index].isSuccess()) {
				gifts[index].giftId = records[index].Id;
			} else {
				gifts[index].error = failure(results[index].getErrors());
			}
		}
	}

	private static Gift__c build(Import_Batch__c batch, GiftImportRow item) {
		Gift__c gift = new Gift__c(
			Donor_Contact__c = item.donorContactId,
			Donor_Account__c = item.donorAccountId,
			Amount__c = item.amount,
			Gift_Date__c = item.giftDate,
			Status__c = STATUS_RECEIVED,
			Appeal__c = item.appealId,
			Installment__c = item.installmentId,
			Commitment__c = item.commitmentId,
			Created_By_Import_Batch__c = batch.Id
		);
		if (item.brandId != null) {
			// C-47d; left blank, the gift takes its appeal's or the user's brand (R-BR4).
			gift.Brand__c = item.brandId;
		}
		for (Schema.SObjectField field : item.values.keySet()) {
			gift.put(field, item.values.get(field));
		}
		return gift;
	}

	/** The single chosen fund, applied the way every entry screen applies it. */
	private static void applyFunds(List<GiftImportRow> gifts) {
		List<Gift__c> records = new List<Gift__c>();
		Map<Id, Id> fundIdByGiftId = new Map<Id, Id>();
		Map<Id, GiftImportRow> byGiftId = new Map<Id, GiftImportRow>();
		for (GiftImportRow item : gifts) {
			if (item.singleFund == null) {
				continue;
			}
			records.add(new Gift__c(Id = item.giftId, Amount__c = item.amount));
			fundIdByGiftId.put(item.giftId, item.singleFund.fundId);
			byGiftId.put(item.giftId, item);
		}
		if (records.isEmpty()) {
			return;
		}
		Savepoint beforeFunds = Database.setSavepoint();
		try {
			refuseNotApplied(applyChosenFunds(records, fundIdByGiftId), byGiftId);
		} catch (Exception refused) {
			// The designation is all or nothing across the chunk, so one refused gift would
			// take every other with it. Undo the attempt and apply each gift on its own, so
			// only the gift the platform refuses loses its row. The rollback matters: a
			// designation can fail after part of it was written.
			Database.rollback(beforeFunds);
			applyOneByOne(records, fundIdByGiftId, byGiftId);
		}
	}

	/**
	 * Each gift's fund on its own, each attempt undone if it fails, while the transaction has
	 * room: a gift the chunk has no room left for is not attempted and says so, rather than
	 * risking a limit that would fail every row.
	 */
	private static void applyOneByOne(
		List<Gift__c> records,
		Map<Id, Id> fundIdByGiftId,
		Map<Id, GiftImportRow> byGiftId
	) {
		for (Gift__c record : records) {
			GiftImportRow item = byGiftId.get(record.Id);
			if (!hasRoomForOneMore()) {
				item.error = BarnHelp.text('Giving', 'Giving_Import_ErrorNotAttempted');
				continue;
			}
			Savepoint beforeThisGift = Database.setSavepoint();
			try {
				refuseNotApplied(
					applyChosenFunds(
						new List<Gift__c>{ record },
						new Map<Id, Id>{ record.Id => fundIdByGiftId.get(record.Id) }
					),
					byGiftId
				);
			} catch (Exception rowRefused) {
				Database.rollback(beforeThisGift);
				item.error = String.format(
					BarnHelp.text('Giving', 'Giving_Import_ErrorFailed'),
					new List<String>{ rowRefused.getMessage() }
				);
			}
		}
	}

	/** Kept free for the rest of the chunk's work; a test raises it to run out of room. */
	@TestVisible
	private static Integer queriesKeptFree = 30;
	@TestVisible
	private static Integer statementsKeptFree = 20;

	/** Room for one more gift's designation and for the rest of the chunk's work after it. */
	private static Boolean hasRoomForOneMore() {
		return Limits.getLimitQueries() - Limits.getQueries() > queriesKeptFree &&
			Limits.getLimitDmlStatements() - Limits.getDmlStatements() > statementsKeptFree &&
			Limits.getCpuTime() < Limits.getLimitCpuTime() * 0.7;
	}

	/**
	 * Funds a test makes the platform refuse. The refusal comes after the designation and
	 * after a record of its own is written, so a test can see that a failed attempt leaves
	 * nothing behind.
	 */
	@TestVisible
	private static Set<Id> fundsRefusedForTest = new Set<Id>();
	@TestVisible
	private static final String WRITTEN_BEFORE_REFUSAL = 'Written before the refusal';

	private static Set<Id> applyChosenFunds(List<Gift__c> records, Map<Id, Id> fundIdByGiftId) {
		Set<Id> notApplied = GiftService.applyChosenFunds(records, fundIdByGiftId);
		for (Id fundId : fundIdByGiftId.values()) {
			if (fundsRefusedForTest.contains(fundId)) {
				Database.insert(
					new Fund__c(Name = WRITTEN_BEFORE_REFUSAL, Active__c = false),
					true,
					AccessLevel.USER_MODE
				);
				throw new DmlException('Refused for the test.');
			}
		}
		return notApplied;
	}

	private static void refuseNotApplied(Set<Id> notApplied, Map<Id, GiftImportRow> byGiftId) {
		for (Id giftId : notApplied) {
			byGiftId.get(giftId).error = BarnHelp.text(
				'Giving',
				'Giving_GiftBatch_ErrorPostFailed'
			);
		}
	}

	/** A split's parts, all saved together so the allocation total rule sees them whole. */
	private static void insertParts(List<GiftImportRow> gifts) {
		List<Gift_Allocation__c> records = new List<Gift_Allocation__c>();
		List<GiftImportRow> owners = new List<GiftImportRow>();
		for (GiftImportRow item : gifts) {
			for (GiftImportRow.Part part : item.parts) {
				records.add(
					new Gift_Allocation__c(
						Gift__c = item.giftId,
						Fund__c = part.fundId,
						Amount__c = part.amount,
						Percent__c = part.percent
					)
				);
				owners.add(item);
			}
		}
		if (records.isEmpty()) {
			return;
		}
		List<Database.SaveResult> results = Database.insert(records, false, AccessLevel.USER_MODE);
		for (Integer index = 0; index < results.size(); index++) {
			if (!results[index].isSuccess() && owners[index].error == null) {
				owners[index].error = failure(results[index].getErrors());
			}
		}
	}

	/** Deletes each gift whose row failed after it was saved (R-GI7). */
	@TestVisible
	private static void undoTheUnfinished(List<GiftImportRow> gifts) {
		List<Gift__c> unfinished = new List<Gift__c>();
		for (GiftImportRow item : gifts) {
			if (item.error != null && item.giftId != null) {
				unfinished.add(new Gift__c(Id = item.giftId));
				item.giftId = null;
				item.row.Soft_Credit_Id__c = null;
			}
		}
		if (!unfinished.isEmpty()) {
			List<Database.DeleteResult> results = Database.delete(
				unfinished,
				false,
				AccessLevel.USER_MODE
			);
			// Logged together, in one statement; a failed result carries no Id, so the gift's.
			List<Exception> failed = new List<Exception>();
			List<Id> ids = new List<Id>();
			for (Integer i = 0; i < results.size(); i++) {
				if (!results[i].isSuccess()) {
					failed.add(new DmlException(failure(results[i].getErrors())));
					ids.add(unfinished[i].Id);
				}
			}
			ErrorLogger.logEach(failed, ids, 'GiftImportProcessor.undoTheUnfinished');
		}
	}

	private static String failure(List<Database.Error> errors) {
		List<String> messages = new List<String>();
		for (Database.Error error : errors) {
			messages.add(error.getMessage());
		}
		return String.format(
			BarnHelp.text('Giving', 'Giving_Import_ErrorFailed'),
			new List<String>{ String.join(messages, ' ') }
		);
	}

	// -------------------------------------------------------------------------------------
	// Undo (R-GI9)
	// -------------------------------------------------------------------------------------

	/** The objects this processor tags: gifts, whose allocations and credits go with them. */
	public List<Schema.SObjectType> taggedObjects() {
		return new List<Schema.SObjectType>{ Gift__c.SObjectType };
	}

	/**
	 * Why records must survive an undo (R-GI9). A gift stays when a document the donor holds
	 * lists it: it carries a receipt number, a receipt of any status names it, or an issued
	 * year-end statement covers its donor and year (ADR-0010, ADR-0024), or it is locked by the
	 * posting lock: posted to accounting, or in the books in a closed period (ADR-0053). A person, household
	 * or organization stays while a gift this import made, and that is being kept, still names
	 * it as donor, household or soft credit.
	 */
	public Map<Id, String> reasonsToKeep(Id batchId, Schema.SObjectType type, Set<Id> recordIds) {
		Map<Id, String> keep = new Map<Id, String>();
		if (batchId == null || recordIds == null || recordIds.isEmpty()) {
			return keep;
		}
		if (type == Gift__c.SObjectType) {
			keepReceiptedGifts(keep, recordIds);
		} else if (type == Contact.SObjectType || type == Account.SObjectType) {
			keepDonorsOfKeptGifts(keep, batchId, recordIds);
		}
		return keep;
	}

	private static void keepReceiptedGifts(Map<Id, String> keep, Set<Id> giftIds) {
		List<Gift__c> gifts = GiftImportIntegritySelector.selectForUndo(giftIds);
		Set<Id> donorIds = new Set<Id>();
		Set<Integer> years = new Set<Integer>();
		Date closed = GiftPostingLock.closedThrough();
		for (Gift__c gift : gifts) {
			if (gift.Receipt_Number__c != null || !gift.Receipts__r.isEmpty()) {
				keep.put(gift.Id, BarnHelp.text('Giving', 'Giving_Import_UndoKeptReceipted'));
			} else if (GiftPostingLock.isInBooks(gift) && GiftPostingLock.isPosted(gift)) {
				keep.put(gift.Id, BarnHelp.text('Giving', 'Giving_Import_UndoKeptPosted'));
			} else if (GiftPostingLock.isLocked(gift, closed)) {
				keep.put(gift.Id, BarnHelp.text('Giving', 'Giving_Import_UndoKeptClosedPeriod'));
			} else if (gift.Gift_Date__c != null) {
				donorIds.add(
					gift.Donor_Contact__c != null ? gift.Donor_Contact__c : gift.Donor_Account__c
				);
				years.add(gift.Gift_Date__c.year());
			}
		}
		donorIds.remove(null);
		if (donorIds.isEmpty()) {
			return;
		}
		Set<String> covered = new Set<String>();
		for (
			Receipt__c statement : GiftImportIntegritySelector.selectIssuedStatements(
				donorIds,
				years
			)
		) {
			Id donor = statement.Donor_Contact__c != null
				? statement.Donor_Contact__c
				: statement.Donor_Account__c;
			covered.add(donor + ':' + statement.Statement_Year__c.intValue());
		}
		for (Gift__c gift : gifts) {
			Id donor = gift.Donor_Contact__c != null
				? gift.Donor_Contact__c
				: gift.Donor_Account__c;
			if (
				!keep.containsKey(gift.Id) &&
				gift.Gift_Date__c != null &&
				covered.contains(donor + ':' + gift.Gift_Date__c.year())
			) {
				keep.put(gift.Id, BarnHelp.text('Giving', 'Giving_Import_UndoKeptStatement'));
			}
		}
	}

	/**
	 * Runs after the gift pass, so the gifts this import made that still exist are the ones
	 * the undo kept (or could not delete), and their donors stay with them.
	 */
	private static void keepDonorsOfKeptGifts(Map<Id, String> keep, Id batchId, Set<Id> recordIds) {
		Set<Id> named = new Set<Id>();
		for (
			Gift__c gift : GiftImportIntegritySelector.selectImportedGiftsNaming(batchId, recordIds)
		) {
			named.addAll(
				new List<Id>{ gift.Donor_Contact__c, gift.Donor_Account__c, gift.Household__c }
			);
		}
		for (
			Soft_Credit__c credit : GiftImportIntegritySelector.selectImportedCreditsNaming(
				batchId,
				recordIds
			)
		) {
			named.addAll(new List<Id>{ credit.Contact__c, credit.Account__c });
		}
		for (Id recordId : named) {
			if (recordId != null && recordIds.contains(recordId)) {
				keep.put(recordId, BarnHelp.text('Giving', 'Giving_Import_UndoKeptDonor'));
			}
		}
	}
}
