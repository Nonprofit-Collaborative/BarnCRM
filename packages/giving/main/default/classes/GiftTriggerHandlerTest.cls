/**
 * David enters gifts. These tests are the rules he never has to think about: the household
 * arrives by itself, a gift with no date is today's gift, a receipted gift stops changing, and
 * a gift with no designation still lands in a fund.
 */
@IsTest
private class GiftTriggerHandlerTest {
    @TestSetup
    static void makeData() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            GivingTestDataFactory.insertDefaultFund();
            GivingTestDataFactory.insertHouseholdContact('The Nolan Family', 'Ana', 'Nolan');
        }
    }

    private static Contact donor() {
        return [SELECT Id, AccountId FROM Contact LIMIT 1];
    }

    @IsTest
    static void householdIsDerivedFromTheDonorContact() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact person = donor();

            Test.startTest();
            Gift__c gift = GivingTestDataFactory.buildGift(person.Id, 250);
            insert gift;
            Test.stopTest();

            Gift__c saved = [
                SELECT Id, Household__c, Gift_Date__c
                FROM Gift__c
                WHERE Id = :gift.Id
            ];
            System.assertEquals(
                person.AccountId,
                saved.Household__c,
                'David should not have to fill in the household: it comes from the donor.'
            );
            System.assertEquals(
                Date.today(),
                saved.Gift_Date__c,
                'A gift saved without a date is a gift that arrived today.'
            );
        }
    }

    @IsTest
    static void householdIsClearedWhenTheDonorChangesToAnOrganization() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact person = donor();
            Gift__c gift = GivingTestDataFactory.buildGift(person.Id, 100);
            insert gift;
            Account employer = GivingTestDataFactory.insertOrganization('Riverside Foundation');

            Test.startTest();
            gift.Donor_Contact__c = null;
            gift.Donor_Account__c = employer.Id;
            update gift;
            Test.stopTest();

            Gift__c saved = [SELECT Id, Household__c FROM Gift__c WHERE Id = :gift.Id];
            System.assertEquals(
                null,
                saved.Household__c,
                'An organization has no household, so the gift should not keep the old one.'
            );
        }
    }

    @IsTest
    static void householdIsTheDonorAccountWhenThatAccountIsAHousehold() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            List<RecordType> householdTypes = [
                SELECT Id
                FROM RecordType
                WHERE SObjectType = 'Account' AND DeveloperName = 'Household'
                LIMIT 1
            ];
            if (householdTypes.isEmpty()) {
                return;
            }
            Account household = new Account(
                Name = 'The Okafor Family',
                RecordTypeId = householdTypes[0].Id
            );
            insert household;

            Test.startTest();
            Gift__c gift = GivingTestDataFactory.buildAccountGift(household.Id, 500);
            insert gift;
            Test.stopTest();

            Gift__c saved = [SELECT Id, Household__c FROM Gift__c WHERE Id = :gift.Id];
            System.assertEquals(
                household.Id,
                saved.Household__c,
                'A household giving in its own name is credited to itself.'
            );
        }
    }

    @IsTest
    static void personHeldAsAnAccountGetsItsHouseholdFromCore() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            if (!OrgShapeDetector.detect().hasPersonAccounts) {
                return;
            }
            // A person type the running user is given: one they are not is refused on insert.
            Id personType = OrgShapeDetector.creatablePersonRecordTypeId();
            if (personType == null) {
                return;
            }
            Account person = new Account();
            person.put('LastName', 'Okafor');
            person.put('RecordTypeId', personType);
            insert person;

            Test.startTest();
            Gift__c gift = GivingTestDataFactory.buildAccountGift(person.Id, 75);
            insert gift;
            Test.stopTest();

            Gift__c saved = [
                SELECT Id, Donor_Account__c, Household__c
                FROM Gift__c
                WHERE Id = :gift.Id
            ];
            System.assertEquals(
                person.Id,
                saved.Donor_Account__c,
                'A person held as an account is a donor account.'
            );
            System.assertEquals(
                HouseholdService.getHouseholdIdsFor(new Set<Id>{ person.Id }).get(person.Id),
                saved.Household__c,
                'And the household on the gift is the one Core says that person belongs to.'
            );
        }
    }

    @IsTest
    static void aReceiptedGiftStopsChanging() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact person = donor();
            Gift__c gift = GivingTestDataFactory.buildGift(person.Id, 250);
            insert gift;
            GiftService.recordReceiptNumbers(new Map<Id, String>{ gift.Id => 'R-000001' });
            gift.Receipt_Number__c = 'R-000001';

            String message = '';
            Test.startTest();
            try {
                gift.Amount__c = 300;
                update gift;
            } catch (DmlException lockError) {
                message = lockError.getDmlMessage(0);
            }
            Test.stopTest();

            System.assert(
                message.contains('receipt number'),
                'The amount on a receipted gift must not change: ' + message
            );
        }
    }

    @IsTest
    static void changingTheAmountMovesTheOnlyAllocationWithIt() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact person = donor();
            Gift__c gift = GivingTestDataFactory.buildGift(person.Id, 250);
            insert gift;

            Test.startTest();
            gift.Amount__c = 400;
            update gift;
            Test.stopTest();

            Gift_Allocation__c allocation = [
                SELECT Id, Amount__c
                FROM Gift_Allocation__c
                WHERE Gift__c = :gift.Id
            ];
            System.assertEquals(
                400,
                allocation.Amount__c,
                'A gift with one allocation carries that allocation with it.'
            );
        }
    }

    @IsTest
    static void changingTheAmountOfASplitGiftIsRefused() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact person = donor();
            Fund__c second = GivingTestDataFactory.buildFund('Scholarship', false);
            insert second;
            Gift__c gift = GivingTestDataFactory.buildGift(person.Id, 200);
            Fund__c general = [SELECT Id FROM Fund__c WHERE Is_Default__c = TRUE LIMIT 1];
            try {
                GiftService.suppressDefaultAllocations = true;
                insert gift;
            } finally {
                GiftService.suppressDefaultAllocations = false;
            }
            insert new List<Gift_Allocation__c>{
                GivingTestDataFactory.buildAllocation(gift.Id, general.Id, 150),
                GivingTestDataFactory.buildAllocation(gift.Id, second.Id, 50)
            };

            String message = '';
            Test.startTest();
            try {
                gift.Amount__c = 300;
                update gift;
            } catch (DmlException splitError) {
                message = splitError.getDmlMessage(0);
            }
            Test.stopTest();

            System.assert(
                message.contains('split across more than one fund'),
                'A split gift cannot have its amount changed silently: ' + message
            );
        }
    }

    @IsTest
    static void twoHundredGiftsSaveInOneGo() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact person = donor();

            Test.startTest();
            List<Gift__c> gifts = GivingTestDataFactory.buildGifts(person.Id, 200, 25);
            insert gifts;
            Test.stopTest();

            System.assertEquals(
                200,
                [SELECT COUNT() FROM Gift__c],
                'Two hundred gifts in one save is the governor-limit bar (plan Section 7.2).'
            );
            System.assertEquals(
                200,
                [SELECT COUNT() FROM Gift_Allocation__c],
                'Every one of them gets its default allocation.'
            );
        }
    }

    @IsTest
    static void aReceiptNumberCannotBeClearedToLiftTheLock() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact person = donor();
            Gift__c gift = GivingTestDataFactory.buildGift(person.Id, 250);
            insert gift;
            GiftService.recordReceiptNumbers(new Map<Id, String>{ gift.Id => 'R-000002' });
            gift.Receipt_Number__c = 'R-000002';

            String message = '';
            Test.startTest();
            try {
                gift.Receipt_Number__c = null;
                update gift;
            } catch (DmlException clearError) {
                message = clearError.getDmlMessage(0);
            }
            Test.stopTest();

            System.assert(
                message.contains('cannot be changed or cleared'),
                'Clearing the number in one save and changing the amount in the next is the bypass ' +
                    'this rule exists to close: ' +
                    message
            );
            System.assertEquals(
                'R-000002',
                [SELECT Receipt_Number__c FROM Gift__c WHERE Id = :gift.Id].Receipt_Number__c,
                'The number the donor is holding is still there.'
            );
        }
    }

    @IsTest
    static void typingAReceiptNumberOntoAGiftIsRefused() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact person = donor();
            Gift__c gift = GivingTestDataFactory.buildGift(person.Id, 250);
            insert gift;

            String message = '';
            Test.startTest();
            try {
                gift.Receipt_Number__c = 'R-000003';
                gift.Amount__c = 400;
                update gift;
            } catch (DmlException lockError) {
                message = lockError.getDmlMessage(0);
            }
            Test.stopTest();

            System.assertEquals(
                null,
                [SELECT Receipt_Number__c FROM Gift__c WHERE Id = :gift.Id].Receipt_Number__c,
                'Neither value was saved, so the gift is still unreceipted and Issue Receipt can ' +
                'still receipt it.'
            );
            System.assert(
                message.contains('receipt number'),
                'A receipt number comes from the sequence, never from a person typing one in: ' +
                message
            );
        }
    }

    @IsTest
    static void theReceiptingFeatureCanVoidAndReissue() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact person = donor();
            Gift__c gift = GivingTestDataFactory.buildGift(person.Id, 250);
            insert gift;
            GiftService.recordReceiptNumbers(new Map<Id, String>{ gift.Id => 'R-000004' });

            Test.startTest();
            GiftService.recordReceiptNumbers(new Map<Id, String>{ gift.Id => 'R-000005' });
            Test.stopTest();

            System.assertEquals(
                'R-000005',
                [SELECT Receipt_Number__c FROM Gift__c WHERE Id = :gift.Id].Receipt_Number__c,
                'Void and reissue is the sanctioned way the number changes (G-13).'
            );
        }
    }

    @IsTest
    static void aReceiptedGiftCannotBeDeleted() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact person = donor();
            Gift__c gift = GivingTestDataFactory.buildGift(person.Id, 250);
            insert gift;
            GiftService.recordReceiptNumbers(new Map<Id, String>{ gift.Id => 'R-000006' });

            String message = '';
            Test.startTest();
            try {
                delete gift;
            } catch (DmlException deleteError) {
                message = deleteError.getDmlMessage(0);
            }
            Test.stopTest();

            System.assert(
                message.contains('cannot be deleted'),
                'A gift a donor holds a receipt for is reversed, not deleted: ' + message
            );
        }
    }

    @IsTest
    static void aGiftWithARefundCannotBeDeleted() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact person = donor();
            Gift__c gift = GivingTestDataFactory.buildGift(person.Id, 200);
            insert gift;
            GiftService.refund(gift.Id, 50, 'Part back');

            String message = '';
            Test.startTest();
            try {
                delete gift;
            } catch (DmlException deleteError) {
                message = deleteError.getDmlMessage(0);
            }
            Test.stopTest();

            System.assert(
                message.contains('cannot be deleted'),
                'Deleting the original would leave the refund explaining nothing: ' + message
            );
        }
    }

    @IsTest
    static void aPlainMistakeIsStillDeletable() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact person = donor();
            Gift__c gift = GivingTestDataFactory.buildGift(person.Id, 25);
            insert gift;

            Test.startTest();
            delete gift;
            Test.stopTest();

            System.assertEquals(
                0,
                [SELECT COUNT() FROM Gift__c],
                'A gift typed a minute ago with nothing pointing at it is a mistake, not history.'
            );
        }
    }

    @IsTest
    static void davidEntersAGiftAsHimself() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact person = donor();
            User david = new User(Id = UserInfo.getUserId());

            Test.startTest();
            System.runAs(david) {
                insert GivingTestDataFactory.buildGift(person.Id, 60);
            }
            Test.stopTest();

            System.assertEquals(
                1,
                [SELECT COUNT() FROM Gift__c],
                'The user-mode queries and inserts behave for a person entering a gift.'
            );
        }
    }
}
