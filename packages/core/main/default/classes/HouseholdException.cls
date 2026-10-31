/**
 * A household problem a person can act on. Its message is always a custom label, so that
 * what the admin reads in the Error Log is the same sentence the screen shows.
 */
public with sharing class HouseholdException extends Exception {
    /**
     * What a household screen is told. A HouseholdException already says in plain words what
     * went wrong and what to do, so its message goes through as it is. Anything else is a
     * platform failure whose wording is for an administrator reading the Error Log, not for
     * the person at the screen: the whole exception is logged and the screen gets the
     * generic message.
     */
    public static AuraHandledException forScreen(Exception e, String context, Id recordId) {
        return UserErrors.wrap(
            e,
            e instanceof HouseholdException,
            context,
            recordId,
            Label.Core_Households_ErrorUnexpected
        );
    }
}
