/**
 * Tests for AccountKinds: which accounts are organizations, and how the record type for them
 * is detected and stored (canonical model R-O4, R-O5, ADR-0141).
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
            Assert.isTrue(
                AccountKinds.organizationRecordTypeUsable(),
                'Every user can create an organization with no record type.'
            );
            Assert.isTrue(AccountKinds.isOrganizationRecordTypeName(null), 'By name: none.');
            Assert.isTrue(AccountKinds.isOrganizationRecordTypeName('Master'), 'The master.');
            Assert.isFalse(AccountKinds.isOrganizationRecordTypeName('Household'), 'Not one.');
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
            Assert.isTrue(
                AccountKinds.isOrganizationRecordTypeName(chosen.getDeveloperName()),
                'By name: the chosen one.'
            );
            Assert.isFalse(AccountKinds.isOrganizationRecordTypeName(null), 'By name: none.');
        }
    }

    /**
     * Whatever this org's record types and the test user's profile, the test data leaves a
     * record type for organizations the user can save, so tests pass on any org shape.
     */
    @IsTest
    static void testDataLeavesARecordTypeTheUserCanUse() {
        System.runAs(TestUsers.admin()) {
            AccountKindsTestData.useRecordTypeTheUserCanUse();

            Assert.isTrue(AccountKinds.organizationRecordTypeUsable(), 'Usable now.');
            Account organization = AccountKindsTestData.organization('Zztest Usable Org');
            insert organization;
            Account read = [
                SELECT RecordTypeId
                FROM Account
                WHERE Id = :organization.Id
                WITH SYSTEM_MODE
            ];
            Assert.isTrue(
                AccountKinds.isOrganization(read.RecordTypeId),
                'And what it creates is an organization.'
            );
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
    static void theIsOrganizationFieldFollowsTheSetting() {
        System.runAs(TestUsers.admin()) {
            store(AccountKinds.organizationRecordTypeName());
            Account organization = AddressTestDataFactory.newOrganization('Zztest Formula Org');
            Account household = HouseholdTestDataFactory.newHousehold('The Zztest Family');
            Database.insert(new List<Account>{ organization, household }, AccessLevel.SYSTEM_MODE);

            Set<Id> ids = new Set<Id>{ organization.Id, household.Id };
            Map<Id, Account> read = new Map<Id, Account>(
                [SELECT Id, Is_Organization__c FROM Account WHERE Id IN :ids WITH SYSTEM_MODE]
            );
            Assert.isTrue(
                read.get(organization.Id).Is_Organization__c,
                'An account of the chosen record type is an organization.'
            );
            Assert.isFalse(read.get(household.Id).Is_Organization__c, 'A household never is.');
        }
    }

    /**
     * With No record type stored, an account saved without one and an account saved with the
     * master record type Id are read the same way by the formula field and by AccountKinds.
     * The org's own stored value is never read: this test stores its own.
     */
    @IsTest
    static void noRecordTypeAgreesBetweenTheFieldAndTheResolver() {
        System.runAs(TestUsers.admin()) {
            store(AccountKinds.NO_RECORD_TYPE);
            Id masterId;
            for (Schema.RecordTypeInfo info : Schema.SObjectType.Account.getRecordTypeInfos()) {
                if (info.isMaster()) {
                    masterId = info.getRecordTypeId();
                }
            }
            Account blank = (Account) TestDataFactory.pastDuplicateRules(
                new Account(Name = 'Zztest Rt5 No Record Type')
            );
            Account master = (Account) TestDataFactory.pastDuplicateRules(
                new Account(Name = 'Zztest Rt5 Master', RecordTypeId = masterId)
            );
            Account household = HouseholdTestDataFactory.newHousehold('The Zztest Rt5 Family');
            List<Account> accounts = new List<Account>{ blank, household };
            Database.insert(accounts, AccessLevel.SYSTEM_MODE);
            // The platform refuses the master record type Id for a user who can use any other
            // record type (INVALID_CROSS_REFERENCE_KEY), so this account exists only in an org
            // shape where it is accepted; when it is, it must be read the same way.
            if (Database.insert(master, false, AccessLevel.SYSTEM_MODE).isSuccess()) {
                accounts.add(master);
            }

            Map<Id, Schema.RecordTypeInfo> byId = Schema.SObjectType.Account.getRecordTypeInfosById();
            for (Account read : [
                SELECT Id, Name, RecordTypeId, Is_Organization__c
                FROM Account
                WHERE Id IN :accounts
                WITH SYSTEM_MODE
            ]) {
                Assert.areEqual(
                    AccountKinds.isOrganization(read.RecordTypeId),
                    read.Is_Organization__c,
                    'The field and the resolver agree for ' + read.Name + '.'
                );
                Schema.RecordTypeInfo info = read.RecordTypeId == null
                    ? null
                    : byId.get(read.RecordTypeId);
                if (read.Id == household.Id) {
                    Assert.isFalse(read.Is_Organization__c, 'A household never is.');
                } else if (info == null || info.isMaster()) {
                    // Saved with no record type, or the master's. An account saved without one
                    // takes the running user's default record type when the user has one,
                    // and is then rightly not an organization.
                    Assert.isTrue(read.Is_Organization__c, read.Name + ' is an organization.');
                }
            }
        }
    }

    /** A stored record type that is no longer a candidate is replaced on the next install. */
    @IsTest
    static void installReplacesAStoredRecordTypeThatIsNoLongerACandidate() {
        System.runAs(TestUsers.admin()) {
            store('No_Such_Record_Type_Rt5');

            Test.startTest();
            AccountKinds.storeDetectedIfBlank();
            Test.stopTest();

            String stored = BarnCRM_Settings__c.getOrgDefaults().Organization_Record_Type__c;
            Assert.areEqual(
                AccountKinds.detectOrganizationRecordType(),
                stored,
                'The stale value is replaced by the detected one.'
            );
            Assert.isTrue(
                AccountKinds.NO_RECORD_TYPE.equals(stored) || AccountKinds.isCandidate(stored),
                'What is stored now is usable, so the field and the resolver agree.'
            );
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
            AccountKinds.candidatesOverride = new List<AccountKinds.Candidate>();
            AccountKinds.storeDetectedIfBlank();
            Test.stopTest();

            Assert.areEqual(
                AccountKinds.NO_RECORD_TYPE,
                BarnCRM_Settings__c.getOrgDefaults().Organization_Record_Type__c,
                'A usable stored value is never overwritten.'
            );
        }
    }

    @IsTest
    static void noRecordTypeIsAllowedOnlyWithoutACandidate() {
        System.runAs(TestUsers.admin()) {
            AccountKinds.candidatesOverride = new List<AccountKinds.Candidate>();
            Assert.isTrue(AccountKinds.noRecordTypeAllowed(), 'No candidate: it works.');
            AccountKinds.candidatesOverride = new List<AccountKinds.Candidate>{
                candidate('Business', 'Business', false)
            };
            Assert.isFalse(AccountKinds.noRecordTypeAllowed(), 'A candidate: it never does.');
            AccountKinds.reset();
            Assert.areEqual(
                AccountKinds.candidateRecordTypes().isEmpty(),
                AccountKinds.noRecordTypeAllowed(),
                'In this org, it follows its own record types.'
            );
        }
    }

    /**
     * A stored No record type in an org with a candidate is stale: the next install stores the
     * detected candidate. In an org with none it stays. The org's own stored value is not read.
     */
    @IsTest
    static void installReplacesNoRecordTypeWhereACandidateExists() {
        System.runAs(TestUsers.admin()) {
            store(AccountKinds.NO_RECORD_TYPE);
            Boolean hasCandidate = !AccountKinds.candidateRecordTypes().isEmpty();

            Test.startTest();
            AccountKinds.storeDetectedIfBlank();
            Test.stopTest();

            String stored = BarnCRM_Settings__c.getOrgDefaults().Organization_Record_Type__c;
            if (hasCandidate) {
                Assert.isTrue(AccountKinds.isCandidate(stored), 'A candidate replaced it.');
                Assert.areEqual(
                    AccountKinds.detectOrganizationRecordType(),
                    stored,
                    'The detected one.'
                );
            } else {
                Assert.areEqual(AccountKinds.NO_RECORD_TYPE, stored, 'Kept where it works.');
            }
        }
    }
}
