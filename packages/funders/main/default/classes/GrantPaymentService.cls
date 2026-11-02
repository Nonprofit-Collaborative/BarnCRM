/**
 * The rules of a grant payment (canonical model 29ZM, ADR-NEXT
 * `NEXT-funders-restricted-funds-schedules-calendar.md`): the statuses (R-GP1), building a
 * schedule (R-GP2) and the received date (R-GP3).
 *
 * The split of a schedule is worked out in the browser (`grantScheduleModel`, plan 9.9); this
 * class checks the rows it is handed and saves them as the person.
 */
public with sharing class GrantPaymentService {
    public static final String STATUS_EXPECTED = 'Expected';
    public static final String STATUS_RECEIVED = 'Received';
    public static final String STATUS_CANCELLED = 'Cancelled';

    /** The statuses that make a payment part of the schedule: anything but Cancelled. */
    public static final List<String> LIVE_STATUSES = new List<String>{
        STATUS_EXPECTED,
        STATUS_RECEIVED
    };

    /** The most payments one schedule may hold: monthly for ten years. */
    public static final Integer MAX_PAYMENTS = 120;

    /** Thrown with a message a person can act on. */
    public class PaymentException extends Exception {
    }

    /** One row of a schedule to save. */
    public class Row {
        public Date dueDate;
        public Decimal amount;
    }

    /**
     * R-GP3: an empty Received Date becomes today when a payment becomes Received. A date already
     * there is kept.
     *
     * @param payments the payments being saved
     * @param oldById their saved versions, null on insert
     */
    public static void fillReceivedDates(
        List<Grant_Payment__c> payments,
        Map<Id, Grant_Payment__c> oldById
    ) {
        Date today = Date.today();
        for (Grant_Payment__c payment : payments) {
            Grant_Payment__c old = oldById == null ? null : oldById.get(payment.Id);
            if (old != null && old.Status__c == payment.Status__c) {
                continue;
            }
            if (payment.Status__c == STATUS_RECEIVED && payment.Received_Date__c == null) {
                payment.Received_Date__c = today;
            }
        }
    }

    /**
     * R-GP2: whether a schedule can be built for the grant: Awarded, with Amount Awarded above
     * zero and both award dates, and no Expected or Received payment.
     *
     * @param grant the grant, with its stage, amount awarded and award dates
     * @param livePayments how many of its payments are Expected or Received
     */
    public static Boolean canBuild(Grant__c grant, Integer livePayments) {
        return grant != null &&
            grant.Stage__c == GrantService.STAGE_AWARDED &&
            grant.Amount_Awarded__c != null &&
            grant.Amount_Awarded__c > 0 &&
            grant.Award_Start_Date__c != null &&
            grant.Award_End_Date__c != null &&
            grant.Award_End_Date__c >= grant.Award_Start_Date__c &&
            livePayments == 0;
    }

    /** How many of the grant's payments are Expected or Received, as the person sees them. */
    public static Integer livePayments(Id grantId) {
        return [
            SELECT COUNT()
            FROM Grant_Payment__c
            WHERE Grant__c = :grantId AND Status__c IN :LIVE_STATUSES
            WITH USER_MODE
        ];
    }

    /**
     * R-GP2: saves a built schedule as the person. Refused unless the grant can still be built,
     * and every row has a due date within the award period and an amount above zero, and the rows
     * add up to the amount awarded. The frequency they were split at is kept on the grant.
     *
     * @param grantId the grant
     * @param frequency a Payment Frequency value, or blank to leave the grant's as it is
     * @param rows the payments, as the browser split them
     */
    public static void saveSchedule(Id grantId, String frequency, List<Row> rows) {
        List<Grant__c> grants = [
            SELECT Id, Stage__c, Amount_Awarded__c, Award_Start_Date__c, Award_End_Date__c
            FROM Grant__c
            WHERE Id = :grantId
            WITH USER_MODE
            LIMIT 1
        ];
        Grant__c grant = grants.isEmpty() ? null : grants[0];
        if (!canBuild(grant, grant == null ? 0 : livePayments(grantId))) {
            throw new PaymentException(Label.Funders_Schedule_CannotBuild);
        }
        if (rows == null || rows.isEmpty() || rows.size() > MAX_PAYMENTS) {
            throw new PaymentException(Label.Funders_Schedule_ErrorRows);
        }
        Decimal total = 0;
        List<Grant_Payment__c> payments = new List<Grant_Payment__c>();
        for (Row row : rows) {
            if (
                row == null ||
                row.dueDate == null ||
                row.amount == null ||
                row.amount <= 0 ||
                row.dueDate < grant.Award_Start_Date__c ||
                row.dueDate > grant.Award_End_Date__c
            ) {
                throw new PaymentException(Label.Funders_Schedule_ErrorRows);
            }
            total += row.amount;
            payments.add(
                new Grant_Payment__c(
                    Grant__c = grantId,
                    Due_Date__c = row.dueDate,
                    Amount__c = row.amount,
                    Status__c = STATUS_EXPECTED
                )
            );
        }
        if (total != grant.Amount_Awarded__c) {
            throw new PaymentException(Label.Funders_Schedule_ErrorRows);
        }
        Database.insert(payments, AccessLevel.USER_MODE);
        if (String.isNotBlank(frequency)) {
            Database.update(
                new Grant__c(Id = grantId, Payment_Frequency__c = frequency),
                AccessLevel.USER_MODE
            );
        }
    }

    /** Marks one payment Received, as the person: the received automation fills the date. */
    public static void markReceived(Id paymentId) {
        update as user new Grant_Payment__c(Id = paymentId, Status__c = STATUS_RECEIVED);
    }
}
