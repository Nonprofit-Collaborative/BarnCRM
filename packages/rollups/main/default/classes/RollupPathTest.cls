/**
 * The path notation of canonical model R-R1, read.
 *
 * These tests have not been executed: no Salesforce org exists in this environment.
 */
@IsTest(testFor='ApexClass:RollupPath')
private class RollupPathTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.adminWith('Rollup_Builder_Admin');
    }

    @IsTest
    static void oneReferenceAttributeIsOneHop() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            RollupPath.Parsed parsed = RollupPath.parse('Household__c');

            System.Assert.areEqual(1, parsed.branches.size(), 'One alternative');
            System.Assert.areEqual(1, parsed.onlyBranch().segments.size(), 'One segment');
            System.Assert.isFalse(
                parsed.needsHouseholdResolution(),
                'A plain lookup needs no membership lookup'
            );
            System.Assert.areEqual(
                '',
                RollupPath.toGrandparentFieldPath(parsed.onlyBranch()),
                'One hop is not a chain'
            );
        }
    }

    @IsTest
    static void twoReferenceAttributesBecomeARelationshipChain() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            RollupPath.Parsed parsed = RollupPath.parse('Gift_Allocation__c > Gift__c');

            System.Assert.areEqual(
                'Gift_Allocation__r.Gift__r.Id',
                RollupPath.toGrandparentFieldPath(parsed.onlyBranch()),
                'Custom references walk as their relationship names and the chain ends at the parent id'
            );
        }
    }

    @IsTest
    static void alternativesAreKeptInTheOrderTheyWereWritten() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            RollupPath.Parsed parsed = RollupPath.parse('Household__c | Donor_Account__c');

            System.Assert.areEqual(2, parsed.branches.size(), 'Two alternatives');
            System.Assert.areEqual(
                'Household__c',
                parsed.branches[0].segments[0],
                'The first alternative is tried first'
            );
            System.Assert.areEqual(
                'Donor_Account__c',
                parsed.branches[1].segments[0],
                'Then the second'
            );
        }
    }

    @IsTest
    static void aModeResolvedTokenIsNotARelationship() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            RollupPath.Parsed parsed = RollupPath.parse('Donor_Contact__c > {Household}');

            System.Assert.isTrue(
                parsed.needsHouseholdResolution(),
                'The household token is resolved, not walked'
            );
            System.Assert.areEqual(
                new List<String>{ 'Donor_Contact__c' },
                parsed.onlyBranch().referencePrefix(),
                'The reference before the token is what reaches the person'
            );
        }
    }

    @IsTest
    static void bothTokensAreRecognised() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            System.Assert.isTrue(RollupPath.isToken('{Household}'), 'The household token');
            System.Assert.isTrue(RollupPath.isToken('{HouseholdMembers}'), 'The members token');
            System.Assert.isFalse(RollupPath.isToken('Household__c'), 'A field is not a token');
        }
    }

    @IsTest
    static void standardAndCustomReferencesWalkTheirOwnWay() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            System.Assert.areEqual(
                'Account',
                RollupPath.relationshipNameFor('AccountId'),
                'A standard reference drops Id'
            );
            System.Assert.areEqual(
                'Donor_Contact__r',
                RollupPath.relationshipNameFor('Donor_Contact__c'),
                'A custom reference swaps __c for __r'
            );
        }
    }

    @IsTest
    static void anythingThatIsNotAnAttributeOrATokenIsRefused() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            try {
                RollupPath.parse('Account.Name > Something');
                System.Assert.fail('A dotted name is not a segment');
            } catch (RollupPath.RollupPathException expected) {
                System.Assert.isNotNull(expected.getMessage(), 'The message names the problem');
            }
            try {
                RollupPath.parse('   ');
                System.Assert.fail('A blank path reaches nothing');
            } catch (RollupPath.RollupPathException expected) {
                System.Assert.isNotNull(expected.getMessage(), 'The message names the problem');
            }
        }
    }
}
