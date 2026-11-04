/**
 * The Grant Calendar tab (F-08, ADR-0162 `0162-funders-restricted-funds-schedules-calendar.md`
 * decision 8): the application deadlines, requirement due dates and expected payments between
 * two dates, for everyone or the person's own.
 *
 * Thin by design (plan Section 9.9): the rows come from `GrantDeadlineSelector`, the reader the
 * Grant Pipeline's Upcoming Deadlines uses, in the pipeline's row shape; laying them into weeks
 * happens in the browser module `grantCalendarModel`. Everything runs as the person.
 */
public with sharing class GrantCalendarController {
    private static final String CONTEXT = 'GrantCalendarController';
    public static final String KIND_PAYMENT = 'payment';
    /** The longest range one call reads: six weeks, the most a month view shows. */
    public static final Integer MAX_DAYS = 42;
    private static final Integer MAX_ROWS = 500;

    /** What the tab draws. */
    public class Calendar {
        @AuraEnabled
        public Date today;
        @AuraEnabled
        public List<GrantPipelineController.Card> rows = new List<GrantPipelineController.Card>();
        /** A kind reached the row limit, so some rows may be missing. */
        @AuraEnabled
        public Boolean truncated = false;
        /** The payment object's label, read by describe, for the payment rows. */
        @AuraEnabled
        public String paymentLabel;
        /** The requirement object's label, read by describe, for the colour legend. */
        @AuraEnabled
        public String requirementLabel;
    }

    /**
     * The rows between two dates, both included.
     *
     * @param fromDate the first day shown
     * @param toDate the last day shown, at most six weeks after the first
     * @param mineOnly only the person's own grants and requirements
     */
    @AuraEnabled
    public static Calendar getCalendar(Date fromDate, Date toDate, Boolean mineOnly) {
        if (fromDate == null || toDate == null || toDate < fromDate) {
            throw UserErrors.message(BarnHelp.text('Funders', 'Funders_Calendar_LoadFailed'));
        }
        try {
            if (fromDate.daysBetween(toDate) >= MAX_DAYS) {
                toDate = fromDate.addDays(MAX_DAYS - 1);
            }
            Calendar calendar = new Calendar();
            calendar.today = Date.today();
            calendar.paymentLabel = Schema.SObjectType.Grant_Payment__c.getLabel();
            calendar.requirementLabel = Schema.SObjectType.Grant_Requirement__c.getLabel();

            List<Grant__c> applications = GrantDeadlineSelector.applications(
                fromDate,
                toDate,
                mineOnly,
                MAX_ROWS
            );
            for (Grant__c grant : applications) {
                GrantPipelineController.Card row = GrantPipelineController.toCard(grant);
                row.kind = GrantPipelineController.KIND_APPLICATION;
                calendar.rows.add(row);
            }
            List<Grant_Requirement__c> requirements = GrantDeadlineSelector.requirements(
                fromDate,
                toDate,
                mineOnly,
                MAX_ROWS
            );
            for (Grant_Requirement__c requirement : requirements) {
                calendar.rows.add(GrantPipelineController.toRequirementRow(requirement));
            }
            List<Grant_Payment__c> payments = GrantDeadlineSelector.expectedPayments(
                fromDate,
                toDate,
                mineOnly,
                MAX_ROWS
            );
            for (Grant_Payment__c payment : payments) {
                calendar.rows.add(toPaymentRow(payment));
            }
            calendar.truncated =
                applications.size() == MAX_ROWS ||
                requirements.size() == MAX_ROWS ||
                payments.size() == MAX_ROWS;
            return calendar;
        } catch (Exception e) {
            ErrorLogger.log(e, CONTEXT + '.getCalendar');
            throw UserErrors.message(BarnHelp.text('Funders', 'Funders_Calendar_LoadFailed'));
        }
    }

    private static GrantPipelineController.Card toPaymentRow(Grant_Payment__c payment) {
        GrantPipelineController.Card row = new GrantPipelineController.Card();
        row.id = payment.Id;
        row.name = payment.Name;
        row.kind = KIND_PAYMENT;
        row.deadline = payment.Due_Date__c;
        row.amount = payment.Amount__c;
        row.grantId = payment.Grant__c;
        row.grantName = payment.Grant__r?.Name;
        row.funderId = payment.Grant__r?.Funder__c;
        row.funderName = payment.Grant__r?.Funder__r?.Name;
        row.ownerName = payment.Grant__r?.Owner?.Name;
        return row;
    }
}
