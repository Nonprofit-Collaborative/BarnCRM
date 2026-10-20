/**
 * Builds and removes the Volunteers sample data set (C-10, canonical model Part G "Sample
 * data"). The set is small and built in code rather than read from a static resource: three
 * jobs, four skills, one recurring schedule, a month of past shifts with attendance, a few
 * upcoming shifts with bookings, hours in each of the three statuses, skills and interests on
 * the people, and a few requirements.
 *
 * Every record goes through the module's own rules, as an administrator's would: sign-ups and
 * hours are inserted in user mode, attendance writes hours when Volunteer Settings says so, and
 * the statuses are set with the approval verbs (R-VG5), which need Manage Volunteers. A loader
 * without it leaves the hours as the save gave them.
 *
 * Removal deletes, one chunk per call: the sample hours (an Approved entry is reopened first,
 * because R-VG9 refuses deleting it and nothing stands that rule down), the sample people's
 * sign-ups, the sample jobs' shifts, schedules and jobs (their job skills go with them), the
 * volunteer skills and requirements of sample people, then the skills. Only sample people's rows
 * are taken. Hours a real person recorded against a sample job are not sample hours, and a shift
 * a real person is signed up for or has hours on is not deleted. Removal leaves out the sample
 * records such real rows point at (that shift, its job, a job with a real person's hours, a skill
 * a real person or a real job holds), which R-VJ1 or a Restrict lookup would refuse, deletes the
 * rest with partial success, and carries on to Core's removal. `logWhatWasKept`, at the end,
 * names each kept record and why in one Warning in the Error Log.
 */
public with sharing class VolunteerSampleDataLoader {
    /** How many of Core's sample people volunteer. */
    @TestVisible
    private static final Integer PEOPLE = 24;

    /** The newest entries left Submitted, and the next ones Rejected; the rest are Approved. */
    private static final Integer LEFT_SUBMITTED = 4;
    private static final Integer LEFT_REJECTED = 2;

    /** Records deleted per removeNext() call. Tests lower it. */
    @TestVisible
    private static Integer removeChunkSize = 200;

    /** The Error Log context of what removal kept or could not remove. */
    private static final String REMOVE_CONTEXT = 'VolunteerSampleDataRemoveStages';

    /** How many real rows of each kind the reads of what removal keeps take. */
    private static final Integer KEPT_CAP = 200;

    private static final String JOB_PANTRY = 'Food pantry sort';
    private static final String JOB_DESK = 'Front desk';
    private static final String JOB_GARDEN = 'Community garden';

    private static final String SIGNUP_ATTENDED = 'Attended';
    private static final String SHIFT_COMPLETED = 'Completed';

    private static VolunteerSampleDataSelector selector = new VolunteerSampleDataSelector();

    // ------------------------------------------------------------------------- stage 0

    /** Skills, jobs, their job skills, the recurring schedule and the one-off shifts. */
    public static void loadJobs() {
        List<Skill__c> skills = new List<Skill__c>{
            skill('First aid', 'Holds a current first aid certificate.'),
            skill('Spanish', 'Can welcome and help Spanish speaking visitors.'),
            skill('Forklift', 'Licensed to drive the warehouse forklift.'),
            skill('Gardening', 'Enjoys planting, weeding and harvesting.')
        };
        Database.insert(skills, AccessLevel.USER_MODE);

        Volunteer_Job__c pantry = job(
            JOB_PANTRY,
            'Sort donated food by type and date, and stock the pantry shelves.',
            'Warehouse'
        );
        Volunteer_Job__c desk = job(
            JOB_DESK,
            'Greet visitors, answer the phone and sign people in.',
            'Main office'
        );
        Volunteer_Job__c garden = job(
            JOB_GARDEN,
            'Plant, weed and harvest the community garden beds.',
            'Garden lot'
        );
        List<Volunteer_Job__c> jobs = new List<Volunteer_Job__c>{ pantry, desk, garden };
        Database.insert(jobs, AccessLevel.USER_MODE);

        Database.insert(
            new List<Job_Skill__c>{
                new Job_Skill__c(Job__c = pantry.Id, Skill__c = skills[2].Id),
                new Job_Skill__c(Job__c = desk.Id, Skill__c = skills[1].Id),
                new Job_Skill__c(Job__c = garden.Id, Skill__c = skills[3].Id),
                new Job_Skill__c(Job__c = garden.Id, Skill__c = skills[0].Id)
            },
            AccessLevel.USER_MODE
        );

        Date today = ShiftScheduleService.today();
        // Its save asks for its shifts up to the horizon, as any schedule's does (R-SSC2).
        Database.insert(
            new Shift_Schedule__c(
                Name = 'Saturday sorting',
                Job__c = pantry.Id,
                Weekdays__c = 'Saturday',
                Every_N_Weeks__c = 1,
                Start_Time__c = Time.newInstance(9, 0, 0, 0),
                End_Time__c = Time.newInstance(12, 0, 0, 0),
                Start_Date__c = today,
                Volunteers_Needed__c = 6,
                Active__c = true
            ),
            AccessLevel.USER_MODE
        );

        List<Volunteer_Shift__c> shifts = new List<Volunteer_Shift__c>();
        for (Integer week = 4; week >= 1; week--) {
            for (Volunteer_Job__c each : jobs) {
                shifts.add(shift(each.Id, today.addDays(-7 * week), SHIFT_COMPLETED));
            }
        }
        for (Integer days : new List<Integer>{ 3, 10 }) {
            shifts.add(shift(desk.Id, today.addDays(days), ShiftScheduleService.STATUS_OPEN));
            shifts.add(shift(garden.Id, today.addDays(days + 1), ShiftScheduleService.STATUS_OPEN));
        }
        Database.insert(shifts, AccessLevel.USER_MODE);
    }

    // ------------------------------------------------------------------------- stage 1

    /**
     * Sign-ups, hours, volunteer skills and requirements for up to 24 of Core's sample people.
     * Nothing when there are none.
     */
    public static void loadPeople() {
        List<Contact> people = selector.samplePeople(PEOPLE);
        if (people.isEmpty()) {
            return;
        }
        Integer count = people.size();
        Datetime now = Datetime.now();
        List<Volunteer_Signup__c> signups = new List<Volunteer_Signup__c>();
        Map<Id, Volunteer_Shift__c> shiftsById = new Map<Id, Volunteer_Shift__c>();
        Integer past = 0;
        Integer upcoming = 0;
        for (Volunteer_Shift__c shift : selector.sampleOneOffShifts()) {
            shiftsById.put(shift.Id, shift);
            Boolean done = shift.End_Time__c < now;
            Integer places = Math.min(done ? 3 : 2, count);
            for (Integer k = 0; k < places; k++) {
                Integer index = done ? past * 3 + k : 12 + upcoming * 2 + k;
                String status = done ? SIGNUP_ATTENDED : (k == 0 ? 'Confirmed' : 'Signed up');
                signups.add(
                    new Volunteer_Signup__c(
                        Volunteer_Shift__c = shift.Id,
                        Contact__c = people[Math.mod(index, count)].Id,
                        Status__c = status
                    )
                );
            }
            if (done) {
                past++;
            } else {
                upcoming++;
            }
        }
        // Attendance writes the hours when Volunteer Settings says so (R-VU3).
        Database.insert(signups, AccessLevel.USER_MODE);

        List<Volunteer_Hours__c> hours = hoursNotYetWritten(signups, shiftsById);
        Date today = ShiftScheduleService.today();
        Id gardenId = jobNamed(JOB_GARDEN);
        for (Integer i = 0; i < count; i++) {
            hours.add(
                new Volunteer_Hours__c(
                    Contact__c = people[i].Id,
                    Volunteer_Job__c = gardenId,
                    Date_Worked__c = today.addDays(-40 - 3 * i),
                    Hours__c = 2 + Math.mod(i, 3)
                )
            );
        }
        Database.insert(hours, AccessLevel.USER_MODE);

        insertSkillsAndRequirements(people, today);
    }

    /** Entries for attended sign-ups whose hours attendance did not write. */
    private static List<Volunteer_Hours__c> hoursNotYetWritten(
        List<Volunteer_Signup__c> signups,
        Map<Id, Volunteer_Shift__c> shiftsById
    ) {
        Set<Id> attended = new Set<Id>();
        for (Volunteer_Signup__c signup : signups) {
            if (signup.Status__c == SIGNUP_ATTENDED) {
                attended.add(signup.Id);
            }
        }
        Set<Id> written = VolunteerIntegritySelector.selectSignupsWithHours(attended);
        List<Volunteer_Hours__c> hours = new List<Volunteer_Hours__c>();
        for (Volunteer_Signup__c signup : signups) {
            if (!attended.contains(signup.Id) || written.contains(signup.Id)) {
                continue;
            }
            Volunteer_Shift__c shift = shiftsById.get(signup.Volunteer_Shift__c);
            hours.add(
                new Volunteer_Hours__c(
                    Contact__c = signup.Contact__c,
                    Volunteer_Shift__c = shift.Id,
                    Volunteer_Job__c = shift.Volunteer_Job__c,
                    Volunteer_Signup__c = signup.Id,
                    Date_Worked__c = ShiftScheduleService.orgDate(shift.Start_Time__c),
                    Hours__c = VolunteerSignupService.lengthInHours(shift)
                )
            );
        }
        return hours;
    }

    private static void insertSkillsAndRequirements(List<Contact> people, Date today) {
        List<Id> skillIds = selector.skillIds(4);
        List<Volunteer_Skill__c> held = new List<Volunteer_Skill__c>();
        List<Volunteer_Requirement__c> requirements = new List<Volunteer_Requirement__c>();
        for (Integer i = 0; i < people.size(); i++) {
            if (!skillIds.isEmpty()) {
                held.add(
                    new Volunteer_Skill__c(
                        Contact__c = people[i].Id,
                        Skill__c = skillIds[Math.mod(i, skillIds.size())],
                        Type__c = Math.mod(i, 3) == 2 ? 'Interest' : 'Skill'
                    )
                );
            }
            if (i < 6) {
                requirements.add(
                    new Volunteer_Requirement__c(
                        Contact__c = people[i].Id,
                        Type__c = 'Background check',
                        Status__c = 'Completed',
                        Completed_Date__c = today.addDays(-60),
                        Expires__c = today.addDays(-60).addYears(2)
                    )
                );
            } else if (i < 8) {
                requirements.add(
                    new Volunteer_Requirement__c(
                        Contact__c = people[i].Id,
                        Type__c = 'Orientation',
                        Status__c = 'In progress'
                    )
                );
            }
        }
        Database.insert(held, AccessLevel.USER_MODE);
        Database.insert(requirements, AccessLevel.USER_MODE);
    }

    // ------------------------------------------------------------------------- stage 2

    /**
     * Gives the hours their statuses with the approval verbs: the newest four stay Submitted,
     * the next two are Rejected with a reason, and the rest are Approved. Without Manage
     * Volunteers the hours keep the status the save gave them.
     */
    public static void decideHours() {
        if (!VolunteerHoursService.canManage()) {
            return;
        }
        Set<Id> submitted = new Set<Id>();
        Set<Id> rejected = new Set<Id>();
        Set<Id> approved = new Set<Id>();
        List<Volunteer_Hours__c> hours = selector.sampleHours(10000);
        for (Integer i = 0; i < hours.size(); i++) {
            if (i < LEFT_SUBMITTED) {
                submitted.add(hours[i].Id);
            } else if (i < LEFT_SUBMITTED + LEFT_REJECTED) {
                rejected.add(hours[i].Id);
            } else {
                approved.add(hours[i].Id);
            }
        }
        VolunteerHoursService.reopen(submitted);
        if (!rejected.isEmpty()) {
            VolunteerHoursService.reject(rejected, Label.Volunteers_SampleData_RejectionReason);
        }
        VolunteerHoursService.approve(approved);
    }

    // ------------------------------------------------------------------------- removal

    /** How many removeNext() calls clear every Volunteers sample record. */
    public static Integer removeStageCount() {
        Integer stages = 0;
        for (Integer recordCount : selector.removalCounts()) {
            stages += (recordCount + removeChunkSize - 1) / removeChunkSize;
        }
        return stages;
    }

    /**
     * Deletes the next chunk of Volunteers sample records and returns how many went, 0 once none
     * are left. Each kind is emptied before the next is started, in dependency order.
     */
    public static Integer removeNext() {
        Integer removed = removeHours();
        if (removed == 0) {
            removed = deleteAll(selector.signupIds(removeChunkSize));
        }
        if (removed == 0) {
            removed = deleteAll(selector.shiftIds(removeChunkSize));
        }
        if (removed == 0) {
            removed = deleteAll(selector.scheduleIds(removeChunkSize));
        }
        if (removed == 0) {
            removed = deleteAll(selector.jobIds(removeChunkSize, findKept(false).jobIds()));
        }
        if (removed == 0) {
            removed = deleteAll(selector.volunteerSkillIds(removeChunkSize));
        }
        if (removed == 0) {
            removed = deleteAll(selector.requirementIds(removeChunkSize));
        }
        if (removed == 0) {
            removed = deleteAll(selector.skillIds(removeChunkSize, findKept(true).skillIds()));
        }
        return removed;
    }

    /**
     * Logs one Warning naming each sample record real records kept from removal, and why, and
     * returns its message; null when nothing was kept. Run once, after the last stage.
     */
    public static String logWhatWasKept() {
        Kept kept = findKept(true);
        List<String> sentences = kept.sentences();
        if (sentences.isEmpty()) {
            return null;
        }
        sentences.add(Label.Volunteers_SampleData_KeptNext);
        String message = String.join(sentences, ' ');
        ErrorLogger.logMessage(message, REMOVE_CONTEXT, ErrorLogger.SEVERITY_WARNING);
        return message;
    }

    /**
     * The sample records real records point at. The shifts and jobs are read always; the skills
     * only when asked, as they cost two more reads.
     */
    private static Kept findKept(Boolean withSkills) {
        Kept kept = new Kept();
        for (Volunteer_Signup__c signup : selector.realSignupsOnSampleShifts(KEPT_CAP)) {
            kept.addShift(
                signup.Volunteer_Shift__c,
                signup.Volunteer_Shift__r.Name,
                signup.Volunteer_Shift__r.Volunteer_Job__c,
                signup.Volunteer_Shift__r.Volunteer_Job__r.Name,
                personName(signup.Contact__r, signup.Account__r),
                false
            );
        }
        for (Volunteer_Hours__c entry : selector.realHoursOnSampleJobs(KEPT_CAP)) {
            String person = personName(entry.Contact__r, entry.Account__r);
            if (entry.Volunteer_Shift__r?.Volunteer_Job__r?.Sample_Data__c == true) {
                kept.addShift(
                    entry.Volunteer_Shift__c,
                    entry.Volunteer_Shift__r.Name,
                    entry.Volunteer_Shift__r.Volunteer_Job__c,
                    entry.Volunteer_Shift__r.Volunteer_Job__r.Name,
                    person,
                    true
                );
            } else if (entry.Volunteer_Job__r?.Sample_Data__c == true) {
                kept.addJobHours(entry.Volunteer_Job__c, entry.Volunteer_Job__r.Name, person);
            }
        }
        if (withSkills) {
            for (Volunteer_Skill__c row : selector.realVolunteerSkillsOnSampleSkills(KEPT_CAP)) {
                kept.addSkill(
                    row.Skill__c,
                    row.Skill__r.Name,
                    String.format(
                        Label.Volunteers_SampleData_KeptSkillPerson,
                        new List<Object>{
                            row.Skill__r.Name,
                            personName(row.Contact__r, row.Account__r)
                        }
                    )
                );
            }
            for (Job_Skill__c row : selector.realJobSkillsOnSampleSkills(KEPT_CAP)) {
                kept.addSkill(
                    row.Skill__c,
                    row.Skill__r.Name,
                    String.format(
                        Label.Volunteers_SampleData_KeptSkillJob,
                        new List<Object>{ row.Skill__r.Name, row.Job__r.Name }
                    )
                );
            }
        }
        return kept;
    }

    private static String personName(Contact contact, Account account) {
        if (contact != null && String.isNotBlank(contact.Name)) {
            return contact.Name;
        }
        if (account != null && String.isNotBlank(account.Name)) {
            return account.Name;
        }
        return Label.Volunteers_SampleData_KeptUnnamed;
    }

    /** The sample shifts, jobs and skills real records keep, and who or what keeps each. */
    private class Kept {
        private final Map<Id, String> shiftNames = new Map<Id, String>();
        /** For each kept shift, each real person on it, and whether they have hours there. */
        private final Map<Id, Map<String, Boolean>> shiftPeople = new Map<Id, Map<String, Boolean>>();
        /** For each kept shift and person, whether they have a sign-up there. */
        private final Map<Id, Set<String>> shiftSignups = new Map<Id, Set<String>>();
        private final Map<Id, String> jobNames = new Map<Id, String>();
        private final Set<Id> jobsOfShifts = new Set<Id>();
        private final Map<Id, Set<String>> jobHoursPeople = new Map<Id, Set<String>>();
        private final Map<Id, String> skillNames = new Map<Id, String>();
        private final Map<Id, Set<String>> skillReasons = new Map<Id, Set<String>>();

        void addShift(
            Id shiftId,
            String shiftName,
            Id jobId,
            String jobName,
            String person,
            Boolean hours
        ) {
            shiftNames.put(shiftId, shiftName);
            if (!shiftPeople.containsKey(shiftId)) {
                shiftPeople.put(shiftId, new Map<String, Boolean>());
                shiftSignups.put(shiftId, new Set<String>());
            }
            Map<String, Boolean> people = shiftPeople.get(shiftId);
            people.put(person, hours || people.get(person) == true);
            if (!hours) {
                shiftSignups.get(shiftId).add(person);
            }
            jobNames.put(jobId, jobName);
            jobsOfShifts.add(jobId);
        }

        void addJobHours(Id jobId, String jobName, String person) {
            jobNames.put(jobId, jobName);
            if (!jobHoursPeople.containsKey(jobId)) {
                jobHoursPeople.put(jobId, new Set<String>());
            }
            jobHoursPeople.get(jobId).add(person);
        }

        void addSkill(Id skillId, String skillName, String reason) {
            skillNames.put(skillId, skillName);
            if (!skillReasons.containsKey(skillId)) {
                skillReasons.put(skillId, new Set<String>());
            }
            skillReasons.get(skillId).add(reason);
        }

        Set<Id> jobIds() {
            return jobNames.keySet();
        }

        Set<Id> skillIds() {
            return skillNames.keySet();
        }

        /** One plain sentence per kept record and reason. */
        List<String> sentences() {
            List<String> result = new List<String>();
            for (Id shiftId : shiftNames.keySet()) {
                Map<String, Boolean> people = shiftPeople.get(shiftId);
                for (String person : people.keySet()) {
                    Boolean hours = people.get(person);
                    Boolean signup = shiftSignups.get(shiftId).contains(person);
                    String what = hours && signup
                        ? Label.Volunteers_SampleData_KeptHoursAndSignup
                        : hours
                              ? Label.Volunteers_SampleData_KeptHours
                              : Label.Volunteers_SampleData_KeptSignup;
                    result.add(
                        String.format(
                            Label.Volunteers_SampleData_KeptShift,
                            new List<Object>{ shiftNames.get(shiftId), person, what }
                        )
                    );
                }
            }
            for (Id jobId : jobNames.keySet()) {
                if (jobsOfShifts.contains(jobId)) {
                    result.add(
                        String.format(
                            Label.Volunteers_SampleData_KeptJobShifts,
                            new List<Object>{ jobNames.get(jobId) }
                        )
                    );
                }
                if (jobHoursPeople.containsKey(jobId)) {
                    for (String person : jobHoursPeople.get(jobId)) {
                        result.add(
                            String.format(
                                Label.Volunteers_SampleData_KeptJobHours,
                                new List<Object>{ jobNames.get(jobId), person }
                            )
                        );
                    }
                }
            }
            for (Id skillId : skillNames.keySet()) {
                result.addAll(skillReasons.get(skillId));
            }
            return result;
        }
    }

    /** Reopens the Approved entries in the next chunk (R-VG9), then deletes the chunk. */
    private static Integer removeHours() {
        List<Volunteer_Hours__c> chunk = selector.sampleHours(removeChunkSize);
        Set<Id> approved = new Set<Id>();
        for (Volunteer_Hours__c entry : chunk) {
            if (entry.Status__c == VolunteerHoursService.STATUS_APPROVED) {
                approved.add(entry.Id);
            }
        }
        if (!approved.isEmpty()) {
            VolunteerHoursService.reopen(approved);
        }
        return deleteAll(new List<Id>(new Map<Id, Volunteer_Hours__c>(chunk).keySet()));
    }

    /**
     * Deletes these records with partial success and returns how many went. A record refused for
     * a reason removal did not foresee is logged as a Warning and left, so one record never stops
     * the removal; when none of them went, the next kind is started.
     */
    private static Integer deleteAll(List<Id> ids) {
        if (ids.isEmpty()) {
            return 0;
        }
        Integer deleted = 0;
        List<String> problems = new List<String>();
        List<Id> problemIds = new List<Id>();
        List<Database.DeleteResult> results = Database.delete(ids, false, AccessLevel.USER_MODE);
        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) {
                deleted++;
            } else {
                problems.add(
                    String.format(
                        Label.Volunteers_SampleData_NotRemoved,
                        new List<Object>{ results[i].getErrors()[0].getMessage() }
                    )
                );
                problemIds.add(ids[i]);
            }
        }
        if (!problems.isEmpty()) {
            ErrorLogger.logMessages(
                problems,
                problemIds,
                REMOVE_CONTEXT,
                ErrorLogger.SEVERITY_WARNING
            );
        }
        return deleted;
    }

    // ------------------------------------------------------------------------- builders

    private static Skill__c skill(String name, String description) {
        return new Skill__c(
            Name = name,
            Description__c = description,
            Active__c = true,
            Sample_Data__c = true
        );
    }

    private static Volunteer_Job__c job(String name, String description, String location) {
        return new Volunteer_Job__c(
            Name = name,
            Description__c = description,
            Location__c = location,
            Active__c = true,
            Sample_Data__c = true
        );
    }

    /** A three hour morning shift on the day, four places. */
    private static Volunteer_Shift__c shift(Id jobId, Date day, String status) {
        Datetime starts = ShiftScheduleService.toOrgDatetime(day, Time.newInstance(9, 0, 0, 0));
        return new Volunteer_Shift__c(
            Volunteer_Job__c = jobId,
            Start_Time__c = starts,
            End_Time__c = starts.addHours(3),
            Volunteers_Needed__c = 4,
            Status__c = status
        );
    }

    private static Id jobNamed(String name) {
        for (Volunteer_Job__c each : selector.sampleJobs()) {
            if (each.Name == name) {
                return each.Id;
            }
        }
        return null;
    }
}
