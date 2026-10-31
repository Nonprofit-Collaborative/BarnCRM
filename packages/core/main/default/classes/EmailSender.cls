/**
 * The one seam between BarnCRM and the platform's email service.
 *
 * Every feature that sends mail (acknowledgments, pledge reminders, shift reminders, the error
 * digest) sends through it, so a test can prove what was composed and what was recorded
 * without depending on whether an org can send mail. `MessagingEmailSender` is the one shipped
 * implementation; tests use `RecordingEmailSender`.
 */
@NamespaceAccessible
public interface EmailSender {
    /**
     * Sends the messages and reports one outcome per message, in the same order. One address
     * that bounces must not stop the others going out, so the send is partial success, not all
     * or nothing. A call the platform refuses as a whole throws.
     */
    List<EmailSendOutcome> send(List<Messaging.SingleEmailMessage> messages);
}
