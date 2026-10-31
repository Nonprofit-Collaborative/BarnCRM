/**
 * Decides which donors are owed an ask reminder and lays out the task for each (canonical model
 * Section 25S, plan feature G-29).
 *
 * The decision is pure: it reads the donor rows it is handed and builds tasks and stamps, and
 * writes nothing. `AskReminderWriter` does the writing, so the rules here can be tested without
 * a database and the elevated writes stay in one small class.
 *
 * A donor is reminded once per Next Ask Date (R-AC3). The record of that is the donor's own
 * `Ask_Reminder_For_Date__c`, stamped to the date a task was made for, rather than a search of
 * the task list: a task is a person's work, they may complete or delete it, and neither must
 * make the same date remind them again.
 */
public with sharing class AskReminderService {
    private static final String SETTINGS_OBJECT = 'Giving_Settings__c';
    private static final String KEY_ENABLED = 'Ask_Reminders_Enabled__c';

    /** How many days back a missed Next Ask Date is still caught up (R-AC4). */
    public static final Integer CATCH_UP_DAYS = 30;

    public static final String TASK_STATUS = 'Not Started';
    public static final String TASK_PRIORITY = 'Normal';

    /** What one pass over a chunk of donors did. */
    public class Outcome {
        public Integer created = 0;
        public Integer failed = 0;
    }

    /**
     * Whether the pass is switched on. An unset value means on: the shipped default is on, and a
     * reminder that never came because an administrator never opened the console is worse than
     * one nobody asked for, which costs a task someone can delete.
     */
    public static Boolean isEnabled() {
        Object value = SettingsService.getValue(SETTINGS_OBJECT, KEY_ENABLED);
        if (value == null) {
            return true;
        }
        if (value instanceof Boolean) {
            return (Boolean) value;
        }
        String text = String.valueOf(value).trim();
        return String.isBlank(text) ? true : Boolean.valueOf(text);
    }

    /** The oldest Next Ask Date that still gets a reminder today. */
    public static Date earliestDate(Date today) {
        return today.addDays(-CATCH_UP_DAYS);
    }

    /**
     * True when this donor is owed a reminder today: its date has arrived, is not older than the
     * catch up window, and a reminder has not already been made for that date.
     */
    public static Boolean isDue(SObject donor, Date today) {
        Date nextAsk = (Date) donor.get('Next_Ask_Date__c');
        if (nextAsk == null || nextAsk > today || nextAsk < earliestDate(today)) {
            return false;
        }
        return (Date) donor.get('Ask_Reminder_For_Date__c') != nextAsk;
    }

    /**
     * The reminders a chunk of donors is owed, in the same order as `due`, which is filled with
     * the donors they are for. Each donor gets one task for its owner (R-AC5).
     */
    public static List<Task> remindersFor(List<SObject> donors, Date today, List<SObject> due) {
        List<Task> tasks = new List<Task>();
        if (donors == null) {
            return tasks;
        }
        for (SObject donor : donors) {
            if (isDue(donor, today)) {
                due.add(donor);
                tasks.add(taskFor(donor));
            }
        }
        return tasks;
    }

    /** Runs one chunk end to end: decide, write, and say how it went. */
    public static Outcome remindChunk(List<SObject> donors, Date today) {
        List<SObject> due = new List<SObject>();
        List<Task> tasks = remindersFor(donors, today, due);
        Outcome outcome = new Outcome();
        if (tasks.isEmpty()) {
            return outcome;
        }
        outcome.created = AskReminderWriter.save(tasks, due);
        outcome.failed = tasks.size() - outcome.created;
        return outcome;
    }

    /** Records when a pass finished and what it did, which is what the Nightly Jobs page shows. */
    public static void recordRun(Datetime completedAt, Integer created, Integer failed) {
        AskReminderWriter.stampRun(
            completedAt,
            String.format(
                System.Label.Giving_AskReminder_SummaryFormat,
                new List<String>{ String.valueOf(created), String.valueOf(failed) }
            )
        );
    }

    /**
     * One task for one donor. A person's task hangs off the person, with their organization on
     * the What side so it also shows there; an organization's task hangs off the organization.
     */
    private static Task taskFor(SObject donor) {
        Task reminder = new Task(
            Subject = String.format(
                System.Label.Giving_AskReminder_Subject,
                new List<String>{ String.valueOf(donor.get('Name')) }
            ),
            Description = System.Label.Giving_AskReminder_Description,
            ActivityDate = (Date) donor.get('Next_Ask_Date__c'),
            Status = TASK_STATUS,
            Priority = TASK_PRIORITY,
            OwnerId = (Id) donor.get('OwnerId')
        );
        if (donor.getSObjectType() == Contact.SObjectType) {
            reminder.WhoId = donor.Id;
            reminder.WhatId = (Id) donor.get('AccountId');
        } else {
            reminder.WhatId = donor.Id;
        }
        return reminder;
    }
}
