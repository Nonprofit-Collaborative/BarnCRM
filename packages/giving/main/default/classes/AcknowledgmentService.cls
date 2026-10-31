/**
 * Queueing gifts for a thank you and sending the ones that are waiting (feature G-12, ADR-0032).
 *
 * Three rules run through everything here:
 *
 * - **Nothing sends inside a trigger.** The gift handler reaches `applyRules` and
 *   `releaseClaims`, which set a picklist and clear a key. Sending is a run, started by a person
 *   or by the nightly schedule, so a two hundred gift import is not two hundred emails.
 * - **A gift is claimed before anything is sent.** `Gift_Key__c` is unique, so the row is the
 *   claim, and a retried chunk resumes rather than thanking a donor twice (R-AK7).
 * - **One failure is one row.** A send that fails is recorded on its own row and in the Error
 *   Log, and the rest of the chunk goes out (R-AK10).
 */
public with sharing class AcknowledgmentService {
    public static final String STATUS_QUEUED = 'Queued';
    public static final String STATUS_SENT = 'Sent';
    public static final String STATUS_FAILED = 'Failed';

    /** The permission to run a send. Bare, correctly: a custom permission in the same package. */
    public static final String SEND_PERMISSION = 'Send_Acknowledgments';

    private static final String CONTEXT_SEND = 'AcknowledgmentService.sendEmails';

    public class AcknowledgmentException extends Exception {
    }

    /** What one chunk of a run did, so the run record can add it up. */
    public class SendCounts {
        public Integer processed = 0;
        public Integer sent = 0;
        public Integer errors = 0;

        public void add(SendCounts other) {
            this.processed += other.processed;
            this.sent += other.sent;
            this.errors += other.errors;
        }
    }

    // ------------------------------------------------------------------ the queue (trigger side)

    /**
     * Sets the acknowledgment status of gifts being saved, and nothing else (R-AK1, R-AK4,
     * R-AK8).
     *
     * Two statuses are a person's and are never overwritten: Do not acknowledge, which is an
     * instruction, and Acknowledged, which is a fact. Everything else is the queue's to decide.
     *
     * @param gifts the gifts in the save, edited in place because this runs in a before context
     * @param oldGifts the prior versions on an update, null on an insert
     */
    public static void applyRules(List<Gift__c> gifts, Map<Id, Gift__c> oldGifts) {
        if (gifts == null || gifts.isEmpty() || !isEnabled()) {
            return;
        }
        List<Gift__c> undecided = new List<Gift__c>();
        for (Gift__c gift : gifts) {
            if (
                AcknowledgmentRuleService.STATUS_DO_NOT_ACKNOWLEDGE.equals(
                    gift.Acknowledgment_Status__c
                ) ||
                AcknowledgmentRuleService.STATUS_ACKNOWLEDGED.equals(gift.Acknowledgment_Status__c)
            ) {
                continue;
            }
            undecided.add(gift);
        }
        if (undecided.isEmpty()) {
            return;
        }

        List<Acknowledgment_Rule__c> rules = AcknowledgmentSelector.activeRules();
        Set<String> earlierDonors = needsFirstGiftAnswer(rules)
            ? AcknowledgmentRuleService.donorsWithEarlierGifts(
                  undecided,
                  oldGifts == null ? new Set<Id>() : oldGifts.keySet()
              )
            : new Set<String>();

        for (Gift__c gift : undecided) {
            if (!AcknowledgmentRuleService.isAcknowledgeable(gift)) {
                // A pending, refunded or reversing gift leaves the queue rather than sitting in
                // it forever. It is not "do not acknowledge", which is a person's word.
                gift.Acknowledgment_Status__c = AcknowledgmentRuleService.STATUS_NOT_REQUIRED;
                continue;
            }
            AcknowledgmentRuleService.RuleMatch match = AcknowledgmentRuleService.matchFor(
                gift,
                rules,
                earlierDonors
            );
            if (match == null) {
                // No rule covers this gift, so the package has no opinion about it (R-AK1).
                continue;
            }
            gift.Acknowledgment_Status__c = AcknowledgmentRuleService.CHANNEL_NONE.equals(
                    match.channel
                )
                ? AcknowledgmentRuleService.STATUS_NOT_REQUIRED
                : AcknowledgmentRuleService.STATUS_TO_ACKNOWLEDGE;
        }
    }

    /**
     * Releases the claim on gifts a person deliberately put back in the queue (R-AK7).
     *
     * This is the only way a gift that has been thanked for is thanked for again, and it is a
     * person's act: setting the status back to To acknowledge. The earlier row is left exactly as
     * it is, so the record afterwards reads as two thank yous rather than as one that changed its
     * mind.
     */
    public static void releaseClaims(List<Gift__c> gifts, Map<Id, Gift__c> oldGifts) {
        if (gifts == null || gifts.isEmpty() || oldGifts == null) {
            return;
        }
        Set<Id> requeued = new Set<Id>();
        for (Gift__c gift : gifts) {
            Gift__c before = oldGifts.get(gift.Id);
            if (before == null) {
                continue;
            }
            Boolean nowQueued = AcknowledgmentRuleService.STATUS_TO_ACKNOWLEDGE.equals(
                gift.Acknowledgment_Status__c
            );
            Boolean wasQueued = AcknowledgmentRuleService.STATUS_TO_ACKNOWLEDGE.equals(
                before.Acknowledgment_Status__c
            );
            if (nowQueued && !wasQueued) {
                requeued.add(gift.Id);
            }
        }
        if (requeued.isEmpty()) {
            return;
        }
        List<Acknowledgment__c> standing = AcknowledgmentSelector.claimsFor(requeued);
        if (standing.isEmpty()) {
            return;
        }
        for (Acknowledgment__c row : standing) {
            row.Gift_Key__c = null;
        }
        AcknowledgmentWriter.updateAcknowledgments(standing);
    }

    // ------------------------------------------------------------------------ the send (run side)

    /**
     * Thanks the email gifts in this chunk and reports what happened.
     *
     * The order is the point. Rules are matched, recipients and templates are resolved, the rows
     * are claimed, and only then is anything sent: a claim that failed on the unique key is a
     * gift somebody else has already thanked for, and it is dropped silently rather than sent to
     * twice.
     */
    public static SendCounts sendEmails(List<Gift__c> gifts, Id runId) {
        SendCounts counts = new SendCounts();
        if (gifts == null || gifts.isEmpty()) {
            return counts;
        }
        counts.processed = gifts.size();

        List<Acknowledgment_Rule__c> rules = AcknowledgmentSelector.activeRules();
        if (rules.isEmpty()) {
            return counts;
        }
        Set<String> earlierDonors = needsFirstGiftAnswer(rules)
            ? AcknowledgmentRuleService.donorsWithEarlierGifts(gifts, idsOf(gifts))
            : new Set<String>();
        Set<Id> optedOut = optedOutOfEmail(gifts);

        // Pass one: work out who gets what, without writing anything.
        List<Gift__c> sendable = new List<Gift__c>();
        List<AcknowledgmentRuleService.RuleMatch> matches = new List<AcknowledgmentRuleService.RuleMatch>();
        List<Id> recipientIds = new List<Id>();
        List<String> unreachable = new List<String>();

        for (Gift__c gift : gifts) {
            AcknowledgmentRuleService.RuleMatch match = AcknowledgmentRuleService.matchFor(
                gift,
                rules,
                earlierDonors
            );
            if (match == null || !AcknowledgmentRuleService.CHANNEL_EMAIL.equals(match.channel)) {
                // A letter gift and an unmatched gift are both somebody else's business.
                continue;
            }
            Id recipientId = recipientContactIdFor(gift);
            if (recipientId == null) {
                unreachable.add(gift.Name);
                counts.errors++;
                continue;
            }
            if (optedOut.contains(gift.Id)) {
                // The donor asked not to be emailed: no row, no error, and the gift stays queued
                // for the letter run (R-AK13, ADR-0144).
                continue;
            }
            sendable.add(gift);
            matches.add(match);
            recipientIds.add(recipientId);
        }
        if (!unreachable.isEmpty()) {
            // One entry for the chunk, not one per gift: the point is that somebody has to give
            // these donors an address, and thirty log entries do not say that better than one.
            ErrorLogger.logMessage(
                String.format(
                    Label.Giving_Acknowledgment_NoRecipient,
                    new List<String>{
                        String.valueOf(unreachable.size()),
                        String.join(unreachable, ', ')
                    }
                ),
                CONTEXT_SEND,
                ErrorLogger.SEVERITY_WARNING,
                runId
            );
        }
        if (sendable.isEmpty()) {
            return counts;
        }

        Map<Id, Contact> recipients = AcknowledgmentSelector.contactsById(
            new Set<Id>(recipientIds)
        );
        Map<String, Id> templateIds = templateIdsByDeveloperName(developerNamesOf(matches));

        // Pass two: claim. The row is written before anything is sent, so the claim is real.
        List<Acknowledgment__c> rows = new List<Acknowledgment__c>();
        for (Integer index = 0; index < sendable.size(); index++) {
            Contact recipient = recipients.get(recipientIds[index]);
            rows.add(
                new Acknowledgment__c(
                    Gift__c = sendable[index].Id,
                    Rule__c = matches[index].ruleId,
                    Channel__c = AcknowledgmentRuleService.CHANNEL_EMAIL,
                    Template__c = matches[index].template,
                    Status__c = STATUS_QUEUED,
                    Recipient_Contact__c = recipientIds[index],
                    Recipient_Email__c = recipient == null ? null : recipient.Email,
                    Run__c = runId,
                    Gift_Key__c = String.valueOf(sendable[index].Id)
                )
            );
        }
        List<Database.SaveResult> claimed = AcknowledgmentWriter.claim(rows);

        // Pass three: send the claims that are ours, one invocation for the whole chunk.
        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
        List<Acknowledgment__c> messageRows = new List<Acknowledgment__c>();
        List<Acknowledgment__c> unsendable = new List<Acknowledgment__c>();
        List<Gift__c> stamped = new List<Gift__c>();
        Id fromAddressId = fromAddressId();

        for (Integer index = 0; index < claimed.size(); index++) {
            if (!claimed[index].isSuccess()) {
                // Almost always the unique key: this gift has a standing acknowledgment, so
                // somebody has already thanked for it (R-AK7). Nothing to do and nothing to say.
                continue;
            }
            Acknowledgment__c row = rows[index];
            row.Id = claimed[index].getId();
            Id templateId = templateIds.get(row.Template__c);
            if (templateId == null) {
                row.Status__c = STATUS_FAILED;
                row.Failure_Reason__c = String.format(
                    Label.Giving_Acknowledgment_TemplateNotFound,
                    new List<String>{ String.valueOf(row.Template__c) }
                );
                row.Gift_Key__c = null;
                unsendable.add(row);
                counts.errors++;
                continue;
            }
            messages.add(
                messageFor(sendable[index], row.Recipient_Contact__c, templateId, fromAddressId)
            );
            messageRows.add(row);
        }
        if (!unsendable.isEmpty()) {
            AcknowledgmentWriter.updateAcknowledgments(unsendable);
            ErrorLogger.logMessage(
                String.format(
                    Label.Giving_Acknowledgment_TemplatesMissing,
                    new List<String>{ String.valueOf(unsendable.size()) }
                ),
                CONTEXT_SEND,
                ErrorLogger.SEVERITY_ERROR,
                runId
            );
        }
        if (messages.isEmpty()) {
            return counts;
        }

        List<EmailSendOutcome> outcomes = emailSender.send(messages);
        List<Acknowledgment__c> settled = new List<Acknowledgment__c>();
        List<String> failures = new List<String>();
        for (Integer index = 0; index < messageRows.size(); index++) {
            Acknowledgment__c row = messageRows[index];
            EmailSendOutcome outcome = index < outcomes.size() ? outcomes[index] : null;
            if (outcome != null && outcome.sent == true) {
                row.Status__c = STATUS_SENT;
                row.Sent_On__c = System.now();
                settled.add(row);
                stamped.add(
                    new Gift__c(
                        Id = row.Gift__c,
                        Acknowledgment_Status__c = AcknowledgmentRuleService.STATUS_ACKNOWLEDGED,
                        Acknowledgment_Date__c = Date.today()
                    )
                );
                counts.sent++;
            } else {
                row.Status__c = STATUS_FAILED;
                row.Failure_Reason__c = failureReasonOf(
                    outcome,
                    Label.Giving_Acknowledgment_SendFailedUnknown
                );
                // The key goes, so the next send tries this gift again (R-AK7).
                row.Gift_Key__c = null;
                settled.add(row);
                failures.add(row.Failure_Reason__c);
                counts.errors++;
            }
        }
        AcknowledgmentWriter.updateAcknowledgments(settled);
        AcknowledgmentWriter.stampGifts(stamped);
        if (!failures.isEmpty()) {
            ErrorLogger.logMessages(failures, CONTEXT_SEND, ErrorLogger.SEVERITY_ERROR);
        }
        return counts;
    }

    /**
     * The contact a thank you is addressed to: the donor when the donor is a person, and the
     * organization's primary contact when it is not. An organization with no primary contact has
     * nobody to email, and says so rather than guessing (R-AK9).
     */
    public static Id recipientContactIdFor(Gift__c gift) {
        if (gift.Donor_Contact__c != null) {
            return gift.Donor_Contact__c;
        }
        if (gift.Donor_Account__c != null && gift.Donor_Account__r != null) {
            return gift.Donor_Account__r.Primary_Contact__c;
        }
        return null;
    }

    /**
     * The gifts, by Id, whose email recipient has Email Opt Out set (R-AK13, ADR-0144). The send
     * skips them, and the letter run and the page treat them as letters, so all three read the
     * opt-out through this one method. The recipient is `recipientContactIdFor`'s, so for an
     * organization or household gift it is the primary contact's opt-out that counts.
     */
    public static Set<Id> optedOutOfEmail(List<Gift__c> gifts) {
        Set<Id> giftIds = new Set<Id>();
        if (gifts == null || gifts.isEmpty()) {
            return giftIds;
        }
        Map<Id, Id> recipientByGift = new Map<Id, Id>();
        for (Gift__c gift : gifts) {
            Id recipientId = recipientContactIdFor(gift);
            if (recipientId != null && gift.Id != null) {
                recipientByGift.put(gift.Id, recipientId);
            }
        }
        Set<Id> optedOutContacts = AcknowledgmentSelector.optedOutOfEmail(
            new Set<Id>(recipientByGift.values())
        );
        for (Id giftId : recipientByGift.keySet()) {
            if (optedOutContacts.contains(recipientByGift.get(giftId))) {
                giftIds.add(giftId);
            }
        }
        return giftIds;
    }

    /**
     * One message, composed by the platform rather than by us (ADR-0032).
     *
     * The template is a standard email template, the contact is the target so that
     * `{!Contact.FirstName}` resolves, and the gift is the `WhatId` so that `{!Gift__c.Amount__c}`
     * does. The package composes no HTML and merges no tokens of its own.
     *
     * The activity is not saved, because logging a task per thank you would make this feature
     * depend on a standard object the packages may not use (plan Section 4.2).
     */
    @TestVisible
    private static Messaging.SingleEmailMessage messageFor(
        Gift__c gift,
        Id recipientContactId,
        Id templateId,
        Id fromAddressId
    ) {
        Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
        message.setTemplateId(templateId);
        message.setTargetObjectId(recipientContactId);
        message.setWhatId(gift.Id);
        message.setTreatTargetObjectAsRecipient(true);
        message.setSaveAsActivity(false);
        if (fromAddressId != null) {
            message.setOrgWideEmailAddressId(fromAddressId);
        }
        return message;
    }

    // ---------------------------------------------------------------------------- odds and ends

    /** Whether gifts join the queue at all (R-AK5). */
    public static Boolean isEnabled() {
        return Giving_Settings__c.getOrgDefaults().Acknowledgments_Enabled__c == true;
    }

    /**
     * Whether the running user may run a send. Read once per transaction: the answer cannot change
     * inside one, and a batch chunk would otherwise ask the same question ninety times.
     *
     * Visible to tests because a custom permission cannot be granted to the user a test runs as
     * without assigning a permission set, which would make every send test a test of permission
     * set assignment. This is the same accommodation `ReceiptService` makes for the same reason.
     */
    @TestVisible
    private static Boolean sendPermission = null;

    /** True when a person may run a send. */
    public static Boolean canSend() {
        if (sendPermission == null) {
            sendPermission = FeatureManagement.checkPermission(SEND_PERMISSION);
        }
        return sendPermission;
    }

    public static void requireSendPermission() {
        if (!canSend()) {
            throw new AcknowledgmentException(Label.Giving_Acknowledgment_NoPermission);
        }
    }

    /**
     * The organization wide address to send from, or null for the running user's own address.
     * A configured address that the org does not have is not an error worth stopping a send for:
     * the thank you goes out from the user instead, and the setting is visibly wrong on the page.
     */
    @TestVisible
    public static Id fromAddressId() {
        String configured = Giving_Settings__c.getOrgDefaults().Acknowledgment_From_Address__c;
        if (String.isBlank(configured)) {
            return null;
        }
        List<OrgWideEmailAddress> addresses = [
            SELECT Id
            FROM OrgWideEmailAddress
            WHERE Address = :configured.trim()
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return addresses.isEmpty() ? null : addresses[0].Id;
    }

    /** Records what the last run did, so the page can say so without opening a run (R-AK12). */
    public static void recordLastRun(String summary) {
        // Only these two keys, on the locked stored record; a first save keeps the checkboxes
        // that ship on (OrgSettingsSystemWriter, ADR-0021).
        OrgSettingsSystemWriter.save(
            Giving_Settings__c.SObjectType,
            new Map<Schema.SObjectField, Object>{
                Giving_Settings__c.Acknowledgments_Last_Run__c => System.now(),
                Giving_Settings__c.Acknowledgments_Last_Run_Summary__c => summary == null ||
                    summary.length() <= 255
                    ? summary
                    : summary.substring(0, 255)
            }
        );
    }

    /**
     * The sender in use. Overridable by a test, which is the whole reason the interface exists:
     * an org that cannot send mail should still be able to prove what this class recorded.
     */
    @TestVisible
    private static EmailSender emailSender = new MessagingEmailSender();

    /**
     * The sentence a person reads on a row whose email did not go: the platform's first error,
     * trimmed to what fits on the record, or `unknown` when it gave none. The rest of the detail
     * is in the Error Log entry the caller writes.
     */
    public static String failureReasonOf(EmailSendOutcome outcome, String unknown) {
        return outcome == null || String.isBlank(outcome.error) ? unknown : outcome.error.left(255);
    }

    private static Boolean needsFirstGiftAnswer(List<Acknowledgment_Rule__c> rules) {
        for (Acknowledgment_Rule__c rule : rules) {
            if (rule.First_Gift_Only__c == true) {
                return true;
            }
        }
        return false;
    }

    private static Set<Id> idsOf(List<Gift__c> gifts) {
        Set<Id> ids = new Set<Id>();
        for (Gift__c gift : gifts) {
            if (gift.Id != null) {
                ids.add(gift.Id);
            }
        }
        return ids;
    }

    private static Set<String> developerNamesOf(List<AcknowledgmentRuleService.RuleMatch> matches) {
        Set<String> names = new Set<String>();
        for (AcknowledgmentRuleService.RuleMatch match : matches) {
            if (String.isNotBlank(match.template)) {
                names.add(match.template.trim());
            }
        }
        return names;
    }

    private static Map<String, Id> templateIdsByDeveloperName(Set<String> developerNames) {
        Map<String, Id> byName = new Map<String, Id>();
        if (developerNames.isEmpty()) {
            return byName;
        }
        for (EmailTemplate template : [
            SELECT Id, DeveloperName
            FROM EmailTemplate
            WHERE DeveloperName IN :developerNames
            WITH SYSTEM_MODE
        ]) {
            byName.put(template.DeveloperName, template.Id);
        }
        return byName;
    }
}
