/**
 * The import's Create New Field dialog and the connection panel on BarnCRM Settings (C-49d).
 * Every method checks the caller may create fields; ImportNewFieldService does the work.
 */
public with sharing class ImportNewFieldController {
    public class Choice {
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String value;

        public Choice(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    /** Whether the running user may create fields, and whether the org is connected. */
    @AuraEnabled
    public static ImportNewFieldService.Connection getConnection() {
        try {
            return ImportNewFieldService.connection();
        } catch (Exception e) {
            throw UserErrors.wrap(e, 'ImportNewFieldController.getConnection', true);
        }
    }

    @AuraEnabled
    public static ImportNewFieldService.Connection setUpConnection() {
        try {
            return ImportNewFieldService.setUpConnection();
        } catch (Exception e) {
            throw UserErrors.wrap(e, 'ImportNewFieldController.setUpConnection', true);
        }
    }

    /** The org's own permission sets, for the optional extra grant. */
    @AuraEnabled
    public static List<Choice> getPermissionSets() {
        try {
            requireCreate();
            List<Choice> choices = new List<Choice>();
            for (PermissionSet each : [
                SELECT Id, Label
                FROM PermissionSet
                WHERE
                    IsOwnedByProfile = FALSE
                    AND IsCustom = TRUE
                    AND NamespacePrefix = NULL
                    AND PermissionSetGroupId = NULL
                WITH USER_MODE
                ORDER BY Label
                LIMIT 500
            ]) {
                choices.add(new Choice(each.Label, each.Id));
            }
            return choices;
        } catch (Exception e) {
            throw UserErrors.wrap(e, 'ImportNewFieldController.getPermissionSets', true);
        }
    }

    /** Queues the field's creation; returns the job Id the dialog polls with `checkField`. */
    @AuraEnabled
    public static Id createField(String requestJson) {
        try {
            return ImportNewFieldService.start(
                (ImportNewFieldService.FieldRequest) JSON.deserialize(
                    requestJson,
                    ImportNewFieldService.FieldRequest.class
                )
            );
        } catch (Exception e) {
            throw UserErrors.wrap(e, 'ImportNewFieldController.createField', true);
        }
    }

    @AuraEnabled
    public static ImportNewFieldService.Outcome checkField(
        Id jobId,
        String objectApiName,
        String apiName
    ) {
        try {
            return ImportNewFieldService.check(jobId, objectApiName, apiName);
        } catch (Exception e) {
            throw UserErrors.wrap(e, 'ImportNewFieldController.checkField', true);
        }
    }

    private static void requireCreate() {
        if (!ImportNewFieldService.canCreate()) {
            throw new ImportNewFieldService.NewFieldException(
                Label.Core_ImportNewField_NoPermission
            );
        }
    }
}
