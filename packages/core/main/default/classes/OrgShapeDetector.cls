/**
 * Reports what is installed in this org, so that BarnCRM can recommend a coexistence
 * mode (plan Section 4.5) and Health Check can tell an administrator what it found
 * (plan Section 4.8).
 *
 * Detection is not dependency. Every package, Person Account, and Industries name used here
 * is a String constant handed to a describe call, never a compile-time reference, so Core
 * still deploys and runs on a Platform-only org (ADR-0009, ADR-0013). Those four constant
 * declarations carry the marker that scripts/ci/check-standard-objects.sh honors, as do the
 * Nonprofit Cloud names in OrgShapeSelector and HouseholdSelector.
 *
 * The result is cached for the transaction because a global describe is expensive.
 */
@NamespaceAccessible
public with sharing class OrgShapeDetector {
    // The four detection constants. Each is read by detect() below and by nothing else.
    private static final String NPSP_PREFIX = 'npsp__'; // detection-only: NPSP key prefix
    private static final String PERSON_ACCOUNT_FIELD = 'IsPersonAccount'; // detection-only: field map key
    private static final String INDUSTRIES_GIFT_OBJECT = 'GiftTransaction'; // detection-only: describe key
    private static final String SALES_CLOUD_OBJECT = 'Opportunity'; // detection-only: describe key, reported only

    @TestVisible
    private static OrgShape overrideShape;

    private static OrgShape cachedShape;

    /**
     * What one org looks like. Every flag is answerable from a describe call except
     * platformEncryptionPossible, which is deliberately null: Shield Platform Encryption
     * cannot be detected reliably from inside a managed package, so Health Check says so
     * rather than guessing.
     */
    public class OrgShape {
        @AuraEnabled
        public Boolean hasNpsp;
        @AuraEnabled
        public Boolean hasPersonAccounts;
        @AuraEnabled
        public Boolean hasIndustriesNonprofit;
        @AuraEnabled
        public Boolean hasSalesCloudObjects;
        @AuraEnabled
        public Boolean isMultiCurrency;
        @AuraEnabled
        public Boolean platformEncryptionPossible;

        /**
         * Whether this org already models households the Nonprofit Cloud way, as an Account
         * carrying a native household group. True unless the probe came back with a definite
         * zero, because unknown is treated as "assume they exist": see
         * OrgShapeSelector.nativeHouseholdGroupCount and ADR-0036. An org without the object
         * at all is a definite zero, not an unknown (ADR-NEXT).
         */
        @AuraEnabled
        public Boolean hasNativeHouseholdGroups;

        /**
         * How many native households were counted, or null when the count could not be made.
         * Null is the honest answer to an unanswerable question, and Health Check says so
         * rather than showing a zero it does not have.
         */
        @AuraEnabled
        public Integer nativeHouseholdGroupCount;

        /**
         * Account record types whose describe reports them as person types. Empty unless
         * Person Accounts are enabled. HouseholdService reads this set, so it is computed
         * dynamically and never from a static record type reference.
         */
        public Set<Id> personAccountRecordTypeIds;

        public OrgShape() {
            this.hasNpsp = false;
            this.hasPersonAccounts = false;
            this.hasIndustriesNonprofit = false;
            this.hasSalesCloudObjects = false;
            this.isMultiCurrency = false;
            this.platformEncryptionPossible = null;
            // Unknown until the probe answers, and unknown means assume they exist.
            this.hasNativeHouseholdGroups = true;
            this.nativeHouseholdGroupCount = null;
            this.personAccountRecordTypeIds = new Set<Id>();
        }
    }

    /** Account record types that are person types. Empty unless Person Accounts are enabled. */
    public static Set<Id> personRecordTypeIds() {
        // The cheap read: no full detect(), and never null.
        Set<Id> personTypes = personAccountRecordTypeIds();
        return personTypes == null ? new Set<Id>() : personTypes;
    }

    /**
     * What this org looks like, computed once per transaction.
     */
    public static OrgShape detect() {
        if (overrideShape != null) {
            return overrideShape;
        }
        if (cachedShape != null) {
            return cachedShape;
        }

        OrgShape shape = new OrgShape();
        Set<String> objectNames = describedObjectNames();

        shape.hasNpsp = hasObjectWithPrefix(objectNames, NPSP_PREFIX.toLowerCase());
        shape.hasIndustriesNonprofit = objectNames.contains(INDUSTRIES_GIFT_OBJECT.toLowerCase());
        shape.hasSalesCloudObjects = objectNames.contains(SALES_CLOUD_OBJECT.toLowerCase());
        shape.hasPersonAccounts = hasPersonAccounts();
        shape.personAccountRecordTypeIds = personAccountRecordTypeIds();
        // Asked on its own, never inferred from the fundraising objects above: the native
        // household group is an Industries common object that the Fundraising licence does
        // not gate, so an org can have it without having any of them. A null count is the
        // probe saying it could not tell, and an org that might have native households is
        // treated as one that has them (ADR-0036). An org without the object counts zero
        // (ADR-NEXT).
        shape.nativeHouseholdGroupCount = OrgShapeSelector.nativeHouseholdGroupCount();
        shape.hasNativeHouseholdGroups =
            shape.nativeHouseholdGroupCount == null ||
            shape.nativeHouseholdGroupCount > 0;
        shape.isMultiCurrency = UserInfo.isMultiCurrencyOrganization();
        shape.platformEncryptionPossible = null;

        cachedShape = shape;
        return shape;
    }

    // One facet at a time, for the callers on a save path that need one answer and not the
    // whole shape: detect() costs two global describes, a record type query and the native
    // household probe, and these cost one cached describe, plus one small query each where
    // the facet needs it. Each follows a test's override shape and reuses a shape already
    // detected in this transaction.
    private static Boolean cachedHasPersonAccounts;
    private static Set<Id> cachedPersonTypes;
    private static Boolean cachedHasNativeHouseholdGroups;

    /**
     * Whether this org stores people as accounts: one Account field describe, cached. Other
     * packages ask here rather than reading `detect().hasPersonAccounts`, since an
     * `@AuraEnabled` field cannot also be `@NamespaceAccessible`.
     */
    @NamespaceAccessible
    public static Boolean hasPersonAccounts() {
        if (overrideShape != null) {
            return overrideShape.hasPersonAccounts == true;
        }
        if (cachedShape != null) {
            return cachedShape.hasPersonAccounts == true;
        }
        if (cachedHasPersonAccounts == null) {
            cachedHasPersonAccounts = Account.SObjectType.getDescribe(
                    SObjectDescribeOptions.DEFERRED
                )
                .fields.getMap()
                .containsKey(PERSON_ACCOUNT_FIELD.toLowerCase());
        }
        return cachedHasPersonAccounts;
    }

    /** Every Account record type that is a person type; empty, with no query, without them. */
    @NamespaceAccessible
    public static Set<Id> personAccountRecordTypeIds() {
        if (overrideShape != null) {
            return overrideShape.personAccountRecordTypeIds == null
                ? new Set<Id>()
                : overrideShape.personAccountRecordTypeIds;
        }
        if (cachedShape != null) {
            return cachedShape.personAccountRecordTypeIds;
        }
        if (cachedPersonTypes == null) {
            cachedPersonTypes = hasPersonAccounts()
                ? OrgShapeSelector.personTypeRecordTypeIds()
                : new Set<Id>();
        }
        return cachedPersonTypes;
    }

    /**
     * Whether this org already has native Nonprofit Cloud households, asked as "is there
     * one" (a single row) rather than counted. Unknown is treated as yes, as detect() does
     * (ADR-0036).
     */
    public static Boolean hasNativeHouseholdGroups() {
        if (overrideShape != null) {
            return overrideShape.hasNativeHouseholdGroups == true;
        }
        if (cachedShape != null) {
            return cachedShape.hasNativeHouseholdGroups == true;
        }
        if (cachedHasNativeHouseholdGroups == null) {
            Boolean found = OrgShapeSelector.anyNativeHouseholdGroup();
            cachedHasNativeHouseholdGroups = found == null || found;
        }
        return cachedHasNativeHouseholdGroups;
    }

    /**
     * The person account record type the running user creates a new person with, or null when
     * none is available to them.
     *
     * personAccountRecordTypeIds holds every person type in the org, which is right for
     * telling a person account from an organization but not for creating one: a record type
     * not assigned to the user's profile or permission sets is refused on insert
     * (INVALID_CROSS_REFERENCE_KEY). A Nonprofit Cloud trial ships a Person Account record
     * type that the System Administrator profile is not given. So the choice is made from the
     * running user's describe: their default record type when it is a person type, otherwise
     * the available person type whose developer name sorts first, so the answer is the same
     * every time. Not cached: the describe follows System.runAs.
     */
    @NamespaceAccessible
    public static Id creatablePersonRecordTypeId() {
        Set<Id> personTypes = personAccountRecordTypeIds();
        if (personTypes == null || personTypes.isEmpty()) {
            return null;
        }
        Map<Id, Schema.RecordTypeInfo> infos = Account.SObjectType.getDescribe(
                SObjectDescribeOptions.DEFERRED
            )
            .getRecordTypeInfosById();
        Schema.RecordTypeInfo chosen;
        for (Id recordTypeId : personTypes) {
            Schema.RecordTypeInfo info = infos.get(recordTypeId);
            if (info == null || !info.isAvailable()) {
                continue;
            }
            if (info.isDefaultRecordTypeMapping()) {
                return recordTypeId;
            }
            if (chosen == null || info.getDeveloperName() < chosen.getDeveloperName()) {
                chosen = info;
            }
        }
        return chosen == null ? null : chosen.getRecordTypeId();
    }

    /**
     * The coexistence mode this org shape calls for (plan Section 4.5). Nonprofit Cloud
     * wins over NPSP: an org with both is a Nonprofit Cloud org that also has the older
     * package in it. A mode named after a product is recommended only where that product is
     * detected (ADR-0062), so an org with Person
     * Accounts and neither product is Standalone; its people still get junction membership
     * (CoexistenceService.withMembership).
     */
    public static String recommendedCoexistenceMode() {
        return recommendedCoexistenceMode(detect());
    }

    /** The same rule for a given shape, so the Setup Assistant can ask it of its own. */
    public static String recommendedCoexistenceMode(OrgShape shape) {
        if (shape != null && shape.hasIndustriesNonprofit == true) {
            return CoexistenceService.MODE_NONPROFIT_CLOUD;
        }
        if (shape != null && shape.hasNpsp == true) {
            return CoexistenceService.MODE_NPSP;
        }
        return CoexistenceService.MODE_STANDALONE;
    }

    private static Set<String> describedObjectNames() {
        Set<String> names = new Set<String>();
        for (String objectName : Schema.getGlobalDescribe().keySet()) {
            names.add(objectName.toLowerCase());
        }
        return names;
    }

    private static Boolean hasObjectWithPrefix(Set<String> objectNames, String prefix) {
        for (String objectName : objectNames) {
            if (objectName.startsWith(prefix)) {
                return true;
            }
        }
        return false;
    }

    @TestVisible
    private static void reset() {
        overrideShape = null;
        cachedShape = null;
        cachedHasPersonAccounts = null;
        cachedPersonTypes = null;
        cachedHasNativeHouseholdGroups = null;
    }
}
