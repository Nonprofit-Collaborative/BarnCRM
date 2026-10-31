/**
 * The shipped sender: one `Messaging.sendEmail` call for the whole chunk, not one per message.
 *
 * That is not a micro optimization. Apex allows ten email invocations per transaction, so a chunk
 * that sent one message at a time would stop after ten. Passing the list and asking for partial
 * success gets the whole chunk out in one invocation and gives back a result per message: the
 * failures are named and the rest still went.
 */
@NamespaceAccessible
public with sharing class MessagingEmailSender implements EmailSender {
    @NamespaceAccessible
    public List<EmailSendOutcome> send(List<Messaging.SingleEmailMessage> messages) {
        List<EmailSendOutcome> outcomes = new List<EmailSendOutcome>();
        if (messages == null || messages.isEmpty()) {
            return outcomes;
        }
        for (Messaging.SendEmailResult result : Messaging.sendEmail(messages, false)) {
            if (result.isSuccess()) {
                outcomes.add(EmailSendOutcome.succeeded());
            } else {
                List<Messaging.SendEmailError> errors = result.getErrors();
                outcomes.add(
                    EmailSendOutcome.failed(
                        errors == null || errors.isEmpty()
                            ? null
                            : errors[0].getMessage()?.left(255)
                    )
                );
            }
        }
        return outcomes;
    }
}
