/**
 * What the Schedule Sessions panel on a cohort or a program calls (P-11, canonical model 29ZA6,
 * R-SE4). The panel works out the dates (one per chosen weekday between two dates) in its
 * framework-free module; this class checks again that the service is an active service of the
 * program, that there are at most 200 dates, and creates one Scheduled session per date, for the
 * cohort when called from one. User mode throughout; plain wrappers (plan Section 9.9); anything
 * unexpected is recorded in the Error Log before it is reported (plan Section 7.2).
 */
public with sharing class SessionScheduleController {
    private static final String CONTEXT = 'Schedule sessions panel';
    /** The most sessions created in one action. */
    public static final Integer MAX_SESSIONS = 200;
    private static final Integer NAME_LENGTH = 80;

    public class Option {
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String value;
    }

    /** The panel's whole state. */
    public class Schedule {
        @AuraEnabled
        public Id programId;
        @AuraEnabled
        public Id cohortId;
        @AuraEnabled
        public String cohortName;
        @AuraEnabled
        public List<Option> services = new List<Option>();
        @AuraEnabled
        public Date startDate;
        @AuraEnabled
        public Date endDate;
        @AuraEnabled
        public Boolean canSchedule = false;
        @AuraEnabled
        public Integer maxSessions = MAX_SESSIONS;
        /** After scheduling: how many sessions were created. */
        @AuraEnabled
        public Integer created = 0;
    }

    @AuraEnabled
    public static Schedule getSchedule(Id recordId) {
        try {
            return scheduleFor(recordId);
        } catch (Exception failure) {
            throw report(failure, recordId);
        }
    }

    /**
     * Creates one Scheduled session of the service on each date, at the start time when one is
     * given ("HH:mm", seconds and more ignored), for the cohort when `recordId` is one.
     */
    @AuraEnabled
    public static Schedule scheduleSessions(
        Id recordId,
        Id serviceId,
        List<Date> dates,
        String startTime
    ) {
        if (serviceId == null) {
            throw UserErrors.message(Label.Programs_Schedule_ServiceRequired);
        }
        Set<Date> unique = new Set<Date>(dates == null ? new List<Date>() : dates);
        unique.remove(null);
        if (unique.isEmpty()) {
            throw UserErrors.message(Label.Programs_Schedule_NoDates);
        }
        if (unique.size() > MAX_SESSIONS) {
            throw UserErrors.message(
                String.format(Label.Programs_Schedule_TooMany, new List<Object>{ MAX_SESSIONS })
            );
        }
        Time starts = parsedTime(startTime);
        try {
            Schedule schedule = scheduleFor(recordId);
            Option service = null;
            for (Option offered : schedule.services) {
                if ((Id) offered.value == serviceId) {
                    service = offered;
                }
            }
            if (service == null) {
                throw UserErrors.message(Label.Programs_Schedule_ServiceRequired);
            }
            List<Date> sorted = new List<Date>(unique);
            sorted.sort();
            List<Session__c> sessions = new List<Session__c>();
            for (Date day : sorted) {
                sessions.add(
                    new Session__c(
                        Name = sessionName(service.label, day),
                        Service__c = serviceId,
                        Cohort__c = schedule.cohortId,
                        Session_Date__c = day,
                        Start_Time__c = starts,
                        Status__c = SessionAttendance.SCHEDULED
                    )
                );
            }
            Database.insert(sessions, true, AccessLevel.USER_MODE);
            schedule.created = sessions.size();
            return schedule;
        } catch (Exception failure) {
            throw report(failure, recordId);
        }
    }

    // ------------------------------------------------------------------------------ helpers

    private static Schedule scheduleFor(Id recordId) {
        Schedule schedule = new Schedule();
        if (recordId != null && recordId.getSObjectType() == Cohort__c.SObjectType) {
            Cohort__c cohort = CohortSelector.selectCohort(recordId);
            if (cohort == null) {
                throw UserErrors.message(Label.Programs_Cohort_NotFound);
            }
            schedule.cohortId = cohort.Id;
            schedule.cohortName = cohort.Name;
            schedule.programId = cohort.Program__c;
            schedule.startDate = cohort.Start_Date__c;
            schedule.endDate = cohort.End_Date__c;
        } else if (recordId != null && recordId.getSObjectType() == Program__c.SObjectType) {
            if (CohortSelector.selectProgram(recordId) == null) {
                throw UserErrors.message(Label.Programs_Schedule_ActionFailed);
            }
            schedule.programId = recordId;
        } else {
            throw UserErrors.message(Label.Programs_Schedule_ActionFailed);
        }
        for (Service__c service : CohortSelector.selectActiveServices(schedule.programId)) {
            Option option = new Option();
            option.label = service.Name;
            option.value = service.Id;
            schedule.services.add(option);
        }
        schedule.canSchedule = Schema.SObjectType.Session__c.isCreateable();
        return schedule;
    }

    /** "Service name date", cut to fit the name field. */
    @TestVisible
    private static String sessionName(String serviceName, Date day) {
        String suffix = ' ' + day.format();
        String base = serviceName == null ? '' : serviceName;
        return base.left(NAME_LENGTH - suffix.length()) + suffix;
    }

    /** "13:30", "13:30:00.000" or empty; anything else is refused. */
    @TestVisible
    private static Time parsedTime(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        List<String> parts = value.trim().split(':');
        if (
            parts.size() < 2 ||
            !parts[0].isNumeric() ||
            !parts[1].left(2).isNumeric() ||
            Integer.valueOf(parts[0]) > 23 ||
            Integer.valueOf(parts[1].left(2)) > 59
        ) {
            throw UserErrors.message(Label.Programs_Schedule_BadTime);
        }
        return Time.newInstance(Integer.valueOf(parts[0]), Integer.valueOf(parts[1].left(2)), 0, 0);
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
        return UserErrors.message(Label.Programs_Schedule_ActionFailed);
    }
}
