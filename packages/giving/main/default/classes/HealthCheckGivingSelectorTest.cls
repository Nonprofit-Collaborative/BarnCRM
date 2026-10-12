/**
 * Tests for HealthCheckGivingSelector (G-20 follow-up, ADR-0053, ADR-0021 as amended by
 * ADR-0057): the org-wide, without-sharing read behind the unposted-in-closed-period finding.
 */
@IsTest
private class HealthCheckGivingSelectorTest {
    private static User jen() {
        return TestDataFactory.createUser(
            'Jen',
            new List<String>{ 'Nonprofit_Admin', 'Giving_Admin' }
        );
    }

    private static User david() {
        return TestDataFactory.createUser(
            'David',
            new List<String>{ 'Nonprofit_Staff', 'Giving_Staff' }
        );
    }

    private static Date lastClosedDay() {
        return Date.today().toStartOfMonth().addDays(-1);
    }

    /**
     * Every combination the rule distinguishes that a live insert can actually produce, in one
     * org: the three counting statuses are counted; Pending, In-kind, and a gift dated after
     * the close are not. `Status__c` also carries `<required>true</required>` in its own field
     * metadata, and that is enforced at the DML layer for a custom field, not only by the page
     * layout: an explicit `null` is rejected with REQUIRED_FIELD_MISSING on insert, confirmed
     * against oi-test while building this test. `GiftPostingLock.isInBooks` still reads a blank
     * status as Received, and `HealthCheckGivingSelector`'s query still matches `Status__c =
     * NULL` for parity with that rule and for any record that predates the requirement, but
     * this test cannot manufacture that row, so it is not part of the count this test asserts.
     * Three gifts qualify; three do not. Each test method adds the seventh combination, an
     * already-posted gift, itself: posting reads in user mode (ADR-0053), so it needs a gift
     * the posting user owns, unlike this shared setup, whose gifts belong to the running user,
     * not to a test's own `jen`.
     */
    @TestSetup
    static void makeData() {
        GivingTestDataFactory.insertDefaultFund();
        Contact ana = GivingTestDataFactory.insertHouseholdContact(
            'The Nolan Family',
            'Ana',
            'Nolan'
        );

        Gift__c received = GivingTestDataFactory.buildGift(ana.Id, 10);
        received.Status__c = 'Received';
        received.Gift_Date__c = lastClosedDay();

        Gift__c refunded = GivingTestDataFactory.buildGift(ana.Id, 20);
        refunded.Status__c = 'Refunded';
        refunded.Gift_Date__c = lastClosedDay();

        Gift__c writtenOff = GivingTestDataFactory.buildGift(ana.Id, 30);
        writtenOff.Status__c = 'Written off';
        writtenOff.Gift_Date__c = lastClosedDay();

        Gift__c pending = GivingTestDataFactory.buildGift(ana.Id, 50);
        pending.Status__c = 'Pending';
        pending.Gift_Date__c = lastClosedDay();

        Gift__c inKind = GivingTestDataFactory.buildGift(ana.Id, 0);
        inKind.Status__c = 'Received';
        inKind.Type__c = 'In-kind';
        inKind.Fair_Market_Value__c = 60;
        inKind.In_Kind_Description__c = 'A used laptop';
        inKind.Gift_Date__c = lastClosedDay();

        Gift__c afterClose = GivingTestDataFactory.buildGift(ana.Id, 70);
        afterClose.Status__c = 'Received';
        afterClose.Gift_Date__c = Date.today();

        insert new List<Gift__c>{ received, refunded, writtenOff, pending, inKind, afterClose };
    }

    /**
     * Jen's own gift, already posted before the period closes: added by each test method that
     * needs the eighth combination, because posting it needs a gift she owns.
     */
    private static void addAnAlreadyPostedGift(User jen) {
        System.runAs(jen) {
            Contact owned = GivingTestDataFactory.insertHouseholdContact(
                'The Diaz Family',
                'Priya',
                'Diaz'
            );
            Gift__c alreadyPosted = GivingTestDataFactory.buildGift(owned.Id, 80);
            alreadyPosted.Status__c = 'Received';
            alreadyPosted.Gift_Date__c = lastClosedDay();
            insert alreadyPosted;
            GiftPostingService.markPosted(new Set<Id>{ alreadyPosted.Id });
        }
    }

    @IsTest
    static void countsExactlyTheCountingStatusesNotTheRest() {
        User jen = jen();
        addAnAlreadyPostedGift(jen);
        GivingTestDataFactory.closeBooksThrough(lastClosedDay());

        System.runAs(jen) {
            Integer count = HealthCheckGivingSelector.countUnpostedInClosedPeriod(
                lastClosedDay(),
                1001
            );

            System.assertEquals(
                3,
                count,
                'Received, Refunded and Written off count; Pending, In-kind, a gift dated ' +
                'after the close and an already-posted gift do not.'
            );
        }
    }

    @IsTest
    static void linksNameOnlyTheQualifyingGifts() {
        User jen = jen();
        addAnAlreadyPostedGift(jen);
        GivingTestDataFactory.closeBooksThrough(lastClosedDay());

        // The selector's own query never selects Amount__c (the ADR-0057 amendment promises
        // nothing but Id, Name and Gift_Date__c crosses the sharing boundary), so the three
        // qualifying gifts are identified here, as the running test user who owns them, before
        // entering Jen's context to call the selector.
        Set<Id> expectedIds = new Map<Id, Gift__c>(
                [SELECT Id FROM Gift__c WHERE Amount__c IN (10, 20, 30)]
            )
            .keySet();

        List<Gift__c> linked;
        System.runAs(jen) {
            linked = HealthCheckGivingSelector.unpostedInClosedPeriod(lastClosedDay(), 10);
        }

        System.assertEquals(
            expectedIds,
            new Map<Id, Gift__c>(linked).keySet(),
            'Only the three qualifying gifts (10 Received, 20 Refunded, 30 Written off) are ' +
            'named.'
        );
    }

    /**
     * The selector asserts `HealthCheckService.canManageSettings()` itself (ADR-0057), not
     * only its caller, so a future caller that forgets the check still reaches nothing: called
     * directly, bypassing `HealthCheckGivingChecks.findings()` entirely, a viewer without the
     * permission gets an empty answer even though qualifying, unposted, closed-period gifts
     * exist.
     */
    @IsTest
    static void aViewerWithoutManageSettingsGetsNothingEvenCalledDirectly() {
        GivingTestDataFactory.closeBooksThrough(lastClosedDay());

        System.runAs(david()) {
            Integer count = HealthCheckGivingSelector.countUnpostedInClosedPeriod(
                lastClosedDay(),
                1001
            );
            List<Gift__c> linked = HealthCheckGivingSelector.unpostedInClosedPeriod(
                lastClosedDay(),
                10
            );

            System.assertEquals(
                0,
                count,
                'The gate is asserted in the selector itself, so a viewer without Manage ' +
                'BarnCRM Settings gets nothing, not an under-permissioned peek at the org.'
            );
            System.assertEquals(0, linked.size());
        }
    }
}
