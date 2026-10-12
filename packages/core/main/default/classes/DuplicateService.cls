/**
 * Duplicate suggestions: asking the platform what it thinks, and remembering what a person
 * decided about the answer (C-20, canonical model Section 29A, ADR-0050).
 *
 * Nothing in this class compares two records. The comparison is the platform's: the org's own
 * active duplicate rules decide what counts as the same person or the same household, and
 * `Datacloud.FindDuplicatesByIds` runs those rules against records that already exist. That is
 * the gap BarnCRM fills, because a duplicate rule otherwise only runs when somebody saves a
 * record, and the platform job that runs rules over existing records exists only in the two
 * largest editions.
 *
 * The parts are separable so the part with a decision in it can be tested without depending
 * on how an org's rules are set: `pairsToRecord` is arithmetic on identifiers, `matchesFor` is
 * the one call into the matching engine, and `recordPairs` writes the platform's own duplicate
 * record sets.
 */
public with sharing class DuplicateService {
    /** How many records one call to the platform's matcher accepts. */
    public static final Integer MAX_RECORDS_PER_CALL = 50;

    private static final String SEPARATOR = '-';
    private static final String CONTEXT_MATCH = 'Duplicate scan: asking the platform for matches';
    private static final String CONTEXT_WRITE = 'Duplicate scan: recording a suggestion';

    /**
     * What the matcher answers in a test, in place of the platform's call. Which records an
     * org's rules call duplicates is the org's business, so a test that must assert exact
     * counts sets the answer here and asserts what the scan does with it.
     */
    @TestVisible
    private static List<Pair> stubMatches;

    /** In a test, the matcher fails as the platform's call can, so the failure path is exercised. */
    @TestVisible
    private static Boolean stubFails = false;

    /**
     * In a test, the check for pairs already dismissed is skipped, which is what a dismissal
     * racing another person's sees: the other dismissal lands between the check and the write.
     */
    @TestVisible
    private static Boolean skipDismissedCheck = false;

    /**
     * How many matcher calls and suggestion writes have failed in this transaction. A failure
     * is logged and answered with nothing so the scan carries on; the scan reads this to say
     * how many chunks it could not check, so a failed chunk never reads as a clean one.
     */
    public static Integer failureCount = 0;

    /** Raised with a message the page shows as it is. */
    public class DuplicateException extends Exception {
    }

    /** Two records the platform says are the same thing. */
    public class Pair {
        public Id left;
        public Id right;
        public String key;
        public String ruleName;

        public Pair(Id first, Id second, String ruleName) {
            Boolean firstLower = String.valueOf(first).compareTo(String.valueOf(second)) <= 0;
            this.left = firstLower ? first : second;
            this.right = firstLower ? second : first;
            this.key = pairKey(first, second);
            this.ruleName = ruleName;
        }
    }

    /**
     * The identifier a pair is remembered by: both record identifiers in ascending order, so A
     * with B and B with A are the same pair and are dismissed once.
     */
    public static String pairKey(Id first, Id second) {
        if (first == null || second == null) {
            return null;
        }
        String a = String.valueOf(first);
        String b = String.valueOf(second);
        return a.compareTo(b) <= 0 ? a + SEPARATOR + b : b + SEPARATOR + a;
    }

    /** Every pair that can be made out of the records in one suggestion. */
    public static Set<String> pairKeysAmong(List<Id> recordIds) {
        Set<String> keys = new Set<String>();
        if (recordIds == null) {
            return keys;
        }
        for (Integer i = 0; i < recordIds.size(); i++) {
            for (Integer j = i + 1; j < recordIds.size(); j++) {
                String key = pairKey(recordIds[i], recordIds[j]);
                if (key != null) {
                    keys.add(key);
                }
            }
        }
        return keys;
    }

    /**
     * The pairs worth writing down, out of what the matcher answered: a record matched to
     * itself is dropped, A with B and B with A fold into one, and anything already known (a
     * pair in a suggestion, a pair somebody dismissed) is passed over (R-DP3, R-DP5).
     */
    public static List<Pair> pairsToRecord(List<Pair> found, Set<String> known) {
        List<Pair> result = new List<Pair>();
        Set<String> seen = known == null ? new Set<String>() : new Set<String>(known);
        if (found == null) {
            return result;
        }
        for (Pair candidate : found) {
            if (
                candidate == null ||
                candidate.left == null ||
                candidate.right == null ||
                candidate.left == candidate.right ||
                seen.contains(candidate.key)
            ) {
                continue;
            }
            seen.add(candidate.key);
            result.add(candidate);
        }
        return result;
    }

    /**
     * What the org's active duplicate rules say about these records, which must all be of one
     * object. Only matches of that same object are kept: a rule for people can also name leads,
     * and a lead is nothing BarnCRM can merge.
     *
     * A failure is logged and answered with nothing rather than thrown. The platform raises when
     * an object has no active rule, and one chunk that cannot be matched is no reason to stop a
     * scan.
     */
    public static List<Pair> matchesFor(List<Id> recordIds) {
        List<Pair> found = new List<Pair>();
        if (recordIds == null || recordIds.isEmpty()) {
            return found;
        }
        Schema.SObjectType sourceType = recordIds[0].getSObjectType();
        if (stubMatches != null && !stubFails) {
            return stubbedMatchesFor(new Set<Id>(recordIds), sourceType);
        }
        try {
            if (stubFails) {
                throw new DuplicateException('Matcher failure simulated in a test.');
            }
            List<Datacloud.FindDuplicatesResult> results = Datacloud.FindDuplicatesByIds.findDuplicatesByIds(
                recordIds
            );
            for (Integer index = 0; index < results.size() && index < recordIds.size(); index++) {
                for (
                    Datacloud.DuplicateResult duplicateResult : results[index].getDuplicateResults()
                ) {
                    String ruleName = duplicateResult.getDuplicateRule();
                    for (Datacloud.MatchResult matchResult : duplicateResult.getMatchResults()) {
                        for (Datacloud.MatchRecord matched : matchResult.getMatchRecords()) {
                            SObject record = matched.getRecord();
                            if (
                                record != null &&
                                record.Id != null &&
                                record.Id.getSObjectType() == sourceType
                            ) {
                                found.add(new Pair(recordIds[index], record.Id, ruleName));
                            }
                        }
                    }
                }
            }
        } catch (Exception caught) {
            failureCount++;
            ErrorLogger.log(caught, CONTEXT_MATCH);
            return new List<Pair>();
        }
        return found;
    }

    /** The stubbed answer, as the platform would give it: only for the records asked about. */
    private static List<Pair> stubbedMatchesFor(Set<Id> asked, Schema.SObjectType sourceType) {
        List<Pair> found = new List<Pair>();
        for (Pair pair : stubMatches) {
            Boolean mentioned = asked.contains(pair.left) || asked.contains(pair.right);
            if (mentioned && pair.left.getSObjectType() == sourceType) {
                found.add(pair);
            }
        }
        return found;
    }

    /**
     * Only pairs BarnCRM can act on (R-DP2): a pair of accounts is kept only when both are
     * households. People pairs pass through untouched.
     */
    public static List<Pair> actionablePairs(List<Pair> pairs) {
        List<Pair> result = new List<Pair>();
        if (pairs == null || pairs.isEmpty()) {
            return result;
        }
        Set<Id> accountIds = new Set<Id>();
        for (Pair pair : pairs) {
            if (pair.left.getSObjectType() == Account.SObjectType) {
                accountIds.add(pair.left);
                accountIds.add(pair.right);
            }
        }
        Set<Id> households = accountIds.isEmpty()
            ? new Set<Id>()
            : DuplicateSelector.householdIds(accountIds);
        for (Pair pair : pairs) {
            Boolean isAccountPair = pair.left.getSObjectType() == Account.SObjectType;
            if (
                !isAccountPair ||
                (households.contains(pair.left) && households.contains(pair.right))
            ) {
                result.add(pair);
            }
        }
        return result;
    }

    /**
     * Writes each pair as a duplicate record set of two, which is where the platform keeps the
     * duplicates its own rules report, so the standard Duplicate Record Sets tab and any report
     * on it show the scan's findings too. Answers how many were written; a failure is logged and
     * the scan carries on.
     *
     * The platform requires every set to name the duplicate rule behind it. A pair carries the
     * name of the rule that matched it; when that name is not among the active rules, any active
     * rule for the pair's object stands in. A pair whose object has no active rule is not
     * written, because no rule of the org's could have found it (R-DP1).
     */
    public static Integer recordPairs(List<Pair> pairs, Map<String, Id> ruleIdsByName) {
        if (pairs == null || pairs.isEmpty()) {
            return 0;
        }
        Set<String> objectNames = new Set<String>();
        for (Pair pair : pairs) {
            objectNames.add(pair.left.getSObjectType().getDescribe().getName());
        }
        Map<String, Id> fallbackByObject = DuplicateSelector.activeRuleIdByObject(objectNames);
        List<Pair> writable = new List<Pair>();
        List<DuplicateRecordSet> sets = new List<DuplicateRecordSet>();
        for (Pair pair : pairs) {
            Id ruleId = ruleIdsByName == null ? null : ruleIdsByName.get(pair.ruleName);
            if (ruleId == null) {
                ruleId = fallbackByObject.get(pair.left.getSObjectType().getDescribe().getName());
            }
            if (ruleId == null) {
                continue;
            }
            writable.add(pair);
            sets.add(new DuplicateRecordSet(DuplicateRuleId = ruleId));
        }
        if (sets.isEmpty()) {
            return 0;
        }
        Savepoint beforeWrite = Database.setSavepoint();
        try {
            Database.insert(sets, AccessLevel.USER_MODE);
            List<DuplicateRecordItem> items = new List<DuplicateRecordItem>();
            for (Integer index = 0; index < writable.size(); index++) {
                items.add(
                    new DuplicateRecordItem(
                        DuplicateRecordSetId = sets[index].Id,
                        RecordId = writable[index].left
                    )
                );
                items.add(
                    new DuplicateRecordItem(
                        DuplicateRecordSetId = sets[index].Id,
                        RecordId = writable[index].right
                    )
                );
            }
            Database.insert(items, AccessLevel.USER_MODE);
            return sets.size();
        } catch (Exception caught) {
            Database.rollback(beforeWrite);
            failureCount++;
            ErrorLogger.log(caught, CONTEXT_WRITE);
            return 0;
        }
    }

    /** The pairs among these records that already sit in a suggestion nobody has closed. */
    public static Set<String> pairsAlreadySuggested(Set<Id> recordIds) {
        Set<String> known = new Set<String>();
        if (recordIds == null || recordIds.isEmpty()) {
            return known;
        }
        Set<Id> setIds = new Set<Id>();
        for (DuplicateRecordItem item : DuplicateSelector.itemsForRecords(recordIds)) {
            setIds.add(item.DuplicateRecordSetId);
        }
        Map<Id, List<Id>> recordsBySet = new Map<Id, List<Id>>();
        for (DuplicateRecordItem item : DuplicateSelector.itemsForSets(setIds)) {
            if (!recordsBySet.containsKey(item.DuplicateRecordSetId)) {
                recordsBySet.put(item.DuplicateRecordSetId, new List<Id>());
            }
            recordsBySet.get(item.DuplicateRecordSetId).add(item.RecordId);
        }
        for (List<Id> records : recordsBySet.values()) {
            known.addAll(pairKeysAmong(records));
        }
        return known;
    }

    /** The pairs left once the ones a person already dismissed are taken out (R-DP5). */
    public static List<Pair> withoutDismissed(List<Pair> pairs) {
        List<Pair> result = new List<Pair>();
        if (pairs == null || pairs.isEmpty()) {
            return result;
        }
        Set<String> keys = new Set<String>();
        for (Pair pair : pairs) {
            keys.add(pair.key);
        }
        Set<String> dismissed = DuplicateSelector.dismissedKeys(keys);
        for (Pair pair : pairs) {
            if (!dismissed.contains(pair.key)) {
                result.add(pair);
            }
        }
        return result;
    }

    /**
     * Records that the records in a suggestion are not duplicates of each other, and takes the
     * suggestion away (R-DP5). The dismissal is written first, so a failed delete rolls both
     * back together. Answers how many dismissals were written.
     *
     * Two people dismissing the same pair at once is the same decision made twice, not an
     * error: a pair somebody else has just remembered, or a suggestion somebody else has just
     * taken away, counts as done.
     */
    public static Integer dismiss(Id duplicateRecordSetId, String reason) {
        DuplicateRecordSet found = requireSet(duplicateRecordSetId);
        List<Id> records = new List<Id>();
        for (DuplicateRecordItem item : found.DuplicateRecordItems) {
            records.add(item.RecordId);
        }
        Set<String> keys = pairKeysAmong(records);
        if (!skipDismissedCheck) {
            keys.removeAll(DuplicateSelector.dismissedKeys(keys));
        }
        List<Duplicate_Dismissal__c> dismissals = new List<Duplicate_Dismissal__c>();
        String cleanReason = String.isBlank(reason) ? null : reason.trim().left(255);
        for (String key : keys) {
            dismissals.add(new Duplicate_Dismissal__c(Pair_Key__c = key, Reason__c = cleanReason));
        }
        Integer written = 0;
        Savepoint beforeWrite = Database.setSavepoint();
        try {
            if (!dismissals.isEmpty()) {
                for (
                    Database.SaveResult saved : Database.insert(
                        dismissals,
                        false,
                        AccessLevel.USER_MODE
                    )
                ) {
                    if (saved.isSuccess()) {
                        written++;
                    } else {
                        requireOnly(saved.getErrors(), StatusCode.DUPLICATE_VALUE);
                    }
                }
            }
            for (
                Database.DeleteResult deleted : Database.delete(
                    new List<DuplicateRecordSet>{ found },
                    false,
                    AccessLevel.USER_MODE
                )
            ) {
                if (!deleted.isSuccess()) {
                    requireOnly(deleted.getErrors(), StatusCode.ENTITY_IS_DELETED);
                }
            }
        } catch (Exception caught) {
            Database.rollback(beforeWrite);
            throw caught;
        }
        return written;
    }

    /** Throws unless every error is the one that means somebody else got there first. */
    private static void requireOnly(List<Database.Error> errors, StatusCode harmless) {
        for (Database.Error problem : errors) {
            if (problem.getStatusCode() != harmless) {
                throw new DmlException(problem.getMessage());
            }
        }
    }

    /**
     * Takes a suggestion away without remembering anything, which is what a merge leaves
     * behind: the two records are one record now, so the pair cannot come back.
     */
    public static void closeSet(Id duplicateRecordSetId) {
        if (duplicateRecordSetId == null) {
            return;
        }
        List<DuplicateRecordSet> sets = DuplicateSelector.setsByIds(
            new Set<Id>{ duplicateRecordSetId }
        );
        if (!sets.isEmpty()) {
            Database.delete(sets, AccessLevel.USER_MODE);
        }
    }

    /**
     * The suggestion, provided it is one this feature reviews: at least two records, every one
     * a person or an account. A suggestion about leads, or anything else, is refused rather
     * than dismissed or closed from here (R-DP2).
     */
    public static DuplicateRecordSet requireSet(Id duplicateRecordSetId) {
        if (duplicateRecordSetId == null) {
            throw new DuplicateException(Label.Core_Duplicates_ErrorNoSuggestion);
        }
        List<DuplicateRecordSet> sets = DuplicateSelector.setsByIds(
            new Set<Id>{ duplicateRecordSetId }
        );
        if (sets.isEmpty()) {
            throw new DuplicateException(Label.Core_Duplicates_ErrorNoSuggestion);
        }
        if (sets[0].DuplicateRecordItems.size() < 2) {
            throw new DuplicateException(Label.Core_Duplicates_ErrorNotReviewable);
        }
        for (DuplicateRecordItem item : sets[0].DuplicateRecordItems) {
            Schema.SObjectType itemType = item.RecordId.getSObjectType();
            if (itemType != Contact.SObjectType && itemType != Account.SObjectType) {
                throw new DuplicateException(Label.Core_Duplicates_ErrorNotReviewable);
            }
        }
        return sets[0];
    }

    /**
     * The suggestion, provided it names exactly these records: a merge from the panel may only
     * close the suggestion it was started from.
     */
    public static DuplicateRecordSet requireSetOf(Id duplicateRecordSetId, Set<Id> recordIds) {
        DuplicateRecordSet found = requireSet(duplicateRecordSetId);
        Set<Id> named = new Set<Id>();
        for (DuplicateRecordItem item : found.DuplicateRecordItems) {
            named.add(item.RecordId);
        }
        if (recordIds == null || !named.equals(recordIds)) {
            throw new DuplicateException(Label.Core_Duplicates_ErrorNotThisPair);
        }
        return found;
    }
}
