/**
 * OrgShapeDetector's one-facet answers, the shape a test hands to other packages, and the
 * caches behind them (C-07). Every test forces its shape or compares with a describe, so it
 * passes whatever the org has: NPSP or not, Person Accounts or not, Nonprofit Cloud or not.
 * The recommendation and detect() are in OrgShapeDetectorTest.
 */
@IsTest(testFor='ApexClass:OrgShapeDetector')
private class OrgShapeDetectorFacetsTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	private static final String PERSON_ACCOUNT_FIELD = 'ispersonaccount'; // detection-only: Account field map key, so the answer can be compared on any org shape

	@IsTest
	static void aNewShapeAssumesNativeHouseholdsAndNothingElse() {
		System.runAs(TestUsers.admin()) {
			OrgShapeDetector.OrgShape shape = new OrgShapeDetector.OrgShape();

			Assert.isFalse(shape.getHasNpsp(), 'No NPSP until detected');
			Assert.isFalse(shape.getHasPersonAccounts(), 'No Person Accounts until detected');
			Assert.isFalse(shape.getHasIndustriesNonprofit(), 'No Nonprofit Cloud until detected');
			Assert.isFalse(shape.getHasSalesCloudObjects(), 'No Sales Cloud objects until detected');
			Assert.isFalse(shape.getIsMultiCurrency(), 'One currency until detected');
			Assert.isTrue(shape.getHasNativeHouseholdGroups(), 'Unknown means assume they exist');
			Assert.isNull(shape.getNativeHouseholdGroupCount(), 'No count until probed');
			Assert.isNull(shape.platformEncryptionPossible, 'Encryption is never guessed');
			Assert.isTrue(shape.personAccountRecordTypeIds.isEmpty(), 'No person types until detected');
		}
	}

	@IsTest
	static void putSetsEachFlagByName() {
		System.runAs(TestUsers.admin()) {
			OrgShapeDetector.OrgShape shape = new OrgShapeDetector.OrgShape()
				.put('hasNpsp', true)
				.put('hasPersonAccounts', true)
				.put('hasIndustriesNonprofit', true)
				.put('hasSalesCloudObjects', true)
				.put('isMultiCurrency', true)
				.put('hasNativeHouseholdGroups', false)
				.put('nativeHouseholdGroupCount', 3);

			Assert.isTrue(shape.getHasNpsp(), 'hasNpsp');
			Assert.isTrue(shape.getHasPersonAccounts(), 'hasPersonAccounts');
			Assert.isTrue(shape.getHasIndustriesNonprofit(), 'hasIndustriesNonprofit');
			Assert.isTrue(shape.getHasSalesCloudObjects(), 'hasSalesCloudObjects');
			Assert.isTrue(shape.getIsMultiCurrency(), 'isMultiCurrency');
			Assert.isFalse(shape.getHasNativeHouseholdGroups(), 'hasNativeHouseholdGroups');
			Assert.areEqual(3, shape.getNativeHouseholdGroupCount(), 'nativeHouseholdGroupCount');
		}
	}

	@IsTest
	static void putRefusesAFlagItDoesNotKnow() {
		System.runAs(TestUsers.admin()) {
			try {
				new OrgShapeDetector.OrgShape().put('hasEverything', true);
				Assert.fail('An unknown flag must be refused');
			} catch (IllegalArgumentException refused) {
				Assert.isTrue(refused.getMessage().contains('hasEverything'), 'The message names the flag');
			}
		}
	}

	@IsTest
	static void anotherPackagesNpspShapeIsWhatDetectAnswers() {
		System.runAs(TestUsers.admin()) {
			OrgShapeDetector.reset();

			OrgShapeDetector.useNpspForTest(true);
			Assert.isTrue(OrgShapeDetector.hasNpsp(), 'NPSP is on the forced shape');
			Assert.isTrue(OrgShapeDetector.detect().getHasNpsp(), 'detect() answers the forced shape');
			Assert.areEqual(CoexistenceService.MODE_NPSP, OrgShapeDetector.recommendedCoexistenceMode(), 'NPSP mode');

			OrgShapeDetector.useNpspForTest(false);
			Assert.isFalse(OrgShapeDetector.hasNpsp(), 'And off when forced off');
			Assert.areEqual(
				CoexistenceService.MODE_STANDALONE,
				OrgShapeDetector.recommendedCoexistenceMode(),
				'Standalone without NPSP'
			);

			OrgShapeDetector.useNpspForTest(null);
			Assert.isFalse(OrgShapeDetector.hasNpsp(), 'No answer means no NPSP');
		}
	}

	@IsTest
	static void aForcedShapeAnswersEveryFacet() {
		System.runAs(TestUsers.admin()) {
			Id aPersonType = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
				.get('BarnCRM_Organization')
				.getRecordTypeId();
			OrgShapeDetector.OrgShape shape = new OrgShapeDetector.OrgShape()
				.put('hasPersonAccounts', true)
				.put('hasNativeHouseholdGroups', false);
			shape.personAccountRecordTypeIds = new Set<Id>{ aPersonType };
			OrgShapeDetector.overrideShape = shape;

			Assert.isTrue(OrgShapeDetector.hasPersonAccounts(), 'Person Accounts from the forced shape');
			Assert.isFalse(OrgShapeDetector.hasNativeHouseholdGroups(), 'No native households from the forced shape');
			Assert.areEqual(new Set<Id>{ aPersonType }, OrgShapeDetector.personAccountRecordTypeIds(), 'Person types');
			Assert.areEqual(
				new Set<Id>{ aPersonType },
				OrgShapeDetector.personRecordTypeIds(),
				'The cheap read agrees'
			);

			shape.put('hasNativeHouseholdGroups', true).put('hasPersonAccounts', false);
			shape.personAccountRecordTypeIds = null;
			Assert.isTrue(OrgShapeDetector.hasNativeHouseholdGroups(), 'Native households when the shape has them');
			Assert.isFalse(OrgShapeDetector.hasPersonAccounts(), 'No Person Accounts when the shape has none');
			Assert.isTrue(OrgShapeDetector.personAccountRecordTypeIds().isEmpty(), 'A missing set is an empty one');
			Assert.isTrue(OrgShapeDetector.personRecordTypeIds().isEmpty(), 'Never null');
		}
	}

	@IsTest
	static void noPersonTypeCanBeCreatedWhenNoneIsGivenOrKnown() {
		System.runAs(TestUsers.admin()) {
			OrgShapeDetector.OrgShape shape = new OrgShapeDetector.OrgShape();
			OrgShapeDetector.overrideShape = shape;
			Assert.isNull(OrgShapeDetector.creatablePersonRecordTypeId(), 'No person types, so none to create with');

			// An Id of the right kind that names no record type of the org.
			shape.personAccountRecordTypeIds = new Set<Id>{ '012000000000000AAA' };
			Assert.isNull(
				OrgShapeDetector.creatablePersonRecordTypeId(),
				'A person type the user cannot see is never chosen'
			);
		}
	}

	@IsTest
	static void facetsReadTheOrgAndAreCached() {
		System.runAs(TestUsers.admin()) {
			OrgShapeDetector.reset();
			Boolean described = Schema.SObjectType.Account.fields.getMap().containsKey(PERSON_ACCOUNT_FIELD);

			Assert.areEqual(described, OrgShapeDetector.hasPersonAccounts(), 'Read from the Account describe');
			Assert.areEqual(described, OrgShapeDetector.hasPersonAccounts(), 'And the same again from the cache');
			Set<Id> types = OrgShapeDetector.personAccountRecordTypeIds();
			Assert.isNotNull(types, 'A set is always answered');
			Assert.areEqual(described, !types.isEmpty(), 'Person types exist exactly when Person Accounts do');

			Boolean native1 = OrgShapeDetector.hasNativeHouseholdGroups();
			Assert.areEqual(native1, OrgShapeDetector.hasNativeHouseholdGroups(), 'The probe answer is cached');

			OrgShapeDetector.OrgShape shape = OrgShapeDetector.detect();
			Assert.areEqual(described, OrgShapeDetector.hasPersonAccounts(), 'A detected shape answers the same');
			Assert.areEqual(
				shape.getHasNativeHouseholdGroups(),
				OrgShapeDetector.hasNativeHouseholdGroups(),
				'A detected shape answers the native household facet'
			);
			Assert.areEqual(
				shape.personAccountRecordTypeIds,
				OrgShapeDetector.personAccountRecordTypeIds(),
				'And the person types'
			);
		}
	}
}
