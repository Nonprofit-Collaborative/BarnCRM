/**
 * The rules of a grant payment (canonical model 29ZM, ADR-0162
 * `0162-funders-restricted-funds-schedules-calendar.md`): the statuses (R-GP1), building a
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

    /**
     * R-GP3, the ledger half: keeps one Received entry per received payment of a restricted
     * grant in step with it. Added when the payment is Received, changed with its amount or date,
     * removed when it leaves Received or is deleted. Entries typed by hand name no payment and are
     * never touched; a grant that is not restricted gets no new entry.
     *
     * Runs in system mode on purpose: the entry's Payment field is set by BarnCRM only (read only
     * for staff), and the person already saved the payment the entry copies.
     *
     * @param payments the payments saved, or being deleted
     * @param deleting true from before delete: their entries go
     */
    public static void syncLedger(List<Grant_Payment__c> payments, Boolean deleting) {
        Set<Id> paymentIds = new Map<Id, Grant_Payment__c>(payments).keySet();
        Map<Id, Grant_Fund_Entry__c> entryByPayment = new Map<Id, Grant_Fund_Entry__c>();
        for (Grant_Fund_Entry__c entry : [
            SELECT Id, Grant_Payment__c, Amount__c, Entry_Date__c
            FROM Grant_Fund_Entry__c
            WHERE Grant_Payment__c IN :paymentIds
            WITH SYSTEM_MODE
        ]) {
            entryByPayment.put(entry.Grant_Payment__c, entry);
        }
        Set<Id> restricted = deleting ? new Set<Id>() : restrictedGrants(payments);
        List<Grant_Fund_Entry__c> toUpsert = new List<Grant_Fund_Entry__c>();
        List<Grant_Fund_Entry__c> toDelete = new List<Grant_Fund_Entry__c>();
        for (Grant_Payment__c payment : payments) {
            Grant_Fund_Entry__c entry = entryByPayment.get(payment.Id);
            if (deleting || payment.Status__c != STATUS_RECEIVED) {
                if (entry != null) {
                    toDelete.add(entry);
                }
                continue;
            }
            Date entryDate = payment.Received_Date__c == null
                ? Date.today()
                : payment.Received_Date__c;
            if (entry == null && restricted.contains(payment.Grant__c)) {
                toUpsert.add(
                    new Grant_Fund_Entry__c(
                        Grant__c = payment.Grant__c,
                        Grant_Payment__c = payment.Id,
                        Type__c = STATUS_RECEIVED,
                        Amount__c = payment.Amount__c,
                        Entry_Date__c = entryDate,
                        Description__c = payment.Name
                    )
                );
            } else if (
                entry != null &&
                (entry.Amount__c != payment.Amount__c ||
                entry.Entry_Date__c != entryDate)
            ) {
                entry.Amount__c = payment.Amount__c;
                entry.Entry_Date__c = entryDate;
                toUpsert.add(entry);
            }
        }
        if (!toDelete.isEmpty()) {
            Database.delete(toDelete, AccessLevel.SYSTEM_MODE);
        }
        if (!toUpsert.isEmpty()) {
            Database.upsert(toUpsert, AccessLevel.SYSTEM_MODE);
        }
    }

    /** The grants among these received payments' that are Restricted. */
    private static Set<Id> restrictedGrants(List<Grant_Payment__c> payments) {
        Set<Id> grantIds = new Set<Id>();
        for (Grant_Payment__c payment : payments) {
            if (payment.Status__c == STATUS_RECEIVED) {
                grantIds.add(payment.Grant__c);
            }
        }
        Set<Id> restricted = new Set<Id>();
        if (grantIds.isEmpty()) {
            return restricted;
        }
        for (Grant__c grant : [
            SELECT Id
            FROM Grant__c
            WHERE Id IN :grantIds AND Restricted__c = TRUE
            WITH SYSTEM_MODE
        ]) {
            restricted.add(grant.Id);
        }
        return restricted;
    }

    /**
     * Marks one payment Received, as the person: the received automation fills the date and
     * writes the ledger entry. Returns what it replaced, for Undo (modules-17).
     */
    public static FundersUndoState markReceived(Id paymentId) {
        FundersUndoState previous = new FundersUndoState();
        for (Grant_Payment__c row : [
            SELECT Id, Status__c, Received_Date__c
            FROM Grant_Payment__c
            WHERE Id = :paymentId
            WITH USER_MODE
            LIMIT 1
        ]) {
            previous.id = row.Id;
            previous.status = row.Status__c;
            previous.dateValue = row.Received_Date__c;
        }
        update as user new Grant_Payment__c(Id = paymentId, Status__c = STATUS_RECEIVED);
        return previous;
    }

    /**
     * Undo for Mark Received (modules-17): puts back the Expected status and the Received Date the
     * payment had, as the person, and removes the Received ledger entry the mark wrote. The
     * received automation removes it when the payment leaves Received; it is removed here too in
     * case that automation was switched off in between. Only a payment still Received goes back,
     * and only to Expected.
     *
     * @return true when it was put back
     */
    public static Boolean undoReceived(Id paymentId, String status, Date receivedDate) {
        if (paymentId == null || status != STATUS_EXPECTED) {
            return false;
        }
        List<Grant_Payment__c> rows = [
            SELECT Id, Status__c
            FROM Grant_Payment__c
            WHERE Id = :paymentId
            WITH USER_MODE
            LIMIT 1
        ];
        if (rows.isEmpty() || rows[0].Status__c != STATUS_RECEIVED) {
            return false;
        }
        update as user new Grant_Payment__c(
            Id = paymentId,
            Status__c = status,
            Received_Date__c = receivedDate
        );
        // System mode as in syncLedger: the entry's Payment field is set by BarnCRM only.
        List<Grant_Fund_Entry__c> entries = [
            SELECT Id
            FROM Grant_Fund_Entry__c
            WHERE Grant_Payment__c = :paymentId AND Type__c = :STATUS_RECEIVED
            WITH SYSTEM_MODE
        ];
        if (!entries.isEmpty()) {
            Database.delete(entries, AccessLevel.SYSTEM_MODE);
        }
        return true;
    }
}
