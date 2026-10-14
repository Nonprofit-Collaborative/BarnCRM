/**
 * The exception an @AuraEnabled method throws so the screen shows the message itself rather
 * than the platform's generic "script thrown" text.
 */
public with sharing class ControllerErrors {
    public static AuraHandledException messageFor(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }
}
