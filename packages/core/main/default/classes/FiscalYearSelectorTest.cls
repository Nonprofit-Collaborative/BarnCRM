/**
 * Tests for FiscalYearSelector (feature C-11, ADR-NEXT).
 *
 * The fiscal year in Setup cannot be changed from Apex, so the org is read once for real, as
 * an administrator and as a user with no BarnCRM permissions at all, and injected everywhere
 * else.
 */
@IsTest(testFor='ApexClass:FiscalYearSelector')
private class FiscalYearSelectorTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    @IsTest
    static void theOrgFiscalYearIsAMonthThePlatformKnows() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            Integer month = FiscalYearSelector.fiscalYearStartMonth();
            Test.stopTest();

            System.assertEquals(
                [SELECT FiscalYearStartMonth FROM Organization WITH SYSTEM_MODE LIMIT 1]
                .FiscalYearStartMonth,
                month,
                'The month is the one Setup holds, with nothing in BarnCRM in between.'
            );
        }
    }

    @IsTest
    static void staffOnMinimumAccessReadTheSameMonth() {
        Integer asAdmin;
        User staff;
        System.runAs(TestUsers.admin()) {
            asAdmin = FiscalYearSelector.fiscalYearStartMonth();
            staff = TestUsers.minimumAccessUserWith('Fystaff', new List<String>{ 'BarnCRM_Staff' });
        }
        // Read again rather than from this transaction's cache, so the staff user's own read
        // is the one asserted.
        FiscalYearSelector.cachedStartMonth = null;
        System.runAs(staff) {
            System.assertEquals(
                asAdmin,
                FiscalYearSelector.fiscalYearStartMonth(),
                'Rollups run as whoever saved a record, so the month cannot depend on who reads ' +
                'it: a staff user gets the same window an administrator does.'
            );
        }
    }

    @IsTest
    static void theInjectedMonthIsTheOneReturned() {
        System.runAs(TestUsers.admin()) {
            FiscalYearSelector.setTestStartMonth(7);

            System.assertEquals(
                7,
                FiscalYearSelector.fiscalYearStartMonth(),
                'A module test sets the org month through the seam and reads it back.'
            );

            FiscalYearSelector.setTestStartMonth(null);
            System.assert(
                FiscalYearSelector.fiscalYearStartMonth() >= 1 &&
                    FiscalYearSelector.fiscalYearStartMonth() <= 12,
                'Null goes back to reading the org.'
            );
        }
    }

    @IsTest
    static void aMonthThePlatformCannotMeanFallsBackToJanuary() {
        System.runAs(TestUsers.admin()) {
            FiscalYearSelector.startMonthOverride = 13;

            System.assertEquals(
                1,
                FiscalYearSelector.fiscalYearStartMonth(),
                'A value outside 1 to 12 is never used as a window boundary.'
            );
        }
    }

    @IsTest
    static void customFiscalYearsAreReadWithoutFailing() {
        System.runAs(TestUsers.admin()) {
            Boolean custom = FiscalYearSelector.usesCustomFiscalYears();
            System.assertNotEquals(null, custom, 'The answer is true or false, never null.');

            FiscalYearSelector.customFiscalYearsOverride = true;
            System.assert(FiscalYearSelector.usesCustomFiscalYears(), 'The injected answer');
        }
    }

    @IsTest
    static void aMonthIsPrintedAsAMonthAndNotAsANumber() {
        System.runAs(TestUsers.admin()) {
            String july = FiscalYearSelector.monthName(7);

            System.assertNotEquals(
                '7',
                july,
                'The settings page reads "starts in July", not "starts in 7", so the number is ' +
                'turned into a name in the running user language.'
            );
            System.assertNotEquals(
                FiscalYearSelector.monthName(1),
                july,
                'Two different months read as two different names.'
            );
            System.assertEquals(
                '13',
                FiscalYearSelector.monthName(13),
                'A month outside 1 to 12 is printed as it is rather than throwing.'
            );
        }
    }
}
