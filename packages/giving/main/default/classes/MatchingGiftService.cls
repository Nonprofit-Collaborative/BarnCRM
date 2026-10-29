/**
 * Matching gifts: the employer's gift that an employee's gift earned (feature G-10, canonical
 * model R-G11).
 *
 * The two gifts stay two gifts. The company gave its money and is hard credited for it, the
 * employee gave theirs and is hard credited for that, and the link records that one caused the
 * other. The employee then gets a soft credit on the company's gift, so their real influence on
 * the organization's income is visible without anyone being credited with money they did not
 * give.
 *
 * What is checked before a link is accepted:
 *
 *   - one gift of the pair comes from an account whose record type is Organization, and it is
 *     the employer's gift;
 *   - the other comes from a person, and it is the employee's gift;
 *   - where that person's Employer is filled in, it names that same organization;
 *   - neither gift is already linked to a third gift, and a gift never matches itself;
 *   - neither gift has been refunded or written off, because a link that outlived the money
 *     would keep crediting an employee for a match the organization gave back.
 *
 * Where Employer is blank the link is accepted without complaint. Filling it in is what turns a
 * silent mistake into a message.
 *
 * There are two ways in and they enforce the same rules: `link` and `unlink`, called by an action
 * with two record ids, and `applyLinkChanges`, called by the gift trigger when someone edits the
 * Matched Gift field on the record page.
 *
 * A refund of the employer's gift reverses that credit rather than removing it (ADR-0031). The
 * negative gift `GiftService.refund` inserts is not half of a matching pair, so it earns no
 * matched donor credit of its own; `syncReversalCredits` mirrors the employer gift's credits onto
 * it negatively instead, prorated to the amount returned. That is the same shape R-SC5 gives
 * household credits, and it is what makes a partial refund read as the amount the employer still
 * holds rather than as the whole match.
 */
public with sharing class MatchingGiftService {
    public class MatchingGiftException extends Exception {
    }

    /**
     * Links an employee's gift to the employer's gift that matched it, from either side.
     */
    public static void link(Id employeeGiftId, Id employerGiftId) {
        if (employeeGiftId == null || employerGiftId == null) {
            throw new MatchingGiftException(Label.Giving_MatchingGift_GiftNotFound);
        }
        if (employeeGiftId == employerGiftId) {
            throw new MatchingGiftException(Label.Giving_MatchingGift_SameGift);
        }
        Map<Id, Gift__c> giftById = giftsById(new Set<Id>{ employeeGiftId, employerGiftId });
        Gift__c employeeGift = giftById.get(employeeGiftId);
        Gift__c employerGift = giftById.get(employerGiftId);
        if (employeeGift == null || employerGift == null) {
            throw new MatchingGiftException(Label.Giving_MatchingGift_GiftNotFound);
        }
        if (!isOrganizationGift(employerGift)) {
            throw new MatchingGiftException(Label.Giving_MatchingGift_EmployerMustBeOrganization);
        }
        String problem = problemWith(employerGift, employeeGift);
        if (problem != null) {
            throw new MatchingGiftException(problem);
        }

        Database.update(
            new List<Gift__c>{
                new Gift__c(Id = employeeGiftId, Matched_Gift__c = employerGiftId),
                new Gift__c(Id = employerGiftId, Matched_Gift__c = employeeGiftId)
            },
            true,
            AccessLevel.USER_MODE
        );
        insertCredits(
            missingCreditsFor(
                new Map<Id, Id>{ employerGift.Id => donorPersonOf(employeeGift) },
                new Map<Id, Gift__c>{ employerGift.Id => employerGift }
            )
        );
        // A gift refunded in part is still linkable: R-G11 only refuses a link where the whole
        // gift has gone back. Reversing here as well as on the refund keeps recognition at the
        // amount still held whichever of the two happened first (ADR-0031).
        syncReversalCredits(new Set<Id>{ employerGift.Id });
    }

    /**
     * Undoes a link from either side, and removes the credit the link created.
     */
    public static void unlink(Id giftId) {
        if (giftId == null) {
            throw new MatchingGiftException(Label.Giving_MatchingGift_GiftNotFound);
        }
        Gift__c gift = giftsById(new Set<Id>{ giftId }).get(giftId);
        if (gift == null) {
            throw new MatchingGiftException(Label.Giving_MatchingGift_GiftNotFound);
        }
        if (gift.Matched_Gift__c == null) {
            return;
        }
        Id otherGiftId = gift.Matched_Gift__c;
        Database.update(
            new List<Gift__c>{
                new Gift__c(Id = giftId, Matched_Gift__c = null),
                new Gift__c(Id = otherGiftId, Matched_Gift__c = null)
            },
            true,
            AccessLevel.USER_MODE
        );
        Set<Id> pair = new Set<Id>{ giftId, otherGiftId };
        removeMatchedDonorCredits(pair);
        // The negative credits reverse the credit that has just gone, so they go with it: an
        // orphaned minus 200 is a worse number than no rows at all (ADR-0031).
        syncReversalCredits(pair);
    }

    /**
     * The trigger path: someone typed into Matched Gift on a gift record, or an import did.
     * Refuses a link the rules do not allow, writes the other side of the one they do, and
     * maintains the matched donor credit either way.
     */
    public static void applyLinkChanges(List<Gift__c> gifts, Map<Id, Gift__c> priorById) {
        if (gifts == null || gifts.isEmpty()) {
            return;
        }
        Map<Id, Id> newPartnerByGift = new Map<Id, Id>();
        Map<Id, Id> oldPartnerByGift = new Map<Id, Id>();
        Set<Id> involved = new Set<Id>();
        for (Gift__c gift : gifts) {
            Id priorPartnerId = null;
            if (priorById != null && priorById.containsKey(gift.Id)) {
                priorPartnerId = priorById.get(gift.Id).Matched_Gift__c;
            }
            if (gift.Matched_Gift__c == priorPartnerId) {
                continue;
            }
            involved.add(gift.Id);
            if (gift.Matched_Gift__c != null) {
                newPartnerByGift.put(gift.Id, gift.Matched_Gift__c);
                involved.add(gift.Matched_Gift__c);
            }
            if (priorPartnerId != null) {
                oldPartnerByGift.put(gift.Id, priorPartnerId);
                involved.add(priorPartnerId);
            }
        }
        if (involved.isEmpty()) {
            return;
        }

        Map<Id, Gift__c> giftById = giftsById(involved);
        Map<Id, Gift__c> updateById = new Map<Id, Gift__c>();
        Map<Id, Id> employeePersonByEmployerGift = new Map<Id, Id>();
        Set<Id> creditsToRemoveFor = new Set<Id>();
        Map<Id, Gift__c> byId = new Map<Id, Gift__c>(gifts);

        for (Id giftId : oldPartnerByGift.keySet()) {
            Id oldPartnerId = oldPartnerByGift.get(giftId);
            if (newPartnerByGift.get(giftId) == oldPartnerId) {
                continue;
            }
            creditsToRemoveFor.add(giftId);
            creditsToRemoveFor.add(oldPartnerId);
            Gift__c oldPartner = giftById.get(oldPartnerId);
            if (oldPartner != null && oldPartner.Matched_Gift__c == giftId) {
                updateById.put(
                    oldPartnerId,
                    new Gift__c(Id = oldPartnerId, Matched_Gift__c = null)
                );
            }
        }

        for (Id giftId : newPartnerByGift.keySet()) {
            Id partnerId = newPartnerByGift.get(giftId);
            Gift__c edited = giftById.get(giftId);
            Gift__c partner = giftById.get(partnerId);
            Gift__c record = byId.get(giftId);
            if (edited == null || partner == null) {
                record.addError(Label.Giving_MatchingGift_GiftNotFound);
                continue;
            }
            if (giftId == partnerId) {
                record.addError(Label.Giving_MatchingGift_SameGift);
                continue;
            }
            Gift__c employerGift = isOrganizationGift(edited) ? edited : partner;
            Gift__c employeeGift = employerGift.Id == edited.Id ? partner : edited;
            if (!isOrganizationGift(employerGift)) {
                record.addError(Label.Giving_MatchingGift_EmployerMustBeOrganization);
                continue;
            }
            String problem = problemWith(employerGift, employeeGift);
            if (problem != null) {
                record.addError(problem);
                continue;
            }
            if (partner.Matched_Gift__c != giftId) {
                updateById.put(partnerId, new Gift__c(Id = partnerId, Matched_Gift__c = giftId));
            }
            creditsToRemoveFor.remove(giftId);
            creditsToRemoveFor.remove(partnerId);
            employeePersonByEmployerGift.put(employerGift.Id, donorPersonOf(employeeGift));
        }

        if (!creditsToRemoveFor.isEmpty()) {
            removeMatchedDonorCredits(creditsToRemoveFor);
        }
        if (!updateById.isEmpty()) {
            // Writing the other side of the link fires this handler again for the partner gift.
            // The credits are therefore worked out after this line and not before it, so that
            // the pass that gets there first inserts them and this one sees them and stops.
            Database.update(updateById.values(), true, AccessLevel.USER_MODE);
        }
        insertCredits(missingCreditsFor(employeePersonByEmployerGift, giftById));
        syncReversalCredits(involved);
    }

    /**
     * Brings the negative Matched Donor credits carried by these gifts' refunds and write-offs
     * into line with the credits the gifts themselves carry (ADR-0031).
     *
     * Keyed on the gift being reversed rather than on the refund action, and idempotent, so the
     * same records come out whichever happened first: the refund of a linked gift, a link made on
     * a gift already partly refunded, or the unlink that takes the credit away again. A gift with
     * no matched donor credit wants no negative ones, which is how the unlink case removes them
     * without a branch of its own.
     */
    public static void syncReversalCredits(Set<Id> reversedGiftIds) {
        if (reversedGiftIds == null || reversedGiftIds.isEmpty()) {
            return;
        }
        List<Gift__c> reversals = GiftSelector.selectReversalsFor(reversedGiftIds);
        if (reversals.isEmpty()) {
            return;
        }
        Map<Id, List<Soft_Credit__c>> creditsByGift = matchedDonorCreditsByGift(reversedGiftIds);
        Set<Id> reversalGiftIds = new Set<Id>();
        Map<String, Soft_Credit__c> wanted = new Map<String, Soft_Credit__c>();
        for (Gift__c reversal : reversals) {
            reversalGiftIds.add(reversal.Id);
            addReversedCredits(reversal, creditsByGift.get(reversal.Original_Gift__c), wanted);
        }
        SoftCreditService.reconcileAutomaticCredits(
            wanted,
            SoftCreditSelector.selectAutomaticForGifts(
                reversalGiftIds,
                SoftCreditService.ROLE_MATCHED_DONOR
            )
        );
    }

    /**
     * The matched donor credits these gifts carry, grouped by the gift carrying them.
     */
    private static Map<Id, List<Soft_Credit__c>> matchedDonorCreditsByGift(Set<Id> giftIds) {
        Map<Id, List<Soft_Credit__c>> creditsByGift = new Map<Id, List<Soft_Credit__c>>();
        for (
            Soft_Credit__c credit : SoftCreditSelector.selectAutomaticForGifts(
                giftIds,
                SoftCreditService.ROLE_MATCHED_DONOR
            )
        ) {
            if (!creditsByGift.containsKey(credit.Gift__c)) {
                creditsByGift.put(credit.Gift__c, new List<Soft_Credit__c>());
            }
            creditsByGift.get(credit.Gift__c).add(credit);
        }
        return creditsByGift;
    }

    /**
     * The negative credits one reversing gift should carry, added to the wanted map.
     *
     * The share each credit was given, applied to what came back: a matched donor credit is the
     * whole of the employer's gift, so 100 percent of a refund of 200 is minus 200. A credit with
     * no percent belongs to a gift of zero, which cannot be refunded.
     */
    private static void addReversedCredits(
        Gift__c reversal,
        List<Soft_Credit__c> credits,
        Map<String, Soft_Credit__c> wanted
    ) {
        if (credits == null || reversal.Amount__c == null) {
            return;
        }
        for (Soft_Credit__c credit : credits) {
            Id creditedId = credit.Contact__c != null ? credit.Contact__c : credit.Account__c;
            Decimal reversedAmount = SoftCreditService.amountOf(
                credit.Percent__c,
                reversal.Amount__c
            );
            if (creditedId == null || reversedAmount == null) {
                continue;
            }
            wanted.put(
                SoftCreditService.automaticCreditKey(reversal.Id, creditedId),
                SoftCreditService.buildAutomaticCredit(
                    reversal.Id,
                    creditedId,
                    SoftCreditService.ROLE_MATCHED_DONOR,
                    reversedAmount,
                    reversal.Amount__c
                )
            );
        }
    }

    /**
     * The matched donor credits these links need and do not yet have, in one query however many
     * links are in front of it.
     */
    private static List<Soft_Credit__c> missingCreditsFor(
        Map<Id, Id> employeePersonByEmployerGift,
        Map<Id, Gift__c> giftById
    ) {
        List<Soft_Credit__c> credits = new List<Soft_Credit__c>();
        if (employeePersonByEmployerGift.isEmpty()) {
            return credits;
        }
        Set<String> alreadyCredited = new Set<String>();
        for (
            Soft_Credit__c existing : SoftCreditSelector.selectAutomaticForGifts(
                employeePersonByEmployerGift.keySet(),
                SoftCreditService.ROLE_MATCHED_DONOR
            )
        ) {
            Id creditedId = existing.Contact__c != null ? existing.Contact__c : existing.Account__c;
            alreadyCredited.add(
                String.valueOf(existing.Gift__c) + ':' + String.valueOf(creditedId)
            );
        }
        for (Id employerGiftId : employeePersonByEmployerGift.keySet()) {
            Id employeePersonId = employeePersonByEmployerGift.get(employerGiftId);
            Gift__c employerGift = giftById.get(employerGiftId);
            if (employeePersonId == null || employerGift == null) {
                continue;
            }
            if (
                alreadyCredited.contains(
                    String.valueOf(employerGiftId) + ':' + String.valueOf(employeePersonId)
                )
            ) {
                continue;
            }
            credits.add(
                SoftCreditService.buildAutomaticCredit(
                    employerGiftId,
                    employeePersonId,
                    SoftCreditService.ROLE_MATCHED_DONOR,
                    employerGift.Amount__c,
                    employerGift.Amount__c
                )
            );
        }
        return credits;
    }

    /**
     * The reason this pair may not be linked, or null when it may. The employer's gift is
     * assumed to have been identified already.
     */
    private static String problemWith(Gift__c employerGift, Gift__c employeeGift) {
        if (employerGift.Id == employeeGift.Id) {
            return Label.Giving_MatchingGift_SameGift;
        }
        if (isOrganizationGift(employeeGift) || donorPersonOf(employeeGift) == null) {
            return Label.Giving_MatchingGift_EmployeeMustBePerson;
        }
        if (
            linkedElsewhere(employeeGift, employerGift.Id) ||
            linkedElsewhere(employerGift, employeeGift.Id)
        ) {
            return Label.Giving_MatchingGift_AlreadyLinked;
        }
        if (isClosedOut(employerGift) || isClosedOut(employeeGift)) {
            return Label.Giving_MatchingGift_GiftNotReceived;
        }
        Id statedEmployerId = employerOf(employeeGift);
        if (statedEmployerId != null && statedEmployerId != employerGift.Donor_Account__c) {
            return Label.Giving_MatchingGift_EmployerMismatch;
        }
        return null;
    }

    /**
     * A gift that has been refunded, written off or cancelled is not money the organization has, so it is
     * not half of a new matching gift pair. The refund is recorded on the gift itself rather than
     * by deleting it, so without this the link would outlive the money (R-G11, R-SC5).
     *
     * This refuses a link being made, not a refund of a gift already linked: an existing link
     * survives the refund and `syncReversalCredits` reverses the credit instead (ADR-0031).
     */
    private static Boolean isClosedOut(Gift__c gift) {
        return gift != null &&
            (SoftCreditService.STATUS_REFUNDED.equals(gift.Status__c) ||
            SoftCreditService.STATUS_WRITTEN_OFF.equals(gift.Status__c) ||
            SoftCreditService.STATUS_CANCELLED.equals(gift.Status__c));
    }

    private static void insertCredits(List<Soft_Credit__c> credits) {
        if (credits != null && !credits.isEmpty()) {
            Database.insert(credits, true, AccessLevel.USER_MODE);
        }
    }

    private static void removeMatchedDonorCredits(Set<Id> giftIds) {
        List<Soft_Credit__c> toDelete = SoftCreditSelector.selectAutomaticForGifts(
            giftIds,
            SoftCreditService.ROLE_MATCHED_DONOR
        );
        if (!toDelete.isEmpty()) {
            Database.delete(toDelete, true, AccessLevel.USER_MODE);
        }
    }

    private static Map<Id, Gift__c> giftsById(Set<Id> giftIds) {
        return new Map<Id, Gift__c>(GiftLookupSelector.selectForMatching(giftIds));
    }

    /** A gift whose donor account is of the record type the org chose for organizations. */
    private static Boolean isOrganizationGift(Gift__c gift) {
        return gift != null &&
            gift.Donor_Account__c != null &&
            gift.Donor_Account__r != null &&
            AccountKinds.isOrganizationRecordTypeName(
                gift.Donor_Account__r.RecordType?.DeveloperName
            );
    }

    private static Boolean linkedElsewhere(Gift__c gift, Id intendedPartnerId) {
        return gift.Matched_Gift__c != null && gift.Matched_Gift__c != intendedPartnerId;
    }

    private static Id donorPersonOf(Gift__c gift) {
        return gift.Donor_Contact__c != null ? gift.Donor_Contact__c : gift.Donor_Account__c;
    }

    private static Id employerOf(Gift__c gift) {
        if (gift.Donor_Contact__c != null && gift.Donor_Contact__r != null) {
            return gift.Donor_Contact__r.Employer__c;
        }
        if (gift.Donor_Account__c != null && gift.Donor_Account__r != null) {
            return gift.Donor_Account__r.Employer__c;
        }
        return null;
    }
}
