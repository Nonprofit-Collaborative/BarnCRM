/**
 * The stages of the Giving sample data load, and the removal that undoes them (C-10).
 *
 * Three stages, each a static method taking an already parsed payload so a test can run one
 * without the queueable chain:
 *
 * 1. `loadReferenceData` inserts the funds, the appeals (parents before children), and the
 *    commitments. The commitment trigger generates each schedule of installments, exactly as
 *    it would for a pledge entered on screen, so no installment is written here.
 * 2. `loadGiftChunk` inserts one chunk of gifts with their allocations, the soft credits a
 *    fundraiser would have entered by hand, and the tributes. The automatic household soft
 *    credits are left to the rule that writes them, and the gifts that name a commitment are
 *    left to the rule that applies them to installments.
 * 3. `finish` marks the installments that are already past due Overdue, which is the same
 *    method the daily job calls, so the set has a genuinely overdue pledge in it rather than
 *    a status typed into a file.
 *
 * The allocations are inserted by this class rather than left to the default allocation
 * rule: that rule puts everything in the organization's one default fund, which would leave
 * eight funds in the set and gifts against only one of them.
 *
 * Removal deletes gifts, commitments, appeals and funds. Allocations, soft credits and
 * tributes are details of a gift, and installments are details of a commitment, so the
 * platform deletes them with their master; nothing here has to find them.
 */
public with sharing class GivingSampleDataLoader {
    private static final String CONTEXT = 'GivingSampleDataLoader';

    /** The key of the set's unrestricted fund, which an org's own default fund stands in for. */
    private static final String GENERAL_FUND_KEY = 'General Fund';

    /** The registry rows whose delete protection the removal stands down; see removeNext(). */
    private static final String COMMITMENT_AUTOMATION = 'Commitment_Schedule';
    private static final String INSTALLMENT_AUTOMATION = 'Installment_Protection';

    /** Records deleted per removeNext() call, the size of a load chunk. Tests lower it. */
    @TestVisible
    private static Integer removeChunkSize = GivingSampleData.GIFT_CHUNK_SIZE;

    /**
     * Stage one: funds, appeals and commitments. Returns the key to Id map the gift stages
     * need, which is small enough (about forty entries) to travel with the queued job.
     */
    public static Map<String, Id> loadReferenceData(GivingSampleDataSet data) {
        Map<String, Id> idsByKey = new Map<String, Id>();
        idsByKey.putAll(insertFunds(data));
        idsByKey.putAll(insertAppeals(data));
        idsByKey.putAll(insertCommitments(data, idsByKey));
        return idsByKey;
    }

    /**
     * Funds. When the org already has a default fund (its own, or the General Fund a new org
     * starts with), the set's unrestricted "General Fund" is not created: the sample gifts that
     * would have gone to it go to the org's default fund instead, so the org never has two funds
     * of that name. The org's fund is not flagged as sample data, so removal never deletes it.
     */
    private static Map<String, Id> insertFunds(GivingSampleDataSet data) {
        List<Fund__c> funds = new List<Fund__c>();
        List<String> keys = new List<String>();
        Id ownDefaultFundId = GiftService.resolveDefaultFundId();
        Map<String, Id> reused = new Map<String, Id>();
        for (Map<String, Object> row : data.funds) {
            String fundKey = GivingSampleDataSet.asString(row.get('key'));
            if (ownDefaultFundId != null && fundKey == GENERAL_FUND_KEY) {
                reused.put(fundKey, ownDefaultFundId);
                continue;
            }
            keys.add(fundKey);
            funds.add(
                new Fund__c(
                    Sample_Data__c = true,
                    Name = GivingSampleDataSet.asString(row.get('name')),
                    Description__c = GivingSampleDataSet.asString(row.get('description')),
                    Accounting_Code__c = GivingSampleDataSet.asString(row.get('accountingCode')),
                    Restricted__c = row.get('restricted') == true,
                    Active__c = row.get('active') != false
                    // Is_Default__c is deliberately left alone: the org's own default fund
                    // stays the default, and only one fund may carry the flag (R-F4).
                )
            );
        }
        Map<String, Id> idsByKey = insertAndMap(funds, keys);
        idsByKey.putAll(reused);
        return idsByKey;
    }

    /**
     * Appeals, parents first: a child appeal names its parent, and the parent has to exist
     * before the child can point at it.
     */
    private static Map<String, Id> insertAppeals(GivingSampleDataSet data) {
        Map<String, Id> idsByKey = new Map<String, Id>();
        for (Integer pass = 0; pass < 2; pass++) {
            List<Appeal__c> appeals = new List<Appeal__c>();
            List<String> keys = new List<String>();
            for (Map<String, Object> row : data.appeals) {
                String parentKey = GivingSampleDataSet.asString(row.get('parent'));
                Boolean isParent = String.isBlank(parentKey);
                if ((pass == 0) != isParent) {
                    continue;
                }
                keys.add(GivingSampleDataSet.asString(row.get('key')));
                appeals.add(
                    new Appeal__c(
                        Sample_Data__c = true,
                        Name = GivingSampleDataSet.asString(row.get('name')),
                        Description__c = GivingSampleDataSet.asString(row.get('description')),
                        Goal__c = GivingSampleDataSet.toDecimal(row.get('goal')),
                        Cost__c = GivingSampleDataSet.toDecimal(row.get('cost')),
                        Start_Date__c = GivingSampleDataSet.dateFor(row.get('startDaysAgo')),
                        End_Date__c = GivingSampleDataSet.dateFor(row.get('endDaysAgo')),
                        Active__c = row.get('active') != false,
                        Parent_Appeal__c = isParent ? null : idsByKey.get(parentKey)
                    )
                );
            }
            idsByKey.putAll(insertAndMap(appeals, keys));
        }
        return idsByKey;
    }

    private static Map<String, Id> insertCommitments(
        GivingSampleDataSet data,
        Map<String, Id> referenceIdsByKey
    ) {
        GivingSampleDataSelector selector = new GivingSampleDataSelector();
        Map<String, Id> peopleByKey = selector.samplePeopleByKey();
        Map<String, Id> accountsByKey = selector.sampleAccountsByKey();

        List<Commitment__c> commitments = new List<Commitment__c>();
        List<String> keys = new List<String>();
        for (Map<String, Object> row : data.commitments) {
            String donorKey = GivingSampleDataSet.asString(row.get('donor'));
            Id donorContact = peopleByKey.get(donorKey);
            Id donorAccount = donorContact == null ? accountsByKey.get(donorKey) : null;
            if (donorContact == null && donorAccount == null) {
                continue;
            }
            keys.add(GivingSampleDataSet.asString(row.get('key')));
            commitments.add(
                new Commitment__c(
                    Sample_Data__c = true,
                    Donor_Contact__c = donorContact,
                    Donor_Account__c = donorAccount,
                    Type__c = GivingSampleDataSet.asString(row.get('type')),
                    Frequency__c = GivingSampleDataSet.asString(row.get('frequency')),
                    Amount__c = GivingSampleDataSet.toDecimal(row.get('amount')),
                    Expected_Total__c = GivingSampleDataSet.toDecimal(row.get('expectedTotal')),
                    Installments_Planned__c = GivingSampleDataSet.toDecimal(
                        row.get('installmentsPlanned')
                    ),
                    Start_Date__c = GivingSampleDataSet.dateFor(row.get('startDaysAgo')),
                    End_Date__c = GivingSampleDataSet.dateFor(row.get('endDaysAgo')),
                    Day_of_Month__c = GivingSampleDataSet.toDecimal(row.get('dayOfMonth')),
                    Status__c = GivingSampleDataSet.asString(row.get('status')),
                    Fund__c = referenceIdsByKey.get(GivingSampleDataSet.asString(row.get('fund'))),
                    Appeal__c = referenceIdsByKey.get(
                        GivingSampleDataSet.asString(row.get('appeal'))
                    )
                )
            );
        }
        return insertAndMap(commitments, keys);
    }

    /**
     * Stage two: one chunk of gifts, their allocations, their tributes, and the soft credits
     * a fundraiser would have entered. Returns how many gifts were inserted.
     */
    public static Integer loadGiftChunk(
        GivingSampleDataSet data,
        Integer chunkIndex,
        Map<String, Id> referenceIdsByKey
    ) {
        List<Map<String, Object>> chunk = data.giftsInChunk(chunkIndex);
        if (chunk.isEmpty()) {
            return 0;
        }
        GivingSampleDataSelector selector = new GivingSampleDataSelector();
        Map<String, Id> peopleByKey = selector.samplePeopleByKey();
        Map<String, Id> accountsByKey = selector.sampleAccountsByKey();

        // The refunds go in second. A negative gift must name the gift it reverses (rule
        // R-G3, enforced by a validation rule), and in this file a reversal sits directly
        // after the gift it reverses, so its original is usually still unsaved at this point.
        List<Map<String, Object>> originals = new List<Map<String, Object>>();
        List<Map<String, Object>> reversals = new List<Map<String, Object>>();
        for (Map<String, Object> row : chunk) {
            if (String.isBlank(GivingSampleDataSet.asString(row.get('originalGift')))) {
                originals.add(row);
            } else {
                reversals.add(row);
            }
        }

        Map<String, Id> giftIdsByKey = insertGifts(
            originals,
            peopleByKey,
            accountsByKey,
            referenceIdsByKey,
            new Map<String, Id>()
        );
        if (!reversals.isEmpty()) {
            Map<String, Id> originalIdsByKey = originalsFor(reversals, selector);
            originalIdsByKey.putAll(giftIdsByKey);
            giftIdsByKey.putAll(
                insertGifts(
                    reversals,
                    peopleByKey,
                    accountsByKey,
                    referenceIdsByKey,
                    originalIdsByKey
                )
            );
        }
        if (giftIdsByKey.isEmpty()) {
            return 0;
        }

        insertAllocations(chunk, giftIdsByKey, referenceIdsByKey);
        insertSoftCredits(data, giftIdsByKey, peopleByKey, accountsByKey);
        insertTributes(data, giftIdsByKey, peopleByKey);
        return giftIdsByKey.size();
    }

    /**
     * Inserts one set of gift rows and returns their keys mapped to the identifiers they
     * were given.
     *
     * Every gift in this set carries its own allocations, so the rule that would put an
     * unallocated gift in the organization's default fund is stood down for the insert and
     * restored straight afterwards (the caller's own value is restored, not `false`, so a
     * screen part way through its own suppressed insert is not disturbed). Without this each
     * gift would arrive with a default allocation and then a second, real one.
     */
    private static Map<String, Id> insertGifts(
        List<Map<String, Object>> rows,
        Map<String, Id> peopleByKey,
        Map<String, Id> accountsByKey,
        Map<String, Id> referenceIdsByKey,
        Map<String, Id> originalsByKey
    ) {
        List<Gift__c> gifts = new List<Gift__c>();
        List<String> keys = new List<String>();
        for (Map<String, Object> row : rows) {
            String donorKey = GivingSampleDataSet.asString(row.get('donor'));
            Id donorContact = peopleByKey.get(donorKey);
            Id donorAccount = donorContact == null ? accountsByKey.get(donorKey) : null;
            if (donorContact == null && donorAccount == null) {
                continue;
            }
            keys.add(GivingSampleDataSet.asString(row.get('key')));
            gifts.add(
                buildGift(row, donorContact, donorAccount, referenceIdsByKey, originalsByKey)
            );
        }
        if (gifts.isEmpty()) {
            return new Map<String, Id>();
        }
        Boolean callerSuppression = GiftService.suppressDefaultAllocations;
        try {
            GiftService.suppressDefaultAllocations = true;
            Database.insert(gifts, AccessLevel.USER_MODE);
        } finally {
            GiftService.suppressDefaultAllocations = callerSuppression;
        }
        return mapKeys(gifts, keys);
    }

    private static Gift__c buildGift(
        Map<String, Object> row,
        Id donorContact,
        Id donorAccount,
        Map<String, Id> referenceIdsByKey,
        Map<String, Id> originalsByKey
    ) {
        Date giftDate = GivingSampleDataSet.dateFor(row.get('daysAgo'));
        String acknowledgment = GivingSampleDataSet.asString(row.get('acknowledgmentStatus'));
        Gift__c gift = new Gift__c(
            Sample_Data__c = true,
            External_Id__c = GivingSampleData.EXTERNAL_ID_PREFIX +
                GivingSampleDataSet.asString(row.get('key')),
            Donor_Contact__c = donorContact,
            Donor_Account__c = donorAccount,
            Gift_Date__c = giftDate,
            Amount__c = GivingSampleDataSet.toDecimal(row.get('amount')),
            Type__c = GivingSampleDataSet.asString(row.get('type')),
            Status__c = GivingSampleDataSet.asString(row.get('status')),
            Acknowledgment_Status__c = acknowledgment,
            Payment_Reference__c = GivingSampleDataSet.asString(row.get('paymentReference')),
            Appeal__c = referenceIdsByKey.get(GivingSampleDataSet.asString(row.get('appeal'))),
            Commitment__c = referenceIdsByKey.get(
                GivingSampleDataSet.asString(row.get('commitment'))
            ),
            In_Kind_Description__c = GivingSampleDataSet.asString(row.get('inKindDescription')),
            Fair_Market_Value__c = GivingSampleDataSet.toDecimal(row.get('fairMarketValue')),
            Refund_Reason__c = GivingSampleDataSet.asString(row.get('refundReason')),
            Original_Gift__c = originalsByKey.get(
                GivingSampleDataSet.asString(row.get('originalGift'))
            )
        );
        if ('Acknowledged'.equals(acknowledgment)) {
            gift.Acknowledgment_Date__c = giftDate == null ? null : giftDate.addDays(4);
        }
        return gift;
    }

    /**
     * The gifts that the negative gifts in this chunk reverse. They are almost always in the
     * same chunk, and the file puts a reversal directly after its original, but a chunk
     * boundary between the two is a matter of how many gifts the file happens to hold, so
     * the originals already inserted are looked up rather than assumed.
     */
    private static Map<String, Id> originalsFor(
        List<Map<String, Object>> chunk,
        GivingSampleDataSelector selector
    ) {
        Set<String> externalIds = new Set<String>();
        for (Map<String, Object> row : chunk) {
            String originalKey = GivingSampleDataSet.asString(row.get('originalGift'));
            if (String.isNotBlank(originalKey)) {
                externalIds.add(GivingSampleData.EXTERNAL_ID_PREFIX + originalKey);
            }
        }
        Map<String, Id> byKey = new Map<String, Id>();
        if (externalIds.isEmpty()) {
            return byKey;
        }
        Map<String, Id> byExternalId = selector.giftIdsByExternalId(externalIds);
        for (String externalId : byExternalId.keySet()) {
            byKey.put(
                externalId.removeStart(GivingSampleData.EXTERNAL_ID_PREFIX),
                byExternalId.get(externalId)
            );
        }
        return byKey;
    }

    private static void insertAllocations(
        List<Map<String, Object>> chunk,
        Map<String, Id> giftIdsByKey,
        Map<String, Id> referenceIdsByKey
    ) {
        List<Gift_Allocation__c> allocations = new List<Gift_Allocation__c>();
        for (Map<String, Object> row : chunk) {
            Id giftId = giftIdsByKey.get(GivingSampleDataSet.asString(row.get('key')));
            if (giftId == null) {
                continue;
            }
            for (Map<String, Object> allocation : GivingSampleDataSet.allocationsOf(row)) {
                Id fundId = referenceIdsByKey.get(
                    GivingSampleDataSet.asString(allocation.get('fund'))
                );
                if (fundId == null) {
                    continue;
                }
                allocations.add(
                    new Gift_Allocation__c(
                        Gift__c = giftId,
                        Fund__c = fundId,
                        Amount__c = GivingSampleDataSet.toDecimal(allocation.get('amount'))
                    )
                );
            }
        }
        if (!allocations.isEmpty()) {
            Database.insert(allocations, AccessLevel.USER_MODE);
        }
    }

    private static void insertSoftCredits(
        GivingSampleDataSet data,
        Map<String, Id> giftIdsByKey,
        Map<String, Id> peopleByKey,
        Map<String, Id> accountsByKey
    ) {
        List<Soft_Credit__c> credits = new List<Soft_Credit__c>();
        for (Map<String, Object> row : data.softCreditsFor(giftIdsByKey.keySet())) {
            Id giftId = giftIdsByKey.get(GivingSampleDataSet.asString(row.get('gift')));
            String personKey = GivingSampleDataSet.asString(row.get('person'));
            Id person = peopleByKey.get(personKey);
            Id account = person == null ? accountsByKey.get(personKey) : null;
            if (giftId == null || (person == null && account == null)) {
                continue;
            }
            credits.add(
                new Soft_Credit__c(
                    Gift__c = giftId,
                    Contact__c = person,
                    Account__c = account,
                    Role__c = GivingSampleDataSet.asString(row.get('role')),
                    Amount__c = GivingSampleDataSet.toDecimal(row.get('amount')),
                    Is_Automatic__c = false
                )
            );
        }
        if (!credits.isEmpty()) {
            Database.insert(credits, AccessLevel.USER_MODE);
        }
    }

    private static void insertTributes(
        GivingSampleDataSet data,
        Map<String, Id> giftIdsByKey,
        Map<String, Id> peopleByKey
    ) {
        List<Tribute__c> tributes = new List<Tribute__c>();
        for (Map<String, Object> row : data.tributesFor(giftIdsByKey.keySet())) {
            Id giftId = giftIdsByKey.get(GivingSampleDataSet.asString(row.get('gift')));
            if (giftId == null) {
                continue;
            }
            tributes.add(
                new Tribute__c(
                    Gift__c = giftId,
                    Type__c = GivingSampleDataSet.asString(row.get('type')),
                    Honoree_Contact__c = peopleByKey.get(
                        GivingSampleDataSet.asString(row.get('honoreePerson'))
                    ),
                    Honoree_Name__c = GivingSampleDataSet.asString(row.get('honoreeName')),
                    Notification_Recipient_Contact__c = peopleByKey.get(
                        GivingSampleDataSet.asString(row.get('recipientPerson'))
                    ),
                    Message__c = GivingSampleDataSet.asString(row.get('message'))
                )
            );
        }
        if (!tributes.isEmpty()) {
            Database.insert(tributes, AccessLevel.USER_MODE);
        }
    }

    /**
     * Stage three: settles the installments whose due date has already gone by, using the
     * same method the daily job runs, and returns how many changed. That is what makes the
     * lapsed monthly donor in the set genuinely overdue rather than labelled overdue.
     *
     * Rollup fields (total giving, this year, largest gift, appeal and fund totals) are not
     * recalculated here. Gift rollups run on the nightly reconciliation rather than on save,
     * and starting a full recalculation from a sample data load would launch the engine's
     * batch jobs behind the administrator's back. The admin guide sends the reader to
     * Recalculate on the Rollups page instead.
     */
    public static Integer finish() {
        try {
            return CommitmentService.markOverdue();
        } catch (Exception failed) {
            // A sample set that loaded is worth more than a status that did not settle.
            ErrorLogger.log(failed, CONTEXT);
            return 0;
        }
    }

    /**
     * How many removeNext() calls clear every Giving sample record: the chunks each kind needs,
     * counted once when the removal batch starts. Gifts are counted as the reversals and the
     * rest, because the two are removed one after the other.
     */
    public static Integer removeStageCount() {
        GivingSampleDataSelector selector = new GivingSampleDataSelector();
        Integer reversals = selector.sampleReversalIds().size();
        return chunksFor(reversals) +
            chunksFor(selector.sampleGiftIds().size() - reversals) +
            chunksFor(selector.sampleCommitmentIds().size()) +
            chunksFor(selector.sampleAppealIds().size()) +
            chunksFor(selector.sampleFundIds().size());
    }

    private static Integer chunksFor(Integer recordCount) {
        return (recordCount + removeChunkSize - 1) / removeChunkSize;
    }

    /**
     * Deletes the next chunk of Giving sample records and returns how many went, 0 once none
     * are left. A stage of GivingSampleDataRemoveStages calls it (ADMIN-3), because the whole
     * set's gift automation is more than one transaction can run. The order is the dependency
     * order, and each kind is emptied before the next is started: refunds and write-offs first,
     * because a gift that a reversal points at refuses to be deleted (ADR-0010), then the other
     * gifts, because a commitment whose installments have been paid refuses to be deleted while
     * those gifts are still there, then commitments (their installments go with them), then
     * appeals and funds, which the gifts pointed at.
     *
     * The two protection rules are stood down for this transaction. They exist to stop a
     * person deleting giving history by accident (R-IN2, R-CM7), and an installment that a
     * sample gift paid still reads as paid until the rollups next run, so without the
     * bypass the sample commitments would refuse to go and the whole remove would fail. The
     * bypass is per transaction, so the administrator's own next delete is protected as
     * usual.
     */
    public static Integer removeNext() {
        GivingSampleDataSelector selector = new GivingSampleDataSelector();
        AutomationControl.bypass(COMMITMENT_AUTOMATION);
        AutomationControl.bypass(INSTALLMENT_AUTOMATION);
        try {
            Integer removed = deleteChunk(selector.sampleReversalIds());
            if (removed == 0) {
                removed = deleteChunk(selector.sampleGiftIds());
            }
            if (removed == 0) {
                removed = deleteChunk(selector.sampleCommitmentIds());
            }
            if (removed == 0) {
                removed = deleteChunk(selector.sampleAppealIds());
            }
            if (removed == 0) {
                removed = deleteChunk(selector.sampleFundIds());
            }
            return removed;
        } finally {
            AutomationControl.clearBypass(COMMITMENT_AUTOMATION);
            AutomationControl.clearBypass(INSTALLMENT_AUTOMATION);
        }
    }

    private static Integer deleteChunk(List<Id> ids) {
        List<Id> chunk = new List<Id>();
        for (Integer i = 0; i < ids.size() && i < removeChunkSize; i++) {
            chunk.add(ids[i]);
        }
        if (!chunk.isEmpty()) {
            Database.delete(chunk, AccessLevel.USER_MODE);
        }
        return chunk.size();
    }

    /** Inserts the records and returns their keys mapped to the identifiers they were given. */
    private static Map<String, Id> insertAndMap(List<SObject> records, List<String> keys) {
        if (records.isEmpty()) {
            return new Map<String, Id>();
        }
        Database.insert(records, AccessLevel.USER_MODE);
        return mapKeys(records, keys);
    }

    private static Map<String, Id> mapKeys(List<SObject> records, List<String> keys) {
        Map<String, Id> idsByKey = new Map<String, Id>();
        for (Integer index = 0; index < records.size(); index++) {
            idsByKey.put(keys[index], records[index].Id);
        }
        return idsByKey;
    }
}
