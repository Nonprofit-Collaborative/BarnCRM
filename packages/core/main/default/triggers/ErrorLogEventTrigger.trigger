/**
 * Writes the Error Log rows for the events `ErrorLogWriter` published.
 *
 * This is deliberately not routed through `TriggerDispatcher`: recording a failure is not an
 * automation an administrator can switch off or pause (rule R-A3), and a pause during a bulk load
 * is exactly when the entries matter most. `ErrorLogEventHandler` explains the rest.
 */
trigger ErrorLogEventTrigger on Error_Log_Event__e(after insert) {
	ErrorLogEventHandler.handle(Trigger.new);
}
