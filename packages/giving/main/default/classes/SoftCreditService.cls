/**
 * Soft credits: the recognition a person or an organization gets for a gift they did not give
 * (feature G-08, canonical model Section 24).
 *
 * The one piece of automation here is the household credit. When a gift arrives from a person,
 * every other current member of that person's household is recognized for the whole of it. Full
 * amount, not a share: recognition is not divided, because both people are being recognized for
 * the same gift, which is the convention nonprofits and NPSP have always used. The admin guide
 * says so in the same words, because it surprises people who expect the numbers to add up.
 *
 * Three properties matter more than anything else here:
 *
 *   - **Idempotent.** Recomputing a gift's automatic credits twice leaves the same records. The
 *     method works out what should exist, compares it with what does, and inserts, updates, or
 *     deletes the difference.
 *   - **Manual credits are untouchable.** Only records with Is Automatic true are ever read for
 *     comparison, changed, or removed. A credit David entered is his (R-SC6).
 *   - **Negative gifts produce negative credits.** A refund is a gift with a negative amount, so
 *     its automatic credits are negative too and recognition totals correct themselves the same
 *     way giving totals do (R-SC5). That is the only reversal: the gift being refunded keeps the
 *     credits it earned, so a fully refunded gift leaves a visible pair that nets to zero rather
 *     than nothing at all (ADR-0023).
 */
public with sharing class SoftCreditService {
    public static final String ROLE_HOUSEHOLD_MEMBER = 'Household Member';
    public static final String ROLE_MATCHED_DONOR = 'Matched Donor';
    public static final String STATUS_REFUNDED = 'Refunded';
    public static final String STATUS_WRITTEN_OFF = 'Written off';
    public static final String STATUS_CANCELLED = 'Cancelled';

    private static final String SETTINGS_OBJECT = 'Giving_Settings__c';
    private static final String SETTING_AUTOMATIC_HOUSEHOLD_CREDITS = 'Automatic_Household_Soft_Credits__c';
    private static final Integer PERCENT_SCALE = 2;

    /**
     * How many gifts of one household a membership change recomputes in one job.
     *
     * The number that matters is not gifts but the soft credit rows they imply: one household of
     * ten people means nine credits per gift, and the transaction limit is ten thousand rows.
     * Five hundred gifts leaves headroom for a household larger than any real one. Recognition on
     * a household that has given more than that is corrected by the next save of the gift itself,
     * which is the same path every other correction takes.
     */
    public static final Integer GIFTS_PER_HOUSEHOLD_CAP = 500;

    /**
     * Whether this org wants household members credited automatically. Default on, and a missing
     * or unreadable setting is treated as on, because that is what the package ships with.
     */
    public static Boolean automaticHouseholdCreditsEnabled() {
        Object stored = SettingsService.getValue(
            SETTINGS_OBJECT,
            SETTING_AUTOMATIC_HOUSEHOLD_CREDITS
        );
        if (stored == null) {
            return true;
        }
        if (stored instanceof Boolean) {
            return (Boolean) stored;
        }
        return Boolean.valueOf(String.valueOf(stored));
    }

    /**
     * Brings the automatic household member credits for these gifts into line with the gifts as
     * they now stand. Safe to call on insert, on update, and twice in a row.
     *
     * A gift whose donor is not a person in a household ends up with no automatic household
     * credits, which is how removal happens: nothing is special cased. A gift that has been
     * refunded or written off keeps its credits, because the negative gift recording the reversal
     * carries the negative credit that cancels them (ADR-0023).
     */
    public static void createHouseholdMemberCredits(List<Gift__c> gifts) {
        if (gifts == null || gifts.isEmpty()) {
            return;
        }
        // The setting off does not mean "do nothing": it means no household member is wanted, so
        // the reconcile below removes the credits an earlier setting created (R-SC3).
        Boolean wantCredits = automaticHouseholdCreditsEnabled();
        Map<Id, Gift__c> giftById = new Map<Id, Gift__c>();
        for (Gift__c gift : gifts) {
            if (gift != null && gift.Id != null) {
                giftById.put(gift.Id, gift);
            }
        }
        if (giftById.isEmpty()) {
            return;
        }

        Map<Id, Id> donorPersonByGift = new Map<Id, Id>();
        Set<Id> personIds = new Set<Id>();
        // Every gift earns recognition, a refunded or written off one included (ADR-0023). The
        // reversal is the negative gift's own negative credit, not the removal of this one:
        // doing both would take a fully refunded gift's recognition to minus its own amount
        // instead of to zero.
        for (Gift__c gift : giftById.values()) {
            if (wantCredits) {
                Id donorPersonId = donorPersonOf(gift);
                if (donorPersonId != null) {
                    donorPersonByGift.put(gift.Id, donorPersonId);
                    personIds.add(donorPersonId);
                }
            }
        }

        Map<Id, Set<Id>> membersByHousehold = new Map<Id, Set<Id>>();
        Map<Id, Id> householdByPerson = new Map<Id, Id>();
        if (!personIds.isEmpty()) {
            householdByPerson = HouseholdService.getHouseholdIdsFor(personIds);
            Set<Id> householdIds = new Set<Id>();
            for (Id householdId : householdByPerson.values()) {
                if (householdId != null) {
                    householdIds.add(householdId);
                }
            }
            if (!householdIds.isEmpty()) {
                membersByHousehold = HouseholdService.getMemberPersonIds(householdIds);
            }
        }

        Map<String, Soft_Credit__c> wanted = new Map<String, Soft_Credit__c>();
        for (Id giftId : donorPersonByGift.keySet()) {
            Id donorPersonId = donorPersonByGift.get(giftId);
            Id householdId = householdByPerson.get(donorPersonId);
            if (householdId == null) {
                continue;
            }
            Set<Id> memberIds = membersByHousehold.get(householdId);
            if (memberIds == null) {
                continue;
            }
            Gift__c gift = giftById.get(giftId);
            for (Id memberId : memberIds) {
                if (memberId == null || memberId == donorPersonId) {
                    continue;
                }
                wanted.put(
                    key(giftId, memberId),
                    build(giftId, memberId, ROLE_HOUSEHOLD_MEMBER, gift.Amount__c, gift.Amount__c)
                );
            }
        }

        reconcileAutomaticCredits(
            wanted,
            SoftCreditSelector.selectAutomaticForGifts(giftById.keySet(), ROLE_HOUSEHOLD_MEMBER)
        );
    }

    /**
     * Removes every credit BarnCRM created for these gifts, and leaves alone every credit a
     * person entered by hand (R-SC6).
     *
     * One caller: `GiftSoftCreditHandler.beforeDelete`. This docstring used to claim the matching
     * gift service calls it too when a link is undone; it does not, and never has.
     * `MatchingGiftService` has its own private `removeMatchedDonorCredits`, which deletes only
     * the Matched Donor rows. Whether the two should share this method is a real question and a
     * separate one.
     *
     * At its one call site the platform would delete these rows anyway, because `Gift__c` on
     * `Soft_Credit__c` is a master detail field and the cascade removes the children. The call
     * still earns its place by running `before` the delete, so anything reading credits in the
     * same transaction sees them gone rather than half gone. That is a narrower claim than the
     * old comment made, and it is the one the tests now prove.
     */
    public static void removeAutomaticCredits(Set<Id> giftIds) {
        if (giftIds == null || giftIds.isEmpty()) {
            return;
        }
        List<Soft_Credit__c> existing = SoftCreditSelector.selectAutomaticForGifts(giftIds);
        if (!existing.isEmpty()) {
            Database.delete(existing, true, AccessLevel.USER_MODE);
        }
    }

    /**
     * Recomputes the automatic household credits on every gift belonging to these households,
     * which is what a change of household membership makes necessary (R-SC3): the person who
     * joined has to be credited on the gifts already recorded, and the person who left has to
     * stop being credited on them.
     *
     * A household's gift history is unbounded, so this is deliberately capped and deliberately
     * asynchronous: `HouseholdSoftCreditRecompute` calls it one chunk of gifts at a time. A
     * household with more gifts than `GIFTS_PER_HOUSEHOLD_CAP` has the most recent that many
     * recomputed and the overflow reported to the Error Log, because silently doing part of the
     * job is worse than saying which part was left.
     */
    public static void recomputeForHouseholds(Set<Id> householdIds) {
        if (householdIds == null || householdIds.isEmpty()) {
            return;
        }
        List<Gift__c> gifts = GiftLookupSelector.selectForHouseholds(
            householdIds,
            GIFTS_PER_HOUSEHOLD_CAP * householdIds.size()
        );
        if (gifts.isEmpty()) {
            return;
        }
        createHouseholdMemberCredits(gifts);
    }

    /**
     * The recognition one person gets on one gift, as a record ready to insert. Used by the
     * matching gift service, which credits an employee on their employer's gift.
     */
    public static Soft_Credit__c buildAutomaticCredit(
        Id giftId,
        Id personId,
        String role,
        Decimal amount,
        Decimal giftAmount
    ) {
        return build(giftId, personId, role, amount, giftAmount);
    }

    /**
     * A credited amount as a share of the gift. A gift of nothing has no share, which is not an
     * error: an in-kind gift recorded at zero still recognizes the household.
     */
    public static Decimal percentOf(Decimal amount, Decimal giftAmount) {
        if (amount == null || giftAmount == null || giftAmount == 0) {
            return null;
        }
        return (amount / giftAmount * 100).setScale(PERCENT_SCALE, System.RoundingMode.HALF_UP);
    }

    /**
     * The amount a share of a gift comes to.
     */
    public static Decimal amountOf(Decimal percent, Decimal giftAmount) {
        if (percent == null || giftAmount == null) {
            return null;
        }
        return (giftAmount * percent / 100).setScale(2, System.RoundingMode.HALF_UP);
    }

    /**
     * Makes the automatic credits that exist for a set of gifts equal to the ones wanted:
     * inserting what is missing, correcting an amount that has moved, and deleting what is no
     * longer wanted, all keyed by gift and credited party.
     *
     * Public because `MatchingGiftService` reconciles the negative Matched Donor credits a
     * refund of an employer's gift produces (ADR-0031), and that is the same job as this one on
     * a different role. The two callers pass disjoint roles, so each one's existing list is its
     * own: passing credits of one role against wanted credits of another would delete them.
     */
    public static void reconcileAutomaticCredits(
        Map<String, Soft_Credit__c> wanted,
        List<Soft_Credit__c> existing
    ) {
        List<Soft_Credit__c> toUpdate = new List<Soft_Credit__c>();
        List<Soft_Credit__c> toDelete = new List<Soft_Credit__c>();
        Set<String> seen = new Set<String>();

        for (Soft_Credit__c credit : existing) {
            Id creditedPersonId = credit.Contact__c != null ? credit.Contact__c : credit.Account__c;
            String creditKey = key(credit.Gift__c, creditedPersonId);
            Soft_Credit__c target = wanted.get(creditKey);
            if (target == null || seen.contains(creditKey)) {
                // No longer wanted, or a duplicate of one already kept (R-SC7).
                toDelete.add(credit);
                continue;
            }
            seen.add(creditKey);
            if (credit.Amount__c != target.Amount__c || credit.Percent__c != target.Percent__c) {
                // Only the fields being changed: a user mode update of the row as read would
                // also carry the master detail to the gift, which nobody may edit.
                toUpdate.add(
                    new Soft_Credit__c(
                        Id = credit.Id,
                        Amount__c = target.Amount__c,
                        Percent__c = target.Percent__c
                    )
                );
            }
        }

        List<Soft_Credit__c> toInsert = new List<Soft_Credit__c>();
        for (String creditKey : wanted.keySet()) {
            if (!seen.contains(creditKey)) {
                toInsert.add(wanted.get(creditKey));
            }
        }

        if (!toDelete.isEmpty()) {
            Database.delete(toDelete, true, AccessLevel.USER_MODE);
        }
        if (!toUpdate.isEmpty()) {
            Database.update(toUpdate, true, AccessLevel.USER_MODE);
        }
        if (!toInsert.isEmpty()) {
            Database.insert(toInsert, true, AccessLevel.USER_MODE);
        }
    }

    private static Soft_Credit__c build(
        Id giftId,
        Id personId,
        String role,
        Decimal amount,
        Decimal giftAmount
    ) {
        Soft_Credit__c credit = new Soft_Credit__c(
            Gift__c = giftId,
            Role__c = role,
            Amount__c = amount,
            Percent__c = percentOf(amount, giftAmount),
            Is_Automatic__c = true
        );
        if (personId != null && personId.getSObjectType() == Contact.SObjectType) {
            credit.Contact__c = personId;
        } else {
            credit.Account__c = personId;
        }
        return credit;
    }

    /**
     * The key `reconcileAutomaticCredits` compares on: one credited party, on one gift, in one
     * role. Exposed for the callers that build a wanted map of their own. Named for the map
     * rather than for the row, because `reconcileAutomaticCredits` already uses `creditKey` as a
     * local.
     */
    public static String automaticCreditKey(Id giftId, Id personId) {
        return key(giftId, personId);
    }

    private static Id donorPersonOf(Gift__c gift) {
        return gift.Donor_Contact__c != null ? gift.Donor_Contact__c : gift.Donor_Account__c;
    }

    private static String key(Id giftId, Id personId) {
        return String.valueOf(giftId) + ':' + String.valueOf(personId);
    }
}
