/**
 * The queries the rest of the package is built on. Every one of them runs in user mode, so a
 * test that passes here is a query a user is allowed to run.
 */
@IsTest
private class GivingSelectorTest {
    @TestSetup
    static void makeData() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            GivingTestDataFactory.insertDefaultFund();
            GivingTestDataFactory.insertHouseholdContact('The Nolan Family', 'Ana', 'Nolan');
        }
    }

    @IsTest
    static void giftsAreReadWithTheirAllocations() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact person = [SELECT Id FROM Contact LIMIT 1];
            Gift__c gift = GivingTestDataFactory.buildGift(person.Id, 120);
            insert gift;

            Test.startTest();
            List<Gift__c> withAllocations = GiftSelector.selectWithAllocations(
                new Set<Id>{ gift.Id }
            );
            Map<Id, Gift__c> amounts = GiftSelector.selectAmountsById(new Set<Id>{ gift.Id });
            List<Gift__c> plain = GiftSelector.selectById(new Set<Id>{ gift.Id });
            Test.stopTest();

            System.assertEquals(1, withAllocations.size(), 'The gift comes back.');
            System.assertEquals(
                1,
                withAllocations[0].Gift_Allocations__r.size(),
                'With the default allocation it was given.'
            );
            System.assertEquals(120, amounts.get(gift.Id).Amount__c, 'And its amount.');
            System.assertEquals(gift.Id, plain[0].Id, 'And by identifier alone.');
        }
    }

    @IsTest
    static void fundsAndAppealsAreReadByIdentifier() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Fund__c fund = [SELECT Id FROM Fund__c LIMIT 1];
            Appeal__c appeal = GivingTestDataFactory.buildAppeal('Spring appeal');
            insert appeal;

            Test.startTest();
            List<Fund__c> funds = FundSelector.selectById(new Set<Id>{ fund.Id });
            List<Appeal__c> appeals = AppealSelector.selectById(new Set<Id>{ appeal.Id });
            Map<Id, Id> parents = AppealSelector.selectParentsById(new Set<Id>{ appeal.Id });
            Test.stopTest();

            System.assertEquals(1, funds.size(), 'The fund comes back.');
            System.assertEquals(1, appeals.size(), 'The appeal comes back.');
            System.assertEquals(null, parents.get(appeal.Id), 'With no parent above it.');
        }
    }

    @IsTest
    static void allocationsAreCountedByFund() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact person = [SELECT Id FROM Contact LIMIT 1];
            Fund__c fund = [SELECT Id FROM Fund__c LIMIT 1];
            insert GivingTestDataFactory.buildGifts(person.Id, 3, 10);

            Test.startTest();
            Map<Id, Integer> counts = GiftAllocationSelector.countByFundIds(new Set<Id>{ fund.Id });
            List<Gift_Allocation__c> allocations = GiftAllocationSelector.selectById(
                new Map<Id, Gift_Allocation__c>([SELECT Id FROM Gift_Allocation__c]).keySet()
            );
            Test.stopTest();

            System.assertEquals(3, counts.get(fund.Id), 'Three gifts landed in the default fund.');
            System.assertEquals(3, allocations.size(), 'And three allocations are readable.');
        }
    }

    @IsTest
    static void recordTypeNamesAreReadWithoutAskingWhetherAPersonIsAnAccount() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Account organization = GivingTestDataFactory.insertOrganization('Riverside Foundation');

            Test.startTest();
            Map<Id, String> names = GivingAccountSelector.selectRecordTypeNamesById(
                new Set<Id>{ organization.Id }
            );
            Map<Id, String> nothing = GivingAccountSelector.selectRecordTypeNamesById(
                new Set<Id>()
            );
            Test.stopTest();

            System.assert(
                names.get(organization.Id) == null || names.get(organization.Id) != 'Household',
                'An organization is not a household.'
            );
            System.assertEquals(0, nothing.size(), 'Asking about nothing costs no query.');
        }
    }
}
