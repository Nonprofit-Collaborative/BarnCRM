/**
 * Tests for FiscalYearSelector (feature C-11, ADR-0025).
 *
 * The fiscal year in Setup cannot be changed from Apex, so the org side is read once for
 * real and injected everywhere else. The BarnCRM side is deliberately the same call the
 * rollup engine makes, which is what the mismatch finding depends on.
 */
@IsTest
private class FiscalYearSelectorTest {
    @IsTest
    static void theOrgFiscalYearIsAMonthThePlatformKnows() {
        Test.startTest();
        Integer month = FiscalYearSelector.orgFiscalYearStartMonth();
        Test.stopTest();

        System.assertNotEquals(
            null,
            month,
            'Every org has a fiscal year start month in Setup, so an administrator running ' +
            'Health Check always gets an answer to compare against.'
        );
        System.assert(
            month >= 1 && month <= 12,
            'The Setup fiscal year is a month number, and the finding prints it as a month ' +
                'name. Got: ' +
                month
        );
    }

    @IsTest
    static void theBarnCRMFiscalYearIsTheOneTheRollupsUse() {
        SettingsService.saveSystemValue('Fiscal_Year_Start_Month__c', 7);

        System.assertEquals(
            7,
            FiscalYearSelector.settingsFiscalYearStartMonth(),
            'The setting is read back as the month it was set to.'
        );
        System.assertEquals(
            RollupDateWindow.fiscalYearStartMonth(),
            FiscalYearSelector.settingsFiscalYearStartMonth(),
            'The number Health Check compares is the number Giving This Year was computed ' +
                'from. Reading the setting a second way here would let the check pass while the ' +
                'totals were still measured on another boundary.'
        );
    }

    @IsTest
    static void anUntouchedSettingReadsAsJanuaryBecauseThatIsWhatTheRollupsDid() {
        System.assertEquals(
            1,
            FiscalYearSelector.settingsFiscalYearStartMonth(),
            'With the setting never saved, the rollup engine falls back to January, so that ' +
            'is the boundary the totals were measured on and the month Setup has to match.'
        );
    }

    @IsTest
    static void anOrgFiscalYearThatCouldNotBeReadIsNull() {
        FiscalYearSelector.orgStartMonthOverridden = true;
        FiscalYearSelector.orgStartMonthOverride = null;

        System.assertEquals(
            null,
            FiscalYearSelector.orgFiscalYearStartMonth(),
            'A value nobody could read comes back as null, which Health Check reports as no ' +
            'finding: it is not evidence that the two fiscal years disagree.'
        );
    }

    @IsTest
    static void aMonthIsPrintedAsAMonthAndNotAsANumber() {
        String july = FiscalYearSelector.monthName(7);

        System.assertNotEquals(
            '7',
            july,
            'The finding reads "starts in July", not "starts in 7", so the number is turned ' +
            'into a name in the running user language.'
        );
        System.assertNotEquals(
            FiscalYearSelector.monthName(1),
            july,
            'Two different months read as two different names, which is the whole content of ' +
            'the finding.'
        );
        System.assertEquals(
            '13',
            FiscalYearSelector.monthName(13),
            'A month outside 1 to 12 is printed as it is rather than throwing, because a ' +
            'settings value nobody validated must not take the report down.'
        );
    }
}
