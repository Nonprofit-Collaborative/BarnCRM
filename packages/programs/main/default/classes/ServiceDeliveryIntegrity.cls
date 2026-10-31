/**
 * Keeps the Service Delivery Log at one delivery per person, service and day (R-SD4) when the
 * day's delivery is one the saving user cannot see. ADR-0021 (system mode for package owned
 * data).
 *
 * DOCUMENTED EXCEPTION to the user mode rule (plan Section 4.13): under the Participant Privacy
 * Private preset (P-08), a delivery another staff member logged is invisible, so the log offers
 * that person as unrecorded and a plain save would add a second row. This class finds the
 * existing row whoever can see it and changes it instead, on these conditions:
 *
 * 1. **Permission checked first.** `canChange` requires update access to Service Delivery and to
 *    its Attendance and Quantity fields; without it the caller falls back to an ordinary user
 *    mode insert, which the platform refuses or allows as it would any save.
 * 2. **Only two fields written.** Attendance and Quantity, the two the log edits, on a row that
 *    already names the same person, service and day. Nothing else on it changes.
 * 3. **Nothing hidden is returned.** Only the row's Id leaves the read, and only to be written
 *    back; the log is then re-read in user mode, so the hidden row still does not show.
 */
public without sharing class ServiceDeliveryIntegrity {
    /** Whether the running user may change a delivery's attendance and quantity at all. */
    public static Boolean canChange() {
        Schema.DescribeSObjectResult deliveries = Schema.SObjectType.Service_Delivery__c;
        return deliveries.isUpdateable() &&
            Schema.SObjectType.Service_Delivery__c.fields.Attendance__c.isUpdateable() &&
            Schema.SObjectType.Service_Delivery__c.fields.Quantity__c.isUpdateable();
    }

    /**
     * The existing delivery for each of these people on this service and day, keyed by the
     * person's contact or account Id, whoever logged it. The first one made wins, as in the log.
     */
    public static Map<Id, Id> existingDeliveryIds(
        Id serviceId,
        Date deliveryDate,
        Set<Id> personIds
    ) {
        Map<Id, Id> byPerson = new Map<Id, Id>();
        if (serviceId == null || deliveryDate == null || personIds.isEmpty()) {
            return byPerson;
        }
        for (Service_Delivery__c delivery : [
            SELECT Id, Contact__c, Account__c
            FROM Service_Delivery__c
            WHERE
                Service__c = :serviceId
                AND Delivery_Date__c = :deliveryDate
                AND (Contact__c IN :personIds
                OR Account__c IN :personIds)
            WITH SYSTEM_MODE
            ORDER BY CreatedDate, Name
        ]) {
            Id person = delivery.Contact__c != null ? delivery.Contact__c : delivery.Account__c;
            if (!byPerson.containsKey(person)) {
                byPerson.put(person, delivery.Id);
            }
        }
        return byPerson;
    }

    /** Writes attendance and quantity onto existing rows the user may not be able to see. */
    public static void changeHidden(List<Service_Delivery__c> changes) {
        if (changes.isEmpty()) {
            return;
        }
        List<Service_Delivery__c> plain = new List<Service_Delivery__c>();
        for (Service_Delivery__c change : changes) {
            plain.add(
                new Service_Delivery__c(
                    Id = change.Id,
                    Attendance__c = change.Attendance__c,
                    Quantity__c = change.Quantity__c
                )
            );
        }
        Database.update(plain, true, AccessLevel.SYSTEM_MODE);
    }
}
