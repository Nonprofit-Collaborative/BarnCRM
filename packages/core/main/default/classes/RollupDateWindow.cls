/**
 * The fiscal year window a fiscal-aware rollup is limited to.
 *
 * Canonical model R-R3: the window is never stored on the definition. It is computed at run time
 * from the org's fiscal year start month (BarnCRM Settings `Fiscal_Year_Start_Month__c`) and the
 * definition's Fiscal Year Offset, so changing the start month and recalculating corrects every
 * fiscal total in the org without touching a single definition.
 *
 * Offset 0 is the fiscal year the org is in today, -1 the one before it, -2 the one before that.
 * A window runs from the first day of the start month, inclusive, to the same day one year later,
 * exclusive, so a gift dated on a boundary lands in exactly one window, the later one.
 */
public with sharing class RollupDateWindow {
    /** Raised when a definition asks for a fiscal window it cannot have. */
    public class RollupDateWindowException extends Exception {
    }

    @TestVisible
    private static Date todayOverride;

    /** One fiscal year, as the two dates that bound it. */
    public class Window {
        public Date startInclusive;
        public Date endExclusive;

        private Window(Date startInclusive, Date endExclusive) {
            this.startInclusive = startInclusive;
            this.endExclusive = endExclusive;
        }
    }

    /**
     * The month the fiscal year starts, 1 through 12, defaulting to January when the setting has
     * never been touched or holds something the platform cannot mean.
     */
    public static Integer fiscalYearStartMonth() {
        Object stored = SettingsService.getValue('Fiscal_Year_Start_Month__c');
        if (stored == null) {
            return 1;
        }
        Integer month;
        try {
            month = Integer.valueOf(String.valueOf(stored));
        } catch (Exception ignored) {
            return 1;
        }
        return month >= 1 && month <= 12 ? month : 1;
    }

    /** The window for an offset, counted back from the fiscal year the org is in today. */
    public static Window windowFor(Integer offset) {
        Integer resolvedOffset = offset == null ? 0 : offset;
        Integer startMonth = fiscalYearStartMonth();
        Date today = todayOverride == null ? Date.today() : todayOverride;
        Integer currentFiscalStartYear = today.month() >= startMonth
            ? today.year()
            : today.year() - 1;
        Date windowStart = Date.newInstance(currentFiscalStartYear + resolvedOffset, startMonth, 1);
        return new Window(windowStart, windowStart.addYears(1));
    }

    /**
     * The window as a where clause fragment over one date attribute, or an empty string when the
     * definition is not fiscal-year aware.
     *
     * The attribute is the one the definition aggregates for a date aggregate, and for a currency
     * aggregate it is the date attribute the caller names. A fiscal-aware definition with no date
     * attribute to bound is a definition that cannot be built, and it is refused rather than
     * silently returning every record.
     */
    public static String toWhereClause(
        Boolean fiscalYearAware,
        Integer offset,
        String dateFieldName
    ) {
        if (fiscalYearAware != true) {
            return '';
        }
        if (String.isBlank(dateFieldName)) {
            throw new RollupDateWindowException(System.Label.Core_Rollups_ErrorInvalidFilter);
        }
        Window window = windowFor(offset);
        return dateFieldName +
            ' >= ' +
            String.valueOf(window.startInclusive) +
            ' AND ' +
            dateFieldName +
            ' < ' +
            String.valueOf(window.endExclusive);
    }
}
