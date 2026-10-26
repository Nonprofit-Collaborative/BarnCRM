/**
 * A new Giving org starts with one default fund, and an org that has already decided is never
 * touched: not one with a fund of its own, not one whose Default Fund is set, and not on the
 * second run.
 */
@IsTest(testFor='ApexClass:FundDefaultsService')
private class FundDefaultsServiceTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.adminWith('Giving_Admin');
    }

    @IsTest
    static void anEmptyOrgGetsAGeneralFundThatIsTheDefault() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Test.startTest();
            Test.testInstall(new GivingPostInstall(), null);
            Test.stopTest();

            List<Fund__c> funds = allFunds();
            Assert.areEqual(1, funds.size(), 'A new org starts with exactly one fund.');
            Fund__c fund = funds[0];
            Assert.areEqual(Label.Giving_Fund_DefaultName, fund.Name, 'Named by the label.');
            Assert.areEqual('General Fund', fund.Name, 'The label reads General Fund.');
            Assert.isTrue(fund.Active__c, 'It is offered on new gifts.');
            Assert.isFalse(fund.Restricted__c, 'It is unrestricted money.');
            Assert.isTrue(fund.Is_Default__c, 'It catches undesignated gifts.');
            Assert.isNull(
                fund.Accounting_Code__c,
                'The accounting code is the organization to set.'
            );
            Assert.areEqual(
                String.valueOf(fund.Id),
                Giving_Settings__c.getOrgDefaults().Default_Fund__c,
                'Giving settings name it as the Default Fund, so the setting is never blank.'
            );
            Assert.areEqual(
                fund.Id,
                GiftService.resolveDefaultFundId(),
                'A gift entered without a fund now has somewhere to go.'
            );
        }
    }

    @IsTest
    static void anOrgWithAFundOfItsOwnGetsNothingAdded() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            // An inactive, non-default fund still counts: the org has made its own choices.
            Fund__c mine = GivingTestDataFactory.buildFund('Scholarship', false);
            mine.Active__c = false;
            insert mine;

            Test.startTest();
            Fund__c created = FundDefaultsService.installDefaultFundDuringInstall(null);
            Test.stopTest();

            Assert.isNull(created, 'Nothing is created beside an existing fund.');
            Assert.areEqual(1, allFunds().size(), 'Only the org\'s own fund exists.');
            Assert.isNull(
                Giving_Settings__c.getOrgDefaults().Default_Fund__c,
                'The Default Fund setting is not filled in on the org\'s behalf.'
            );
        }
    }

    @IsTest
    static void aDefaultFundAlreadySetIsLeftAlone() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            String chosen = '001000000000000AAA';
            insert new Giving_Settings__c(
                SetupOwnerId = UserInfo.getOrganizationId(),
                Default_Fund__c = chosen
            );

            Test.startTest();
            Fund__c created = FundDefaultsService.installDefaultFundDuringInstall(null);
            Test.stopTest();

            Assert.isNull(created, 'No fund is created when a default is already chosen.');
            Assert.isTrue(allFunds().isEmpty(), 'No fund appears.');
            Assert.areEqual(
                chosen,
                Giving_Settings__c.getOrgDefaults().Default_Fund__c,
                'The chosen default is unchanged.'
            );
        }
    }

    @IsTest
    static void runningItAgainDoesNotAddASecondFund() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            GivingPostInstall handler = new GivingPostInstall();
            Test.testInstall(handler, null);
            Id first = allFunds()[0].Id;

            Test.startTest();
            Test.testInstall(handler, new Version(1, 0), true);
            Fund__c again = FundDefaultsService.ensureDefaultFund();
            Test.stopTest();

            Assert.isNull(again, 'The service reports nothing created.');
            List<Fund__c> funds = allFunds();
            Assert.areEqual(1, funds.size(), 'There is still one fund.');
            Assert.areEqual(first, funds[0].Id, 'It is the same fund.');
        }
    }

    @IsTest
    static void aFundTheAdminRenamedOrUntickedAsDefaultIsNotRecreated() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Test.testInstall(new GivingPostInstall(), null);
            Fund__c fund = allFunds()[0];
            fund.Name = 'Annual Fund';
            fund.Is_Default__c = false;
            update fund;

            Test.startTest();
            Test.testInstall(new GivingPostInstall(), new Version(1, 0), true);
            Test.stopTest();

            List<Fund__c> funds = allFunds();
            Assert.areEqual(1, funds.size(), 'An upgrade does not bring General Fund back.');
            Assert.areEqual('Annual Fund', funds[0].Name, 'The administrator\'s edit stands.');
        }
    }

    private static List<Fund__c> allFunds() {
        return [
            SELECT Id, Name, Active__c, Restricted__c, Is_Default__c, Accounting_Code__c
            FROM Fund__c
            WITH SYSTEM_MODE
        ];
    }
}
