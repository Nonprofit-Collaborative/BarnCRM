/**
 * Writes the Error Log row from the event `ErrorLogWriter` published.
 *
 * ADR-0021 (system mode writes for package owned data) is the authority for this class and
 * names it as one of its writers. This is the write that must happen whoever was working when
 * the failure happened, including a user with no create access on the Error Log. Running in
 * system mode ensures the entry is written even when the running user would otherwise lack
 * permission to create it. It runs in the platform's own subscriber transaction, reads nothing,
 * and returns nothing.
 *
 * It does not go through `TriggerDispatcher`. Recording a failure is not an automation an
 * administrator can switch off or pause: rule R-A3 says turning an automation off never suppresses
 * error logging, and a pause during a bulk load is exactly when the entries matter most.
 *
 * It never throws. A failure here would retry the event and could loop.
 */
public without sharing class ErrorLogEventHandler {
    private static final String DEFAULT_SEVERITY = 'Error';
    private static final Set<String> SEVERITIES = new Set<String>{
        'Info',
        'Warning',
        'Error',
        'Critical'
    };

    public static void handle(List<Error_Log_Event__e> events) {
        if (events == null || events.isEmpty()) {
            return;
        }
        List<Error_Log__c> entries = new List<Error_Log__c>();
        for (Error_Log_Event__e event : events) {
            entries.add(
                new Error_Log__c(
                    Timestamp__c = event.CreatedDate == null ? System.now() : event.CreatedDate,
                    User__c = event.User_Id__c,
                    Context__c = event.Context__c,
                    Message__c = event.Message__c,
                    Technical_Detail__c = event.Technical_Detail__c,
                    Record_Reference__c = event.Record_Reference__c,
                    Object_Name__c = event.Object_Name__c,
                    Severity__c = SEVERITIES.contains(event.Severity__c)
                        ? event.Severity__c
                        : DEFAULT_SEVERITY,
                    Status__c = 'New'
                )
            );
        }
        try {
            Database.insert(entries, false, AccessLevel.SYSTEM_MODE);
        } catch (Exception failedToLog) {
            // Deliberate last resort: this is the write that turns an Error Log event into the
            // Error_Log__c row, so when it itself fails there is nowhere left to record the
            // failure but the debug log. Kept intentionally (PMD AvoidDebugStatements finding
            // accepted, not suppressed).
            System.debug(
                LoggingLevel.ERROR,
                'BarnCRM could not write an Error Log record from an event: ' +
                failedToLog.getMessage()
            );
        }
    }
}
