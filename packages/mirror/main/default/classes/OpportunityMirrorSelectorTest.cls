/**
 * The queries behind the Opportunity mirror (X-01), read straight from the selector: what each
 * returns for no input, for a gift or appeal it should find and for a record it should not. These
 * hold in an org of any shape. The person-account queries run in full only where the org stores
 * people as accounts; elsewhere they prove the empty answer (plan Section 4.2, ADR-0013).
 */
@IsTest(testFor='ApexClass:OpportunityMirrorSelector')
private class OpportunityMirrorSelectorTest {
    private static final String LINKED_ID = '006000000000001AAA';
    private static final String OTHER_ID = '006000000000002AAA';
    private static final String CAMPAIGN_ID = '701000000000001AAA';

    @TestSetup
    static void setup() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            GivingTestDataFactory.ensureDefaultFund();
            GivingTestDataFactory.insertHouseholdContact('The Garcia Household', 'Luis', 'Garcia');
        }
    }

    // The queries run in user mode: the person running them needs the link field's access.
    private static User userWith(String mirrorPermissionSet) {
        return TestDataFactory.createUserOnTheRunningUsersProfile(
            'Maria',
            new List<String>{ 'Giving_Admin', mirrorPermissionSet }
        );
    }

    @IsTest
    static void noInputReturnsNothingAndRunsNoQuery() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Set<Id> someId = new Set<Id>{ UserInfo.getUserId() };
            List<String> idField = new List<String>{ 'Id' };
            Test.startTest();
            Assert.isTrue(
                OpportunityMirrorSelector.opportunitiesById(null, idField, someId).isEmpty(),
                'No Opportunity object, so no Opportunities.'
            );
            Assert.isTrue(
                OpportunityMirrorSelector.opportunitiesById('Pledge__x', idField, null).isEmpty(),
                'No identifiers, so no Opportunities.'
            );
            Assert.isTrue(
                OpportunityMirrorSelector.primaryRolesByOpportunity(null, someId).isEmpty(),
                'No role object, so no roles.'
            );
            Assert.isTrue(
                OpportunityMirrorSelector.primaryRolesByOpportunity('PledgeRole__x', new Set<Id>())
                    .isEmpty(),
                'No Opportunities, so no roles.'
            );
            Assert.isTrue(
                OpportunityMirrorSelector.namesById(null, null).isEmpty(),
                'No one to name.'
            );
            Assert.isTrue(
                OpportunityMirrorSelector.namesById(new Set<Id>(), new Set<Id>()).isEmpty(),
                'Empty sets name no one.'
            );
            Assert.isTrue(
                OpportunityMirrorSelector.personContactIds(null).isEmpty(),
                'No accounts.'
            );
            Assert.isTrue(
                OpportunityMirrorSelector.personContactIds(new Set<Id>()).isEmpty(),
                'Empty accounts.'
            );
            Assert.isTrue(
                OpportunityMirrorSelector.personAccountByContact(null).isEmpty(),
                'No contacts.'
            );
            Assert.isTrue(
                OpportunityMirrorSelector.personAccountByContact(new Set<Id>()).isEmpty(),
                'Empty contacts.'
            );
            Assert.isTrue(
                OpportunityMirrorSelector.linkedOpportunityIds(null).isEmpty(),
                'No identifiers.'
            );
            Assert.isTrue(
                OpportunityMirrorSelector.linkedOpportunityIds(new Set<String>()).isEmpty(),
                'Empty identifiers.'
            );
            Assert.isTrue(
                OpportunityMirrorSelector.appealIdsByCampaignId(null).isEmpty(),
                'No Campaigns.'
            );
            Assert.isTrue(
                OpportunityMirrorSelector.appealIdsByCampaignId(new Set<String>()).isEmpty(),
                'Empty Campaigns.'
            );
            Test.stopTest();
        }
    }

    @IsTest
    static void theGiftQueryChangesWithTheRunAndTheLastRunFilter() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            assertGiftQueries();
        }
    }

    private static void assertGiftQueries() {
        String uncopied = OpportunityMirrorSelector.giftsToCopyQuery(false);
        Assert.areEqual(
            OpportunityMirrorSelector.giftsToCopyQuery(false, false),
            uncopied,
            'One argument means no last-run filter.'
        );
        Assert.isTrue(uncopied.contains('Opportunity_Id__c = NULL'), 'Gifts with no Opportunity.');
        Assert.isFalse(uncopied.contains(':since'), 'No last-run filter.');
        Assert.isFalse(uncopied.contains(':fromDate'), 'No range.');
        Assert.isTrue(
            OpportunityMirrorSelector.giftsToCopyQuery(false, true)
                .contains('LastModifiedDate >= :since'),
            'Linked gifts changed since the last run.'
        );
        String ranged = OpportunityMirrorSelector.giftsToCopyQuery(true);
        Assert.isTrue(ranged.contains('Gift_Date__c >= :fromDate'), 'Dated in the range.');
        Assert.isTrue(ranged.contains('Opportunity_Id__c != NULL'), 'Linked gifts are in a range.');
        Assert.isFalse(ranged.contains(':since'), 'A range has no last-run filter.');
        Assert.isTrue(ranged.endsWith('ORDER BY Gift_Date__c, Id'), 'Oldest first.');
    }

    @IsTest
    static void theWonQueryFiltersByRecordTypeOnlyWhenAsked() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            List<String> fields = new List<String>{ 'Id', 'Name' };
            String object1 = 'Pledge__x'; // only named in text: the query is never run
            String all = OpportunityMirrorSelector.wonOpportunitiesQuery(object1, fields, false);
            String typed = OpportunityMirrorSelector.wonOpportunitiesQuery(object1, fields, true);
            Assert.isFalse(all.contains('RecordTypeId'), 'Every record type.');
            Assert.isTrue(typed.contains('RecordTypeId IN :recordTypeIds'), 'Only chosen types.');
            Assert.isTrue(
                all.startsWith('SELECT Id, Name FROM ' + object1 + ' WHERE IsWon'),
                'Won.'
            );
            Assert.isTrue(typed.endsWith('ORDER BY CloseDate, Id'), 'Oldest first.');
        }
    }

    @IsTest
    static void linkedOpportunityIdsAreThoseNamedByAGift() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact luis = [SELECT Id FROM Contact WHERE LastName = 'Garcia' LIMIT 1];
            Gift__c linked = GivingTestDataFactory.buildGift(luis.Id, 25);
            linked.Opportunity_Id__c = LINKED_ID;
            Database.insert(linked, AccessLevel.SYSTEM_MODE);
            Set<String> found;
            Test.startTest();
            System.runAs(userWith('Opportunity_Mirror')) {
                found = OpportunityMirrorSelector.linkedOpportunityIds(
                    new Set<String>{ LINKED_ID, OTHER_ID }
                );
            }
            Test.stopTest();
            Assert.areEqual(new Set<String>{ LINKED_ID }, found, 'Only the one a gift names.');
        }
    }

    @IsTest
    static void anAppealIsFoundByItsCampaign() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Appeal__c appeal = GivingTestDataFactory.buildAppeal('Year-End Appeal');
            appeal.Campaign_Id__c = CAMPAIGN_ID;
            Database.insert(appeal, AccessLevel.SYSTEM_MODE);
            Map<String, Id> found;
            Test.startTest();
            System.runAs(userWith('Campaign_Sync')) {
                found = OpportunityMirrorSelector.appealIdsByCampaignId(
                    new Set<String>{ CAMPAIGN_ID, '701000000000002AAA' }
                );
            }
            Test.stopTest();
            Assert.areEqual(1, found.size(), 'Only the Campaign an appeal names.');
            Assert.areEqual(appeal.Id, found.get(CAMPAIGN_ID), 'The appeal behind it.');
        }
    }

    @IsTest
    static void aPlainContactAndAPlainAccountHoldNoPerson() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact luis = [SELECT Id, AccountId FROM Contact WHERE LastName = 'Garcia' LIMIT 1];
            Test.startTest();
            Map<Id, Id> contactsByAccount = OpportunityMirrorSelector.personContactIds(
                new Set<Id>{ luis.AccountId }
            );
            Map<Id, Id> accountsByContact = OpportunityMirrorSelector.personAccountByContact(
                new Set<Id>{ luis.Id }
            );
            Test.stopTest();
            Assert.isTrue(contactsByAccount.isEmpty(), 'A household is not a person account.');
            Assert.isTrue(accountsByContact.isEmpty(), 'A household member is not a person.');
        }
    }

    @IsTest
    static void namesComeFromContactsAndAccountsTheUserCanSee() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact luis = [
                SELECT Id, Name, AccountId, Account.Name
                FROM Contact
                WHERE LastName = 'Garcia'
                LIMIT 1
            ];
            Test.startTest();
            Map<Id, String> names = OpportunityMirrorSelector.namesById(
                new Set<Id>{ luis.Id },
                new Set<Id>{ luis.AccountId }
            );
            Test.stopTest();
            Assert.areEqual(luis.Name, names.get(luis.Id), 'The contact name.');
            Assert.areEqual(luis.Account.Name, names.get(luis.AccountId), 'The account name.');
        }
    }
}
