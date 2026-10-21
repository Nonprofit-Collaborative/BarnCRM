/**
 * Turns a failure into the sentence an administrator sees. An exception BarnCRM raised on
 * purpose carries a label-based message and is shown as it is. Anything else (a platform
 * exception such as a failed save or an empty query) is replaced by a label that says what to
 * do, so nobody sees raw exception text; the detail stays in the Error Log.
 */
public with sharing class UserErrors {
    /**
     * @param caught the failure
     * @param context where it happened, for the Error Log
     * @param log false when the caller cannot insert a record (a cacheable call)
     */
    public static AuraHandledException wrap(Exception caught, String context, Boolean log) {
        if (log != false) {
            ErrorLogger.log(caught, context);
        }
        String message = isKnown(caught) ? caught.getMessage() : Label.Core_UnexpectedError;
        if (String.isBlank(message)) {
            message = Label.Core_UnexpectedError;
        }
        AuraHandledException reported = new AuraHandledException(message);
        reported.setMessage(message);
        return reported;
    }

    /**
     * A failure raised by BarnCRM code with a message written for a person. The platform's own
     * exception types live in the System namespace.
     */
    @TestVisible
    private static Boolean isKnown(Exception caught) {
        String typeName = caught.getTypeName();
        return !typeName.startsWith('System.') &&
            !typeName.startsWith('Database.') &&
            typeName.endsWith('Exception');
    }
}
