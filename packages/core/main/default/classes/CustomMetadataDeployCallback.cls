/**
 * Records how a custom metadata manager deployment ended (canonical model R-S6).
 *
 * Success writes one Setting Change, with the deployment Id, so the change is audited once it
 * has happened rather than when it was asked for, and so the page can see that it finished.
 * Failure writes an Error Log entry whose record reference is the deployment Id, with
 * Salesforce's reason in words the page shows as they are.
 *
 * Salesforce runs this in its own transaction after the deployment, so everything it needs is
 * carried on the instance. The audit row is written in system mode: it is package-owned data
 * (ADR-0021), and the transaction is not guaranteed to run as the person who saved.
 */
public with sharing class CustomMetadataDeployCallback implements Metadata.DeployCallback {
    public static final String ERROR_CONTEXT = 'Custom metadata';

    private final String rowName;
    private final String label;
    private final String oldValue;
    private final String newValue;
    private final Id requestedBy;

    public CustomMetadataDeployCallback(
        String rowName,
        String label,
        String oldValue,
        String newValue,
        Id requestedBy
    ) {
        this.rowName = rowName;
        this.label = label;
        this.oldValue = oldValue;
        this.newValue = newValue;
        this.requestedBy = requestedBy;
    }

    public void handleResult(Metadata.DeployResult result, Metadata.DeployCallbackContext context) {
        Id deploymentId = context == null ? null : context.getCallbackJobId();
        if (result != null && result.status == Metadata.DeployStatus.Succeeded) {
            Database.insert(
                new Setting_Change__c(
                    Setting_Name__c = rowName.left(255),
                    Old_Value__c = oldValue,
                    New_Value__c = newValue,
                    Changed_By__c = requestedBy,
                    Changed_At__c = System.now(),
                    Deployment_Id__c = deploymentId
                ),
                AccessLevel.SYSTEM_MODE
            );
            return;
        }
        ErrorLogger.logMessage(
            String.format(
                System.Label.Core_CmdtManager_DeployFailed,
                new List<Object>{ label, reasonOf(result) }
            ),
            ERROR_CONTEXT,
            ErrorLogger.SEVERITY_ERROR,
            deploymentId
        );
    }

    /** Salesforce's own words for each component that failed, or a plain fallback. */
    @TestVisible
    private static String reasonOf(Metadata.DeployResult result) {
        List<String> problems = new List<String>();
        if (result != null && result.details != null && result.details.componentFailures != null) {
            for (Metadata.DeployMessage failure : result.details.componentFailures) {
                if (String.isNotBlank(failure.problem)) {
                    problems.add(failure.problem);
                }
            }
        }
        if (problems.isEmpty() && result != null && String.isNotBlank(result.errorMessage)) {
            problems.add(result.errorMessage);
        }
        return problems.isEmpty()
            ? System.Label.Core_CmdtManager_DeployFailedNoReason
            : String.join(problems, ' ');
    }
}
