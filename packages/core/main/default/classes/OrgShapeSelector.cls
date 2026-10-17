/**
 * The queries org shape detection needs (feature C-07). They live in a selector because
 * every SOQL statement does (plan Section 7.1).
 *
 * Both queries are dynamic on purpose. One filters on a field that exists only where Person
 * Accounts are enabled, and the other names an Industries object that is absent from a
 * Platform-only org, so a static query of either would stop Core compiling where Core has to
 * run (ADR-0009, ADR-0013). Each query is held as a complete literal, so nothing is ever
 * concatenated into it, and each Nonprofit Cloud name is a String constant carrying the
 * marker scripts/ci/check-standard-objects.sh honors, never a compile-time reference.
 */
public with sharing class OrgShapeSelector {
    private static final String PERSON_ACCOUNT_FIELD = 'ispersonaccount'; // detection-only: Account field map key, present only where Person Accounts are enabled
    private static final String PERSON_RECORD_TYPE_QUERY = 'SELECT Id FROM RecordType WHERE SobjectType = \'Account\' AND IsPersonType = true';

    // The Nonprofit Cloud household group, and the whole text of the one question asked about
    // it. A Nonprofit Cloud household is an Account carrying a child group of this type: there
    // is no field on Account, so this count is the only way to tell whether the org models
    // households natively (docs/architecture/reference/nonprofit-cloud-data-model.md
    // Section 4). It is probed on its own and never inferred from the fundraising objects,
    // because the group is an Industries common object that the Fundraising licence does not
    // gate.
    private static final String NATIVE_HOUSEHOLD_GROUP = 'PartyRelationshipGroup'; // detection-only: describe key, so Health Check can tell an administrator whether this org already models households natively
    // Capped: rows a COUNT() matches count toward the 50,000 query row limit, and that limit
    // cannot be caught, so an uncapped count would fail every transaction that detects the
    // org shape in an org with more native households than that. Health Check says "more
    // than" the cap (NATIVE_COUNT_CAP).
    private static final String NATIVE_HOUSEHOLD_GROUP_COUNT_QUERY = 'SELECT COUNT() FROM PartyRelationshipGroup WHERE Type = \'Household\' LIMIT 1001'; // detection-only: counts the org's native households, the only native indicator that an Account is a Nonprofit Cloud household
    private static final String NATIVE_HOUSEHOLD_GROUP_ANY_QUERY = 'SELECT Id FROM PartyRelationshipGroup WHERE Type = \'Household\' LIMIT 1'; // detection-only: whether the org has any native household at all, one row

    /** The native household count stops one above this, and Health Check says "more than". */
    public static final Integer NATIVE_COUNT_CAP = 1000;

    /**
     * Set only by tests, so that a counted answer can be exercised on an org where the object
     * does not exist. Production code always runs the probe.
     */
    @TestVisible
    private static Integer nativeHouseholdGroupCountOverride;

    /**
     * Set only by tests, so that the failure path is exercised on an org where no real probe
     * can be made to fail. Production code never sets it.
     */
    @TestVisible
    private static Boolean failNativeHouseholdGroupProbe = false;

    /**
     * Set only by tests: stands in for the native household group in the describe, so the
     * present-object path runs on an org without the object. The query still names the real
     * object, so there it fails and the answer is unknown. Production code never sets it.
     */
    @TestVisible
    private static Schema.SObjectType nativeHouseholdGroupTypeOverride;

    /**
     * The Account record types that describe themselves as person types.
     *
     * Empty, without querying, when the org has no Person Accounts. RecordType.IsPersonType
     * exists only where Person Accounts are enabled, so the query would throw a QueryException
     * (No such column) anywhere else. The org is checked by describe first, with the same test
     * OrgShapeDetector uses (the Account field that marks a person account); the exception is never the way
     * this is found out. Callable on any org shape.
     */
    public static Set<Id> personTypeRecordTypeIds() {
        Set<Id> recordTypeIds = new Set<Id>();
        if (!Schema.SObjectType.Account.fields.getMap().containsKey(PERSON_ACCOUNT_FIELD)) {
            return recordTypeIds;
        }
        for (SObject recordType : Database.query(PERSON_RECORD_TYPE_QUERY, AccessLevel.USER_MODE)) {
            recordTypeIds.add((Id) recordType.get('Id'));
        }
        return recordTypeIds;
    }

    /**
     * How many native Nonprofit Cloud households this org has, or null when the question
     * could not be answered.
     *
     * Zero when the object is not in the global describe at all (ADR-NEXT, narrowing
     * ADR-0036). Treating that absence as unknown made every org without Nonprofit Cloud look
     * as though it had native households, and in an org with Contacts to Multiple Accounts on,
     * where every contact has a native membership row, every BarnCRM household then read as a
     * native one: naming, addresses, memberships, tidy-up, merges and import undo all stood
     * aside. Null still means unknown, and unknown is not zero, when the object is described
     * but the running user cannot read it (the Group Membership permission set gates it) or
     * when the query fails. Zero for an absent object is an answer for the paths that only
     * leave a household alone (naming, greetings, addresses, memberships). It is not enough
     * for a path that deletes: the global describe is filtered by the running user's
     * permission set licences, so a user without the licence in a Nonprofit Cloud org can see
     * no object at all, and no signal Apex offers was confirmed to see past that filter. The
     * deleting paths therefore also ask nativeHouseholdGroupObjectDescribed (ADR-NEXT).
     *
     * The caller treats unknown as "assume they exist" (OrgShapeDetector.detect). The two
     * mistakes do not cost the same, which is the reasoning ADR-0036 uses for the delete
     * guard and the reason to repeat it here. A false negative tells a later guard that this
     * org has no native households, and the guard then silently opens, renames and tidies up
     * a household BarnCRM does not own. A false positive only makes that guard cautious
     * about an org that had nothing to protect.
     *
     * This is a count of the org, asked once per transaction by the detector. It is not the
     * per-record question the delete guard asks, which stays in
     * HouseholdSelector.getAccountsWithNativeDependents and is not duplicated here.
     */
    public static Integer nativeHouseholdGroupCount() {
        return probeNativeHouseholdGroups(false);
    }

    /**
     * Whether the org has any native household at all: true, false, or null when that could
     * not be told, on the same terms as the count. One row, for the save paths that only need
     * to know whether to be careful.
     */
    public static Boolean anyNativeHouseholdGroup() {
        Integer found = probeNativeHouseholdGroups(true);
        return found == null ? null : found > 0;
    }

    /**
     * Whether the native household group is in this transaction's global describe, so that a
     * zero count is one the probe actually made. False is not proof the org lacks the object:
     * the describe is filtered by the running user's licences (ADR-NEXT). A test that injects a
     * count is treated as describing the object, since the count stands for a probe that ran.
     */
    public static Boolean nativeHouseholdGroupObjectDescribed() {
        if (nativeHouseholdGroupCountOverride != null) {
            return true;
        }
        return Schema.getGlobalDescribe().containsKey(NATIVE_HOUSEHOLD_GROUP);
    }

    private static Integer probeNativeHouseholdGroups(Boolean anyIsEnough) {
        try {
            if (failNativeHouseholdGroupProbe == true) {
                throw new QueryException('Injected probe failure, tests only.');
            }
            if (nativeHouseholdGroupCountOverride != null) {
                return nativeHouseholdGroupCountOverride;
            }
            Schema.SObjectType groupType = nativeHouseholdGroupTypeOverride != null
                ? nativeHouseholdGroupTypeOverride
                : Schema.getGlobalDescribe().get(NATIVE_HOUSEHOLD_GROUP);
            if (groupType == null) {
                // Not in this org: a known none, not an unknown (ADR-NEXT).
                return 0;
            }
            if (!groupType.getDescribe().isAccessible()) {
                return null;
            }
            if (anyIsEnough) {
                // detection-only: one row, read from the literal above
                return Database.query(NATIVE_HOUSEHOLD_GROUP_ANY_QUERY, AccessLevel.USER_MODE)
                    .size();
            }
            // detection-only: the count itself, read from the literal above and never built by concatenation
            return Database.countQuery(NATIVE_HOUSEHOLD_GROUP_COUNT_QUERY, AccessLevel.USER_MODE);
        } catch (Exception probeFailed) {
            // No logging from a selector. Not being able to answer is reported as unknown,
            // and the caller decides what unknown means.
            return null;
        }
    }
}
