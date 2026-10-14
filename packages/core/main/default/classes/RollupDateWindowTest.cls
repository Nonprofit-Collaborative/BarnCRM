/**
 * Fiscal year windows, against a fiscal year that does not start in January (canonical model R-R3).
 *
 * These tests have not been executed: no Salesforce org exists in this environment.
 */
@IsTest(testFor='ApexClass:RollupDateWindow')
private class RollupDateWindowTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    @IsTest
    static void fiscalYearWindowsResolveAgainstOrgFiscalSettings() {
        System.runAs(TestUsers.admin()) {
            SettingsService.saveSystemValue('Fiscal_Year_Start_Month__c', 7);
            SettingsService.clearCaches();
            RollupDateWindow.todayOverride = Date.newInstance(2026, 9, 8);

            RollupDateWindow.Window thisYear = RollupDateWindow.windowFor(0);
            RollupDateWindow.Window lastYear = RollupDateWindow.windowFor(-1);
            RollupDateWindow.Window twoYearsAgo = RollupDateWindow.windowFor(-2);

            System.Assert.areEqual(
                Date.newInstance(2026, 7, 1),
                thisYear.startInclusive,
                'September 2026 is inside the fiscal year that started in July 2026'
            );
            System.Assert.areEqual(
                Date.newInstance(2027, 7, 1),
                thisYear.endExclusive,
                'A window is one year long'
            );
            System.Assert.areEqual(
                Date.newInstance(2025, 7, 1),
                lastYear.startInclusive,
                'Last year is the one before'
            );
            System.Assert.areEqual(
                Date.newInstance(2024, 7, 1),
                twoYearsAgo.startInclusive,
                'Two years ago is the one before that'
            );
        }
    }

    @IsTest
    static void aDateBeforeTheStartMonthBelongsToTheYearThatBegan() {
        System.runAs(TestUsers.admin()) {
            SettingsService.saveSystemValue('Fiscal_Year_Start_Month__c', 7);
            SettingsService.clearCaches();
            RollupDateWindow.todayOverride = Date.newInstance(2026, 3, 31);

            RollupDateWindow.Window thisYear = RollupDateWindow.windowFor(0);

            System.Assert.areEqual(
                Date.newInstance(2025, 7, 1),
                thisYear.startInclusive,
                'March 2026 is still inside the fiscal year that started in July 2025'
            );
        }
    }

    @IsTest
    static void aBoundaryDatedRecordLandsInTheLaterWindowOnly() {
        System.runAs(TestUsers.admin()) {
            SettingsService.saveSystemValue('Fiscal_Year_Start_Month__c', 7);
            SettingsService.clearCaches();
            RollupDateWindow.todayOverride = Date.newInstance(2026, 9, 8);

            String clause = RollupDateWindow.toWhereClause(true, 0, 'Gift_Date__c');

            System.Assert.areEqual(
                'Gift_Date__c >= 2026-07-01 AND Gift_Date__c < 2027-07-01',
                clause,
                'The start is inclusive and the end exclusive, so 1 July lands in exactly one window'
            );
        }
    }

    @IsTest
    static void anOrgThatHasNeverSetTheMonthStartsInJanuary() {
        System.runAs(TestUsers.admin()) {
            SettingsService.clearCaches();
            RollupDateWindow.todayOverride = Date.newInstance(2026, 9, 8);

            System.Assert.areEqual(
                1,
                RollupDateWindow.fiscalYearStartMonth(),
                'January is the default'
            );
            System.Assert.areEqual(
                Date.newInstance(2026, 1, 1),
                RollupDateWindow.windowFor(0).startInclusive,
                'A calendar fiscal year is the ordinary case'
            );
        }
    }

    @IsTest
    static void theEngineReadsTheFiscalYearCoreChecks() {
        System.runAs(TestUsers.admin()) {
            SettingsService.saveSystemValue('Fiscal_Year_Start_Month__c', 7);

            System.Assert.areEqual(
                FiscalYearSelector.settingsFiscalYearStartMonth(),
                RollupDateWindow.fiscalYearStartMonth(),
                'The number Health Check compares is the number the totals were computed from. ' +
                    'Reading the setting a second way would let the check pass while the totals ' +
                    'were measured on another boundary.'
            );
            System.Assert.areEqual(7, RollupDateWindow.fiscalYearStartMonth(), 'July');
        }
    }

    @IsTest
    static void aRollupThatIsNotFiscalAwareGetsNoWindow() {
        System.runAs(TestUsers.admin()) {
            System.Assert.areEqual(
                '',
                RollupDateWindow.toWhereClause(false, 0, 'Gift_Date__c'),
                'Only a fiscal aware rollup is bounded'
            );
            System.Assert.areEqual(
                '',
                RollupDateWindow.toWhereClause(null, null, null),
                'Nor is an unset one'
            );
        }
    }

    @IsTest
    static void aFiscalAwareRollupWithNoDateToBoundIsRefused() {
        System.runAs(TestUsers.admin()) {
            try {
                RollupDateWindow.toWhereClause(true, 0, null);
                System.Assert.fail(
                    'A window with nothing to measure would silently count every year'
                );
            } catch (RollupDateWindow.RollupDateWindowException expected) {
                System.Assert.isNotNull(expected.getMessage(), 'The message names the problem');
            }
        }
    }
}
