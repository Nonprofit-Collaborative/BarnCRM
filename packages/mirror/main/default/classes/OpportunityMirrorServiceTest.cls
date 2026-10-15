/**
 * The Opportunity mirror, Gifts to Opportunities (X-01, canonical model Section 29C), as Maria
 * and David see it: saving a gift gives it an Opportunity, a change follows it there, and nothing
 * about the Opportunity ever refuses the gift.
 *
 * Opportunity is read only through dynamic queries here too, so this class compiles where
 * Opportunity does not exist; on such an org every test checks that the mirror did nothing and
 * stops (R-OM1).
 */
@IsTest(testFor='ApexClass:OpportunityMirrorService')
private class OpportunityMirrorServiceTest {
    private static final String LOG_CONTEXT = 'Opportunity mirror';
    // detection-only: read by name so this class compiles where Opportunity does not exist
    private static final String ROLE_OBJECT = 'OpportunityContactRole';

    @TestSetup
    static void setup() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            GivingTestDataFactory.ensureDefaultFund();
            GivingTestDataFactory.insertHouseholdContact('The Garcia Household', 'Luis', 'Garcia');
            choose(OpportunityMirrorService.GIFTS_TO_OPPORTUNITIES);
        }
    }

    private static void choose(String direction) {
        Mirror_Settings__c settings = Mirror_Settings__c.getOrgDefaults();
        settings.Opportunity_Mirror_Direction__c = direction;
        upsert settings;
    }

    /** Maria: an administrator who can create Opportunities. */
    private static User maria() {
        return TestDataFactory.createUserOnTheRunningUsersProfile(
            'Maria',
            new List<String>{ 'Giving_Admin', 'Opportunity_Mirror' }
        );
    }

    private static Contact luis() {
        return [SELECT Id, AccountId FROM Contact WHERE LastName = 'Garcia' LIMIT 1];
    }

    private static Gift__c gift(Decimal amount) {
        Gift__c gift = GivingTestDataFactory.buildGift(luis().Id, amount);
        gift.Gift_Date__c = Date.newInstance(2026, 9, 20);
        return gift;
    }

    private static Gift__c reread(Id giftId) {
        return (Gift__c) Database.queryWithBinds(
            'SELECT ' + OpportunityMirrorSelector.GIFT_FIELDS + ' FROM Gift__c WHERE Id = :giftId',
            new Map<String, Object>{ 'giftId' => giftId },
            AccessLevel.SYSTEM_MODE
        )[0];
    }

    private static String opportunityObject() {
        return OpportunityMirrorService.opportunityType().getDescribe().getName();
    }

    private static SObject opportunity(String opportunityId) {
        return Database.queryWithBinds(
            'SELECT Id, Name, Amount, CloseDate, StageName, IsWon, AccountId FROM ' +
                opportunityObject() +
                ' WHERE Id = :opportunityId',
            new Map<String, Object>{ 'opportunityId' => opportunityId },
            AccessLevel.SYSTEM_MODE
        )[0];
    }

    private static List<SObject> primaryRoles(String opportunityId) {
        return Database.queryWithBinds(
            'SELECT ContactId, Role FROM ' +
                ROLE_OBJECT +
                ' WHERE OpportunityId = :opportunityId AND IsPrimary = TRUE',
            new Map<String, Object>{ 'opportunityId' => opportunityId },
            AccessLevel.SYSTEM_MODE
        );
    }

    private static Integer countOpportunities() {
        return Database.countQuery(
            'SELECT COUNT() FROM ' + opportunityObject(),
            AccessLevel.SYSTEM_MODE
        );
    }

    private static List<Error_Log__c> warnings() {
        return [
            SELECT Message__c
            FROM Error_Log__c
            WHERE Context__c = :LOG_CONTEXT AND Severity__c = 'Warning'
            WITH SYSTEM_MODE
        ];
    }

    /**
     * The absent branch of every test that stops where the org has no Opportunity: the gifts
     * saved, none was linked, and nothing was logged (R-OM1). `OpportunityMirrorUnavailableTest`
     * runs this branch.
     */
    private static void assertNothingMirrored() {
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Gift__c WHERE Opportunity_Id__c != NULL WITH SYSTEM_MODE],
            'Without Opportunity no gift is linked (R-OM1).'
        );
        Assert.areEqual(0, warnings().size(), 'And nothing is logged.');
    }

    @IsTest
    static void savingAGiftGivesItAWonOpportunityWithTheDonorAsPrimaryContact() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Gift__c given = gift(100);
            Test.startTest();
            System.runAs(maria()) {
                insert given;
            }
            Test.stopTest();

            Gift__c saved = reread(given.Id);
            if (!OpportunityMirrorService.isAvailable()) {
                Assert.isNull(
                    saved.Opportunity_Id__c,
                    'Without Opportunity the mirror does nothing.'
                );
                return;
            }
            Assert.isNotNull(
                saved.Opportunity_Id__c,
                'The Opportunity is linked in the same save.'
            );
            SObject copy = opportunity(saved.Opportunity_Id__c);
            Assert.areEqual(100, (Decimal) copy.get('Amount'), 'Amount is copied.');
            Assert.areEqual(saved.Gift_Date__c, copy.get('CloseDate'), 'Gift Date is Close Date.');
            Assert.areEqual(true, copy.get('IsWon'), 'A Received gift is won (R-OM3).');
            Assert.areEqual(
                saved.Household__c,
                copy.get('AccountId'),
                'The household is the Account.'
            );
            Assert.isTrue(
                ((String) copy.get('Name')).contains('Luis Garcia'),
                'The Opportunity is named after the donor: ' + copy.get('Name')
            );
            List<SObject> roles = primaryRoles(saved.Opportunity_Id__c);
            Assert.areEqual(1, roles.size(), 'One primary contact role.');
            Assert.areEqual(
                luis().Id,
                roles[0].get('ContactId'),
                'The donor is the primary contact.'
            );
            Assert.areEqual(0, warnings().size(), 'Nothing to warn about.');
        }
    }

    @IsTest
    static void aChangeToTheGiftFollowsItAndACancelledGiftLosesTheOpportunity() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            User admin = maria();
            Gift__c given = gift(100);
            System.runAs(admin) {
                insert given;
            }
            if (!OpportunityMirrorService.isAvailable()) {
                assertNothingMirrored();
                return;
            }
            String linked = reread(given.Id).Opportunity_Id__c;
            Test.startTest();
            System.runAs(admin) {
                update new Gift__c(Id = given.Id, Amount__c = 150);
                update new Gift__c(Id = given.Id, Status__c = 'Pending');
                update new Gift__c(Id = given.Id, Status__c = 'Cancelled');
            }
            Test.stopTest();

            Gift__c saved = reread(given.Id);
            Assert.areEqual(
                linked,
                saved.Opportunity_Id__c,
                'The same Opportunity, not a new one.'
            );
            SObject copy = opportunity(linked);
            Assert.areEqual(150, (Decimal) copy.get('Amount'), 'The new amount followed it.');
            Assert.areEqual(false, copy.get('IsWon'), 'A Cancelled gift is a lost Opportunity.');
            Assert.areEqual(1, countOpportunities(), 'Nothing is ever deleted or duplicated.');
        }
    }

    @IsTest
    static void aPendingGiftGetsNoOpportunityUntilItIsReceived() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            User admin = maria();
            Gift__c pledged = gift(80);
            pledged.Status__c = 'Pending';
            Test.startTest();
            System.runAs(admin) {
                insert pledged;
                Assert.isNull(
                    reread(pledged.Id).Opportunity_Id__c,
                    'Pending is not in the totals.'
                );
                update new Gift__c(Id = pledged.Id, Status__c = 'Received');
            }
            Test.stopTest();
            Assert.areEqual(
                OpportunityMirrorService.isAvailable(),
                reread(pledged.Id).Opportunity_Id__c != null,
                'Received, it gets its Opportunity (R-OM2).'
            );
        }
    }

    @IsTest
    static void aRefundIsItsOwnNegativeOpportunity() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            User admin = maria();
            Gift__c original = gift(200);
            System.runAs(admin) {
                insert original;
            }
            Id refundId;
            Test.startTest();
            System.runAs(admin) {
                refundId = GiftService.refund(original.Id, 200, 'Charged twice');
            }
            Test.stopTest();
            if (!OpportunityMirrorService.isAvailable()) {
                assertNothingMirrored();
                return;
            }
            SObject negative = opportunity(reread(refundId).Opportunity_Id__c);
            Assert.areEqual(-200, (Decimal) negative.get('Amount'), 'The refund nets the total.');
            Assert.areEqual(true, negative.get('IsWon'), 'A refund is in the totals, so won.');
            Gift__c refunded = reread(original.Id);
            Assert.areEqual('Refunded', refunded.Status__c, 'Giving marked the original.');
            Assert.areEqual(
                true,
                opportunity(refunded.Opportunity_Id__c).get('IsWon'),
                'A Refunded original is still won; its refund takes the money back.'
            );
        }
    }

    @IsTest
    static void aDeletedOpportunityIsReportedAndNotReplaced() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            User admin = maria();
            Gift__c given = gift(100);
            System.runAs(admin) {
                insert given;
            }
            if (!OpportunityMirrorService.isAvailable()) {
                assertNothingMirrored();
                return;
            }
            String linked = reread(given.Id).Opportunity_Id__c;
            Database.delete(new List<Id>{ linked }, true, AccessLevel.SYSTEM_MODE);
            Test.startTest();
            System.runAs(admin) {
                update new Gift__c(Id = given.Id, Amount__c = 120);
            }
            Test.stopTest();
            Assert.areEqual(linked, reread(given.Id).Opportunity_Id__c, 'The link is kept.');
            Assert.areEqual(0, countOpportunities(), 'No replacement is made (R-OM9).');
            List<Error_Log__c> logged = warnings();
            Assert.areEqual(1, logged.size(), 'One Warning.');
            Assert.isTrue(
                logged[0].Message__c.contains('deleted or is not visible to you'),
                'Worded for a user mode read: ' + logged[0].Message__c
            );
        }
    }

    @IsTest
    static void aTypedValueThatIsNotAnOpportunityIsRefused() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Gift__c given = gift(100);
            given.Opportunity_Id__c = UserInfo.getUserId();
            Database.SaveResult saved;
            Test.startTest();
            System.runAs(maria()) {
                saved = Database.insert(given, false);
            }
            Test.stopTest();
            if (!OpportunityMirrorService.isAvailable()) {
                Assert.isTrue(
                    saved.isSuccess(),
                    'Without Opportunity the value is not read (R-OM1).'
                );
                Assert.areEqual(0, warnings().size(), 'And nothing is logged.');
                return;
            }
            Assert.isFalse(saved.isSuccess(), 'Another object\'s id is refused (R-OM10).');
        }
    }

    @IsTest
    static void someoneWithoutThePermissionSetStillHasTheirGiftsCopied() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            // David enters gifts and may create Opportunities, but was not given the Opportunity
            // Mirror permission set, so he cannot see the Opportunity ID field (R-OM5).
            User david = TestDataFactory.createUser('David', new List<String>{ 'Giving_Admin' });
            // David's profile sees only what he owns, so he is given a donor of his own.
            Account household = new Account(Name = 'The Chen Household', OwnerId = david.Id);
            insert household;
            Contact mei = new Contact(
                FirstName = 'Mei',
                LastName = 'Chen',
                AccountId = household.Id,
                OwnerId = david.Id
            );
            insert mei;
            Gift__c given = GivingTestDataFactory.buildGift(mei.Id, 10);
            Test.startTest();
            System.runAs(david) {
                insert given;
                update new Gift__c(Id = given.Id, Amount__c = 15);
            }
            Test.stopTest();
            String linked = reread(given.Id).Opportunity_Id__c;
            if (!OpportunityMirrorService.isAvailable()) {
                Assert.isNull(linked, 'Without Opportunity the mirror does nothing.');
                return;
            }
            Assert.isNotNull(linked, 'The link is written onto the gift being saved.');
            Assert.areEqual(
                15,
                (Decimal) opportunity(linked).get('Amount'),
                'His change followed.'
            );
            Assert.areEqual(0, warnings().size(), 'Nothing skipped.');
        }
    }

    @IsTest
    static void aSaveTooLargeToCopyIsSavedUncopiedAndLoggedOnce() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            User admin = maria();
            Assert.isTrue(
                OpportunityMirrorService.hasHeadroom(200),
                'A fresh transaction has room.'
            );
            MirrorSync.simulatedCpuTimeUsed = Limits.getLimitCpuTime();
            Gift__c first = gift(10);
            Gift__c second = gift(20);
            Test.startTest();
            System.runAs(admin) {
                insert first;
                insert second;
            }
            Test.stopTest();
            MirrorSync.simulatedCpuTimeUsed = null;
            Assert.isNull(reread(first.Id).Opportunity_Id__c, 'The gift saves, uncopied.');
            Assert.isNull(reread(second.Id).Opportunity_Id__c, 'So does the next one.');
            Assert.areEqual(
                OpportunityMirrorService.isAvailable() ? 1 : 0,
                warnings().size(),
                'One Warning for the transaction (R-OM6).'
            );
        }
    }

    @IsTest
    static void twoHundredGiftsAreCopiedInOneSave() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            List<Gift__c> gifts = GivingTestDataFactory.buildGifts(luis().Id, 200, 25);
            Test.startTest();
            System.runAs(maria()) {
                insert gifts;
            }
            Test.stopTest();
            if (!OpportunityMirrorService.isAvailable()) {
                assertNothingMirrored();
                return;
            }
            Assert.areEqual(
                200,
                [SELECT COUNT() FROM Gift__c WHERE Opportunity_Id__c != NULL WITH SYSTEM_MODE],
                'Every gift has its Opportunity (plan Section 7.2).'
            );
            Assert.areEqual(200, countOpportunities(), 'One each.');
        }
    }

    @IsTest
    static void nothingIsCopiedUntilTheDirectionIsChosen() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            choose(OpportunityMirrorService.OFF);
            Gift__c given = gift(100);
            Test.startTest();
            System.runAs(maria()) {
                insert given;
            }
            Test.stopTest();
            Assert.isNull(reread(given.Id).Opportunity_Id__c, 'Off is off (R-OM1).');
            choose(OpportunityMirrorService.OPPORTUNITIES_TO_GIFTS);
            Assert.isFalse(OpportunityMirrorService.copiesGifts(), 'One direction at a time.');
        }
    }
}
