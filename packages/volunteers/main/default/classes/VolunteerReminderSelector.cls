/**
 * The read behind the shift reminder run (V-10, R-VU6): every booking due a reminder, whoever
 * runs the job. ADR-0021 (system mode for package owned data).
 *
 * `without sharing` and `WITH SYSTEM_MODE`, because the run is the organization's own morning
 * job, not a user's action: it must reach every booking and every person's email address.
 * Nothing here is shown to a user, and nothing reaches a dynamic query.
 */
public without sharing class VolunteerReminderSelector {
    /**
     * The bookings due a reminder: not yet reminded, still Signed up or Confirmed, for an open
     * shift that starts after `now` and before `windowEnd`, for a Contact with an email address
     * who has not opted out of email. A booking named by a person account has no Contact and is
     * not reminded.
     */
    public static Database.QueryLocator dueLocator(Datetime now, Datetime windowEnd) {
        return Database.getQueryLocator(
            [
                SELECT
                    Id,
                    Contact__c,
                    Contact__r.FirstName,
                    Contact__r.Email,
                    Volunteer_Shift__r.Start_Time__c,
                    Volunteer_Shift__r.End_Time__c,
                    Volunteer_Shift__r.Location__c,
                    Volunteer_Shift__r.Volunteer_Job__r.Name
                FROM Volunteer_Signup__c
                WHERE
                    Reminder_Sent_On__c = NULL
                    AND Status__c IN ('Signed up', 'Confirmed')
                    AND Contact__c != NULL
                    AND Contact__r.Email != NULL
                    AND Contact__r.HasOptedOutOfEmail = FALSE
                    AND Volunteer_Shift__r.Status__c = 'Open'
                    AND Volunteer_Shift__r.Start_Time__c > :now
                    AND Volunteer_Shift__r.Start_Time__c < :windowEnd
                WITH SYSTEM_MODE
                ORDER BY Volunteer_Shift__r.Start_Time__c
            ]
        );
    }
}
