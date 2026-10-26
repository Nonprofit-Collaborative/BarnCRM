/**
 * A gift saved by a staff member keeps the donor's totals current, as an administrator's save
 * does (canonical model R-R10, "Writable at run time").
 *
 * Giving Staff may read the giving totals and not edit them, so the planner used to refuse every
 * definition on a staff member's save ("BarnCRM cannot write to the field this rollup fills"),
 * and the totals waited for the nightly run. The queued path runs as the same person and failed
 * the same way. The totals are written in system mode on the administrator's definition's
 * behalf, so the planner now asks only whether the engine can write the target.
 */
@IsTest(testFor='ApexClass:RollupPlanner, ApexClass:RollupService, ApexClass:RollupQueue')
private class GiftStaffSaveRollupTest {
    private static final List<String> STAFF_SETS = new List<String>{
        'BarnCRM_Staff',
        'Giving_Staff'
    };

    /** The bulk case: one more than the platform's trigger chunk of 200 and a batch of 250. */
    private static final Integer BULK_GIFTS = 251;

    @TestSetup
    static void makeData() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            GivingTestDataFactory.insertDefaultFund();
            GivingRollupTestData.installShippedRollups();
        }
    }

    /** One gift, recalculated in the save: right before the save returns. */
    @IsTest
    static void aStaffSaveWritesTheTotalsInTheSave() {
        User staff = staffMember('Staffinsave');

        System.runAs(staff) {
            Contact ana = donor();

            Test.startTest();
            insert GivingTestDataFactory.buildGift(ana.Id, 250);
            Contact person = totalsOf(ana.Id);
            Test.stopTest();

            GivingTestDataFactory.assertRollupWrote(person.Total_Giving__c);
            Assert.areEqual(250, person.Total_Giving__c, 'Written in the staff member\'s save');
            Assert.areEqual(1, person.Gift_Count__c, 'Ana\'s gift count');
        }
        assertNothingRefused();
    }

    /** One gift, queued and recalculated just after the save, as the same staff member. */
    @IsTest
    static void aStaffSaveWritesTheTotalsJustAfterTheSave() {
        User staff = staffMember('Staffqueued');
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            RollupTestSupport.recalculateJustAfterTheSave();
        }

        System.runAs(staff) {
            Contact ana = donor();

            Test.startTest();
            insert GivingTestDataFactory.buildGift(ana.Id, 250);
            Test.stopTest();

            Contact person = totalsOf(ana.Id);
            GivingTestDataFactory.assertRollupWrote(person.Total_Giving__c);
            Assert.areEqual(250, person.Total_Giving__c, 'Written by the queued run');
            Assert.areEqual(1, person.Gift_Count__c, 'Ana\'s gift count');
        }
        assertNothingRefused();
    }

    /** 251 gifts in one staff save, with the org recalculating in the save. */
    @IsTest
    static void twoHundredFiftyOneStaffGiftsInTheSave() {
        User staff = staffMember('Staffbulk');

        System.runAs(staff) {
            assertBulkSaveWritesTotals();
        }
        assertNothingRefused();
    }

    /** 251 gifts in one staff save, queued just after the save. */
    @IsTest
    static void twoHundredFiftyOneStaffGiftsJustAfterTheSave() {
        User staff = staffMember('Staffbulkqueued');
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            RollupTestSupport.recalculateJustAfterTheSave();
        }

        System.runAs(staff) {
            assertBulkSaveWritesTotals();
        }
        assertNothingRefused();
    }

    /** The running staff member saves 251 gifts from one donor in one save. */
    private static void assertBulkSaveWritesTotals() {
        Contact ana = donor();
        List<Gift__c> gifts = GivingTestDataFactory.buildGifts(ana.Id, BULK_GIFTS, 10);

        Test.startTest();
        insert gifts;
        Test.stopTest();

        Contact person = totalsOf(ana.Id);
        GivingTestDataFactory.assertRollupWrote(person.Total_Giving__c);
        Assert.areEqual(BULK_GIFTS * 10, person.Total_Giving__c, 'Every gift is counted');
        Assert.areEqual(BULK_GIFTS, person.Gift_Count__c, 'Every gift is counted once');
        Assert.areEqual(
            BULK_GIFTS * 10,
            [SELECT Total_Giving__c FROM Account WHERE Id = :ana.AccountId WITH SYSTEM_MODE]
            .Total_Giving__c,
            'The household\'s total too'
        );
    }

    /** A staff member who may read the giving totals and not edit them. */
    private static User staffMember(String lastName) {
        User staff;
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            staff = TestDataFactory.createUser(lastName, STAFF_SETS);
        }
        System.runAs(staff) {
            Assert.isFalse(
                Schema.SObjectType.Contact.fields.Total_Giving__c.isUpdateable(),
                'Precondition: Giving Staff may not edit a person\'s total giving'
            );
            Assert.isTrue(
                Schema.SObjectType.Contact.fields.Total_Giving__c.isAccessible(),
                'Precondition: Giving Staff may read it'
            );
        }
        return staff;
    }

    /** A donor in a household of her own, saved by the running user. */
    private static Contact donor() {
        Contact ana = GivingTestDataFactory.insertHouseholdContact(
            'The Nolan Family',
            'Ana',
            'Nolan'
        );
        return [SELECT Id, AccountId FROM Contact WHERE Id = :ana.Id];
    }

    private static Contact totalsOf(Id contactId) {
        return [
            SELECT Total_Giving__c, Gift_Count__c
            FROM Contact
            WHERE Id = :contactId
            WITH SYSTEM_MODE
        ];
    }

    /** No definition was refused for want of a permission on any path. */
    private static void assertNothingRefused() {
        Test.getEventBus().deliver();
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Error_Log__c WHERE Context__c LIKE 'RollupPlanner%'],
                'No rollup was refused on the staff member\'s save'
            );
        }
    }
}
