/**
 * What the Service Delivery Log panel on a program calls (P-02, canonical model Section 29ZB).
 *
 * For one of the program's active services and one day, lists everyone with an open enrollment
 * (Applied or Enrolled) with what is recorded for them that day, and saves the attendance and
 * quantities in one go: one delivery per person per service per day, changing the row that is
 * there rather than adding another (R-SD4). Reads and writes in user mode, through the delivery
 * rules like any other save. Returns plain wrappers (plan Section 9.9). Anything unexpected is
 * recorded in the Error Log before it is reported (plan Section 7.2).
 */
public with sharing class ServiceDeliveryLogController {
    private static final String CONTEXT = 'Service delivery log panel';
    /** The most people listed: a bound on the read; the Service Deliveries tab lists them all. */
    public static final Integer MAX_SHOWN = 200;

    public class Option {
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String value;
        /** For a service: its unit of measure. */
        @AuraEnabled
        public String unit;
    }

    /** One person in the log, with what is recorded for them that day, if anything. */
    public class Row {
        @AuraEnabled
        public String key;
        @AuraEnabled
        public String personName;
        @AuraEnabled
        public Id contactId;
        @AuraEnabled
        public Id accountId;
        @AuraEnabled
        public Id enrollmentId;
        @AuraEnabled
        public Id deliveryId;
        @AuraEnabled
        public String attendance;
        @AuraEnabled
        public Decimal quantity;
    }

    /** One person's attendance and quantity to save. */
    public class Entry {
        @AuraEnabled
        public Id contactId { get; set; }
        @AuraEnabled
        public Id accountId { get; set; }
        @AuraEnabled
        public Id enrollmentId { get; set; }
        @AuraEnabled
        public Id deliveryId { get; set; }
        @AuraEnabled
        public String attendance { get; set; }
        @AuraEnabled
        public Decimal quantity { get; set; }
    }

    /** The panel's whole state. */
    public class Log {
        @AuraEnabled
        public List<Option> services = new List<Option>();
        @AuraEnabled
        public Id serviceId;
        @AuraEnabled
        public Date deliveryDate;
        @AuraEnabled
        public List<Option> attendance = new List<Option>();
        @AuraEnabled
        public List<Row> rows = new List<Row>();
        @AuraEnabled
        public Boolean moreThanShown = false;
        @AuraEnabled
        public Boolean canEdit = false;
        /** How many deliveries the last save wrote, 0 on a plain read. */
        @AuraEnabled
        public Integer saved = 0;
    }

    /**
     * The log for this service and day; the program's first active service and today when not
     * given. Not cacheable: it changes with every save.
     */
    @AuraEnabled
    public static Log getLog(Id programId, Id serviceId, Date deliveryDate) {
        if (programId == null) {
            throw UserErrors.message(Label.Programs_Log_ActionFailed);
        }
        try {
            return logFor(programId, serviceId, deliveryDate);
        } catch (Exception failure) {
            throw report(failure, programId);
        }
    }

    /** Saves these entries for the service and day, then returns the log as it now stands. */
    @AuraEnabled
    public static Log save(Id programId, Id serviceId, Date deliveryDate, List<Entry> entries) {
        if (programId == null || serviceId == null || deliveryDate == null) {
            throw UserErrors.message(Label.Programs_Log_ActionFailed);
        }
        try {
            List<Service_Delivery__c> toInsert = new List<Service_Delivery__c>();
            List<Service_Delivery__c> toUpdate = new List<Service_Delivery__c>();
            Set<String> allowed = new Set<String>(ServiceDeliveryService.ATTENDANCE);
            for (Entry entry : entries == null ? new List<Entry>() : entries) {
                if (String.isBlank(entry.attendance)) {
                    continue;
                }
                if (!allowed.contains(entry.attendance)) {
                    throw UserErrors.message(Label.Programs_Log_ActionFailed);
                }
                Decimal quantity = ServiceDeliveryService.isAbsence(entry.attendance)
                    ? 0
                    : (entry.quantity == null ? 1 : entry.quantity);
                if (entry.deliveryId != null) {
                    toUpdate.add(
                        new Service_Delivery__c(
                            Id = entry.deliveryId,
                            Attendance__c = entry.attendance,
                            Quantity__c = quantity
                        )
                    );
                } else {
                    toInsert.add(
                        new Service_Delivery__c(
                            Service__c = serviceId,
                            Delivery_Date__c = deliveryDate,
                            Contact__c = entry.contactId,
                            Account__c = entry.accountId,
                            Enrollment__c = entry.enrollmentId,
                            Attendance__c = entry.attendance,
                            Quantity__c = quantity
                        )
                    );
                }
            }
            List<Service_Delivery__c> toChangeHidden = new List<Service_Delivery__c>();
            toInsert = keepOneRow(toInsert, toUpdate, toChangeHidden);
            Database.insert(toInsert, AccessLevel.USER_MODE);
            Database.update(toUpdate, AccessLevel.USER_MODE);
            ServiceDeliveryIntegrity.changeHidden(toChangeHidden);
            Log log = logFor(programId, serviceId, deliveryDate);
            log.saved = toInsert.size() + toUpdate.size() + toChangeHidden.size();
            return log;
        } catch (Exception failure) {
            throw report(failure, programId);
        }
    }

    /**
     * One row per person, service and day (R-SD4), even when the day's row is one the user
     * cannot see: under the Private preset a delivery somebody else logged is hidden, so the
     * log offers the person as unrecorded. Each new row whose person already has a delivery that
     * day becomes a change to that delivery instead: through `toUpdate` (user mode) when the user
     * can see it, through `toChangeHidden` (`ServiceDeliveryIntegrity`) when not. Returns the
     * rows still to insert.
     */
    private static List<Service_Delivery__c> keepOneRow(
        List<Service_Delivery__c> toInsert,
        List<Service_Delivery__c> toUpdate,
        List<Service_Delivery__c> toChangeHidden
    ) {
        if (toInsert.isEmpty() || !ServiceDeliveryIntegrity.canChange()) {
            return toInsert;
        }
        Set<Id> people = new Set<Id>();
        for (Service_Delivery__c row : toInsert) {
            people.add(row.Contact__c != null ? row.Contact__c : row.Account__c);
        }
        people.remove(null);
        Map<Id, Id> existing = ServiceDeliveryIntegrity.existingDeliveryIds(
            toInsert[0].Service__c,
            toInsert[0].Delivery_Date__c,
            people
        );
        if (existing.isEmpty()) {
            return toInsert;
        }
        Set<Id> existingIds = new Set<Id>(existing.values());
        Set<Id> visible = new Map<Id, Service_Delivery__c>(
                [SELECT Id FROM Service_Delivery__c WHERE Id IN :existingIds WITH USER_MODE]
            )
            .keySet();
        List<Service_Delivery__c> stillNew = new List<Service_Delivery__c>();
        for (Service_Delivery__c row : toInsert) {
            Id deliveryId = existing.get(row.Contact__c != null ? row.Contact__c : row.Account__c);
            if (deliveryId == null) {
                stillNew.add(row);
                continue;
            }
            Service_Delivery__c change = new Service_Delivery__c(
                Id = deliveryId,
                Attendance__c = row.Attendance__c,
                Quantity__c = row.Quantity__c
            );
            if (visible.contains(deliveryId)) {
                toUpdate.add(change);
            } else {
                toChangeHidden.add(change);
            }
        }
        return stillNew;
    }

    private static Log logFor(Id programId, Id serviceId, Date deliveryDate) {
        Log log = new Log();
        log.deliveryDate = deliveryDate == null ? Date.today() : deliveryDate;
        log.canEdit =
            Schema.SObjectType.Service_Delivery__c.isCreateable() &&
            Schema.SObjectType.Service_Delivery__c.isUpdateable();
        for (
            Schema.PicklistEntry entry : Service_Delivery__c.Attendance__c.getDescribe()
                .getPicklistValues()
        ) {
            if (entry.isActive()) {
                Option option = new Option();
                option.label = entry.getLabel();
                option.value = entry.getValue();
                log.attendance.add(option);
            }
        }
        for (Service__c service : ServiceDeliverySelector.selectActiveServices(programId)) {
            Option option = new Option();
            option.label = service.Name;
            option.value = service.Id;
            option.unit = service.Unit_Of_Measure__c;
            log.services.add(option);
            if (service.Id == serviceId || (serviceId == null && log.serviceId == null)) {
                log.serviceId = service.Id;
            }
        }
        if (log.serviceId == null) {
            return log;
        }

        Map<Id, Service_Delivery__c> deliveryByPerson = new Map<Id, Service_Delivery__c>();
        for (
            Service_Delivery__c delivery : ServiceDeliverySelector.selectDeliveriesOn(
                log.serviceId,
                log.deliveryDate,
                MAX_SHOWN + 1
            )
        ) {
            Id person = delivery.Contact__c != null ? delivery.Contact__c : delivery.Account__c;
            if (person != null && !deliveryByPerson.containsKey(person)) {
                deliveryByPerson.put(person, delivery);
            }
        }
        List<Enrollment__c> open = EnrollmentSelector.selectRoster(
            programId,
            EnrollmentService.OPEN_STAGES,
            MAX_SHOWN + 1
        );
        log.moreThanShown = open.size() > MAX_SHOWN;
        Set<Id> listed = new Set<Id>();
        for (Integer i = 0; i < open.size() && i < MAX_SHOWN; i++) {
            Enrollment__c enrollment = open[i];
            Id person = enrollment.Contact__c != null
                ? enrollment.Contact__c
                : enrollment.Account__c;
            if (person == null || listed.contains(person)) {
                continue;
            }
            listed.add(person);
            Row row = new Row();
            row.key = person;
            row.contactId = enrollment.Contact__c;
            row.accountId = enrollment.Account__c;
            row.enrollmentId = enrollment.Id;
            row.personName = enrollment.Contact__c != null
                ? enrollment.Contact__r.Name
                : enrollment.Account__r.Name;
            fill(row, deliveryByPerson.get(person));
            log.rows.add(row);
        }
        // Someone recorded that day without an open enrollment is still shown, after the rest.
        for (Id person : deliveryByPerson.keySet()) {
            if (listed.contains(person)) {
                continue;
            }
            Service_Delivery__c delivery = deliveryByPerson.get(person);
            Row row = new Row();
            row.key = person;
            row.contactId = delivery.Contact__c;
            row.accountId = delivery.Account__c;
            row.enrollmentId = delivery.Enrollment__c;
            row.personName = delivery.Contact__c != null
                ? delivery.Contact__r.Name
                : delivery.Account__r.Name;
            fill(row, delivery);
            log.rows.add(row);
        }
        return log;
    }

    private static void fill(Row row, Service_Delivery__c delivery) {
        if (delivery != null) {
            row.deliveryId = delivery.Id;
            row.attendance = delivery.Attendance__c;
            row.quantity = delivery.Quantity__c;
        }
    }

    /** A refusal is passed on in its own words; anything else is logged first. */
    private static AuraHandledException report(Exception failure, Id recordId) {
        if (failure instanceof AuraHandledException) {
            return (AuraHandledException) failure;
        }
        if (failure instanceof DmlException) {
            return UserErrors.message(((DmlException) failure).getDmlMessage(0));
        }
        ErrorLogger.log(failure, CONTEXT, recordId);
        return UserErrors.message(Label.Programs_Log_ActionFailed);
    }
}
