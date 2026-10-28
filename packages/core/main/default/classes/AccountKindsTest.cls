/**
 * Tests for AccountKinds: which accounts are organizations, and how the record type for them
 * is detected and stored (canonical model R-O4, R-O5, ADR-NEXT).
 *
 * The detection order is tested on injected candidates, so it does not depend on which
 * record types the test org has. The rest reads the org's own record types and holds in any
 * shape: with none to offer, the answer is No record type (Master).
 */
@IsTest(testFor='ApexClass:AccountKinds')
private class AccountKindsTest {
    private static final String KEY = AccountKinds.KEY_ORGANIZATION_RECORD_TYPE;

    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static AccountKinds.Candidate candidate(String name, String label, Boolean inUse) {
        return new AccountKinds.Candidate(name, label, inUse);
    }

    private static void store(String value) {
        // A stale value cannot be saved through SettingsService, so the record is written as
        // the platform would hold it.
        insert as system new BarnCRM_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Organization_Record_Type__c = value
        );
    }

    @IsTest
    static void noCandidateMeansNoRecordType() {
        System.runAs(TestUsers.admin()) {
            Assert.areEqual(
                AccountKinds.NO_RECORD_TYPE,
                AccountKinds.rank(new List<AccountKinds.Candidate>()),
                'An org with no Account record type to offer uses No record type.'
            );
        }
    }

    @IsTest
    static void aRecordTypeAccountsUseComesBeforeAPreferredName() {
        System.runAs(TestUsers.admin()) {
            String chosen = AccountKinds.rank(
                new List<AccountKinds.Candidate>{
                    candidate('Organization', 'Organization', false),
                    candidate('Vendor', 'Vendor', true)
                }
            );
            Assert.areEqual(
                'Vendor',
                chosen,
                'A record type already in use wins over an empty Organization (mwdbdevsb).'
            );
        }
    }

    @IsTest
    static void preferredNamesAreWeighedInOrder() {
        System.runAs(TestUsers.admin()) {
            List<AccountKinds.Candidate> pool = new List<AccountKinds.Candidate>{
                candidate('Default', 'Default', false),
                candidate('Business', 'Business', false),
                candidate('Business_Account', 'Business Account', false),
                candidate('Organization', 'Organization', false),
                candidate('Alpha', 'Alpha', false)
            };
            Assert.areEqual('Organization', AccountKinds.rank(pool), 'Organization first.');
            pool.remove(3);
            Assert.areEqual('Business_Account', AccountKinds.rank(pool), 'Then Business Account.');
            pool.remove(2);
            Assert.areEqual('Business', AccountKinds.rank(pool), 'Then Business.');
            pool.remove(1);
            Assert.areEqual('Default', AccountKinds.rank(pool), 'Then Default.');
        }
    }

    @IsTest
    static void withoutAPreferredNameTheFirstByLabelIsPicked() {
        System.runAs(TestUsers.admin()) {
            String chosen = AccountKinds.rank(
                new List<AccountKinds.Candidate>{
                    candidate('Zed_Type', 'Zeta', false),
                    candidate('Other_Type', 'alpha', false)
                }
            );
            Assert.areEqual('Other_Type', chosen, 'The first by label, ignoring case.');
        }
    }

    @IsTest
    static void householdAndPersonRecordTypesAreNeverOffered() {
        System.runAs(TestUsers.admin()) {
            Assert.isFalse(AccountKinds.isOffered('Household', 'Household', false), 'By name.');
            Assert.isFalse(
                AccountKinds.isOffered('HH_Account', 'Household Account', false),
                'By label.'
            );
            Assert.isFalse(
                AccountKinds.isOffered('Individual_Type', 'Individual', true),
                'Person.'
            );
            Assert.isTrue(AccountKinds.isOffered('Business', 'Business', false), 'A business one.');

            Set<Id> personTypes = OrgShapeDetector.personRecordTypeIds();
            for (Schema.RecordTypeInfo info : AccountKinds.candidateRecordTypes()) {
                Assert.isTrue(info.isActive() && !info.isMaster(), 'Only active real ones.');
                Assert.isFalse(
                    personTypes.contains(info.getRecordTypeId()),
                    'Never a person type.'
                );
                Assert.isFalse(
                    info.getDeveloperName().toLowerCase().contains('household'),
                    'Never a household type.'
                );
            }
            Assert.isFalse(AccountKinds.isCandidate('Household'), 'BarnCRM Household is refused.');
        }
    }

    @IsTest
    static void storedNoRecordTypeMakesAccountsWithoutOneOrganizations() {
        System.runAs(TestUsers.admin()) {
            store(AccountKinds.NO_RECORD_TYPE);

            Assert.areEqual(
                AccountKinds.NO_RECORD_TYPE,
                AccountKinds.organizationRecordTypeName(),
                'Stored wins.'
            );
            Assert.isNull(
                AccountKinds.organizationRecordTypeId(),
                'A new organization gets no record type.'
            );
            Assert.isTrue(
                AccountKinds.isOrganization(null),
                'An account with none is an organization.'
            );
            Id household = HouseholdService.householdRecordTypeId();
            if (household != null) {
                Assert.isFalse(AccountKinds.isOrganization(household), 'A household never is.');
            }
        }
    }

    @IsTest
    static void aStoredCandidateIsTheOrganizationRecordType() {
        System.runAs(TestUsers.admin()) {
            List<Schema.RecordTypeInfo> offered = AccountKinds.candidateRecordTypes();
            if (offered.isEmpty()) {
                Assert.areEqual(
                    AccountKinds.NO_RECORD_TYPE,
                    AccountKinds.organizationRecordTypeName(),
                    'None.'
                );
                return;
            }
            Schema.RecordTypeInfo chosen = offered[offered.size() - 1];
            store(chosen.getDeveloperName());

            Assert.areEqual(
                chosen.getDeveloperName(),
                AccountKinds.organizationRecordTypeName(),
                'Stored wins.'
            );
            Assert.areEqual(
                chosen.getRecordTypeId(),
                AccountKinds.organizationRecordTypeId(),
                'Its Id.'
            );
            Assert.isTrue(
                AccountKinds.isOrganization(chosen.getRecordTypeId()),
                'Its accounts are organizations.'
            );
            Assert.isFalse(AccountKinds.isOrganization(null), 'An account with none is not.');
        }
    }

    @IsTest
    static void aStoredRecordTypeThatIsGoneFallsBackToDetection() {
        System.runAs(TestUsers.admin()) {
            store('No_Such_Record_Type_Rt3');
            AccountKinds.candidatesOverride = new List<AccountKinds.Candidate>{
                candidate('Business', 'Business', false)
            };

            Assert.areEqual(
                AccountKinds.detectOrganizationRecordType(),
                AccountKinds.organizationRecordTypeName(),
                'A stale value is read as the detected one, never as blank.'
            );
            Assert.areEqual('Business', AccountKinds.detectOrganizationRecordType(), 'Detected.');
        }
    }

    @IsTest
    static void installStoresTheDetectedValueOnceAndNeverOverwrites() {
        System.runAs(TestUsers.admin()) {
            AccountKinds.candidatesOverride = new List<AccountKinds.Candidate>();

            Test.startTest();
            AccountKinds.storeDetectedIfBlank();
            Assert.areEqual(
                AccountKinds.NO_RECORD_TYPE,
                BarnCRM_Settings__c.getOrgDefaults().Organization_Record_Type__c,
                'Blank is filled with the detected value.'
            );
            AccountKinds.reset();
            AccountKinds.candidatesOverride = new List<AccountKinds.Candidate>{
                candidate('Business', 'Business', true)
            };
            AccountKinds.storeDetectedIfBlank();
            Test.stopTest();

            Assert.areEqual(
                AccountKinds.NO_RECORD_TYPE,
                BarnCRM_Settings__c.getOrgDefaults().Organization_Record_Type__c,
                'A stored value is never overwritten.'
            );
        }
    }
}
