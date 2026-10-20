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
 * a real person is signed up for or has hours on is not deleted, so R-VJ1 then refuses that job
 * and the removal stops with that message in the Error Log. A real person's volunteer skill on a
 * sample skill stays in the same way: the skill's Restrict lookup refuses deleting the skill.
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
            removed = deleteAll(selector.jobIds(removeChunkSize));
        }
        if (removed == 0) {
            removed = deleteAll(selector.volunteerSkillIds(removeChunkSize));
        }
        if (removed == 0) {
            removed = deleteAll(selector.requirementIds(removeChunkSize));
        }
        if (removed == 0) {
            removed = deleteAll(selector.skillIds(removeChunkSize));
        }
        return removed;
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

    private static Integer deleteAll(List<Id> ids) {
        if (!ids.isEmpty()) {
            Database.delete(ids, AccessLevel.USER_MODE);
        }
        return ids.size();
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
