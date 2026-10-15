/**
 * Records gifts sent by other systems (feature X-03), for the REST endpoint and the Flow action
 * alike. The contract is `docs/api/inbound-gift-api.md` and the decisions behind it ADR-0051.
 *
 * Four rules shape everything here:
 *
 * - A gift is made the way Giving makes one: an ordinary `Gift__c` insert in user mode, then
 *   `GiftService.applyChosenFunds` for a chosen fund, the path quick entry and gift batches use
 *   (ADR-0045). Giving's own triggers derive the household and the default allocation; nothing
 *   here reimplements a gift rule.
 * - External Id is the key (canonical model R-G7). A gift already carrying it is answered, never
 *   edited: `existing` when the amount agrees, `external_id_conflict` when it does not.
 * - A donor is found, never created: by record id, or by email through Core's importer matcher.
 * - Each gift succeeds or fails on its own, and every failure is an answer with a stable error
 *   code, logged to the Error Log so the nonprofit sees a gift that did not arrive.
 */
public with sharing class InboundGiftService {
    private static final Integer MAX_EXTERNAL_ID = 100;
    private static final Integer MAX_PARSER_MESSAGE = 255;
    private static final Integer SAVE_ATTEMPTS = 2;
    private static final String CONTEXT = 'InboundGiftService';

    /** External Id's API name, with and without a namespace, for reading a duplicate error. */
    private static final Set<String> EXTERNAL_ID_NAMES = new Set<String>{
        Gift__c.External_Id__c.getDescribe().getName().toLowerCase(),
        Gift__c.External_Id__c.getDescribe().getLocalName().toLowerCase()
    };

    /**
     * External ids whose fund designation a test makes fail, so the second save attempt can be
     * tested: nothing in a test org splits a gift between its insert and its designation.
     */
    @TestVisible
    private static Set<String> designationRefusedInTest = new Set<String>();

    /**
     * One gift from a REST request body. A body that is not JSON, names a field `InboundGift`
     * does not have, or carries a value of the wrong type is refused as a whole: reading it
     * strictly is what stops a misspelled field from being silently ignored.
     */
    public static InboundGiftResult recordBody(Blob body) {
        InboundGift gift = null;
        String problem = null;
        try {
            gift = (InboundGift) JSON.deserializeStrict(
                body == null ? '' : body.toString(),
                InboundGift.class
            );
        } catch (Exception malformed) {
            problem = malformed.getMessage();
        }
        if (gift == null) {
            InboundGiftResult refused = InboundGiftResult.rejected(
                InboundGiftResult.ERROR_INVALID_REQUEST,
                String.format(
                    Label.Mirror_InboundGift_ErrorInvalidRequest,
                    new List<String>{ String.valueOf(problem).abbreviate(MAX_PARSER_MESSAGE) }
                )
            );
            logRefusals(new List<InboundGift>{ null }, new List<InboundGiftResult>{ refused });
            return refused;
        }
        return record(new List<InboundGift>{ gift })[0];
    }

    /**
     * Records each gift and answers each one, in the order given. Nothing that goes wrong with one
     * gift stops another; only an unexpected failure undoes the whole call, and it is answered as
     * `internal_error` for every gift, which a caller can safely send again.
     */
    public static List<InboundGiftResult> record(List<InboundGift> requests) {
        List<InboundGiftResult> results = new List<InboundGiftResult>();
        if (requests == null || requests.isEmpty()) {
            return results;
        }
        Savepoint start = Database.setSavepoint();
        try {
            results = process(requests);
        } catch (Exception unexpected) {
            Database.rollback(start);
            ErrorLogger.log(unexpected, CONTEXT);
            results = new List<InboundGiftResult>();
            for (Integer index = 0; index < requests.size(); index++) {
                results.add(
                    InboundGiftResult.rejected(
                        InboundGiftResult.ERROR_INTERNAL,
                        Label.Mirror_InboundGift_ErrorInternal
                    )
                );
            }
        }
        logRefusals(requests, results);
        return results;
    }

    private static List<InboundGiftResult> process(List<InboundGift> requests) {
        List<InboundGiftRequest> all = new List<InboundGiftRequest>();
        Map<String, InboundGiftRequest> firstByKey = new Map<String, InboundGiftRequest>();
        List<InboundGiftRequest> repeats = new List<InboundGiftRequest>();
        for (InboundGift request : requests) {
            InboundGiftRequest item = new InboundGiftRequest(request);
            all.add(item);
            item.validate();
            if (item.result != null) {
                continue;
            }
            if (firstByKey.containsKey(item.key)) {
                repeats.add(item);
            } else {
                firstByKey.put(item.key, item);
            }
        }

        // A query or a save the integration user is not allowed to make is a setup problem, not
        // a fault: every gift it stops is answered gift_not_saved, which says not to resend
        // until someone fixes the access, rather than internal_error, which says resend.
        try {
            List<InboundGiftRequest> fresh = answerRecordedGifts(firstByKey.values());
            resolveReferences(fresh);
            List<InboundGiftRequest> ready = new List<InboundGiftRequest>();
            for (InboundGiftRequest item : fresh) {
                if (item.result == null) {
                    ready.add(item);
                }
            }
            insertGifts(ready);
        } catch (QueryException refused) {
            refuseUnanswered(firstByKey.values(), refused);
        } catch (DmlException refused) {
            refuseUnanswered(firstByKey.values(), refused);
        }

        for (InboundGiftRequest item : repeats) {
            InboundGiftRequest first = firstByKey.get(item.key);
            if (first.recordedGiftId == null) {
                item.result = InboundGiftResult.rejected(
                    InboundGiftResult.ERROR_INVALID_FIELD,
                    Label.Mirror_InboundGift_ErrorRepeated
                );
            } else {
                answerFromRecordedGift(
                    item,
                    new Gift__c(Id = first.recordedGiftId, Amount__c = first.recordedAmount)
                );
            }
        }

        List<InboundGiftResult> results = new List<InboundGiftResult>();
        for (InboundGiftRequest item : all) {
            results.add(item.result);
        }
        return results;
    }

    /** Answers the gifts already recorded under their external id, and returns the rest. */
    private static List<InboundGiftRequest> answerRecordedGifts(List<InboundGiftRequest> items) {
        List<InboundGiftRequest> fresh = new List<InboundGiftRequest>();
        Map<String, Gift__c> recorded = InboundGiftSelector.giftsByExternalId(externalIds(items));
        for (InboundGiftRequest item : items) {
            Gift__c found = recorded.get(item.key);
            if (found != null) {
                answerFromRecordedGift(item, found);
            } else {
                fresh.add(item);
            }
        }
        return fresh;
    }

    private static void refuseUnanswered(List<InboundGiftRequest> items, Exception refused) {
        for (InboundGiftRequest item : items) {
            if (item.result == null) {
                item.result = accessRefused(refused);
            }
        }
    }

    /**
     * The donor, fund and appeal each gift names, with one query per kind of reference however
     * many gifts there are. A reference that is malformed, of the wrong kind, or to a record the
     * integration user cannot see gets the same answer as one to nothing, so a caller probing
     * with made-up identifiers learns nothing about what is in the org.
     */
    private static void resolveReferences(List<InboundGiftRequest> items) {
        Set<Id> contactIds = new Set<Id>();
        Set<Id> accountIds = new Set<Id>();
        Set<String> emailKeys = new Set<String>();
        Set<String> fundCodes = new Set<String>();
        Set<Id> fundIds = new Set<Id>();
        Set<Id> appealIds = new Set<Id>();
        for (InboundGiftRequest item : items) {
            InboundGift request = item.request;
            Id donor = InboundGiftRequest.asId(request.donorId);
            if (donor != null && donor.getSObjectType() == Contact.SObjectType) {
                contactIds.add(donor);
            } else if (donor != null && donor.getSObjectType() == Account.SObjectType) {
                accountIds.add(donor);
            }
            if (String.isNotBlank(request.donorEmail)) {
                emailKeys.add(ImportMatcher.emailKey(request.donorEmail));
            }
            if (String.isNotBlank(request.fundCode)) {
                fundCodes.add(request.fundCode.trim());
            }
            addIfOfType(fundIds, request.fundId, Fund__c.SObjectType);
            addIfOfType(appealIds, request.appealId, Appeal__c.SObjectType);
        }

        Map<String, Id> contactByEmail = ImportMatcher.contactsByEmail(emailKeys);
        contactIds.addAll(contactByEmail.values());
        Map<Id, Id> donorByContact = InboundGiftSelector.donorForContacts(contactIds);
        Set<Id> visibleAccounts = InboundGiftSelector.accountIds(accountIds);
        Map<String, Id> fundByCode = InboundGiftSelector.activeFundsByCode(fundCodes);
        Set<Id> activeFunds = InboundGiftSelector.activeFundIds(fundIds);
        Set<Id> visibleAppeals = InboundGiftSelector.appealIds(appealIds);

        for (InboundGiftRequest item : items) {
            InboundGift request = item.request;
            Id donor;
            String donorMissing;
            if (String.isNotBlank(request.donorId)) {
                Id named = InboundGiftRequest.asId(request.donorId);
                donor = named == null
                    ? null
                    : (donorByContact.containsKey(named)
                          ? donorByContact.get(named)
                          : (visibleAccounts.contains(named) ? named : null));
                donorMissing = Label.Mirror_InboundGift_ErrorDonorIdNotFound;
            } else {
                Id contactId = contactByEmail.get(ImportMatcher.emailKey(request.donorEmail));
                donor = contactId == null ? null : donorByContact.get(contactId);
                donorMissing = Label.Mirror_InboundGift_ErrorDonorEmailNotFound;
            }
            if (donor == null) {
                item.result = InboundGiftResult.rejected(
                    InboundGiftResult.ERROR_DONOR_NOT_FOUND,
                    donorMissing
                );
                continue;
            }
            if (donor.getSObjectType() == Contact.SObjectType) {
                item.donorContactId = donor;
            } else {
                item.donorAccountId = donor;
            }

            if (String.isNotBlank(request.fundCode)) {
                item.fundId = fundByCode.get(request.fundCode.trim().toLowerCase());
            } else if (String.isNotBlank(request.fundId)) {
                Id named = InboundGiftRequest.asId(request.fundId);
                item.fundId = activeFunds.contains(named) ? named : null;
            }
            Boolean fundNamed =
                String.isNotBlank(request.fundCode) || String.isNotBlank(request.fundId);
            if (fundNamed && item.fundId == null) {
                item.result = InboundGiftResult.rejected(
                    InboundGiftResult.ERROR_FUND_NOT_FOUND,
                    Label.Mirror_InboundGift_ErrorFundNotFound
                );
                continue;
            }

            if (String.isNotBlank(request.appealId)) {
                Id named = InboundGiftRequest.asId(request.appealId);
                if (!visibleAppeals.contains(named)) {
                    item.result = InboundGiftResult.rejected(
                        InboundGiftResult.ERROR_APPEAL_NOT_FOUND,
                        Label.Mirror_InboundGift_ErrorAppealNotFound
                    );
                    continue;
                }
                item.appealId = named;
            }
        }
    }

    /**
     * Inserts the gifts, each on its own, then designates the ones that named a fund, each on
     * its own too (`GiftService.applyChosenFundsEach`).
     *
     * The platform saves what it can and reports the rest per gift. Designation comes after the
     * insert, and a gift it cannot be applied to (one other automation already split, or one
     * whose allocation the platform refused) must not stay recorded against the wrong fund, so
     * that attempt is rolled back and made again without it. Two attempts at most: the second
     * can only fail the same way if more gifts fail designation, and then the rest are refused
     * rather than retried forever. Up to 200 gifts a call (a Flow batch) stay inside the limits:
     * each attempt is one insert, one allocation query and at most two allocation saves.
     */
    private static void insertGifts(List<InboundGiftRequest> items) {
        List<InboundGiftRequest> remaining = items;
        List<InboundGiftRequest> duplicates = new List<InboundGiftRequest>();
        for (Integer attempt = 0; attempt < SAVE_ATTEMPTS && !remaining.isEmpty(); attempt++) {
            Savepoint beforeAttempt = Database.setSavepoint();
            List<Gift__c> gifts = new List<Gift__c>();
            for (InboundGiftRequest item : remaining) {
                gifts.add(item.toGift());
            }
            List<Database.SaveResult> saves;
            try {
                saves = Database.insert(gifts, false, AccessLevel.USER_MODE);
            } catch (Exception refused) {
                // User mode refuses the whole list when the integration user may not create
                // gifts at all: a setup problem, answered on every gift in the platform's words.
                for (InboundGiftRequest item : remaining) {
                    item.result = notSaved(refused.getMessage());
                }
                break;
            }

            List<InboundGiftRequest> saved = new List<InboundGiftRequest>();
            List<Gift__c> savedGifts = new List<Gift__c>();
            Map<Id, Id> fundByGift = new Map<Id, Id>();
            for (Integer index = 0; index < saves.size(); index++) {
                InboundGiftRequest item = remaining[index];
                if (saves[index].isSuccess()) {
                    item.giftId = gifts[index].Id;
                    saved.add(item);
                    savedGifts.add(gifts[index]);
                    if (item.fundId != null) {
                        fundByGift.put(item.giftId, item.fundId);
                    }
                } else if (isExternalIdClash(saves[index].getErrors())) {
                    duplicates.add(item);
                } else {
                    item.result = notSaved(messagesOf(saves[index].getErrors()));
                }
            }

            Map<Id, String> notApplied;
            try {
                notApplied = GiftService.applyChosenFundsEach(savedGifts, fundByGift);
            } catch (QueryException refused) {
                refuseAttempt(beforeAttempt, saved, refused);
                break;
            } catch (DmlException refused) {
                refuseAttempt(beforeAttempt, saved, refused);
                break;
            }
            if (Test.isRunningTest() && !designationRefusedInTest.isEmpty()) {
                for (InboundGiftRequest item : saved) {
                    if (designationRefusedInTest.contains(item.key)) {
                        notApplied.put(item.giftId, 'Refused by the test.');
                    }
                }
            }
            if (notApplied.isEmpty()) {
                for (InboundGiftRequest item : saved) {
                    item.result = InboundGiftResult.recorded(
                        InboundGiftResult.OUTCOME_CREATED,
                        item.giftId,
                        Label.Mirror_InboundGift_Created
                    );
                    item.recordedGiftId = item.giftId;
                    item.recordedAmount = item.request.amount;
                }
                remaining = new List<InboundGiftRequest>();
                break;
            }

            Database.rollback(beforeAttempt);
            List<InboundGiftRequest> next = new List<InboundGiftRequest>();
            for (InboundGiftRequest item : saved) {
                if (notApplied.containsKey(item.giftId)) {
                    String platformMessage = notApplied.get(item.giftId);
                    item.result = platformMessage == null
                        ? InboundGiftResult.rejected(
                              InboundGiftResult.ERROR_NOT_SAVED,
                              Label.Mirror_InboundGift_ErrorFundNotApplied
                          )
                        : notSaved(platformMessage);
                } else {
                    next.add(item);
                }
                item.giftId = null;
            }
            remaining = next;
        }
        for (InboundGiftRequest item : remaining) {
            if (item.result == null) {
                item.result = InboundGiftResult.rejected(
                    InboundGiftResult.ERROR_NOT_SAVED,
                    Label.Mirror_InboundGift_ErrorFundNotApplied
                );
            }
        }
        answerDuplicates(duplicates);
    }

    /** Designation could not even be attempted: the attempt is undone and its gifts refused. */
    private static void refuseAttempt(
        Savepoint beforeAttempt,
        List<InboundGiftRequest> saved,
        Exception refused
    ) {
        Database.rollback(beforeAttempt);
        for (InboundGiftRequest item : saved) {
            item.giftId = null;
            item.result = accessRefused(refused);
        }
    }

    /**
     * Gifts the unique index refused: another request recorded the same external id between our
     * look and our save, or a gift the integration user cannot see already holds it. Looked up
     * again, and answered as a resend when it can be seen.
     */
    private static void answerDuplicates(List<InboundGiftRequest> duplicates) {
        if (duplicates.isEmpty()) {
            return;
        }
        Map<String, Gift__c> recorded = InboundGiftSelector.giftsByExternalId(
            externalIds(duplicates)
        );
        for (InboundGiftRequest item : duplicates) {
            Gift__c found = recorded.get(item.key);
            if (found != null) {
                answerFromRecordedGift(item, found);
            } else {
                item.result = InboundGiftResult.rejected(
                    InboundGiftResult.ERROR_CONFLICT,
                    Label.Mirror_InboundGift_ErrorConflictUnseen
                );
            }
        }
    }

    /** A gift already carries this external id: the same gift sent again, or a conflict. */
    private static void answerFromRecordedGift(InboundGiftRequest item, Gift__c found) {
        item.recordedGiftId = found.Id;
        item.recordedAmount = found.Amount__c;
        if (found.Amount__c == item.request.amount) {
            item.result = InboundGiftResult.recorded(
                InboundGiftResult.OUTCOME_EXISTING,
                found.Id,
                Label.Mirror_InboundGift_Existing
            );
        } else {
            item.result = InboundGiftResult.rejected(
                InboundGiftResult.ERROR_CONFLICT,
                Label.Mirror_InboundGift_ErrorConflict
            );
            item.result.giftId = found.Id;
        }
    }

    /**
     * Every refusal, one Error Log line each at Warning, naming the external id and the error
     * code and nothing else, so the nonprofit sees a gift that did not arrive. The message is
     * left out on purpose: it can quote a validation rule's words or the parser's, and either
     * can repeat what the donor sent. The sending system has the message in its response.
     */
    private static void logRefusals(List<InboundGift> requests, List<InboundGiftResult> results) {
        List<String> lines = new List<String>();
        for (Integer index = 0; index < results.size(); index++) {
            InboundGiftResult result = results[index];
            if (result == null || result.outcome != InboundGiftResult.OUTCOME_REJECTED) {
                continue;
            }
            InboundGift request = index < requests.size() ? requests[index] : null;
            String externalId = request == null || String.isBlank(request.externalId)
                ? '-'
                : request.externalId.trim().abbreviate(MAX_EXTERNAL_ID);
            lines.add(
                String.format(
                    Label.Mirror_InboundGift_LogRefused,
                    new List<String>{ externalId, result.errorCode }
                )
            );
        }
        ErrorLogger.logMessages(lines, CONTEXT, ErrorLogger.SEVERITY_WARNING);
    }

    private static Set<String> externalIds(List<InboundGiftRequest> items) {
        Set<String> values = new Set<String>();
        for (InboundGiftRequest item : items) {
            values.add(item.externalId);
        }
        return values;
    }

    /**
     * A save refused because another gift holds this external id, and not because some other
     * unique field clashed. The field list is the evidence. When the clashing gift is one the
     * integration user cannot see, the platform names neither the field nor the record; the
     * insert sets no other unique field (receipt numbers are assigned later, by update), so an
     * unnamed clash can only be the external id.
     */
    private static Boolean isExternalIdClash(List<Database.Error> errors) {
        for (Database.Error error : errors) {
            if (error.getStatusCode() != StatusCode.DUPLICATE_VALUE) {
                continue;
            }
            List<String> fields = error.getFields();
            if (fields == null || fields.isEmpty()) {
                return true;
            }
            for (String field : fields) {
                if (field != null && EXTERNAL_ID_NAMES.contains(field.toLowerCase())) {
                    return true;
                }
            }
        }
        return false;
    }

    private static String messagesOf(List<Database.Error> errors) {
        List<String> messages = new List<String>();
        for (Database.Error error : errors) {
            messages.add(error.getMessage());
        }
        return String.join(messages, ' ');
    }

    private static void addIfOfType(Set<Id> target, String value, Schema.SObjectType expected) {
        Id parsed = InboundGiftRequest.asId(value);
        if (parsed != null && parsed.getSObjectType() == expected) {
            target.add(parsed);
        }
    }

    private static InboundGiftResult accessRefused(Exception refused) {
        return InboundGiftResult.rejected(
            InboundGiftResult.ERROR_NOT_SAVED,
            String.format(
                Label.Mirror_InboundGift_ErrorAccess,
                new List<String>{ refused.getMessage() }
            )
        );
    }

    private static InboundGiftResult notSaved(String platformMessage) {
        return InboundGiftResult.rejected(
            InboundGiftResult.ERROR_NOT_SAVED,
            String.format(
                Label.Mirror_InboundGift_ErrorNotSaved,
                new List<String>{ platformMessage }
            )
        );
    }
}
