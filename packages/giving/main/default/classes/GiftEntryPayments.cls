/**
 * Which scheduled payment a gift typed on a gift entry screen pays (canonical model R-DM8,
 * ADR-NEXT `NEXT-gift-entry-pays-a-scheduled-payment.md`).
 *
 * The candidates are donation matching's (R-DM2) and the suggestion is its window and
 * tolerance (R-DM3, through `DonationMatcher.matching`), so a gift typed on a screen and the
 * same gift imported look alike to the same payments. Unlike an import, nothing is decided
 * here: a payment is chosen in advance only when it is the only one suggested, the screen shows
 * it, and the person may change it. The choice is checked again when the gift is saved.
 *
 * Bulk by request: a gift batch asks for every line in one call, one query for all of them.
 */
public with sharing class GiftEntryPayments {
    @TestVisible
    private static final Integer MAXIMUM_CANDIDATES = 5000;
    /** How many payments one gift's list shows, besides the suggested ones, earliest due first. */
    @TestVisible
    private static final Integer MAXIMUM_CHOICES = 50;

    /** One gift being typed: who gave, when and how much. The key is the caller's. */
    public class Request {
        public String key;
        public Id donorContactId;
        public Id donorAccountId;
        public Date giftDate;
        public Decimal amount;

        public Request(
            String key,
            Id donorContactId,
            Id donorAccountId,
            Date giftDate,
            Decimal amount
        ) {
            this.key = key;
            this.donorContactId = donorContactId;
            this.donorAccountId = donorAccountId;
            this.giftDate = giftDate;
            this.amount = amount;
        }

        private Boolean hasDonor() {
            return this.donorContactId != null || this.donorAccountId != null;
        }
    }

    /** One payment a gift can pay, as a list shows it. */
    public class Choice {
        @AuraEnabled
        public String value;
        @AuraEnabled
        public String label;
        @AuraEnabled
        public Boolean suggested = false;
    }

    /** The payments one gift can pay, and the one chosen in advance, if any. */
    public class Choices {
        @AuraEnabled
        public String key;
        @AuraEnabled
        public List<Choice> choices = new List<Choice>();
        /** The payment chosen in advance: set only when exactly one is suggested. */
        @AuraEnabled
        public String suggestedId;
        @AuraEnabled
        public Integer suggestedCount = 0;
    }

    /** For each request, the payments its donor still owes, with the suggestion marked. */
    public static Map<String, Choices> forRequests(List<Request> requests) {
        Map<String, Choices> result = new Map<String, Choices>();
        Map<String, Id> households = householdsOf(requests);
        List<Installment__c> candidates = openFor(requests, households);
        DonationMatcher matcher = new DonationMatcher((Import_Template__c) null);
        Map<String, String> typeLabels = commitmentTypeLabels();
        Map<Id, Set<Integer>> positionsByOwner = positionsByOwner(candidates);
        for (Request request : requests) {
            List<Installment__c> own = new List<Installment__c>();
            for (Integer position : positionsOf(request, households, positionsByOwner)) {
                own.add(candidates[position]);
            }
            Set<Id> suggested = new Map<Id, Installment__c>(
                    matcher.matching(request.giftDate, request.amount, own)
                )
                .keySet();
            Choices choices = new Choices();
            choices.key = request.key;
            choices.suggestedCount = suggested.size();
            if (suggested.size() == 1) {
                choices.suggestedId = new List<Id>(suggested)[0];
            }
            for (Installment__c candidate : own) {
                Boolean isSuggested = suggested.contains(candidate.Id);
                if (choices.choices.size() < MAXIMUM_CHOICES || isSuggested) {
                    choices.choices.add(choiceFor(candidate, isSuggested, typeLabels));
                }
            }
            result.put(request.key, choices);
        }
        return result;
    }

    /**
     * The choices that still stand: for each request key whose chosen payment is still owed and
     * is its donor's (R-DM2, read in the saving user's mode), that payment with its commitment.
     * A key missing from the result chose a payment it may not pay.
     */
    public static Map<String, Installment__c> confirm(
        List<Request> requests,
        Map<String, Id> chosenByKey
    ) {
        Map<String, Installment__c> confirmed = new Map<String, Installment__c>();
        Set<Id> chosenIds = new Set<Id>(chosenByKey.values());
        chosenIds.remove(null);
        if (chosenIds.isEmpty()) {
            return confirmed;
        }
        Map<Id, Installment__c> open = new Map<Id, Installment__c>(
            new InstallmentSelector().selectOpenByIds(chosenIds)
        );
        Map<String, Id> households = householdsOf(requests);
        for (Request request : requests) {
            Installment__c chosen = open.get(chosenByKey.get(request.key));
            if (chosen != null && belongsTo(chosen, request, households.get(request.key))) {
                confirmed.put(request.key, chosen);
            }
        }
        return confirmed;
    }

    /**
     * Each request's household, derived exactly as the gift will derive it (R-G2), by asking
     * the Giving domain about an unsaved gift with the same donor.
     */
    private static Map<String, Id> householdsOf(List<Request> requests) {
        List<Gift__c> probes = new List<Gift__c>();
        for (Request request : requests) {
            probes.add(
                new Gift__c(
                    Donor_Contact__c = request.donorContactId,
                    Donor_Account__c = request.donorContactId == null
                        ? request.donorAccountId
                        : null
                )
            );
        }
        GiftService.deriveHouseholds(probes);
        Map<String, Id> households = new Map<String, Id>();
        for (Integer index = 0; index < requests.size(); index++) {
            households.put(requests[index].key, probes[index].Household__c);
        }
        return households;
    }

    private static List<Installment__c> openFor(
        List<Request> requests,
        Map<String, Id> households
    ) {
        Set<Id> donorIds = new Set<Id>();
        for (Request request : requests) {
            if (request.hasDonor()) {
                donorIds.add(request.donorContactId);
                donorIds.add(request.donorAccountId);
            }
        }
        donorIds.remove(null);
        Set<Id> householdIds = new Set<Id>(households.values());
        householdIds.remove(null);
        if (donorIds.isEmpty() && householdIds.isEmpty()) {
            return new List<Installment__c>();
        }
        return new InstallmentSelector()
            .selectOpenForDonors(donorIds, householdIds, MAXIMUM_CANDIDATES);
    }

    /**
     * Where each candidate sits in the query's order, by each donor and household it is owed
     * by, so a batch of many gifts finds its own candidates without reading every one.
     */
    private static Map<Id, Set<Integer>> positionsByOwner(List<Installment__c> candidates) {
        Map<Id, Set<Integer>> positions = new Map<Id, Set<Integer>>();
        for (Integer index = 0; index < candidates.size(); index++) {
            Commitment__c commitment = candidates[index].Commitment__r;
            for (
                Id owner : new List<Id>{
                    commitment.Donor_Contact__c,
                    commitment.Donor_Account__c,
                    commitment.Household__c
                }
            ) {
                if (owner == null) {
                    continue;
                }
                if (!positions.containsKey(owner)) {
                    positions.put(owner, new Set<Integer>());
                }
                positions.get(owner).add(index);
            }
        }
        return positions;
    }

    /**
     * The positions of one request's candidates, earliest due first (the query's order). The
     * same R-DM2 test `belongsTo` makes: the donor's own, or the donor's household's.
     */
    private static List<Integer> positionsOf(
        Request request,
        Map<String, Id> households,
        Map<Id, Set<Integer>> positionsByOwner
    ) {
        Set<Integer> found = new Set<Integer>();
        for (
            Id owner : new List<Id>{
                request.donorContactId,
                request.donorAccountId,
                households.get(request.key)
            }
        ) {
            if (owner != null && positionsByOwner.containsKey(owner)) {
                found.addAll(positionsByOwner.get(owner));
            }
        }
        List<Integer> ordered = new List<Integer>(found);
        ordered.sort();
        return ordered;
    }

    /** R-DM2: the commitment's donor is the gift's donor, or its household is the donor's. */
    private static Boolean belongsTo(Installment__c candidate, Request request, Id household) {
        Commitment__c commitment = candidate.Commitment__r;
        if (commitment == null || !request.hasDonor()) {
            return false;
        }
        return (request.donorContactId != null &&
            commitment.Donor_Contact__c == request.donorContactId) ||
            (request.donorAccountId != null &&
            commitment.Donor_Account__c == request.donorAccountId) ||
            (household != null &&
            commitment.Household__c == household);
    }

    private static Choice choiceFor(
        Installment__c candidate,
        Boolean suggested,
        Map<String, String> typeLabels
    ) {
        Commitment__c commitment = candidate.Commitment__r;
        String type = typeLabels.get(commitment.Type__c);
        String commitmentName = String.isBlank(type)
            ? commitment.Name
            : type + ' ' + commitment.Name;
        String described = Label.Giving_GiftEntryPays_Choice
            .replace('{0}', commitmentName)
            .replace(
                '{1}',
                candidate.Sequence__c == null
                    ? ''
                    : String.valueOf(candidate.Sequence__c.intValue())
            )
            .replace('{2}', candidate.Due_Date__c == null ? '' : candidate.Due_Date__c.format())
            .replace(
                '{3}',
                candidate.Expected_Amount__c == null
                    ? ''
                    : String.valueOf(candidate.Expected_Amount__c.setScale(2))
            );
        Choice choice = new Choice();
        choice.value = candidate.Id;
        choice.suggested = suggested;
        choice.label = suggested
            ? Label.Giving_GiftEntryPays_SuggestedChoice.replace('{0}', described)
            : described;
        return choice;
    }

    private static Map<String, String> commitmentTypeLabels() {
        Map<String, String> labels = new Map<String, String>();
        for (Schema.PicklistEntry entry : Commitment__c.Type__c.getDescribe().getPicklistValues()) {
            labels.put(entry.getValue(), entry.getLabel());
        }
        return labels;
    }
}
