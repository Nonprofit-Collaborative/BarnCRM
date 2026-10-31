/**
 * The stand-in sender every module's tests use: it records what it was given and answers however
 * the test told it to, because Apex tests do not send mail and `Messaging.SendEmailResult` cannot
 * be constructed (ADR-0032).
 */
@IsTest
@NamespaceAccessible
public class RecordingEmailSender implements EmailSender {
    /** Every message handed to it, in order. */
    @NamespaceAccessible
    public List<Messaging.SingleEmailMessage> received = new List<Messaging.SingleEmailMessage>();

    /** Positions in each call that fail with `failureReason`. */
    @NamespaceAccessible
    public Set<Integer> failAt = new Set<Integer>();

    /** When true every message fails with `failureReason`. */
    @NamespaceAccessible
    public Boolean failAll = false;

    @NamespaceAccessible
    public String failureReason = 'The address bounced.';

    /** When set, the whole call is refused with this message, as a blocked org's would be. */
    @NamespaceAccessible
    public String refuseWith;

    @NamespaceAccessible
    public class RefusedException extends Exception {
    }

    @NamespaceAccessible
    public List<EmailSendOutcome> send(List<Messaging.SingleEmailMessage> messages) {
        if (refuseWith != null) {
            throw new RefusedException(refuseWith);
        }
        received.addAll(messages);
        List<EmailSendOutcome> outcomes = new List<EmailSendOutcome>();
        for (Integer index = 0; index < messages.size(); index++) {
            outcomes.add(
                failAll || failAt.contains(index)
                    ? EmailSendOutcome.failed(failureReason)
                    : EmailSendOutcome.succeeded()
            );
        }
        return outcomes;
    }
}
