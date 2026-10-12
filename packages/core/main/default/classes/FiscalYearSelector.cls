/**
 * The month this org's fiscal year starts in Setup (feature C-11, ADR-0025).
 *
 * BarnCRM holds its own fiscal year in `BarnCRM_Settings__c.Fiscal_Year_Start_Month__c`
 * and every rollup window is computed from it (rule R-R3). The packaged retention reports
 * cannot read that setting: a report filter expresses a relative year with a fiscal year date
 * literal, which resolves against the org's fiscal year in Setup. The two therefore have to
 * be set to the same month, and nothing in the platform makes that happen.
 *
 * `Organization` is a standard object every org has, and it is not one of the objects Core is
 * forbidden to touch (plan Section 4.2), so reading it costs Core nothing on a Platform-only
 * org. The query lives in a selector because every SOQL statement does (plan Section 7.1).
 */
public with sharing class FiscalYearSelector {
    /**
     * Injected by the tests: the Setup fiscal year cannot be changed from Apex. Two fields
     * rather than one because null is a real answer here, meaning "could not be read", and a
     * test has to be able to ask for it.
     */
    @TestVisible
    private static Boolean orgStartMonthOverridden = false;

    @TestVisible
    private static Integer orgStartMonthOverride;

    /**
     * The month the org's fiscal year starts, 1 for January through 12 for December, or null
     * when it cannot be read. Null is reported as no finding rather than as a mismatch: a
     * value nobody could read is not evidence that the two disagree.
     */
    public static Integer orgFiscalYearStartMonth() {
        if (orgStartMonthOverridden == true) {
            return orgStartMonthOverride;
        }

        try {
            List<Organization> organizations = [
                SELECT FiscalYearStartMonth
                FROM Organization
                WITH USER_MODE
                LIMIT 1
            ];
            return organizations.isEmpty() ? null : organizations[0].FiscalYearStartMonth;
        } catch (QueryException cannotRead) {
            return null;
        }
    }

    /**
     * The month BarnCRM starts its own fiscal year in. This is deliberately the same call
     * the rollup engine makes rather than a second reading of the setting, including its
     * January default when the setting has never been touched: the number the check compares
     * has to be the number the totals were actually computed from.
     */
    public static Integer settingsFiscalYearStartMonth() {
        return RollupDateWindow.fiscalYearStartMonth();
    }

    /**
     * A month number as a person reads it, in their own language. Twelve labels would say the
     * same thing and would have to be translated again.
     */
    public static String monthName(Integer month) {
        if (month == null || month < 1 || month > 12) {
            return String.valueOf(month);
        }
        return Datetime.newInstance(2000, month, 1, 0, 0, 0).format('MMMM');
    }
}
