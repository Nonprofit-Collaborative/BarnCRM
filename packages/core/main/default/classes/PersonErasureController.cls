/**
 * The Erase person action (canonical model Section 29H). Everything is decided in
 * `PersonErasure`; this class turns its refusals into messages the screen shows, and anything
 * unexpected into the generic message, logged.
 */
public with sharing class PersonErasureController {
    /** What erasing this person would change, with nothing changed. */
    @AuraEnabled
    public static PersonErasure.Result preview(Id personId) {
        try {
            return PersonErasure.preview(personId);
        } catch (Exception failed) {
            throw asUserError(failed, personId);
        }
    }

    /** Erases the person, once the typed name matches. */
    @AuraEnabled
    public static PersonErasure.Result erase(
        Id personId,
        String typedName,
        String requestReference
    ) {
        try {
            return PersonErasure.erase(personId, typedName, requestReference);
        } catch (Exception failed) {
            throw asUserError(failed, personId);
        }
    }

    private static AuraHandledException asUserError(Exception failed, Id personId) {
        String message;
        if (failed instanceof PersonErasure.ErasureException) {
            message = failed.getMessage();
        } else {
            ErrorLogger.log(failed, 'PersonErasureController', personId);
            message = Label.Core_Households_ErrorUnexpected;
        }
        AuraHandledException error = new AuraHandledException(message);
        error.setMessage(message);
        return error;
    }
}
