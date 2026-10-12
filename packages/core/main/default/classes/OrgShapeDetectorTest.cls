/**
 * Tests for OrgShapeDetector (feature C-07).
 *
 * The recommendation is tested against a forced shape rather than against the org the tests
 * happen to run in, so that every branch is covered on every org shape in the CI matrix.
 * detect() itself is tested against the real org, which is the only honest way to know that
 * the describe calls work where Core has to run.
 */
@IsTest
private class OrgShapeDetectorTest {
    // Held as text here for the same reason it is held as text in OrgShapeSelector: these
    // tests have to pass on a Platform-only org, where the object does not exist, so they may
    // not compile against it either.
    private static final String NATIVE_HOUSEHOLD_GROUP = 'PartyRelationshipGroup'; // detection-only: describe key, so the absent-object path can be asserted on an org that does not have the object

    @IsTest
    static void detectPopulatesTheWholeShape() {
        OrgShapeDetector.reset();

        Test.startTest();
        OrgShapeDetector.OrgShape shape = OrgShapeDetector.detect();
        Test.stopTest();

        System.assertNotEquals(null, shape, 'Detection should always return a shape.');
        System.assertNotEquals(null, shape.hasNpsp, 'hasNpsp should be answered, not left null.');
        System.assertNotEquals(
            null,
            shape.hasPersonAccounts,
            'hasPersonAccounts should be answered, not left null.'
        );
        System.assertNotEquals(
            null,
            shape.hasIndustriesNonprofit,
            'hasIndustriesNonprofit should be answered, not left null.'
        );
        System.assertNotEquals(
            null,
            shape.hasSalesCloudObjects,
            'hasSalesCloudObjects should be answered, not left null.'
        );
        System.assertNotEquals(
            null,
            shape.isMultiCurrency,
            'isMultiCurrency should be answered, not left null.'
        );
        System.assertEquals(
            null,
            shape.platformEncryptionPossible,
            'Platform Encryption cannot be detected, so it stays null and Health Check says so.'
        );
        System.assertNotEquals(
            null,
            shape.personAccountRecordTypeIds,
            'The person account record type set is always present, empty when there are none.'
        );
        System.assertNotEquals(
            null,
            shape.hasNativeHouseholdGroups,
            'hasNativeHouseholdGroups should be answered, not left null.'
        );
        if (shape.nativeHouseholdGroupCount == null) {
            System.assertEquals(
                true,
                shape.hasNativeHouseholdGroups,
                'An uncounted org is assumed to have native households, never assumed not to.'
            );
        } else {
            System.assertEquals(
                shape.nativeHouseholdGroupCount > 0,
                shape.hasNativeHouseholdGroups,
                'A counted org reports exactly what was counted.'
            );
        }
    }

    /**
     * The four probe outcomes. Three of them are injected, because the object they are about
     * cannot be made to exist in an Apex test and Core has to pass its tests on a
     * Platform-only org. The fourth is the real probe on an org without the object.
     */
    @IsTest
    static void anAbsentObjectIsUnknownRatherThanNone() {
        if (Schema.getGlobalDescribe().containsKey(NATIVE_HOUSEHOLD_GROUP)) {
            // This org has the object, so there is no absent path to exercise here. The
            // injected tests below cover the rest.
            return;
        }
        OrgShapeDetector.reset();

        OrgShapeDetector.OrgShape shape = OrgShapeDetector.detect();

        System.assertEquals(
            null,
            shape.nativeHouseholdGroupCount,
            'An object this org does not describe leaves the count unknown, not zero.'
        );
        System.assertEquals(
            true,
            shape.hasNativeHouseholdGroups,
            'Unknown is assumed to be yes, so a later guard stays cautious (ADR-0036).'
        );
    }

    @IsTest
    static void aFailedProbeIsUnknownRatherThanNone() {
        OrgShapeDetector.reset();
        OrgShapeSelector.failNativeHouseholdGroupProbe = true;

        OrgShapeDetector.OrgShape shape = OrgShapeDetector.detect();

        System.assertEquals(
            null,
            shape.nativeHouseholdGroupCount,
            'A probe that threw has counted nothing, so the count stays unknown.'
        );
        System.assertEquals(
            true,
            shape.hasNativeHouseholdGroups,
            'Not being able to answer is not the same as answering no (ADR-0036).'
        );
    }

    @IsTest
    static void aCountedOrgReportsTheCount() {
        OrgShapeDetector.reset();
        OrgShapeSelector.nativeHouseholdGroupCountOverride = 7;

        OrgShapeDetector.OrgShape shape = OrgShapeDetector.detect();

        System.assertEquals(
            7,
            shape.nativeHouseholdGroupCount,
            'A counted org reports the number it counted.'
        );
        System.assertEquals(
            true,
            shape.hasNativeHouseholdGroups,
            'An org with native households has native households.'
        );
    }

    @IsTest
    static void aCountedZeroIsTheOneWayToGetNo() {
        OrgShapeDetector.reset();
        OrgShapeSelector.nativeHouseholdGroupCountOverride = 0;

        OrgShapeDetector.OrgShape shape = OrgShapeDetector.detect();

        System.assertEquals(
            0,
            shape.nativeHouseholdGroupCount,
            'A probe that ran and found nothing reports zero, not unknown.'
        );
        System.assertEquals(
            false,
            shape.hasNativeHouseholdGroups,
            'Only a count that actually ran and came back empty answers no.'
        );
    }

    @IsTest
    static void theProbeIsNotRunTwiceInOneTransaction() {
        OrgShapeDetector.reset();
        OrgShapeSelector.nativeHouseholdGroupCountOverride = 3;

        OrgShapeDetector.OrgShape first = OrgShapeDetector.detect();
        OrgShapeSelector.nativeHouseholdGroupCountOverride = 99;
        OrgShapeDetector.OrgShape second = OrgShapeDetector.detect();

        System.assertEquals(
            3,
            second.nativeHouseholdGroupCount,
            'The count is part of the cached shape, so it is asked once per transaction.'
        );
        System.assert(first === second, 'The shape should be computed once per transaction.');
    }

    @IsTest
    static void detectIsCachedForTheTransaction() {
        OrgShapeDetector.reset();

        OrgShapeDetector.OrgShape first = OrgShapeDetector.detect();
        OrgShapeDetector.OrgShape second = OrgShapeDetector.detect();

        System.assert(first === second, 'The shape should be computed once per transaction.');
    }

    @IsTest
    static void personAccountsAloneRecommendStandalone() {
        OrgShapeDetector.overrideShape = shapeWith(false, true, false);

        System.assertEquals(
            CoexistenceService.MODE_STANDALONE,
            OrgShapeDetector.recommendedCoexistenceMode(),
            'Person Accounts without Nonprofit Cloud name no product, so the org is Standalone.'
        );
    }

    @IsTest
    static void industriesObjectsRecommendNonprofitCloudCoexistence() {
        OrgShapeDetector.overrideShape = shapeWith(false, false, true);

        System.assertEquals(
            CoexistenceService.MODE_NONPROFIT_CLOUD,
            OrgShapeDetector.recommendedCoexistenceMode(),
            'Nonprofit Cloud gift objects mean Nonprofit Cloud coexistence.'
        );
    }

    @IsTest
    static void npspRecommendsNpspCoexistence() {
        OrgShapeDetector.overrideShape = shapeWith(true, false, false);

        System.assertEquals(
            CoexistenceService.MODE_NPSP,
            OrgShapeDetector.recommendedCoexistenceMode(),
            'An NPSP org without Person Accounts gets NPSP coexistence.'
        );
    }

    @IsTest
    static void nonprofitCloudWinsOverNpsp() {
        OrgShapeDetector.overrideShape = shapeWith(true, true, true);

        System.assertEquals(
            CoexistenceService.MODE_NONPROFIT_CLOUD,
            OrgShapeDetector.recommendedCoexistenceMode(),
            'When both products are present, Nonprofit Cloud decides.'
        );
        OrgShapeDetector.overrideShape = shapeWith(true, true, false);
        System.assertEquals(
            CoexistenceService.MODE_NPSP,
            OrgShapeDetector.recommendedCoexistenceMode(),
            'NPSP with Person Accounts and no Nonprofit Cloud is NPSP coexistence.'
        );
    }

    @IsTest
    static void plainOrgRecommendsStandalone() {
        OrgShapeDetector.overrideShape = shapeWith(false, false, false);

        System.assertEquals(
            CoexistenceService.MODE_STANDALONE,
            OrgShapeDetector.recommendedCoexistenceMode(),
            'An org with nothing else in it runs standalone.'
        );
    }

    @IsTest
    static void resetClearsTheOverride() {
        OrgShapeDetector.overrideShape = shapeWith(true, true, true);
        OrgShapeDetector.reset();

        System.assertNotEquals(
            null,
            OrgShapeDetector.detect(),
            'After a reset, detection reads the org again.'
        );
    }

    private static OrgShapeDetector.OrgShape shapeWith(
        Boolean hasNpsp,
        Boolean hasPersonAccounts,
        Boolean hasIndustriesNonprofit
    ) {
        OrgShapeDetector.OrgShape shape = new OrgShapeDetector.OrgShape();
        shape.hasNpsp = hasNpsp;
        shape.hasPersonAccounts = hasPersonAccounts;
        shape.hasIndustriesNonprofit = hasIndustriesNonprofit;
        return shape;
    }
}
