/**
 * Attendance taken on a session (P-11, canonical model 29ZA6 and 29ZB, R-SE2, R-SE3, R-SD7), for
 * the Service Delivery Log panel on a session page through `ServiceDeliveryLogController`.
 *
 * The session gives the service and the day; the roster is the cohort's open enrollments (the
 * program's when the session has no cohort). Saving writes ordinary Service Deliveries naming the
 * session, one per person per session: a person's delivery of this session is changed rather
 * than added to, and their delivery for the same service and day that names no session is
 * adopted by the session. Saving marks a Scheduled session Held; a Cancelled session saves
 * nothing. User mode throughout, except the hidden-row exception `ServiceDeliveryIntegrity`
 * documents.
 */
public with sharing class SessionAttendance {
    public static final String SCHEDULED = 'Scheduled';
    public static final String HELD = 'Held';
    public static final String CANCELLED = 'Cancelled';

    /** The log for the session as it now stands. */
    public static ServiceDeliveryLogController.Log logFor(Id sessionId) {
        Session__c session = checkedSession(sessionId);
        ServiceDeliveryLogController.Log log = new ServiceDeliveryLogController.Log();
        log.sessionId = session.Id;
        log.sessionName = session.Name;
        log.sessionStatus = session.Status__c;
        log.cancelled = session.Status__c == CANCELLED;
        log.cohortName = session.Cohort__r == null ? null : session.Cohort__r.Name;
        log.deliveryDate = session.Session_Date__c;
        log.serviceId = session.Service__c;
        ServiceDeliveryLogController.Option service = new ServiceDeliveryLogController.Option();
        service.label = session.Service__r == null ? null : session.Service__r.Name;
        service.value = session.Service__c;
        service.unit = session.Service__r == null ? null : session.Service__r.Unit_Of_Measure__c;
        log.services.add(service);
        log.canEdit =
            !log.cancelled &&
            Schema.SObjectType.Service_Delivery__c.isCreateable() &&
            Schema.SObjectType.Service_Delivery__c.isUpdateable();
        for (
            Schema.PicklistEntry entry : Service_Delivery__c.Attendance__c.getDescribe()
                .getPicklistValues()
        ) {
            if (entry.isActive()) {
                ServiceDeliveryLogController.Option option = new ServiceDeliveryLogController.Option();
                option.label = entry.getLabel();
                option.value = entry.getValue();
                log.attendance.add(option);
            }
        }

        Integer most = ServiceDeliveryLogController.MAX_SHOWN;
        Map<Id, Service_Delivery__c> deliveryByPerson = new Map<Id, Service_Delivery__c>();
        for (
            Service_Delivery__c delivery : CohortSelector.selectSessionDeliveries(session, most + 1)
        ) {
            Id person = personOf(delivery.Contact__c, delivery.Account__c);
            // The session's own rows come first, so they win over a row it would adopt.
            if (person != null && !deliveryByPerson.containsKey(person)) {
                deliveryByPerson.put(person, delivery);
            }
        }
        List<Enrollment__c> open = session.Cohort__c != null
            ? CohortSelector.selectMembers(
                  session.Cohort__c,
                  EnrollmentService.OPEN_STAGES,
                  most + 1
              )
            : EnrollmentSelector.selectRoster(
                  session.Service__r.Program__c,
                  EnrollmentService.OPEN_STAGES,
                  most + 1
              );
        log.moreThanShown = open.size() > most;
        Set<Id> listed = new Set<Id>();
        for (Integer i = 0; i < open.size() && i < most; i++) {
            Enrollment__c enrollment = open[i];
            Id person = personOf(enrollment.Contact__c, enrollment.Account__c);
            if (person == null || listed.contains(person)) {
                continue;
            }
            listed.add(person);
            ServiceDeliveryLogController.Row row = new ServiceDeliveryLogController.Row();
            row.key = person;
            row.contactId = enrollment.Contact__c;
            row.accountId = enrollment.Account__c;
            row.enrollmentId = enrollment.Id;
            row.personName = CohortService.personNameOf(enrollment);
            fill(row, deliveryByPerson.get(person));
            log.rows.add(row);
        }
        // Someone recorded at this session who is not on the roster is still shown, after the rest.
        for (Id person : deliveryByPerson.keySet()) {
            Service_Delivery__c delivery = deliveryByPerson.get(person);
            if (listed.contains(person) || delivery.Session__c != session.Id) {
                continue;
            }
            ServiceDeliveryLogController.Row row = new ServiceDeliveryLogController.Row();
            row.key = person;
            row.contactId = delivery.Contact__c;
            row.accountId = delivery.Account__c;
            row.enrollmentId = delivery.Enrollment__c;
            row.personName = delivery.Contact__c != null
                ? delivery.Contact__r?.Name
                : delivery.Account__r?.Name;
            fill(row, delivery);
            log.rows.add(row);
        }
        return log;
    }

    /** Saves these entries as the session's deliveries; returns how many were written. */
    public static Integer save(Id sessionId, List<ServiceDeliveryLogController.Entry> entries) {
        Session__c session = checkedSession(sessionId);
        if (session.Status__c == CANCELLED) {
            throw UserErrors.message(Label.Programs_Session_CancelledNoAttendance);
        }
        Set<String> allowed = new Set<String>(ServiceDeliveryService.ATTENDANCE);
        List<Service_Delivery__c> toInsert = new List<Service_Delivery__c>();
        List<Service_Delivery__c> toUpdate = new List<Service_Delivery__c>();
        for (
            ServiceDeliveryLogController.Entry entry : entries == null
                ? new List<ServiceDeliveryLogController.Entry>()
                : entries
        ) {
            if (String.isBlank(entry.attendance)) {
                continue;
            }
            if (!allowed.contains(entry.attendance)) {
                throw UserErrors.message(ServiceDeliveryLogController.failed());
            }
            Decimal quantity = ServiceDeliveryService.isAbsence(entry.attendance)
                ? 0
                : (entry.quantity == null ? 1 : entry.quantity);
            if (entry.deliveryId != null) {
                toUpdate.add(
                    new Service_Delivery__c(
                        Id = entry.deliveryId,
                        Attendance__c = entry.attendance,
                        Quantity__c = quantity,
                        Session__c = session.Id
                    )
                );
            } else {
                toInsert.add(
                    new Service_Delivery__c(
                        Service__c = session.Service__c,
                        Delivery_Date__c = session.Session_Date__c,
                        Session__c = session.Id,
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
        toInsert = keepOneRow(session, toInsert, toUpdate, toChangeHidden);
        Database.insert(toInsert, AccessLevel.USER_MODE);
        Database.update(toUpdate, AccessLevel.USER_MODE);
        ServiceDeliveryIntegrity.changeHidden(toChangeHidden);
        Integer saved = toInsert.size() + toUpdate.size() + toChangeHidden.size();
        if (saved > 0 && session.Status__c == SCHEDULED) {
            Database.update(
                new List<Session__c>{ new Session__c(Id = session.Id, Status__c = HELD) },
                AccessLevel.USER_MODE
            );
        }
        return saved;
    }

    /**
     * One row per person per session (R-SD7): each new row whose person already has a delivery of
     * this session, or of its service and day with no session, becomes a change to that delivery,
     * which then names the session. Through `toUpdate` when the user can see it, through
     * `toChangeHidden` when not (as R-SD4). Returns the rows still to insert.
     */
    private static List<Service_Delivery__c> keepOneRow(
        Session__c session,
        List<Service_Delivery__c> toInsert,
        List<Service_Delivery__c> toUpdate,
        List<Service_Delivery__c> toChangeHidden
    ) {
        if (toInsert.isEmpty() || !ServiceDeliveryIntegrity.canChangeSession()) {
            return toInsert;
        }
        Set<Id> people = new Set<Id>();
        for (Service_Delivery__c row : toInsert) {
            people.add(personOf(row.Contact__c, row.Account__c));
        }
        people.remove(null);
        Map<Id, Id> existing = ServiceDeliveryIntegrity.existingSessionDeliveryIds(
            session.Id,
            session.Service__c,
            session.Session_Date__c,
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
            Id deliveryId = existing.get(personOf(row.Contact__c, row.Account__c));
            if (deliveryId == null) {
                stillNew.add(row);
                continue;
            }
            Service_Delivery__c change = new Service_Delivery__c(
                Id = deliveryId,
                Attendance__c = row.Attendance__c,
                Quantity__c = row.Quantity__c,
                Session__c = session.Id
            );
            if (visible.contains(deliveryId)) {
                toUpdate.add(change);
            } else {
                toChangeHidden.add(change);
            }
        }
        return stillNew;
    }

    private static Session__c checkedSession(Id sessionId) {
        Session__c session = sessionId == null ? null : CohortSelector.selectSession(sessionId);
        if (session == null) {
            throw UserErrors.message(Label.Programs_Session_NotFound);
        }
        return session;
    }

    private static Id personOf(Id contactId, Id accountId) {
        return contactId != null ? contactId : accountId;
    }

    private static void fill(ServiceDeliveryLogController.Row row, Service_Delivery__c delivery) {
        if (delivery != null) {
            row.deliveryId = delivery.Id;
            row.attendance = delivery.Attendance__c;
            row.quantity = delivery.Quantity__c;
        }
    }
}
