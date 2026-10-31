/**
 * Shift reminders (V-10, R-VU6): one email to each person booked on a shift that starts within
 * the lead time, once per booking.
 *
 * Sent through the platform's single email call, to the Contact's own address, so the org's
 * email limits apply and nothing outside Salesforce is needed. A person with Email Opt Out
 * checked, no address, a cancelled booking or a cancelled shift is never emailed (the selector
 * leaves them out). A booking stamped Reminder Sent On is never emailed again; clearing the
 * stamp sends it again. One chunk that fails is logged and the next morning's run retries it.
 */
public with sharing class VolunteerReminderService {
    private static final String LOG_CONTEXT = 'VolunteerReminderService';
    private static final String WHEN_FORMAT = 'EEEE, MMMM d, yyyy h:mm a';
    private static final String TIME_FORMAT = 'h:mm a';

    /** Sends one chunk of messages and says, in order, which went out. */
    public interface ReminderSender {
        List<Boolean> send(List<Messaging.SingleEmailMessage> messages);
    }

    /** The shipped sender: one `Messaging.sendEmail` call for the chunk, partial success on. */
    public class MessagingSender implements ReminderSender {
        public List<Boolean> send(List<Messaging.SingleEmailMessage> messages) {
            List<Boolean> sent = new List<Boolean>();
            for (Messaging.SendEmailResult result : Messaging.sendEmail(messages, false)) {
                sent.add(result.isSuccess());
                if (!result.isSuccess() && !result.getErrors().isEmpty()) {
                    lastFailure = result.getErrors()[0].getMessage();
                }
            }
            return sent;
        }
    }

    /** Set by a test to send nothing for real. */
    @TestVisible
    private static ReminderSender senderInUse = new MessagingSender();

    private static String lastFailure;

    /**
     * The window the morning run reminds: shifts that start after now and before the start of
     * the day `leadDays` after today, in the org's time zone.
     */
    public static Datetime windowEnd(Integer leadDays) {
        return ShiftScheduleService.toOrgDatetime(
            ShiftScheduleService.today().addDays(leadDays + 1),
            Time.newInstance(0, 0, 0, 0)
        );
    }

    /** Whether a run should start: the module is on and the setting is on. */
    public static Boolean isActive() {
        return !ShiftScheduleService.isTurnedOff() && VolunteerSettings.remindersEnabled();
    }

    /**
     * Stamps this chunk of due bookings, emails only the ones whose stamp saved, and clears the
     * stamp again on any that did not go out. Returns how many went out.
     *
     * Stamp first: a booking whose stamp cannot be saved is never emailed, because an email
     * without its stamp would be sent again every morning until the shift.
     */
    public static Integer remind(List<Volunteer_Signup__c> signups) {
        if (signups == null || signups.isEmpty() || !isActive()) {
            return 0;
        }
        Datetime now = ShiftScheduleService.now();
        List<Volunteer_Signup__c> stamps = new List<Volunteer_Signup__c>();
        for (Volunteer_Signup__c signup : signups) {
            stamps.add(new Volunteer_Signup__c(Id = signup.Id, Reminder_Sent_On__c = now));
        }
        List<Database.SaveResult> stamped = Database.update(stamps, false, AccessLevel.SYSTEM_MODE);
        String zone = ShiftScheduleSelector.orgTimeZone();
        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
        List<Volunteer_Signup__c> messageSignups = new List<Volunteer_Signup__c>();
        String stampFailure;
        for (Integer i = 0; i < signups.size(); i++) {
            if (stamped[i].isSuccess()) {
                messages.add(messageFor(signups[i], zone));
                messageSignups.add(signups[i]);
            } else if (stampFailure == null && !stamped[i].getErrors().isEmpty()) {
                stampFailure = stamped[i].getErrors()[0].getMessage();
            }
        }
        if (messageSignups.size() < signups.size()) {
            ErrorLogger.logMessage(
                String.format(
                    System.Label.Volunteers_Reminders_StampFailed,
                    new List<Object>{
                        signups.size() - messageSignups.size(),
                        signups.size(),
                        stampFailure == null ? '' : stampFailure
                    }
                ),
                LOG_CONTEXT,
                ErrorLogger.SEVERITY_WARNING
            );
        }
        if (messages.isEmpty()) {
            return 0;
        }
        lastFailure = null;
        List<Boolean> sent = senderInUse.send(messages);
        List<Volunteer_Signup__c> unstamp = new List<Volunteer_Signup__c>();
        for (Integer i = 0; i < messageSignups.size(); i++) {
            if (i >= sent.size() || !sent[i]) {
                unstamp.add(
                    new Volunteer_Signup__c(Id = messageSignups[i].Id, Reminder_Sent_On__c = null)
                );
            }
        }
        if (!unstamp.isEmpty()) {
            // Not sent: the stamp goes so tomorrow's run tries again while the shift is ahead.
            Database.update(unstamp, false, AccessLevel.SYSTEM_MODE);
            ErrorLogger.logMessage(
                String.format(
                    System.Label.Volunteers_Reminders_SendFailed,
                    new List<Object>{
                        unstamp.size(),
                        signups.size(),
                        lastFailure == null ? '' : lastFailure
                    }
                ),
                LOG_CONTEXT,
                ErrorLogger.SEVERITY_WARNING
            );
        }
        return messageSignups.size() - unstamp.size();
    }

    /** One reminder, addressed to the booking's Contact. */
    @TestVisible
    private static Messaging.SingleEmailMessage messageFor(
        Volunteer_Signup__c signup,
        String zone
    ) {
        Volunteer_Shift__c shift = signup.Volunteer_Shift__r;
        String jobName = shift.Volunteer_Job__r == null ? '' : shift.Volunteer_Job__r.Name;
        String whenText = shift.Start_Time__c.format(WHEN_FORMAT, zone);
        if (shift.End_Time__c != null) {
            whenText += ' - ' + shift.End_Time__c.format(TIME_FORMAT, zone);
        }
        String firstName = signup.Contact__r.FirstName;
        String greeting = String.isBlank(firstName)
            ? System.Label.Volunteers_Reminders_GreetingNoName
            : String.format(
                  System.Label.Volunteers_Reminders_Greeting,
                  new List<Object>{ firstName }
              );
        String body =
            greeting +
            '\n\n' +
            String.format(
                System.Label.Volunteers_Reminders_Body,
                new List<Object>{ jobName, whenText }
            );
        if (String.isNotBlank(shift.Location__c)) {
            body +=
                '\n' +
                String.format(
                    System.Label.Volunteers_Reminders_Where,
                    new List<Object>{ shift.Location__c }
                );
        }
        body += '\n\n' + System.Label.Volunteers_Reminders_Closing;

        Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
        message.setToAddresses(new List<String>{ signup.Contact__r.Email });
        message.setSubject(
            String.format(System.Label.Volunteers_Reminders_Subject, new List<Object>{ jobName })
        );
        message.setPlainTextBody(body);
        message.setSaveAsActivity(false);
        return message;
    }
}
