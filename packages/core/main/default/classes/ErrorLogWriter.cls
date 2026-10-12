/**
 * Gets Error Log entries out of the failing transaction and into the org.
 *
 * ADR-0021 (system mode writes for package owned data) is the authority for this class and
 * names it as one of its writers. An error must be recorded even when the running user has no
 * create access on the Error Log object. The failures that matter most are the ones a person hits
 * because something is missing from their access, and those are exactly the ones a user mode write
 * would drop on the floor. Running in system mode is what ensures the entry survives to tell the
 * administrator what went wrong.
 *
 * WHY THIS IS NOT A SIMPLE INSERT. Almost every failure worth recording ends in a rollback: the
 * dispatcher calls addError or rethrows, the save is refused, and everything written in that
 * transaction is undone. An ordinary insert here would be undone with it, so the entry that says
 * what went wrong would disappear exactly when Maria needs it (canonical model rule R-E4). So the
 * entry is published as an `Error_Log_Event__e` platform event with publish behavior Publish
 * Immediately, which the platform delivers whether or not the transaction commits, and
 * `ErrorLogEventHandler` writes the row from the event.
 *
 * The direct insert survives only as the fallback for when publishing itself fails, for example
 * for a running user with no create access on the event. It is better to lose the entry to a
 * rollback than to lose it altogether. Publishing is governed by Create on the event, so all three
 * packaged permission sets grant Read and Create on `Error_Log_Event__e`, Nonprofit Read Only
 * included; for a user holding none of them the fallback runs and the entry survives only when the
 * transaction commits.
 *
 * No user input reaches this class unescaped: callers pass a message from a Custom Label or an
 * exception's own message, and both the event and the record are written with ordinary typed DML.
 * There is no dynamic SOQL and no dynamic DML anywhere in this file.
 *
 * It never throws (rule R-E2). A failure to log is swallowed rather than masking the original
 * failure, which the caller is usually in the middle of reporting to the user.
 */
public without sharing class ErrorLogWriter {
    public static void write(List<Error_Log__c> entries) {
        if (entries == null || entries.isEmpty()) {
            return;
        }
        if (publish(entries)) {
            return;
        }
        writeDirectly(entries);
    }

    /**
     * Publishes one event per entry. Returns false if anything at all went wrong, so that the
     * caller can fall back to the direct write.
     */
    private static Boolean publish(List<Error_Log__c> entries) {
        try {
            List<Error_Log_Event__e> events = new List<Error_Log_Event__e>();
            for (Error_Log__c entry : entries) {
                events.add(
                    new Error_Log_Event__e(
                        Message__c = entry.Message__c,
                        Technical_Detail__c = entry.Technical_Detail__c,
                        Context__c = entry.Context__c,
                        Record_Reference__c = entry.Record_Reference__c,
                        Object_Name__c = entry.Object_Name__c,
                        Severity__c = entry.Severity__c,
                        User_Id__c = entry.User__c
                    )
                );
            }
            for (Database.SaveResult published : EventBus.publish(events)) {
                if (!published.isSuccess()) {
                    return false;
                }
            }
            return true;
        } catch (Exception cannotPublish) {
            // Deliberate: publish failing is the expected trigger for the writeDirectly
            // fallback below, so this is a normal branch rather than a last resort, but there
            // is still nowhere but the debug log to note why the fallback fired. Kept
            // intentionally (PMD AvoidDebugStatements finding accepted, not suppressed).
            System.debug(
                LoggingLevel.ERROR,
                'BarnCRM could not publish an Error Log event: ' + cannotPublish.getMessage()
            );
            return false;
        }
    }

    /**
     * The fallback. Test visible because the tests that prove the system mode write is still a
     * system mode write have to call it without the platform event in the way.
     */
    @TestVisible
    private static void writeDirectly(List<Error_Log__c> entries) {
        if (entries == null || entries.isEmpty()) {
            return;
        }
        try {
            Database.insert(entries, false, AccessLevel.SYSTEM_MODE);
        } catch (Exception failedToLog) {
            // Deliberate last resort: both the platform event publish and this direct insert
            // have now failed, so there is no remaining path to record the entry anywhere but
            // the debug log. Kept intentionally (PMD AvoidDebugStatements finding accepted,
            // not suppressed).
            System.debug(
                LoggingLevel.ERROR,
                'BarnCRM could not write an Error Log record: ' + failedToLog.getMessage()
            );
        }
    }
}
