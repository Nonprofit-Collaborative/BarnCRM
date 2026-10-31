/**
 * What happened to one message: did it go, and if not, the first reason the platform gave.
 *
 * It exists as its own class because `Messaging.SendEmailResult` cannot be constructed, so a test
 * could not stand in for the platform without one (ADR-0032).
 */
@NamespaceAccessible
public with sharing class EmailSendOutcome {
    @NamespaceAccessible
    public Boolean sent { get; private set; }

    /**
     * The platform's first error message, trimmed to the 255 characters a record's reason field
     * holds; null when it gave none or the message went.
     */
    @NamespaceAccessible
    public String error { get; private set; }

    private EmailSendOutcome(Boolean sent, String error) {
        this.sent = sent;
        this.error = error;
    }

    @NamespaceAccessible
    public static EmailSendOutcome succeeded() {
        return new EmailSendOutcome(true, null);
    }

    @NamespaceAccessible
    public static EmailSendOutcome failed(String error) {
        return new EmailSendOutcome(false, error);
    }
}
