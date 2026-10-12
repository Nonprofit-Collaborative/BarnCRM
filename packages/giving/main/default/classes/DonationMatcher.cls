/**
 * Donation matching (feature G-24, canonical model R-DM1 to R-DM6): an imported gift that pays
 * a scheduled payment the donor already owes is linked to it, so the payment's status and the
 * pledge's paid to date and balance follow through the ordinary gift triggers and rollups.
 *
 * Matching by external ID, which comes first (R-DM1), is the processor's; this class looks
 * for the open installment, and applies the template's behaviour to both.
 */
public with sharing class DonationMatcher {
    public static final String MATCH_OR_CREATE = 'Match or create';
    public static final String ALWAYS_CREATE = 'Always create';
    public static final String MATCH_ONLY = 'Match only';
    public static final String NEVER_MATCH = 'Never match';

    @TestVisible
    private static final Integer DEFAULT_WINDOW_DAYS = 7;
    @TestVisible
    private static final Decimal DEFAULT_TOLERANCE = 0;

    private static final String SETTINGS_OBJECT = 'Giving_Settings__c';
    private static final String KEY_WINDOW = 'Donation_Match_Date_Window_Days__c';
    private static final String KEY_TOLERANCE = 'Donation_Match_Amount_Tolerance__c';

    private static final String RECORD_BEHAVIOUR = 'donationMatching';
    private static final String RECORD_WINDOW = 'matchDateWindowDays';
    private static final String RECORD_TOLERANCE = 'matchAmountTolerance';
    private static final Set<String> BEHAVIOURS = new Set<String>{
        MATCH_OR_CREATE,
        ALWAYS_CREATE,
        MATCH_ONLY,
        NEVER_MATCH
    };

    private final String behaviour;
    private final Integer windowDays;
    private final Decimal tolerance;

    /** How this template's gifts are matched: its own values, else the org's, else the defaults. */
    public DonationMatcher(Import_Template__c template) {
        String chosen = template == null ? null : template.Payment_Matching__c;
        behaviour = String.isBlank(chosen) ? MATCH_OR_CREATE : chosen;
        Decimal days = template == null ? null : template.Match_Date_Window_Days__c;
        days = days != null ? days : setting(KEY_WINDOW);
        windowDays = days == null || days < 0 ? DEFAULT_WINDOW_DAYS : days.intValue();
        Decimal allowed = template == null ? null : template.Match_Amount_Tolerance__c;
        allowed = allowed != null ? allowed : setting(KEY_TOLERANCE);
        tolerance = allowed == null || allowed < 0 ? DEFAULT_TOLERANCE : allowed;
    }

    private DonationMatcher(String behaviour, Integer windowDays, Decimal tolerance) {
        this.behaviour = behaviour;
        this.windowDays = windowDays;
        this.tolerance = tolerance;
    }

    /**
     * How one pass of an import matches (R-DM7). A dry run takes the template's values, and
     * the org's where the template is empty, on its first chunk and carries them to the rest;
     * a commit runs under the values its dry run recorded on the batch, never the template's
     * as they stand now. A batch whose dry run recorded none, which is every batch dry run
     * before the values were recorded, falls back to the template.
     */
    public static DonationMatcher forRun(
        Import_Batch__c batch,
        Import_Template__c template,
        Boolean dryRun
    ) {
        if (dryRun == true) {
            DonationMatcher taken = fromRecord(GiftImportRunState.carriedSettings());
            if (taken == null) {
                // The first chunk: the only time the whole state is read to add the values.
                taken = new DonationMatcher(template);
                GiftImportRunState state = GiftImportRunState.carried();
                state.settings = taken.record();
                state.carry();
            }
            return taken;
        }
        DonationMatcher recorded = fromRecord(
            batch == null ? null : batch.Processor_Settings_JSON__c
        );
        return recorded == null ? new DonationMatcher(template) : recorded;
    }

    /** The values this matcher runs under, as the document the batch keeps (R-DM7). */
    public String record() {
        return JSON.serialize(
            new Map<String, Object>{
                RECORD_BEHAVIOUR => behaviour,
                RECORD_WINDOW => windowDays,
                RECORD_TOLERANCE => tolerance
            }
        );
    }

    /** The matcher a recorded document describes, or null when it describes none. */
    @TestVisible
    private static DonationMatcher fromRecord(String recorded) {
        if (String.isBlank(recorded)) {
            return null;
        }
        try {
            Map<String, Object> values = (Map<String, Object>) JSON.deserializeUntyped(recorded);
            String chosen = (String) values.get(RECORD_BEHAVIOUR);
            Object days = values.get(RECORD_WINDOW);
            Object allowed = values.get(RECORD_TOLERANCE);
            if (!BEHAVIOURS.contains(chosen) || days == null || allowed == null) {
                return null;
            }
            Integer window = Decimal.valueOf(String.valueOf(days)).intValue();
            Decimal within = Decimal.valueOf(String.valueOf(allowed));
            return window < 0 || within < 0 ? null : new DonationMatcher(chosen, window, within);
        } catch (Exception unreadable) {
            return null;
        }
    }

    private static Decimal setting(String key) {
        Object value = SettingsService.getValue(SETTINGS_OBJECT, key);
        if (value == null) {
            return null;
        }
        try {
            return Decimal.valueOf(String.valueOf(value));
        } catch (Exception unreadable) {
            return null;
        }
    }

    /**
     * Under Never match, a row whose external ID names a gift that was there before the run is
     * refused rather than matched (R-DM5). A repeat of an earlier row of the run is not.
     */
    public void refuseExistingUnderNeverMatch(List<GiftImportRow> gifts) {
        if (behaviour != NEVER_MATCH) {
            return;
        }
        for (GiftImportRow item : gifts) {
            if (
                item.error == null &&
                item.matchedExisting &&
                item.sameAs == null &&
                !item.repeatsEarlierChunk
            ) {
                item.error = String.format(
                    Label.Giving_Import_ErrorExternalIdRepeated,
                    new List<String>{ item.externalId }
                );
            }
        }
    }

    /**
     * Finds each gift's open installment (R-DM2 to R-DM4) and applies the behaviour (R-DM5).
     * A payment an earlier row of this run claimed is not offered again. Returns how many
     * gifts were matched.
     */
    public Integer match(List<GiftImportRow> gifts) {
        if (behaviour == ALWAYS_CREATE) {
            return 0;
        }
        Set<Id> donorIds = new Set<Id>();
        Set<Id> householdIds = new Set<Id>();
        Date earliest;
        Date latest;
        for (GiftImportRow item : gifts) {
            if (item.error != null || item.matchedExisting) {
                continue;
            }
            donorIds.add(item.donorContactId);
            donorIds.add(item.donorAccountId);
            householdIds.add(householdOf(item));
            Date low = item.giftDate.addDays(-windowDays);
            Date high = item.giftDate.addDays(windowDays);
            earliest = earliest == null || low < earliest ? low : earliest;
            latest = latest == null || high > latest ? high : latest;
        }
        donorIds.remove(null);
        householdIds.remove(null);
        List<Installment__c> candidates = donorIds.isEmpty() && householdIds.isEmpty()
            ? new List<Installment__c>()
            : GiftImportSelector.selectOpenInstallments(donorIds, householdIds, earliest, latest);

        Set<Id> claimed = claimedEarlier();
        Integer matched = 0;
        for (GiftImportRow item : gifts) {
            if (item.error != null || item.matchedExisting) {
                continue;
            }
            List<Installment__c> closest = closest(item, candidates, claimed);
            if (closest.size() > 1) {
                item.error = String.format(
                    Label.Giving_Import_ErrorMatchTie,
                    new List<String>{ describe(closest[0]), describe(closest[1]) }
                );
            } else if (closest.size() == 1 && behaviour == NEVER_MATCH) {
                item.error = String.format(
                    Label.Giving_Import_ErrorNeverMatchInstallment,
                    new List<String>{ describe(closest[0]) }
                );
            } else if (closest.size() == 1) {
                item.installmentId = closest[0].Id;
                item.commitmentId = closest[0].Commitment__c;
                claimed.add(closest[0].Id);
                matched++;
            } else if (behaviour == MATCH_ONLY) {
                item.error = Label.Giving_Import_ErrorMatchOnlyNone;
            }
        }
        return matched;
    }

    /**
     * The scheduled payments earlier chunks of this run matched (R-DM4), so a dry run reports
     * what the commit will do rather than offering one payment to a row in every chunk.
     */
    private static Set<Id> claimedEarlier() {
        return GiftImportRunState.carried().claimedInstallments;
    }

    /**
     * Adds the payments this chunk's gifts pay, once each row's outcome is final, to what the
     * next chunk is told was claimed. Returns how many of this chunk's gifts pay one, for the
     * run log.
     */
    public Integer carryClaims(List<GiftImportRow> gifts) {
        GiftImportRunState state = GiftImportRunState.carried();
        Integer paying = 0;
        for (GiftImportRow item : gifts) {
            if (item.error == null && !item.matchedExisting && item.installmentId != null) {
                state.claimedInstallments.add(item.installmentId);
                paying++;
            }
        }
        state.carry();
        return paying;
    }

    /**
     * The donor's household: the row's household when the donor is its first person or the
     * household itself; an organization donor has none.
     */
    private static Id householdOf(GiftImportRow item) {
        Import_Row__c row = item.row;
        Boolean person =
            item.donorContactId != null ||
            (item.donorAccountId != null &&
            (item.donorAccountId == row.Person_1_Account__c ||
            item.donorAccountId == row.Household__c));
        return person ? row.Household__c : null;
    }

    /** The unclaimed candidates of this donor at the smallest distance in days, in a list. */
    private List<Installment__c> closest(
        GiftImportRow item,
        List<Installment__c> candidates,
        Set<Id> claimed
    ) {
        Id household = householdOf(item);
        List<Installment__c> best = new List<Installment__c>();
        Integer bestDistance;
        for (Installment__c candidate : candidates) {
            Commitment__c commitment = candidate.Commitment__r;
            Boolean sameDonor =
                (item.donorContactId != null &&
                commitment.Donor_Contact__c == item.donorContactId) ||
                (item.donorAccountId != null &&
                commitment.Donor_Account__c == item.donorAccountId) ||
                (household != null &&
                commitment.Household__c == household);
            if (
                !sameDonor ||
                claimed.contains(candidate.Id) ||
                candidate.Due_Date__c == null ||
                candidate.Expected_Amount__c == null
            ) {
                continue;
            }
            Integer distance = Math.abs(item.giftDate.daysBetween(candidate.Due_Date__c));
            if (
                distance > windowDays ||
                (candidate.Expected_Amount__c - item.amount).abs() > tolerance
            ) {
                continue;
            }
            if (bestDistance == null || distance < bestDistance) {
                best = new List<Installment__c>{ candidate };
                bestDistance = distance;
            } else if (distance == bestDistance) {
                best.add(candidate);
            }
        }
        return best;
    }

    private static String describe(Installment__c installment) {
        return installment.Name + ' (' + installment.Due_Date__c.format() + ')';
    }
}
