/**
 * The reads behind the accounting export (feature X-04), all in user mode, so the file holds
 * the gifts the person running it can see, like any report (ADR-0051).
 *
 * Rows are handed to a sink in SOQL for loop chunks rather than returned as one list, so a
 * large range costs heap for the file being built, not for every record at once.
 */
public with sharing class AccountingExportSelector {
    /** Receives the rows in order. */
    public interface RowSink {
        /** One allocation of one gift; returns false to stop reading. */
        Boolean allocation(Gift_Allocation__c row);
        /** One gift that has no allocation at all; returns false to stop reading. */
        Boolean unallocatedGift(Gift__c row);
    }

    /**
     * Every allocation of every gift dated inside the range with one of these statuses and
     * payment methods, narrowed to one fund when fundId is set, then (only when it is not) every
     * such gift with no allocation, so that no money is left out of an unfiltered file.
     */
    public static void read(
        Date fromDate,
        Date toDate,
        Id fundId,
        Set<String> paymentMethods,
        Set<String> statuses,
        RowSink sink
    ) {
        if (fundId != null) {
            for (List<Gift_Allocation__c> chunk : [
                SELECT
                    Amount__c,
                    Gift__c,
                    Fund__c,
                    Fund__r.Name,
                    Fund__r.Accounting_Code__c,
                    Gift__r.Name,
                    Gift__r.Gift_Date__c,
                    Gift__r.Type__c,
                    Gift__r.Payment_Reference__c,
                    Gift__r.Accounting_Posted_At__c,
                    Gift__r.Original_Gift__r.Name,
                    Gift__r.Donor_Contact__r.Name,
                    Gift__r.Donor_Account__r.Name
                FROM Gift_Allocation__c
                WHERE
                    Fund__c = :fundId
                    AND Gift__r.Gift_Date__c >= :fromDate
                    AND Gift__r.Gift_Date__c <= :toDate
                    AND Gift__r.Type__c IN :paymentMethods
                    AND Gift__r.Status__c IN :statuses
                WITH USER_MODE
                ORDER BY Gift__r.Gift_Date__c, Gift__r.Name, Fund__r.Name
            ]) {
                if (!offer(chunk, sink)) {
                    return;
                }
            }
            return;
        }
        for (List<Gift_Allocation__c> chunk : [
            SELECT
                Amount__c,
                Gift__c,
                Fund__c,
                Fund__r.Name,
                Fund__r.Accounting_Code__c,
                Gift__r.Name,
                Gift__r.Gift_Date__c,
                Gift__r.Type__c,
                Gift__r.Payment_Reference__c,
                Gift__r.Accounting_Posted_At__c,
                Gift__r.Original_Gift__r.Name,
                Gift__r.Donor_Contact__r.Name,
                Gift__r.Donor_Account__r.Name
            FROM Gift_Allocation__c
            WHERE
                Gift__r.Gift_Date__c >= :fromDate
                AND Gift__r.Gift_Date__c <= :toDate
                AND Gift__r.Type__c IN :paymentMethods
                AND Gift__r.Status__c IN :statuses
            WITH USER_MODE
            ORDER BY Gift__r.Gift_Date__c, Gift__r.Name, Fund__r.Name
        ]) {
            if (!offer(chunk, sink)) {
                return;
            }
        }
        for (List<Gift__c> chunk : [
            SELECT
                Id,
                Name,
                Amount__c,
                Gift_Date__c,
                Type__c,
                Payment_Reference__c,
                Accounting_Posted_At__c,
                Original_Gift__r.Name,
                Donor_Contact__r.Name,
                Donor_Account__r.Name
            FROM Gift__c
            WHERE
                Gift_Date__c >= :fromDate
                AND Gift_Date__c <= :toDate
                AND Type__c IN :paymentMethods
                AND Status__c IN :statuses
                AND Amount__c != NULL
                AND Id NOT IN (SELECT Gift__c FROM Gift_Allocation__c)
            WITH USER_MODE
            ORDER BY Gift_Date__c, Name
        ]) {
            for (Gift__c gift : chunk) {
                if (!sink.unallocatedGift(gift)) {
                    return;
                }
            }
        }
    }

    private static Boolean offer(List<Gift_Allocation__c> chunk, RowSink sink) {
        for (Gift_Allocation__c row : chunk) {
            if (!sink.allocation(row)) {
                return false;
            }
        }
        return true;
    }
}
