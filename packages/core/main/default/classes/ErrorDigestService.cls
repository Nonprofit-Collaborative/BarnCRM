/**
 * The error digest (C-23, canonical model R-E5, ADR-0055): one short email to each of the
 * people who look after BarnCRM, counting the Error Log entries that arrived since the last
 * digest and are still New.
 *
 * What it may say is the point of the design. It counts entries by source and by severity and
 * links to the newest by record name; it never copies an entry's message, technical detail or
 * record reference, so it carries less about a donor than the Error Log itself. It goes only to
 * active users of the org, each message addressed to the user record, which the platform does
 * not count against the daily limit on email sent to addresses. A run that finds nothing new
 * sends nothing.
 *
 * Each run remembers the end of the window it covered. A run that sent, or found nothing, moves
 * the window on; a run that could not send leaves it where it was, so the next one tries again
 * with nothing lost and nothing counted twice.
 */
public with sharing class ErrorDigestService {
    public static final String FREQUENCY_DAILY = 'Daily';
    public static final String FREQUENCY_WEEKLY = 'Weekly';

    /** How many entries one digest links to by name; the rest are counted. */
    @TestVisible
    private static final Integer ENTRIES_LISTED = 25;

    /**
     * How early a run may be and still count as due, on top of the date comparison. The job runs
     * at 07:00 and the window it covered ended a few seconds after 07:00 the day before, so a run
     * a second short of a full day must not wait another day. A due date is compared as a local
     * date first, which is what keeps a 23 hour day at a clock change from skipping a digest.
     */
    private static final Integer DUE_TOLERANCE_MINUTES = 60;

    /**
     * The most entries one run reads and counts; beyond it the digest says "more than". Test
     * visible so a test can prove a flooded Error Log still gets its digest.
     */
    @TestVisible
    private static Integer entryCap = 2000;

    /** Query rows kept back for the rest of the run (recipients, the settings record). */
    private static final Integer QUERY_ROW_MARGIN = 1000;

    private static final String LOG_CONTEXT = 'Error digest';

    /**
     * Test seam, null in every real transaction: when a test sets it, messages are added here
     * instead of being handed to the platform, so what the digest composed can be read back.
     */
    @TestVisible
    private static List<Messaging.SingleEmailMessage> capturedMessages;

    /** Test seam: when set, sending fails with this reason, as a blocked org's would. */
    @TestVisible
    private static String sendFailureForTest;

    /** What one run did. */
    public class Outcome {
        public Boolean sent = false;
        public Integer entries = 0;
        public Integer recipients = 0;
        public String summary;
    }

    /** The scheduled run: sends only when the chosen frequency says a digest is due. */
    public static Outcome runScheduled() {
        return run(false);
    }

    /** Send now: ignores the frequency, and still sends nothing when nothing is new. */
    public static Outcome sendNow() {
        return run(true);
    }

    private static Outcome run(Boolean ignoreFrequency) {
        Datetime runAt = System.now();
        // Locked until this run ends, so Send now and the scheduled run take turns: the second
        // reads the window the first moved, and never sends the same entries again.
        BarnCRM_Settings__c settings = OrgSettingsSystemWriter.lockStored();
        if (settings == null) {
            settings = SettingsService.getSettings();
        }
        Datetime coveredUntil = settings.Error_Digest_Covered_Until__c;
        String lastSummary = settings.Error_Digest_Last_Run_Summary__c;
        Integer periodDays = FREQUENCY_WEEKLY.equals(settings.Error_Digest_Frequency__c) ? 7 : 1;
        Outcome outcome = new Outcome();

        if (!ignoreFrequency && coveredUntil != null && !isDue(coveredUntil, periodDays, runAt)) {
            outcome.summary = String.format(
                System.Label.Core_ErrorDigest_SummaryNotDue,
                new List<Object>{ coveredUntil.addDays(periodDays).format() }
            );
            return finish(outcome, runAt, coveredUntil);
        }

        // Two reads spend up to the cap in query rows each; keep a margin for the rest.
        Integer room = (Limits.getLimitQueryRows() - Limits.getQueryRows() - QUERY_ROW_MARGIN) / 2;
        if (room < ENTRIES_LISTED) {
            return notSent(
                outcome,
                System.Label.Core_ErrorDigest_NoRoom,
                lastSummary,
                runAt,
                coveredUntil
            );
        }
        Integer cap = Math.min(entryCap, room);

        Datetime windowStart = coveredUntil == null ? runAt.addDays(-periodDays) : coveredUntil;
        ErrorDigestSelector.Window window = ErrorDigestSelector.newEntries(
            windowStart,
            runAt,
            ENTRIES_LISTED,
            cap
        );
        outcome.entries = window.total;
        // The weekly admin summary (C-54): only in a weekly digest, and only when switched on.
        AdminDigestSummary.Summary summary = includeSummary(settings, periodDays)
            ? AdminDigestSummary.build(windowStart, runAt)
            : null;
        if (window.total == 0 && (summary == null || !summary.hasContent())) {
            outcome.summary = String.format(
                System.Label.Core_ErrorDigest_SummaryNothingNew,
                new List<Object>{ windowStart.format() }
            );
            return finish(outcome, runAt, runAt);
        }

        List<User> recipients = ErrorDigestRecipients.resolve(settings.Error_Digest_Recipients__c);
        if (recipients.isEmpty()) {
            // Not written to the Error Log: the next run would find that entry, fail to send it,
            // and log again. Health Check already names an org where nobody administers.
            outcome.summary = System.Label.Core_ErrorDigest_SummaryNoRecipients;
            return finish(outcome, runAt, coveredUntil);
        }

        String failure = deliver(compose(window, windowStart, recipients, cap, summary), outcome);
        if (outcome.recipients == 0) {
            return notSent(outcome, failure, lastSummary, runAt, coveredUntil);
        }
        outcome.sent = true;
        outcome.summary = String.format(
            System.Label.Core_ErrorDigest_SummarySent,
            new List<Object>{
                counted(window.total, window.capped),
                String.valueOf(outcome.recipients)
            }
        );
        return finish(outcome, runAt, runAt);
    }

    /**
     * Whether the digest carries the admin summary: a weekly digest does, unless the setting is
     * switched off. An empty setting reads as on (its default).
     */
    private static Boolean includeSummary(BarnCRM_Settings__c settings, Integer periodDays) {
        return periodDays == 7 && settings.Error_Digest_Include_Admin_Summary__c != false;
    }

    /**
     * Due when the local date has reached the covered day plus the period, or when the moment
     * is at most the tolerance away. Either is enough.
     */
    private static Boolean isDue(Datetime coveredUntil, Integer periodDays, Datetime runAt) {
        if (runAt.date() >= coveredUntil.date().addDays(periodDays)) {
            return true;
        }
        return coveredUntil.addDays(periodDays).addMinutes(-DUE_TOLERANCE_MINUTES) <= runAt;
    }

    /**
     * A run that could not send keeps its window. It writes to the Error Log only when its
     * reason differs from the last run's, so an org that blocks email gets one entry, not one a
     * day that the next digest would then try to report.
     */
    private static Outcome notSent(
        Outcome outcome,
        String reason,
        String lastSummary,
        Datetime runAt,
        Datetime coveredUntil
    ) {
        outcome.summary = String.format(
            System.Label.Core_ErrorDigest_SummaryNotSent,
            new List<Object>{ reason }
        );
        if (!outcome.summary.equals(lastSummary)) {
            ErrorLogger.logMessage(outcome.summary, LOG_CONTEXT, ErrorLogger.SEVERITY_ERROR);
        }
        return finish(outcome, runAt, coveredUntil);
    }

    /** A count as the digest says it: "2000+" when there were more than it counted. */
    private static String counted(Integer total, Boolean capped) {
        return capped ? total + '+' : String.valueOf(total);
    }

    private static Outcome finish(Outcome outcome, Datetime runAt, Datetime coveredUntil) {
        ErrorDigestWriter.recordRun(runAt, outcome.summary, coveredUntil);
        SettingsService.clearCaches();
        return outcome;
    }

    // ------------------------------------------------------------------------------ the message

    @TestVisible
    private static List<Messaging.SingleEmailMessage> compose(
        ErrorDigestSelector.Window window,
        Datetime windowStart,
        List<User> recipients,
        Integer cap,
        AdminDigestSummary.Summary summary
    ) {
        // Nothing new in the Error Log but something to report: the subject says it is the
        // admin summary rather than claiming zero new entries.
        String subject = window.total == 0
            ? System.Label.Core_AdminDigest_Subject
            : String.format(
                  System.Label.Core_ErrorDigest_Subject,
                  new List<Object>{ counted(window.total, window.capped) }
              );
        String body = body(window, windowStart, cap, summary);
        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
        for (User recipient : recipients) {
            Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
            // Addressed to the user record: internal users only, and not counted against the
            // org's daily limit on email sent to addresses (ADR-0055).
            message.setTargetObjectId(recipient.Id);
            message.setSaveAsActivity(false);
            message.setSenderDisplayName(System.Label.Core_ErrorDigest_SenderName);
            message.setSubject(subject);
            message.setPlainTextBody(body);
            messages.add(message);
        }
        return messages;
    }

    private static String body(
        ErrorDigestSelector.Window window,
        Datetime windowStart,
        Integer cap,
        AdminDigestSummary.Summary summary
    ) {
        String base = URL.getOrgDomainUrl().toExternalForm();
        if (window.total == 0) {
            List<String> only = new List<String>{
                String.format(
                    System.Label.Core_AdminDigest_NoNewErrors,
                    new List<Object>{ windowStart.format() }
                ),
                ''
            };
            only.addAll(AdminDigestSummary.lines(summary, base));
            only.add(System.Label.Core_ErrorDigest_Footer);
            return String.join(only, '\n');
        }
        List<String> lines = new List<String>{
            String.format(
                System.Label.Core_ErrorDigest_Intro,
                new List<Object>{ counted(window.total, window.capped), windowStart.format() }
            ),
            ''
        };
        if (window.capped) {
            lines.add(
                String.format(
                    System.Label.Core_ErrorDigest_Capped,
                    new List<Object>{ String.valueOf(cap) }
                )
            );
            lines.add('');
        }
        lines.add(System.Label.Core_ErrorDigest_BySource);
        lines.addAll(countLines(window.bySource));
        lines.add('');
        lines.add(System.Label.Core_ErrorDigest_BySeverity);
        lines.addAll(countLines(window.bySeverity));
        lines.add('');
        lines.add(System.Label.Core_ErrorDigest_Newest);
        for (Error_Log__c entry : window.newest) {
            lines.add(
                '  ' +
                    String.join(
                        new List<String>{
                            entry.Name,
                            orNoSource(entry.Context__c),
                            String.valueOf(entry.Severity__c)
                        },
                        ', '
                    ) +
                    ': ' +
                    base +
                    '/' +
                    entry.Id
            );
        }
        Integer unlisted = window.total - window.newest.size();
        if (unlisted > 0) {
            lines.add(
                String.format(
                    System.Label.Core_ErrorDigest_More,
                    new List<Object>{ counted(unlisted, window.capped) }
                )
            );
        }
        lines.add('');
        lines.add(
            String.format(
                System.Label.Core_ErrorDigest_ListLink,
                new List<Object>{ base + ErrorLogCountSelector.listViewUrl() }
            )
        );
        lines.add(
            String.format(System.Label.Core_ErrorDigest_StillNew, new List<Object>{ stillNew(cap) })
        );
        lines.add('');
        lines.addAll(AdminDigestSummary.lines(summary, base));
        lines.add(System.Label.Core_ErrorDigest_Footer);
        return String.join(lines, '\n');
    }

    private static String stillNew(Integer cap) {
        Integer count = ErrorLogCountSelector.countNewUpTo(cap);
        return count > cap ? counted(cap, true) : String.valueOf(count);
    }

    private static List<String> countLines(Map<String, Integer> counts) {
        List<String> lines = new List<String>();
        for (String name : counts.keySet()) {
            lines.add('  ' + orNoSource(name) + ': ' + counts.get(name));
        }
        return lines;
    }

    private static String orNoSource(String name) {
        return String.isBlank(name) ? System.Label.Core_ErrorDigest_NoSource : name;
    }

    // ------------------------------------------------------------------------------- sending

    /**
     * Hands the messages to the platform in one call, with partial success so that one refused
     * recipient does not stop the others. Sets how many were delivered on the outcome and
     * returns the first reason one was not, for the run summary.
     */
    private static String deliver(List<Messaging.SingleEmailMessage> messages, Outcome outcome) {
        if (sendFailureForTest != null) {
            return sendFailureForTest;
        }
        if (capturedMessages != null) {
            capturedMessages.addAll(messages);
            outcome.recipients = messages.size();
            return null;
        }
        String firstFailure;
        try {
            for (Messaging.SendEmailResult result : Messaging.sendEmail(messages, false)) {
                if (result.isSuccess()) {
                    outcome.recipients++;
                } else if (firstFailure == null && !result.getErrors().isEmpty()) {
                    firstFailure = result.getErrors()[0].getMessage();
                }
            }
        } catch (Exception refused) {
            // An org set to send system email only refuses the whole call.
            firstFailure = refused.getMessage();
        }
        return String.isBlank(firstFailure)
            ? System.Label.Core_ErrorDigest_UnknownFailure
            : firstFailure.left(150);
    }
}
