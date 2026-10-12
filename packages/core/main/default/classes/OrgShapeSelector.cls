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
    private static final String PERSON_RECORD_TYPE_QUERY = 'SELECT Id FROM RecordType WHERE SobjectType = \'Account\' AND IsPersonType = true';

    // The Nonprofit Cloud household group, and the whole text of the one question asked about
    // it. A Nonprofit Cloud household is an Account carrying a child group of this type: there
    // is no field on Account, so this count is the only way to tell whether the org models
    // households natively (docs/architecture/reference/nonprofit-cloud-data-model.md
    // Section 4). It is probed on its own and never inferred from the fundraising objects,
    // because the group is an Industries common object that the Fundraising licence does not
    // gate.
    private static final String NATIVE_HOUSEHOLD_GROUP = 'PartyRelationshipGroup'; // detection-only: describe key, so Health Check can tell an administrator whether this org already models households natively
    private static final String NATIVE_HOUSEHOLD_GROUP_COUNT_QUERY = 'SELECT COUNT() FROM PartyRelationshipGroup WHERE Type = \'Household\''; // detection-only: counts the org's native households, the only native indicator that an Account is a Nonprofit Cloud household

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
     * The Account record types that describe themselves as person types.
     */
    public static Set<Id> personTypeRecordTypeIds() {
        Set<Id> recordTypeIds = new Set<Id>();
        for (SObject recordType : Database.query(PERSON_RECORD_TYPE_QUERY, AccessLevel.USER_MODE)) {
            recordTypeIds.add((Id) recordType.get('Id'));
        }
        return recordTypeIds;
    }

    /**
     * How many native Nonprofit Cloud households this org has, or null when the question
     * could not be answered.
     *
     * Null means unknown, and unknown is not zero. The object may be missing from the global
     * describe, the running user may not be able to read it, or the query may fail; none of
     * those three is evidence that the org has no native households. Schema.getGlobalDescribe
     * is itself filtered by the running user's permission set licences, and the household
     * group is documented as gated by the Group Membership permission set, so an org that has
     * the object can still describe as though it does not.
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
        try {
            if (failNativeHouseholdGroupProbe == true) {
                throw new QueryException('Injected probe failure, tests only.');
            }
            if (nativeHouseholdGroupCountOverride != null) {
                return nativeHouseholdGroupCountOverride;
            }
            Schema.SObjectType groupType = Schema.getGlobalDescribe().get(NATIVE_HOUSEHOLD_GROUP);
            if (groupType == null || !groupType.getDescribe().isAccessible()) {
                return null;
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
