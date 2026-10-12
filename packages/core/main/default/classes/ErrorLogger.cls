/**
 * Records a caught failure where an administrator can read it (rule R-E1).
 *
 * Two texts are kept apart on purpose. `Message__c` is what Maria reads: what went wrong and
 * what to do about it. `Technical_Detail__c` is what she forwards to a support contact: the
 * exception type, its message, and the stack trace.
 *
 * Every method takes a list or is called once per failure, and every path writes with a single
 * insert, so logging 200 failures in one transaction costs one statement.
 *
 * Nothing here throws (rule R-E2).
 */
@NamespaceAccessible
public with sharing class ErrorLogger {
    public static final String SEVERITY_INFO = 'Info';
    @NamespaceAccessible
    public static final String SEVERITY_WARNING = 'Warning';
    public static final String SEVERITY_ERROR = 'Error';
    public static final String SEVERITY_CRITICAL = 'Critical';
    public static final String STATUS_NEW = 'New';
    public static final String STATUS_ACKNOWLEDGED = 'Acknowledged';
    public static final String STATUS_RESOLVED = 'Resolved';
    public static final String STATUS_IGNORED = 'Ignored';

    private static final Integer MAX_LONG_TEXT = 32000;
    private static final Integer MAX_CONTEXT = 255;
    private static final Integer MAX_OBJECT_NAME = 80;
    private static final Set<String> SEVERITIES = new Set<String>{
        SEVERITY_INFO,
        SEVERITY_WARNING,
        SEVERITY_ERROR,
        SEVERITY_CRITICAL
    };

    @NamespaceAccessible
    public static void log(Exception thrown, String context) {
        log(thrown, context, null);
    }

    @NamespaceAccessible
    public static void log(Exception thrown, String context, Id recordId) {
        if (thrown == null) {
            return;
        }
        log(new List<Exception>{ thrown }, context, recordId);
    }

    @NamespaceAccessible
    public static void log(List<Exception> thrown, String context) {
        log(thrown, context, null);
    }

    @NamespaceAccessible
    public static void log(List<Exception> thrown, String context, Id recordId) {
        if (thrown == null || thrown.isEmpty()) {
            return;
        }
        List<Error_Log__c> entries = new List<Error_Log__c>();
        try {
            for (Exception failure : thrown) {
                if (failure == null) {
                    continue;
                }
                entries.add(
                    buildEntry(
                        friendlyMessage(failure),
                        technicalDetail(failure),
                        context,
                        SEVERITY_ERROR,
                        recordId
                    )
                );
            }
        } catch (Exception failedToBuild) {
            // Deliberate last resort: this catch runs before any Error_Log__c row exists to
            // write, so there is no queue-able entry left to hand to ErrorLogWriter. The debug
            // log is the only place this failure can go. Kept intentionally (PMD
            // AvoidDebugStatements finding accepted, not suppressed).
            System.debug(
                LoggingLevel.ERROR,
                'BarnCRM could not build an Error Log record: ' + failedToBuild.getMessage()
            );
        }
        ErrorLogWriter.write(entries);
    }

    @NamespaceAccessible
    public static void logMessage(String message, String context, String severity) {
        logMessage(message, context, severity, null);
    }

    @NamespaceAccessible
    public static void logMessage(String message, String context, String severity, Id recordId) {
        if (String.isBlank(message)) {
            return;
        }
        ErrorLogWriter.write(
            new List<Error_Log__c>{ buildEntry(message, null, context, severity, recordId) }
        );
    }

    @NamespaceAccessible
    public static void logMessages(List<String> messages, String context, String severity) {
        if (messages == null || messages.isEmpty()) {
            return;
        }
        List<Error_Log__c> entries = new List<Error_Log__c>();
        for (String message : messages) {
            if (String.isNotBlank(message)) {
                entries.add(buildEntry(message, null, context, severity, null));
            }
        }
        ErrorLogWriter.write(entries);
    }

    /**
     * Many messages, each about its own record, in one statement. `recordIds` runs alongside
     * `messages`: entry i is about record i, and a null, or a list shorter than the messages,
     * leaves that entry without a record.
     */
    @NamespaceAccessible
    public static void logMessages(
        List<String> messages,
        List<Id> recordIds,
        String context,
        String severity
    ) {
        if (messages == null || messages.isEmpty()) {
            return;
        }
        List<Error_Log__c> entries = new List<Error_Log__c>();
        for (Integer i = 0; i < messages.size(); i++) {
            if (String.isBlank(messages[i])) {
                continue;
            }
            Id recordId = recordIds == null || i >= recordIds.size() ? null : recordIds[i];
            entries.add(buildEntry(messages[i], null, context, severity, recordId));
        }
        ErrorLogWriter.write(entries);
    }

    private static Error_Log__c buildEntry(
        String message,
        String detail,
        String context,
        String severity,
        Id recordId
    ) {
        Error_Log__c entry = new Error_Log__c(
            Timestamp__c = System.now(),
            User__c = UserInfo.getUserId(),
            Context__c = truncate(String.isBlank(context) ? 'BarnCRM' : context, MAX_CONTEXT),
            Message__c = truncate(message, MAX_LONG_TEXT),
            Technical_Detail__c = truncate(detail, MAX_LONG_TEXT),
            Severity__c = SEVERITIES.contains(severity) ? severity : SEVERITY_ERROR,
            Status__c = STATUS_NEW
        );
        if (recordId != null) {
            entry.Record_Reference__c = String.valueOf(recordId);
            entry.Object_Name__c = truncate(
                String.valueOf(recordId.getSObjectType()),
                MAX_OBJECT_NAME
            );
        }
        return entry;
    }

    /**
     * What Maria reads. Deliberately the label and nothing else: an exception's own message is
     * written for a developer ("Attempt to de-reference a null object") and belongs in the
     * technical detail, which is the field the admin guide tells her to forward.
     */
    private static String friendlyMessage(Exception thrown) {
        return Label.Core_ErrorLog_UnexpectedFailure;
    }

    private static String technicalDetail(Exception thrown) {
        String detail =
            thrown.getTypeName() +
            ': ' +
            thrown.getMessage() +
            '\n' +
            thrown.getStackTraceString();
        Exception cause = thrown.getCause();
        if (cause != null) {
            detail += '\nCaused by ' + cause.getTypeName() + ': ' + cause.getMessage();
        }
        return detail;
    }

    private static String truncate(String value, Integer maxLength) {
        if (String.isBlank(value)) {
            return value;
        }
        return value.length() > maxLength ? value.substring(0, maxLength) : value;
    }
}
