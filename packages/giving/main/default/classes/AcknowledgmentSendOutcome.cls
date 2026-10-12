/**
 * What happened to one message, in the only two facts the feature needs: did it go, and if not,
 * what does a person read on the record.
 *
 * It exists as its own class because `Messaging.SendEmailResult` cannot be constructed, so a test
 * could not stand in for the platform without one (ADR-0032).
 */
public with sharing class AcknowledgmentSendOutcome {
    public Boolean sent { get; private set; }
    public String failureReason { get; private set; }

    private AcknowledgmentSendOutcome(Boolean sent, String failureReason) {
        this.sent = sent;
        this.failureReason = failureReason;
    }

    public static AcknowledgmentSendOutcome succeeded() {
        return new AcknowledgmentSendOutcome(true, null);
    }

    public static AcknowledgmentSendOutcome failed(String reason) {
        return new AcknowledgmentSendOutcome(false, reason);
    }
}
