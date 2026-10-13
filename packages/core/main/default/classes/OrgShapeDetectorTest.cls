/**
 * Tests for OrgShapeDetector (feature C-07).
 *
 * The recommendation is tested against a forced shape rather than against the org the tests
 * happen to run in, so that every branch is covered on every org shape in the CI matrix.
 * detect() itself is tested against the real org, which is the only honest way to know that
 * the describe calls work where Core has to run.
 */
@IsTest(testFor='ApexClass:OrgShapeDetector')
private class OrgShapeDetectorTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    // Held as text here for the same reason it is held as text in OrgShapeSelector: these
    // tests have to pass on a Platform-only org, where the object does not exist, so they may
    // not compile against it either.
    private static final String NATIVE_HOUSEHOLD_GROUP = 'PartyRelationshipGroup'; // detection-only: describe key, so the absent-object path can be asserted on an org that does not have the object

    private static final String PERSON_ACCOUNT_FIELD = 'ispersonaccount'; // detection-only: Account field map key, so the no-Person-Accounts path can be asserted on any org shape

    @IsTest
    static void personTypeRecordTypesAreEmptyAndDoNotThrowWithoutPersonAccounts() {
        System.runAs(TestUsers.admin()) {
            Boolean hasPersonAccounts = Schema.SObjectType.Account.fields.getMap()
                .containsKey(PERSON_ACCOUNT_FIELD);

            Set<Id> personTypes = OrgShapeSelector.personTypeRecordTypeIds();

            System.assertNotEquals(null, personTypes, 'A set is always returned.');
            if (!hasPersonAccounts) {
                System.assert(
                    personTypes.isEmpty(),
                    'Without Person Accounts there are no person types, and no query is made.'
                );
            }
        }
    }

    @IsTest
    static void detectPopulatesTheWholeShape() {
        System.runAs(TestUsers.admin()) {
            OrgShapeDetector.reset();

            Test.startTest();
            OrgShapeDetector.OrgShape shape = OrgShapeDetector.detect();
            Test.stopTest();

            System.assertNotEquals(null, shape, 'Detection should always return a shape.');
            System.assertNotEquals(
                null,
                shape.hasNpsp,
                'hasNpsp should be answered, not left null.'
            );
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
    }

    /**
     * The four probe outcomes. Three of them are injected, because the object they are about
     * cannot be made to exist in an Apex test and Core has to pass its tests on a
     * Platform-only org. The fourth is the real probe on an org without the object.
     */
    @IsTest
    static void anAbsentObjectIsUnknownRatherThanNone() {
        System.runAs(TestUsers.admin()) {
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
    }

    @IsTest
    static void aFailedProbeIsUnknownRatherThanNone() {
        System.runAs(TestUsers.admin()) {
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
    }

    @IsTest
    static void aCountedOrgReportsTheCount() {
        System.runAs(TestUsers.admin()) {
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
    }

    @IsTest
    static void aCountedZeroIsTheOneWayToGetNo() {
        System.runAs(TestUsers.admin()) {
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
    }

    @IsTest
    static void theProbeIsNotRunTwiceInOneTransaction() {
        System.runAs(TestUsers.admin()) {
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
    }

    @IsTest
    static void detectIsCachedForTheTransaction() {
        System.runAs(TestUsers.admin()) {
            OrgShapeDetector.reset();

            OrgShapeDetector.OrgShape first = OrgShapeDetector.detect();
            OrgShapeDetector.OrgShape second = OrgShapeDetector.detect();

            System.assert(first === second, 'The shape should be computed once per transaction.');
        }
    }

    @IsTest
    static void personAccountsAloneRecommendStandalone() {
        System.runAs(TestUsers.admin()) {
            OrgShapeDetector.overrideShape = shapeWith(false, true, false);

            System.assertEquals(
                CoexistenceService.MODE_STANDALONE,
                OrgShapeDetector.recommendedCoexistenceMode(),
                'Person Accounts without Nonprofit Cloud name no product, so the org is Standalone.'
            );
        }
    }

    @IsTest
    static void industriesObjectsRecommendNonprofitCloudCoexistence() {
        System.runAs(TestUsers.admin()) {
            OrgShapeDetector.overrideShape = shapeWith(false, false, true);

            System.assertEquals(
                CoexistenceService.MODE_NONPROFIT_CLOUD,
                OrgShapeDetector.recommendedCoexistenceMode(),
                'Nonprofit Cloud gift objects mean Nonprofit Cloud coexistence.'
            );
        }
    }

    @IsTest
    static void npspRecommendsNpspCoexistence() {
        System.runAs(TestUsers.admin()) {
            OrgShapeDetector.overrideShape = shapeWith(true, false, false);

            System.assertEquals(
                CoexistenceService.MODE_NPSP,
                OrgShapeDetector.recommendedCoexistenceMode(),
                'An NPSP org without Person Accounts gets NPSP coexistence.'
            );
        }
    }

    @IsTest
    static void nonprofitCloudWinsOverNpsp() {
        System.runAs(TestUsers.admin()) {
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
    }

    @IsTest
    static void plainOrgRecommendsStandalone() {
        System.runAs(TestUsers.admin()) {
            OrgShapeDetector.overrideShape = shapeWith(false, false, false);

            System.assertEquals(
                CoexistenceService.MODE_STANDALONE,
                OrgShapeDetector.recommendedCoexistenceMode(),
                'An org with nothing else in it runs standalone.'
            );
        }
    }

    @IsTest
    static void resetClearsTheOverride() {
        System.runAs(TestUsers.admin()) {
            OrgShapeDetector.overrideShape = shapeWith(true, true, true);
            OrgShapeDetector.reset();

            System.assertNotEquals(
                null,
                OrgShapeDetector.detect(),
                'After a reset, detection reads the org again.'
            );
        }
    }

    /**
     * A person type that the running user is not given (here one the describe does not know at
     * all) is never handed out for a new person: inserting with it is refused. With no other
     * person type there is nothing to create with, and the answer is null.
     */
    @IsTest
    static void aPersonTypeTheUserIsNotGivenIsNeverChosen() {
        System.runAs(TestUsers.admin()) {
            OrgShapeDetector.OrgShape shape = shapeWith(false, true, false);
            shape.personAccountRecordTypeIds = new Set<Id>{ Id.valueOf('012000000000999') };
            OrgShapeDetector.overrideShape = shape;

            Assert.isNull(
                OrgShapeDetector.creatablePersonRecordTypeId(),
                'No person type the user can create with.'
            );

            shape.personAccountRecordTypeIds = new Set<Id>();
            Assert.isNull(
                OrgShapeDetector.creatablePersonRecordTypeId(),
                'None at all where the org has no person types.'
            );
        }
    }

    /** A type the running user is given is chosen over one they are not. */
    @IsTest
    static void anAvailablePersonTypeIsChosen() {
        System.runAs(TestUsers.admin()) {
            Id available;
            for (
                Schema.RecordTypeInfo info : Account.SObjectType.getDescribe(
                        SObjectDescribeOptions.DEFERRED
                    )
                    .getRecordTypeInfos()
            ) {
                if (info.isAvailable() && !info.isMaster()) {
                    available = info.getRecordTypeId();
                    break;
                }
            }
            if (available == null) {
                // An org with no Account record type of its own has none to stand in for one.
                return;
            }
            OrgShapeDetector.OrgShape shape = shapeWith(false, true, false);
            shape.personAccountRecordTypeIds = new Set<Id>{
                Id.valueOf('012000000000999'),
                available
            };
            OrgShapeDetector.overrideShape = shape;

            Assert.areEqual(
                available,
                OrgShapeDetector.creatablePersonRecordTypeId(),
                'The type the user is given.'
            );
        }
    }

    /** In the org as it is, the answer is always a person type the running user is given. */
    @IsTest
    static void theRealAnswerIsAnAvailablePersonType() {
        System.runAs(TestUsers.admin()) {
            Id chosen = OrgShapeDetector.creatablePersonRecordTypeId();
            if (chosen == null) {
                Assert.isTrue(
                    noneAvailable(OrgShapeDetector.detect().personAccountRecordTypeIds),
                    'Null only where no person type is given to the user.'
                );
                return;
            }
            Assert.isTrue(
                OrgShapeDetector.detect().personAccountRecordTypeIds.contains(chosen),
                'A person type.'
            );
            Assert.isTrue(
                Account.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
                    .getRecordTypeInfosById()
                    .get(chosen)
                    .isAvailable(),
                'Given to the user.'
            );
        }
    }

    private static Boolean noneAvailable(Set<Id> recordTypeIds) {
        Map<Id, Schema.RecordTypeInfo> infos = Account.SObjectType.getDescribe(
                SObjectDescribeOptions.DEFERRED
            )
            .getRecordTypeInfosById();
        for (Id recordTypeId : recordTypeIds) {
            if (infos.containsKey(recordTypeId) && infos.get(recordTypeId).isAvailable()) {
                return false;
            }
        }
        return true;
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
