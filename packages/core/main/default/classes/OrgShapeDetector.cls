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
         * OrgShapeSelector.nativeHouseholdGroupCount and ADR-0036.
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
        shape.hasPersonAccounts = accountFieldNames().contains(PERSON_ACCOUNT_FIELD.toLowerCase());
        if (shape.hasPersonAccounts == true) {
            shape.personAccountRecordTypeIds = OrgShapeSelector.personTypeRecordTypeIds();
        }
        // Asked on its own, never inferred from the fundraising objects above: the native
        // household group is an Industries common object that the Fundraising licence does
        // not gate, so an org can have it without having any of them. A null count is the
        // probe saying it could not tell, and an org that might have native households is
        // treated as one that has them (ADR-0036).
        shape.nativeHouseholdGroupCount = OrgShapeSelector.nativeHouseholdGroupCount();
        shape.hasNativeHouseholdGroups =
            shape.nativeHouseholdGroupCount == null ||
            shape.nativeHouseholdGroupCount > 0;
        shape.isMultiCurrency = UserInfo.isMultiCurrencyOrganization();
        shape.platformEncryptionPossible = null;

        cachedShape = shape;
        return shape;
    }

    /**
     * The coexistence mode this org shape calls for (plan Section 4.5). Agentforce Nonprofit
     * wins over NPSP: an org with both is a Nonprofit Cloud org that also has the older
     * package in it, and Person Accounts decide how households have to be built.
     */
    public static String recommendedCoexistenceMode() {
        OrgShape shape = detect();
        if (shape.hasIndustriesNonprofit == true || shape.hasPersonAccounts == true) {
            return CoexistenceService.MODE_AGENTFORCE_NONPROFIT;
        }
        if (shape.hasNpsp == true) {
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

    private static Set<String> accountFieldNames() {
        Set<String> names = new Set<String>();
        for (String fieldName : Schema.SObjectType.Account.fields.getMap().keySet()) {
            names.add(fieldName.toLowerCase());
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
    }
}
