/**
 * Reminding donors about pledge installments that are coming due or are overdue (G-30, canonical
 * model 25P and 25Q).
 *
 * It reuses the acknowledgment feature's seams rather than building a second send path: the
 * Core `EmailSender` interface (so a test proves what was composed without an org that can
 * send mail), the email template picked by developer name, the organization wide from address,
 * the Send Acknowledgments permission, and the letter merge file and its CSV escaping. What is
 * new is only what a reminder needs: steps measured in days from the due date, and a log keyed
 * to the installment and the step.
 *
 * Four rules run through everything here:
 *
 * - **Nothing sends unless an administrator turned it on.** `Pledge_Reminders_Enabled__c` is
 *   off by default and is checked before every run, by hand or by the nightly schedule.
 * - **One step per installment per run, the latest one due.** An installment 20 days overdue
 *   with steps at 7 and 14 days gets the 14 day step, not both.
 * - **Only recent steps fire.** A step fires from its day until `CATCH_UP_DAYS` later, so a run
 *   that missed a night still sends, and turning the feature on does not send a final notice to
 *   an installment that went overdue last spring.
 * - **A reminder is claimed before it is sent.** `Reminder_Key__c` is unique, so the row is the
 *   claim and the same step cannot remind the same installment twice. A failed send releases the
 *   key so the next run tries again while the step is still recent. A failure before the send
 *   rolls the claims back; a send the platform refuses, or a settle that fails, still leaves
 *   every claimed email row Sent or Failed, never Queued with its key held.
 */
public with sharing class PledgeReminderService {
    public static final String CHANNEL_EMAIL = 'Email';
    public static final String CHANNEL_LETTER = 'Letter';
    public static final String STATUS_QUEUED = 'Queued';
    public static final String STATUS_SENT = 'Sent';
    public static final String STATUS_FAILED = 'Failed';

    /** How many days after its day a step can still fire. */
    public static final Integer CATCH_UP_DAYS = 14;

    /** How many letters one merge file carries. Beyond this, run it again for the rest. */
    public static final Integer LETTER_LIMIT = 2000;

    private static final String CONTEXT_SEND = 'PledgeReminderService.process';
    private static final String CONTEXT_START = 'PledgeReminderService.startRun';

    public class PledgeReminderException extends Exception {
    }

    /** One reminder a run would make. */
    public class Planned {
        public Installment__c installment;
        public Pledge_Reminder_Step__c step;
        /** The channel it will actually go by: an email step becomes a letter for an opt-out. */
        public String channel;
        public Id recipientId;
    }

    /** What a run, or a preview of one, adds up to. */
    public class Counts {
        public Integer processed = 0;
        public Integer emails = 0;
        public Integer letters = 0;
        public Integer errors = 0;
        public Integer withoutRecipient = 0;

        public void add(Counts other) {
            processed += other.processed;
            emails += other.emails;
            letters += other.letters;
            errors += other.errors;
            withoutRecipient += other.withoutRecipient;
        }
    }

    // ------------------------------------------------------------------------------ the switch

    /** Whether reminders may go out at all. Off by default. */
    public static Boolean isEnabled() {
        return Giving_Settings__c.getOrgDefaults().Pledge_Reminders_Enabled__c == true;
    }

    public static void requireEnabled() {
        if (!isEnabled()) {
            throw new PledgeReminderException(Label.Giving_PledgeReminders_Disabled);
        }
    }

    public static void requireSendPermission() {
        if (!AcknowledgmentService.canSend()) {
            throw new PledgeReminderException(Label.Giving_PledgeReminders_NoPermission);
        }
    }

    // ------------------------------------------------------------------------------ the window

    /** The earliest due date any active step could still be firing for, today. */
    public static Date windowFrom(List<Pledge_Reminder_Step__c> steps, Date today) {
        Integer latest = null;
        for (Pledge_Reminder_Step__c step : steps) {
            Integer days = daysOf(step);
            if (latest == null || days > latest) {
                latest = days;
            }
        }
        // A step at +14 fires for installments due 14 days ago, and for CATCH_UP_DAYS more.
        return latest == null ? today.addDays(1) : today.addDays(-(latest + CATCH_UP_DAYS));
    }

    /** The latest due date any active step could be firing for, today. */
    public static Date windowTo(List<Pledge_Reminder_Step__c> steps, Date today) {
        Integer earliest = null;
        for (Pledge_Reminder_Step__c step : steps) {
            Integer days = daysOf(step);
            if (earliest == null || days < earliest) {
                earliest = days;
            }
        }
        // A step at -7 fires for installments due in 7 days.
        return earliest == null ? today.addDays(-1) : today.addDays(-earliest);
    }

    // ------------------------------------------------------------------------- what would go

    /**
     * Works out which reminder each installment gets today, without writing anything.
     *
     * @param counts filled in with the installments that have nobody to email
     */
    public static List<Planned> plan(
        List<Installment__c> installments,
        List<Pledge_Reminder_Step__c> steps,
        Date today,
        Counts counts
    ) {
        List<Planned> planned = new List<Planned>();
        if (installments == null || installments.isEmpty() || steps == null || steps.isEmpty()) {
            return planned;
        }
        for (Installment__c installment : installments) {
            Pledge_Reminder_Step__c chosen = stepFor(installment, steps, today);
            if (chosen == null) {
                continue;
            }
            Planned item = new Planned();
            item.installment = installment;
            item.step = chosen;
            item.channel = CHANNEL_LETTER.equals(chosen.Channel__c)
                ? CHANNEL_LETTER
                : CHANNEL_EMAIL;
            item.recipientId = recipientContactIdFor(installment);
            planned.add(item);
        }

        // An email goes only to somebody with a working address who has not opted out. A donor
        // who opted out, has no address, or whose address bounced is reminded by letter, the
        // opt-out rule the acknowledgment send follows (R-AK13, R-PR5).
        Set<Id> emailRecipients = new Set<Id>();
        for (Planned item : planned) {
            if (CHANNEL_EMAIL.equals(item.channel) && item.recipientId != null) {
                emailRecipients.add(item.recipientId);
            }
        }
        Set<Id> notEmailable = PledgeReminderSelector.cannotBeEmailed(emailRecipients);
        List<Planned> kept = new List<Planned>();
        for (Planned item : planned) {
            if (CHANNEL_EMAIL.equals(item.channel)) {
                if (item.recipientId == null) {
                    counts.withoutRecipient++;
                    continue;
                }
                if (notEmailable.contains(item.recipientId)) {
                    item.channel = CHANNEL_LETTER;
                }
            }
            kept.add(item);
        }
        return kept;
    }

    /** The one step an installment gets today, or null: the latest whose day is recent. */
    @TestVisible
    private static Pledge_Reminder_Step__c stepFor(
        Installment__c installment,
        List<Pledge_Reminder_Step__c> steps,
        Date today
    ) {
        if (installment.Due_Date__c == null) {
            return null;
        }
        Pledge_Reminder_Step__c chosen = null;
        Date chosenDay = null;
        for (Pledge_Reminder_Step__c step : steps) {
            if (step.Active__c != true || step.Days_From_Due__c == null) {
                continue;
            }
            Date day = installment.Due_Date__c.addDays(daysOf(step));
            if (day > today || day < today.addDays(-CATCH_UP_DAYS)) {
                continue;
            }
            // A before-due step is a heads-up: once the due date arrives it no longer applies,
            // even inside its catch up days (R-PR2).
            if (daysOf(step) < 0 && today >= installment.Due_Date__c) {
                continue;
            }
            if (chosenDay == null || day > chosenDay) {
                chosen = step;
                chosenDay = day;
            }
        }
        return chosen;
    }

    /**
     * Counts what a run started now would do, for the page. Capped, and read in the same user
     * mode as the run.
     */
    public static Counts preview() {
        Counts counts = new Counts();
        List<Pledge_Reminder_Step__c> steps = PledgeReminderSelector.activeSteps();
        if (steps.isEmpty()) {
            return counts;
        }
        Date today = Date.today();
        List<Installment__c> installments = PledgeReminderSelector.openInstallments(
            windowFrom(steps, today),
            windowTo(steps, today),
            PledgeReminderSelector.QUEUE_LIMIT
        );
        counts.processed = installments.size();
        for (Planned item : plan(installments, steps, today, counts)) {
            if (CHANNEL_LETTER.equals(item.channel)) {
                counts.letters++;
            } else {
                counts.emails++;
            }
        }
        return counts;
    }

    // ---------------------------------------------------------------------------- the send

    /**
     * Starts the send and returns the batch job's id. Refuses when reminders are off, or when
     * the person has no permission to send.
     */
    public static Id startRun() {
        requireEnabled();
        requireSendPermission();
        try {
            return Database.executeBatch(new PledgeReminderBatch(), PledgeReminderBatch.SCOPE);
        } catch (Exception queueFailure) {
            ErrorLogger.log(queueFailure, CONTEXT_START);
            throw new PledgeReminderException(Label.Giving_PledgeReminders_UnexpectedError);
        }
    }

    /**
     * Reminds the installments in this chunk and reports what happened.
     *
     * The order is the point: steps are matched, recipients and templates are resolved, the rows
     * are claimed, and only then is anything sent. A claim that failed on the unique key is an
     * installment this step has already reminded, and it is dropped silently.
     */
    public static Counts process(List<Installment__c> installments) {
        Counts counts = new Counts();
        if (installments == null || installments.isEmpty() || !isEnabled()) {
            return counts;
        }
        counts.processed = installments.size();
        List<Pledge_Reminder_Step__c> steps = PledgeReminderSelector.activeSteps();
        Date today = Date.today();
        List<Planned> planned = plan(installments, steps, today, counts);
        if (counts.withoutRecipient > 0) {
            ErrorLogger.logMessage(
                String.format(
                    Label.Giving_PledgeReminders_NoRecipient,
                    new List<String>{ String.valueOf(counts.withoutRecipient) }
                ),
                CONTEXT_SEND,
                ErrorLogger.SEVERITY_WARNING
            );
        }
        if (planned.isEmpty()) {
            return counts;
        }

        Set<Id> recipientIds = new Set<Id>();
        for (Planned item : planned) {
            if (item.recipientId != null) {
                recipientIds.add(item.recipientId);
            }
        }
        Map<Id, Contact> recipients = PledgeReminderSelector.contactsById(recipientIds);

        // Claim: the row is written before anything is sent, so the claim is real.
        List<Pledge_Reminder__c> rows = new List<Pledge_Reminder__c>();
        for (Planned item : planned) {
            Contact recipient = item.recipientId == null ? null : recipients.get(item.recipientId);
            Boolean isEmail = CHANNEL_EMAIL.equals(item.channel);
            rows.add(
                new Pledge_Reminder__c(
                    Installment__c = item.installment.Id,
                    Commitment__c = item.installment.Commitment__c,
                    Step__c = item.step.Id,
                    Step_Name__c = item.step.Name,
                    Channel__c = item.channel,
                    Status__c = STATUS_QUEUED,
                    Template__c = isEmail ? item.step.Email_Template__c : null,
                    Recipient_Contact__c = item.recipientId,
                    Recipient_Email__c = isEmail && recipient != null ? recipient.Email : null,
                    Days_Overdue__c = item.installment.Due_Date__c.daysBetween(today),
                    Reminder_Key__c = keyFor(item.installment.Id, item.step.Id)
                )
            );
        }
        // Everything from the claim to the send runs under a savepoint: if any of it throws, the
        // claims are rolled back with it, so no row is left Queued holding its key.
        Savepoint beforeClaim = Database.setSavepoint();
        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
        List<Pledge_Reminder__c> messageRows = new List<Pledge_Reminder__c>();
        try {
            claimAndCompose(planned, rows, messages, messageRows, counts);
        } catch (Exception beforeSend) {
            Database.rollback(beforeClaim);
            throw beforeSend;
        }
        if (messages.isEmpty()) {
            return counts;
        }
        settle(messageRows, sendAll(messages), counts);
        return counts;
    }

    /**
     * Claims the rows, then composes a message for each email claim that has a template. Rows
     * whose template is gone are settled as Failed here; letters stay Queued for the merge file.
     */
    private static void claimAndCompose(
        List<Planned> planned,
        List<Pledge_Reminder__c> rows,
        List<Messaging.SingleEmailMessage> messages,
        List<Pledge_Reminder__c> messageRows,
        Counts counts
    ) {
        List<Database.SaveResult> claimed = PledgeReminderWriter.claim(rows);

        Set<String> templateNames = new Set<String>();
        for (Planned item : planned) {
            if (
                CHANNEL_EMAIL.equals(item.channel) && String.isNotBlank(item.step.Email_Template__c)
            ) {
                templateNames.add(item.step.Email_Template__c.trim());
            }
        }
        Map<String, Id> templateIds = GivingEmailTemplates.idsByDeveloperName(templateNames);
        Id fromAddressId = AcknowledgmentService.fromAddressId();

        List<Pledge_Reminder__c> unsendable = new List<Pledge_Reminder__c>();
        for (Integer index = 0; index < claimed.size(); index++) {
            if (!claimed[index].isSuccess()) {
                // The unique key: this step has already reminded this installment.
                continue;
            }
            Pledge_Reminder__c row = rows[index];
            row.Id = claimed[index].getId();
            if (CHANNEL_LETTER.equals(row.Channel__c)) {
                counts.letters++;
                continue;
            }
            Id templateId = String.isBlank(row.Template__c)
                ? null
                : templateIds.get(row.Template__c.trim());
            if (templateId == null) {
                row.Status__c = STATUS_FAILED;
                row.Failure_Reason__c = String.format(
                    Label.Giving_PledgeReminders_TemplateNotFound,
                    new List<String>{ String.valueOf(row.Template__c) }
                );
                row.Reminder_Key__c = null;
                unsendable.add(row);
                counts.errors++;
                continue;
            }
            // The installment is the `WhatId`, so `{!Installment__c.Due_Date__c}` resolves.
            messages.add(
                GivingEmailTemplates.message(
                    planned[index].installment.Id,
                    row.Recipient_Contact__c,
                    templateId,
                    fromAddressId
                )
            );
            messageRows.add(row);
        }
        if (!unsendable.isEmpty()) {
            PledgeReminderWriter.updateReminders(unsendable);
            ErrorLogger.logMessage(
                String.format(
                    Label.Giving_PledgeReminders_TemplatesMissing,
                    new List<String>{ String.valueOf(unsendable.size()) }
                ),
                CONTEXT_SEND,
                ErrorLogger.SEVERITY_ERROR
            );
        }
    }

    /**
     * Sends the chunk in one call. A call the platform refuses as a whole sent nothing, so every
     * message comes back failed with the platform's reason, and `settle` releases every key.
     */
    private static List<EmailSendOutcome> sendAll(List<Messaging.SingleEmailMessage> messages) {
        try {
            return emailSender.send(messages);
        } catch (Exception sendFailure) {
            ErrorLogger.log(sendFailure, CONTEXT_SEND);
            List<EmailSendOutcome> outcomes = new List<EmailSendOutcome>();
            for (Integer index = 0; index < messages.size(); index++) {
                outcomes.add(EmailSendOutcome.failed(sendFailure.getMessage()?.left(255)));
            }
            return outcomes;
        }
    }

    /**
     * Marks each sent row Sent and each failed row Failed with its reason and its key released,
     * so the next run tries it again while the step is still recent.
     */
    private static void settle(
        List<Pledge_Reminder__c> messageRows,
        List<EmailSendOutcome> outcomes,
        Counts counts
    ) {
        List<Pledge_Reminder__c> settled = new List<Pledge_Reminder__c>();
        List<String> failures = new List<String>();
        for (Integer index = 0; index < messageRows.size(); index++) {
            Pledge_Reminder__c row = messageRows[index];
            EmailSendOutcome outcome = index < outcomes.size() ? outcomes[index] : null;
            if (outcome != null && outcome.sent == true) {
                row.Status__c = STATUS_SENT;
                row.Sent_On__c = System.now();
                counts.emails++;
            } else {
                row.Status__c = STATUS_FAILED;
                row.Failure_Reason__c = AcknowledgmentService.failureReasonOf(
                    outcome,
                    Label.Giving_PledgeReminders_SendFailedUnknown
                );
                // The key goes, so the next run tries this reminder again while it is recent.
                row.Reminder_Key__c = null;
                failures.add(row.Failure_Reason__c);
                counts.errors++;
            }
            settled.add(row);
        }
        try {
            PledgeReminderWriter.updateReminders(settled);
        } catch (Exception settleFailure) {
            // The mail has gone (or failed), so the rows are not rolled back. Each is settled
            // again on its own with only the fields its outcome needs and a fixed reason, so
            // none stays Queued holding its key; a row that still refuses is logged.
            ErrorLogger.log(settleFailure, CONTEXT_SEND);
            settleEachPlainly(settled);
        }
        if (!failures.isEmpty()) {
            ErrorLogger.logMessages(failures, CONTEXT_SEND, ErrorLogger.SEVERITY_ERROR);
        }
    }

    private static void settleEachPlainly(List<Pledge_Reminder__c> settled) {
        List<Pledge_Reminder__c> plain = new List<Pledge_Reminder__c>();
        for (Pledge_Reminder__c row : settled) {
            Boolean sent = STATUS_SENT.equals(row.Status__c);
            plain.add(
                new Pledge_Reminder__c(
                    Id = row.Id,
                    Status__c = row.Status__c,
                    Sent_On__c = row.Sent_On__c,
                    Reminder_Key__c = row.Reminder_Key__c,
                    Failure_Reason__c = sent ? null : Label.Giving_PledgeReminders_SendFailedUnknown
                )
            );
        }
        List<String> stillQueued = new List<String>();
        List<Database.SaveResult> results = PledgeReminderWriter.settleEach(plain);
        for (Integer index = 0; index < results.size(); index++) {
            if (!results[index].isSuccess()) {
                stillQueued.add(
                    String.valueOf(plain[index].Id) +
                        ': ' +
                        results[index].getErrors()[0].getMessage()
                );
            }
        }
        if (!stillQueued.isEmpty()) {
            ErrorLogger.logMessages(stillQueued, CONTEXT_SEND, ErrorLogger.SEVERITY_ERROR);
        }
    }

    // --------------------------------------------------------------------------- the letters

    /**
     * Writes the merge file for the letters waiting and returns how many are in it. The rows
     * stay Queued until a person says the letters went, because Salesforce cannot know whether
     * anything was printed (the acknowledgment letter rule, R-AK11).
     */
    public static Integer produceLetters() {
        requireSendPermission();
        List<Pledge_Reminder__c> letters = PledgeReminderSelector.lettersWithoutFile(LETTER_LIMIT);
        if (letters.isEmpty()) {
            return 0;
        }
        Id documentId = AcknowledgmentWriter.storeMergeFile(
            String.format(
                Label.Giving_PledgeReminders_MergeFileTitle,
                new List<String>{ String.valueOf(Date.today()) }
            ),
            csvFor(letters),
            letters[0].Id
        );
        for (Pledge_Reminder__c letter : letters) {
            letter.Letter_File_Document_Id__c = documentId;
        }
        PledgeReminderWriter.updateReminders(letters);
        return letters.size();
    }

    /** Says the letters in a file went out. Returns how many were marked. */
    public static Integer markLettersSent() {
        requireSendPermission();
        List<Pledge_Reminder__c> waiting = PledgeReminderSelector.lettersAwaitingConfirmation();
        for (Pledge_Reminder__c letter : waiting) {
            letter.Status__c = STATUS_SENT;
            letter.Sent_On__c = System.now();
        }
        PledgeReminderWriter.updateReminders(waiting);
        return waiting.size();
    }

    /** The columns, in the order they are written. */
    @TestVisible
    private static final List<String> HEADERS = new List<String>{
        'Pledge',
        'Installment',
        'Due Date',
        'Amount Due',
        'Days Overdue',
        'Step',
        'Donor Name',
        'Greeting',
        'Street',
        'City',
        'State',
        'Postal Code',
        'Country'
    };

    /** One CSV, one row per letter, with the header first. */
    @TestVisible
    private static String csvFor(List<Pledge_Reminder__c> letters) {
        List<String> lines = new List<String>{ String.join(HEADERS, ',') };
        for (Pledge_Reminder__c letter : letters) {
            Installment__c installment = letter.Installment__r;
            Contact person = letter.Commitment__r == null
                ? null
                : letter.Commitment__r.Donor_Contact__r;
            Account organization = letter.Commitment__r == null
                ? null
                : letter.Commitment__r.Donor_Account__r;
            Decimal owed = installment == null
                ? null
                : (installment.Expected_Amount__c == null ? 0 : installment.Expected_Amount__c) -
                  (installment.Paid_Amount__c == null ? 0 : installment.Paid_Amount__c);
            String donorName = person != null
                ? person.Name
                : (organization == null ? '' : organization.Name);
            lines.add(
                String.join(
                    new List<String>{
                        cell(letter.Commitment__r == null ? '' : letter.Commitment__r.Name),
                        cell(installment == null ? '' : String.valueOf(installment.Sequence__c)),
                        cell(installment == null ? '' : String.valueOf(installment.Due_Date__c)),
                        cell(owed == null ? '' : String.valueOf(owed)),
                        cell(
                            letter.Days_Overdue__c == null
                                ? ''
                                : String.valueOf(letter.Days_Overdue__c)
                        ),
                        cell(letter.Step_Name__c),
                        cell(donorName),
                        cell(greetingOf(person, organization, donorName)),
                        cell(person != null ? person.MailingStreet : organization?.BillingStreet),
                        cell(person != null ? person.MailingCity : organization?.BillingCity),
                        cell(person != null ? person.MailingState : organization?.BillingState),
                        cell(
                            person != null
                                ? person.MailingPostalCode
                                : organization?.BillingPostalCode
                        ),
                        cell(person != null ? person.MailingCountry : organization?.BillingCountry)
                    },
                    ','
                )
            );
        }
        return String.join(lines, '\n');
    }

    /** How the letter opens: the household's agreed greeting, the first name, or the name. */
    private static String greetingOf(Contact person, Account organization, String donorName) {
        if (
            organization != null && String.isNotBlank(organization.Household_Informal_Greeting__c)
        ) {
            return organization.Household_Informal_Greeting__c;
        }
        if (person != null && String.isNotBlank(person.FirstName)) {
            return person.FirstName;
        }
        return donorName;
    }

    /** CSV escaping, including the spreadsheet formula guard, shared with the thank you letters. */
    private static String cell(String value) {
        return AcknowledgmentLetterMerge.escape(value);
    }

    // ---------------------------------------------------------------------------- odds and ends

    /** Records what the last run did, so the page can say so. */
    public static void recordLastRun(String summary) {
        OrgSettingsSystemWriter.save(
            Giving_Settings__c.SObjectType,
            new Map<Schema.SObjectField, Object>{
                Giving_Settings__c.Pledge_Reminders_Last_Run__c => System.now(),
                Giving_Settings__c.Pledge_Reminders_Last_Run_Summary__c => summary == null ||
                    summary.length() <= 255
                    ? summary
                    : summary.substring(0, 255)
            }
        );
    }

    /**
     * The contact a reminder is addressed to: the pledge's donor when a person, and the
     * organization's primary contact when it is not.
     */
    public static Id recipientContactIdFor(Installment__c installment) {
        if (installment.Commitment__r == null) {
            return null;
        }
        if (installment.Commitment__r.Donor_Contact__c != null) {
            return installment.Commitment__r.Donor_Contact__c;
        }
        if (
            installment.Commitment__r.Donor_Account__c != null &&
            installment.Commitment__r.Donor_Account__r != null
        ) {
            return installment.Commitment__r.Donor_Account__r.Primary_Contact__c;
        }
        return null;
    }

    @TestVisible
    private static String keyFor(Id installmentId, Id stepId) {
        return String.valueOf(installmentId) + '-' + String.valueOf(stepId);
    }

    private static Integer daysOf(Pledge_Reminder_Step__c step) {
        return step.Days_From_Due__c == null ? 0 : step.Days_From_Due__c.intValue();
    }

    /** Overridable by a test, like the acknowledgment feature's sender. */
    @TestVisible
    private static EmailSender emailSender = new MessagingEmailSender();
}
