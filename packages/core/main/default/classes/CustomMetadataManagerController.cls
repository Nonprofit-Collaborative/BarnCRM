/**
 * The custom metadata manager's Apex surface. Every method, reading included, checks
 * `Manage_BarnCRM_Metadata` first: the console shows the page only to holders, and saving
 * changes the org's metadata (ADR-0085,
 * 0085-custom-metadata-manager-edits-only-types-read-directly.md).
 */
public with sharing class CustomMetadataManagerController {
    private static final String PERMISSION = 'Manage_BarnCRM_Metadata';

    @TestVisible
    private static final String PENDING = 'Pending';
    @TestVisible
    private static final String SUCCEEDED = 'Succeeded';
    @TestVisible
    private static final String FAILED = 'Failed';

    /** How a deployment the page started has ended so far. */
    public class Outcome {
        @AuraEnabled
        public String status;
        @AuraEnabled
        public String message;
    }

    @AuraEnabled
    public static List<CustomMetadataManagerService.TypeView> getTypes() {
        requirePermission();
        try {
            return CustomMetadataManagerService.getTypes();
        } catch (Exception e) {
            throw logged(e, System.Label.Core_CmdtManager_LoadError);
        }
    }

    /** Adds or changes a row; returns the deployment Id to pass to getOutcome. */
    @AuraEnabled
    public static String saveRow(String typeName, CustomMetadataManagerService.RowInput input) {
        requirePermission();
        try {
            return CustomMetadataManagerService.save(typeName, input);
        } catch (Exception e) {
            throw logged(e, System.Label.Core_CmdtManager_SaveError);
        }
    }

    @AuraEnabled
    public static String setArchived(String typeName, String developerName, Boolean archived) {
        requirePermission();
        try {
            return CustomMetadataManagerService.setArchived(typeName, developerName, archived);
        } catch (Exception e) {
            throw logged(e, System.Label.Core_CmdtManager_SaveError);
        }
    }

    @AuraEnabled
    public static Outcome getOutcome(String deploymentId) {
        requirePermission();
        Outcome outcome = new Outcome();
        outcome.status = PENDING;
        Id jobId;
        try {
            jobId = Id.valueOf(deploymentId);
        } catch (Exception notAnId) {
            throw asAuraException(System.Label.Core_CmdtManager_LoadError);
        }
        try {
            if (CustomMetadataManagerSelector.hasSucceeded(jobId)) {
                outcome.status = SUCCEEDED;
                return outcome;
            }
            String failure = CustomMetadataManagerSelector.failureMessage(jobId);
            if (failure != null) {
                outcome.status = FAILED;
                outcome.message = failure;
            }
            return outcome;
        } catch (Exception e) {
            throw logged(e, System.Label.Core_CmdtManager_LoadError);
        }
    }

    /** A refusal the service explains is shown as it is; anything else is logged first. */
    private static AuraHandledException logged(Exception e, String fallback) {
        if (e instanceof CustomMetadataManagerService.CustomMetadataManagerException) {
            return asAuraException(e.getMessage());
        }
        ErrorLogger.log(e, CustomMetadataDeployCallback.ERROR_CONTEXT);
        return asAuraException(fallback);
    }

    private static void requirePermission() {
        if (!FeatureManagement.checkPermission(PERMISSION)) {
            throw asAuraException(System.Label.Core_CmdtManager_PermissionRequired);
        }
    }

    private static AuraHandledException asAuraException(String message) {
        AuraHandledException error = new AuraHandledException(message);
        error.setMessage(message);
        return error;
    }
}
