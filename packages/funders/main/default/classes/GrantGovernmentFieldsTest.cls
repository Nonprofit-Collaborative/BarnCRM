/**
 * The government award fields on a grant (F-04, canonical model 29ZH R-GN8): Funders Staff record
 * them, and the Assistance Listing Number, Indirect Cost Rate and Match Required are checked.
 */
@IsTest
private class GrantGovernmentFieldsTest {
    private static final String STAFF = 'Funders_Staff';

    @TestSetup
    static void createTestUsers() {
        TestUsers.adminWith(STAFF);
    }

    private static Grant__c federalGrant() {
        Account funder = GrantTestData.funder('State Education Agency');
        Grant__c grant = GrantTestData.grant('Afterschool', funder.Id, GrantService.STAGE_AWARDED);
        grant.Funding_Source__c = 'Federal Pass-Through';
        grant.Assistance_Listing_Number__c = '84.287';
        grant.Award_Number__c = 'S287C250001';
        grant.Federal_Agency__c = 'Department of Education';
        grant.Indirect_Cost_Rate__c = 15;
        grant.Match_Required__c = 5000;
        return grant;
    }

    private static String refusal(Grant__c grant) {
        Database.SaveResult result = Database.update(grant, false, AccessLevel.USER_MODE);
        return result.isSuccess() ? null : result.getErrors()[0].getMessage();
    }

    @IsTest
    static void staffRecordTheGovernmentAwardFields() {
        System.runAs(TestUsers.adminWith(STAFF)) {
            Grant__c grant = federalGrant();

            Test.startTest();
            insert as user grant;
            Test.stopTest();

            Grant__c saved = [
                SELECT
                    Funding_Source__c,
                    Assistance_Listing_Number__c,
                    Award_Number__c,
                    Federal_Agency__c,
                    Indirect_Cost_Rate__c,
                    Match_Required__c
                FROM Grant__c
                WHERE Id = :grant.Id
                WITH SYSTEM_MODE
            ];
            Assert.areEqual('Federal Pass-Through', saved.Funding_Source__c, 'Funding source');
            Assert.areEqual('84.287', saved.Assistance_Listing_Number__c, 'Listing number');
            Assert.areEqual('S287C250001', saved.Award_Number__c, 'Award number');
            Assert.areEqual('Department of Education', saved.Federal_Agency__c, 'Agency');
            Assert.areEqual(15, saved.Indirect_Cost_Rate__c, 'Rate, in percent');
            Assert.areEqual(5000, saved.Match_Required__c, 'Match');
        }
    }

    @IsTest
    static void badGovernmentAwardValuesAreRefused() {
        System.runAs(TestUsers.adminWith(STAFF)) {
            Grant__c grant = federalGrant();
            insert as user grant;

            Test.startTest();
            grant.Assistance_Listing_Number__c = '84287';
            String badListing = refusal(grant);
            grant.Assistance_Listing_Number__c = '93.U01';
            String letters = refusal(grant);
            grant.Indirect_Cost_Rate__c = 120;
            String badRate = refusal(grant);
            grant.Indirect_Cost_Rate__c = 0;
            grant.Match_Required__c = -1;
            String badMatch = refusal(grant);
            Test.stopTest();

            Assert.isTrue(badListing.contains('84.287'), 'Listing format refused: ' + badListing);
            Assert.isNull(letters, 'A listing with capital letters is a real format');
            Assert.isTrue(badRate.contains('0 to 100'), 'Rate above 100 refused: ' + badRate);
            Assert.isTrue(badMatch.contains('negative'), 'Negative match refused: ' + badMatch);
        }
    }
}
