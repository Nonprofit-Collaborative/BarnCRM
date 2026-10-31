/**
 * The only place ask reminder tasks are written, and the stamps that keep them from repeating.
 *
 * DOCUMENTED EXCEPTION to the user-mode rule (plan Section 4.13), on the ground the stewardship
 * writer states: a reminder is a consequence of a date somebody entered, not a record the nightly
 * job's user chose to create, and it is assigned to the donor's owner, who may be somebody else
 * entirely. Requiring create access on Task from whoever the job runs as would mean the reminder
 * silently stops for the donors least likely to be noticed. The stamp is a write to a field this
 * package owns, computed here, so it is elevated for the same reason.
 *
 * It never throws (rule R-E2): a reminder that could not be made is logged and counted, and its
 * donor is left unstamped so the next night tries again (R-AC5).
 */
public without sharing class AskReminderWriter {
    private static final String CONTEXT = 'Ask reminders';

    /**
     * Inserts the tasks and stamps the donors whose task was made. The two lists are positional:
     * `donors[i]` is who `tasks[i]` is for. Returns how many tasks were created.
     */
    public static Integer save(List<Task> tasks, List<SObject> donors) {
        if (tasks == null || tasks.isEmpty() || donors == null || donors.size() != tasks.size()) {
            return 0;
        }
        List<Database.SaveResult> inserted;
        try {
            inserted = Database.insert(tasks, false, AccessLevel.SYSTEM_MODE);
        } catch (Exception cannotInsert) {
            ErrorLogger.log(cannotInsert, CONTEXT);
            return 0;
        }

        List<SObject> stamps = new List<SObject>();
        List<String> refusals = new List<String>();
        for (Integer i = 0; i < inserted.size(); i++) {
            if (!inserted[i].isSuccess()) {
                refusals.add(inserted[i].getErrors()[0].getMessage());
                continue;
            }
            SObject donor = donors[i];
            SObject stamp = donor.getSObjectType().newSObject(donor.Id);
            stamp.put('Ask_Reminder_For_Date__c', donor.get('Next_Ask_Date__c'));
            stamps.add(stamp);
        }
        if (!refusals.isEmpty()) {
            ErrorLogger.logMessages(refusals, CONTEXT, ErrorLogger.SEVERITY_ERROR);
        }
        stampDonors(stamps);
        return stamps.size();
    }

    /** Records when a pass finished and what it did, on the locked stored settings record. */
    public static void stampRun(Datetime completedAt, String summary) {
        OrgSettingsSystemWriter.save(
            Giving_Settings__c.SObjectType,
            new Map<Schema.SObjectField, Object>{
                Giving_Settings__c.Ask_Reminders_Last_Run__c => completedAt,
                Giving_Settings__c.Ask_Reminders_Last_Run_Summary__c => summary
            }
        );
    }

    private static void stampDonors(List<SObject> stamps) {
        if (stamps.isEmpty()) {
            return;
        }
        List<Database.SaveResult> saved;
        try {
            saved = Database.update(stamps, false, AccessLevel.SYSTEM_MODE);
        } catch (Exception cannotStamp) {
            ErrorLogger.log(cannotStamp, CONTEXT);
            return;
        }
        List<String> refusals = new List<String>();
        for (Database.SaveResult result : saved) {
            if (!result.isSuccess()) {
                refusals.add(result.getErrors()[0].getMessage());
            }
        }
        if (!refusals.isEmpty()) {
            // The task exists but the donor still looks unreminded, so tomorrow it would repeat.
            // Say so loudly: this is the one path to a duplicate (R-AC3).
            ErrorLogger.logMessages(refusals, CONTEXT + ' stamp', ErrorLogger.SEVERITY_ERROR);
        }
    }
}
