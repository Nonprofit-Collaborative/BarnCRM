/**
 * The org's fiscal year, as Setup holds it (feature C-11, ADR-0135).
 *
 * BarnCRM has one fiscal year, the org's (Setup, Company Settings, Fiscal Year). Every rollup
 * window is computed from it (rule R-R3), and the packaged retention reports read it through
 * fiscal year date literals, so the totals and the reports always measure the same year and
 * there is nothing for an administrator to keep in step.
 *
 * `Organization` is a standard object every org has, and it is not one of the objects Core is
 * forbidden to touch (plan Section 4.2), so reading it costs Core nothing on a Platform-only
 * org. The queries live in a selector because every SOQL statement does (plan Section 7.1).
 */
@NamespaceAccessible
public with sharing class FiscalYearSelector {
    /**
     * Injected by tests, which cannot change the fiscal year in Setup. Held as the value the
     * org returned, so an injected value goes through the same check a real one does.
     */
    @TestVisible
    private static Integer startMonthOverride;

    @TestVisible
    private static Boolean customFiscalYearsOverride;

    /** Read once per transaction: a rollup run asks once for every fiscal definition. */
    @TestVisible
    private static Integer cachedStartMonth;

    /**
     * The month the org's fiscal year starts, 1 for January through 12 for December. Every
     * fiscal rollup window and every check that names a fiscal year reads this one method.
     *
     * System mode, deliberately. The month is org configuration, not record data: no sharing
     * rule or field permission governs it, and every user already sees its effect in any
     * report filtered on a fiscal year. In user mode the read would depend on who runs it, and
     * the rollups run as whoever saved a record, as the user who scheduled the nightly run, and
     * as the Automated Process user for platform event work, none of whom need be an
     * administrator. A total measured from January for one runner and from July for another
     * would be silently wrong, so the read must not depend on the runner. January is the
     * answer only when the org returns no month at all, which the platform does not do in
     * practice.
     */
    @NamespaceAccessible
    public static Integer fiscalYearStartMonth() {
        if (startMonthOverride != null) {
            return validMonthOrJanuary(startMonthOverride);
        }
        if (cachedStartMonth == null) {
            cachedStartMonth = validMonthOrJanuary(readOrgStartMonth());
        }
        return cachedStartMonth;
    }

    /**
     * Sets the org's fiscal year start month for the rest of a test, from a module's test,
     * where `@TestVisible` does not reach once the packages are separate. Null goes back to
     * reading the org. Does nothing outside a test.
     */
    @NamespaceAccessible
    public static void setTestStartMonth(Integer month) {
        if (Test.isRunningTest()) {
            startMonthOverride = month;
        }
    }

    /**
     * Whether the org has defined a custom fiscal year (Setup's custom fiscal year option).
     * Report date literals then follow the custom periods while BarnCRM windows stay whole
     * years from the start month, so Health Check says so. False when it cannot be read: an
     * answer nobody could read is not evidence of a custom year. Queried dynamically, so an
     * org without the object still compiles, and in system mode for the reason given on
     * fiscalYearStartMonth.
     */
    public static Boolean usesCustomFiscalYears() {
        if (customFiscalYearsOverride != null) {
            return customFiscalYearsOverride;
        }
        try {
            List<SObject> customYears = Database.query(
                'SELECT Id FROM FiscalYearSettings WHERE IsStandardYear = false LIMIT 1',
                AccessLevel.SYSTEM_MODE
            );
            return !customYears.isEmpty();
        } catch (Exception cannotRead) {
            return false;
        }
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

    private static Integer readOrgStartMonth() {
        try {
            List<Organization> organizations = [
                SELECT FiscalYearStartMonth
                FROM Organization
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            return organizations.isEmpty() ? null : organizations[0].FiscalYearStartMonth;
        } catch (QueryException cannotRead) {
            return null;
        }
    }

    private static Integer validMonthOrJanuary(Integer month) {
        return month != null && month >= 1 && month <= 12 ? month : 1;
    }
}
