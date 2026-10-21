/**
 * Turns a failure into the sentence a person sees. A BarnCRM exception already carries a
 * label-based message and is shown as it is. A failed save shows the first message the
 * platform gives for the row (a validation rule's own wording, for example). Anything else
 * is replaced by a label that says what to do, so nobody sees raw exception text. The caller
 * logs the failure to the Error Log first.
 */
public with sharing class GivingErrors {
    /**
     * @param caught the failure
     * @param unexpectedMessage the label shown for an unexpected failure
     */
    public static AuraHandledException userError(Exception caught, String unexpectedMessage) {
        String message = unexpectedMessage;
        if (isKnown(caught)) {
            message = caught.getMessage();
        } else if (caught instanceof DmlException && caught.getNumDml() > 0) {
            message = caught.getDmlMessage(0);
        }
        if (String.isBlank(message)) {
            message = unexpectedMessage;
        }
        AuraHandledException surfaced = new AuraHandledException(message);
        surfaced.setMessage(message);
        return surfaced;
    }

    /**
     * A failure raised by BarnCRM code on purpose, with a message written for a person. The
     * platform's own exception types live in the System namespace.
     */
    @TestVisible
    private static Boolean isKnown(Exception caught) {
        String typeName = caught.getTypeName();
        return !typeName.startsWith('System.') &&
            !typeName.startsWith('Database.') &&
            typeName.endsWith('Exception');
    }
}
