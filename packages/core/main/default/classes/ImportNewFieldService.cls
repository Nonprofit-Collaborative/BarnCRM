/**
 * Creates a field for an import column (C-49d, ADR "Import creates a new field through a
 * one-time org connection"). Apex cannot create a field itself, so a queued job calls the org's
 * own Metadata API through the Named Credential `Barn_Org_Connection` (the S15 design of
 * ADR-0082 A2), then gives BarnCRM's permission sets access with `FieldPermissions` rows. The
 * wizard polls `check` until the field is in describe.
 */
public with sharing class ImportNewFieldService {
    public static final String CONNECTION = 'Barn_Org_Connection';
    public static final String API_VERSION = '67.0';
    public static final String LOG_CONTEXT = 'Import: create field ';
    public static final String RUNNING = 'Running';
    public static final String CREATED = 'Created';
    public static final String FAILED = 'Failed';
    private static final String MDAPI_NS = 'http://soap.sforce.com/2006/04/metadata';
    private static final Integer NAME_LIMIT = 40;
    private static final Integer MAX_VALUES = 200;
    private static final Set<String> TYPES = new Set<String>{
        'Text',
        'LongTextArea',
        'Number',
        'Currency',
        'Percent',
        'Date',
        'DateTime',
        'Checkbox',
        'Email',
        'Phone',
        'Url',
        'Picklist'
    };
    private static final Set<String> DECIMAL_TYPES = new Set<String>{
        'Number',
        'Currency',
        'Percent'
    };
    /** Words Salesforce or SOQL treat specially; refused as a field's name to stay clear of them. */
    private static final Set<String> RESERVED = new Set<String>(
        ('id name owner type select from where and or not null true false like in order group ' +
            'by limit offset having with update delete insert merge undelete upsert object ' +
            'field system date datetime currency number trigger new old class')
            .split(' ')
    );
    /** Read and edit, or read only, through each packaged permission set. */
    private static final Map<String, Boolean> GRANTS = new Map<String, Boolean>{
        'BarnCRM_Admin' => true,
        'BarnCRM_Staff' => true,
        'BarnCRM_Read_Only' => false
    };

    @TestVisible
    private static Boolean systemPermissionOverride;
    @TestVisible
    private static Boolean connectedOverride;

    /** The field the admin asked for. `apiName` is without `__c`. */
    public class FieldRequest {
        public String objectApiName;
        public String label;
        public String apiName;
        public String type;
        public Integer length;
        public Integer scale;
        public List<String> values = new List<String>();
        public Id permissionSetId;
    }

    public class Connection {
        @AuraEnabled
        public Boolean canCreate = false;
        @AuraEnabled
        public Boolean connected = false;
    }

    public class Outcome {
        @AuraEnabled
        public String state = RUNNING;
        @AuraEnabled
        public String message;
        @AuraEnabled
        public String fieldValue;
        @AuraEnabled
        public String fieldLabel;
    }

    public class NewFieldException extends Exception {
    }

    // -------------------------------------------------------------------------------------
    // Who may, and whether the org is connected
    // -------------------------------------------------------------------------------------

    public static Boolean canCreate() {
        if (
            !FeatureManagement.checkPermission('Manage_BarnCRM_Metadata') ||
            !FeatureManagement.checkPermission('Manage_BarnCRM_Settings')
        ) {
            return false;
        }
        if (systemPermissionOverride != null) {
            return systemPermissionOverride;
        }
        List<UserPermissionAccess> access = [
            SELECT PermissionsCustomizeApplication, PermissionsModifyMetadata
            FROM UserPermissionAccess
            WITH USER_MODE
            LIMIT 1
        ];
        return !access.isEmpty() &&
            access[0].PermissionsCustomizeApplication &&
            access[0].PermissionsModifyMetadata;
    }

    public static Boolean isConnected() {
        if (connectedOverride != null) {
            return connectedOverride;
        }
        return ![
                SELECT Id
                FROM NamedCredential
                WHERE DeveloperName = :CONNECTION
                WITH SYSTEM_MODE
                LIMIT 1
            ]
            .isEmpty();
    }

    public static Connection connection() {
        Connection result = new Connection();
        result.canCreate = canCreate();
        result.connected = isConnected();
        return result;
    }

    /** Creates the Named Credential once, pointing at this org's My Domain. */
    public static Connection setUpConnection() {
        enforce();
        if (!isConnected()) {
            ConnectApi.ExternalCredentialInput credential = new ConnectApi.ExternalCredentialInput();
            credential.developerName = NamespaceUtil.qualify(CONNECTION);
            ConnectApi.NamedCredentialCalloutOptionsInput options = new ConnectApi.NamedCredentialCalloutOptionsInput();
            options.allowMergeFieldsInBody = false;
            options.allowMergeFieldsInHeader = false;
            options.generateAuthorizationHeader = false;
            ConnectApi.NamedCredentialInput input = new ConnectApi.NamedCredentialInput();
            input.developerName = CONNECTION;
            input.masterLabel = Label.Core_ImportNewField_ConnectionLabel;
            input.type = ConnectApi.NamedCredentialType.SecuredEndpoint;
            input.calloutUrl = URL.getOrgDomainUrl().toExternalForm();
            input.externalCredentials = new List<ConnectApi.ExternalCredentialInput>{ credential };
            input.calloutOptions = options;
            if (!Test.isRunningTest()) {
                ConnectApi.NamedCredentials.createNamedCredential(input);
            }
        }
        return connection();
    }

    private static void enforce() {
        if (!canCreate()) {
            throw new NewFieldException(Label.Core_ImportNewField_NoPermission);
        }
    }

    // -------------------------------------------------------------------------------------
    // Checking the request
    // -------------------------------------------------------------------------------------

    /** Everything wrong with the request, in words; empty when it can be created. */
    public static List<String> problems(FieldRequest request) {
        List<String> found = new List<String>();
        Schema.SObjectType objectType = NamespaceUtil.objectType(request.objectApiName);
        if (objectType == null || !objectType.getDescribe().isCreateable()) {
            found.add(Label.Core_ImportNewField_ObjectInvalid);
        }
        if (String.isBlank(request.label) || request.label.trim().length() > NAME_LIMIT) {
            found.add(Label.Core_ImportNewField_LabelRequired);
        }
        String name = request.apiName == null ? '' : request.apiName.trim();
        if (
            name.length() > NAME_LIMIT ||
            !Pattern.matches('[A-Za-z][A-Za-z0-9]*(_[A-Za-z0-9]+)*', name)
        ) {
            found.add(Label.Core_ImportNewField_NameInvalid);
        } else if (RESERVED.contains(name.toLowerCase())) {
            found.add(
                String.format(Label.Core_ImportNewField_NameReserved, new List<String>{ name })
            );
        } else if (
            objectType != null &&
            objectType.getDescribe().fields.getMap().containsKey((name + '__c').toLowerCase())
        ) {
            found.add(Label.Core_ImportNewField_NameTaken);
        }
        if (!TYPES.contains(request.type)) {
            found.add(Label.Core_ImportNewField_TypeInvalid);
        } else if (
            request.type == 'Text' &&
            (request.length == null ||
            request.length < 1 ||
            request.length > 255)
        ) {
            found.add(Label.Core_ImportNewField_LengthInvalid);
        } else if (
            DECIMAL_TYPES.contains(request.type) &&
            (request.scale == null ||
            request.scale < 0 ||
            request.scale > 8)
        ) {
            found.add(Label.Core_ImportNewField_ScaleInvalid);
        } else if (request.type == 'Picklist' && !validValues(request.values)) {
            found.add(Label.Core_ImportNewField_PicklistInvalid);
        }
        return found;
    }

    private static Boolean validValues(List<String> values) {
        if (values == null || values.isEmpty() || values.size() > MAX_VALUES) {
            return false;
        }
        Set<String> seen = new Set<String>();
        for (String value : values) {
            if (String.isBlank(value) || value.length() > 255 || !seen.add(value.toLowerCase())) {
                return false;
            }
        }
        return true;
    }

    // -------------------------------------------------------------------------------------
    // Creating the field
    // -------------------------------------------------------------------------------------

    /** Checks the request and queues the job; returns the job's Id for `check`. */
    public static Id start(FieldRequest request) {
        enforce();
        if (!isConnected()) {
            throw new NewFieldException(Label.Core_ImportNewField_NotConnected);
        }
        List<String> found = problems(request);
        if (!found.isEmpty()) {
            throw new NewFieldException(String.join(found, ' '));
        }
        request.objectApiName = NamespaceUtil.objectType(request.objectApiName)
            .getDescribe()
            .getName();
        return System.enqueueJob(new CreateFieldJob(request));
    }

    public with sharing class CreateFieldJob implements Queueable, Database.AllowsCallouts {
        private final FieldRequest request;

        public CreateFieldJob(FieldRequest request) {
            this.request = request;
        }

        public void execute(QueueableContext queued) {
            String logContext = LOG_CONTEXT + queued.getJobId();
            String failure;
            try {
                failure = create(request, UserInfo.getSessionId());
            } catch (Exception e) {
                ErrorLogger.logWithMessage(
                    e,
                    logContext,
                    String.format(
                        Label.Core_ImportNewField_ConnectionRefused,
                        new List<String>{ e.getMessage() }
                    )
                );
                return;
            }
            if (failure != null) {
                ErrorLogger.logMessage(failure, logContext, ErrorLogger.SEVERITY_ERROR);
                return;
            }
            grantAccess(
                request.objectApiName,
                request.apiName + '__c',
                request.permissionSetId,
                logContext
            );
        }
    }

    /** Calls createMetadata; returns null on success, else the plain reason. */
    @TestVisible
    private static String create(FieldRequest request, String sessionId) {
        HttpRequest call = new HttpRequest();
        call.setEndpoint('callout:' + CONNECTION + '/services/Soap/m/' + API_VERSION);
        call.setMethod('POST');
        call.setHeader('Content-Type', 'text/xml; charset=UTF-8');
        call.setHeader('SOAPAction', '""');
        call.setTimeout(120000);
        call.setBody(envelope(request, sessionId));
        HttpResponse response = new Http().send(call);
        Dom.Document document = new Dom.Document();
        document.load(response.getBody());
        Dom.XmlNode root = document.getRootElement();
        List<String> faults = texts(root, 'faultstring');
        if (!faults.isEmpty()) {
            throw new NewFieldException(faults[0]);
        }
        List<String> success = texts(root, 'success');
        if (!success.isEmpty() && success[0] == 'true') {
            return null;
        }
        List<String> messages = texts(root, 'message');
        return String.format(
            Label.Core_ImportNewField_Refused,
            new List<String>{
                messages.isEmpty() ? response.getStatus() : String.join(messages, ' ')
            }
        );
    }

    @TestVisible
    private static String envelope(FieldRequest request, String sessionId) {
        return '<?xml version="1.0" encoding="UTF-8"?><soapenv:Envelope ' +
            'xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" ' +
            'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:met="' +
            MDAPI_NS +
            '"><soapenv:Header><met:SessionHeader><met:sessionId>' +
            String.valueOf(sessionId).escapeXml() +
            '</met:sessionId></met:SessionHeader></soapenv:Header><soapenv:Body>' +
            '<met:createMetadata><met:metadata xsi:type="met:CustomField">' +
            fieldXml(request) +
            '</met:metadata></met:createMetadata></soapenv:Body></soapenv:Envelope>';
    }

    /** The CustomField's elements, in the WSDL's sequence order. */
    @TestVisible
    private static String fieldXml(FieldRequest request) {
        String type = request.type;
        String xml = element('fullName', request.objectApiName + '.' + request.apiName + '__c');
        if (type == 'Checkbox') {
            xml += element('defaultValue', 'false');
        }
        xml += element('label', request.label.trim());
        if (type == 'Text') {
            xml += element('length', String.valueOf(request.length));
        } else if (type == 'LongTextArea') {
            xml += element('length', '32768');
        }
        if (DECIMAL_TYPES.contains(type)) {
            xml += element('precision', '18') + element('scale', String.valueOf(request.scale));
        }
        xml += element('type', type);
        if (type == 'Picklist') {
            String values = element('sorted', 'false');
            for (String value : request.values) {
                values +=
                    '<met:value>' +
                    element('fullName', value) +
                    element('default', 'false') +
                    element('label', value) +
                    '</met:value>';
            }
            xml +=
                '<met:valueSet>' +
                element('restricted', 'false') +
                '<met:valueSetDefinition>' +
                values +
                '</met:valueSetDefinition></met:valueSet>';
        }
        if (type == 'LongTextArea') {
            xml += element('visibleLines', '3');
        }
        return xml;
    }

    private static String element(String name, String value) {
        return '<met:' + name + '>' + value.escapeXml() + '</met:' + name + '>';
    }

    private static List<String> texts(Dom.XmlNode node, String localName) {
        List<String> found = new List<String>();
        if (node.getNodeType() == Dom.XmlNodeType.ELEMENT) {
            if (node.getName() == localName) {
                found.add(node.getText());
            }
            for (Dom.XmlNode child : node.getChildElements()) {
                found.addAll(texts(child, localName));
            }
        }
        return found;
    }

    // -------------------------------------------------------------------------------------
    // Access
    // -------------------------------------------------------------------------------------

    /**
     * Gives read and edit (read only for BarnCRM Read Only) through the packaged permission sets
     * and the chosen one. Updates a row that exists, so running it twice is harmless. A
     * permission set that cannot take the row (no object read) is logged and skipped. System
     * mode: the running user already holds Modify Metadata, which can deploy the same change.
     */
    public static void grantAccess(
        String objectApiName,
        String fieldName,
        Id chosenId,
        String logContext
    ) {
        String ns = NamespaceUtil.prefix().removeEnd('__');
        Map<Id, Boolean> editById = new Map<Id, Boolean>();
        Map<Id, String> labelById = new Map<Id, String>();
        for (PermissionSet each : [
            SELECT Id, Name, Label
            FROM PermissionSet
            WHERE
                (Name IN :GRANTS.keySet()
                AND NamespacePrefix = :(String.isBlank(ns) ? null : ns))
                OR Id = :chosenId
            WITH SYSTEM_MODE
        ]) {
            editById.put(each.Id, each.Id == chosenId || GRANTS.get(each.Name) == true);
            labelById.put(each.Id, each.Label);
        }
        String field = objectApiName + '.' + fieldName;
        Map<Id, FieldPermissions> byParent = new Map<Id, FieldPermissions>();
        for (FieldPermissions existing : [
            SELECT Id, ParentId, PermissionsRead, PermissionsEdit
            FROM FieldPermissions
            WHERE Field = :field AND ParentId IN :editById.keySet()
            WITH SYSTEM_MODE
        ]) {
            byParent.put(existing.ParentId, existing);
        }
        List<FieldPermissions> added = new List<FieldPermissions>();
        List<FieldPermissions> changed = new List<FieldPermissions>();
        for (Id parentId : editById.keySet()) {
            FieldPermissions row = byParent.containsKey(parentId)
                ? byParent.get(parentId)
                : new FieldPermissions(
                      ParentId = parentId,
                      SobjectType = objectApiName,
                      Field = field
                  );
            row.PermissionsRead = true;
            row.PermissionsEdit = row.PermissionsEdit == true || editById.get(parentId);
            (row.Id == null ? added : changed).add(row);
        }
        List<String> skipped = new List<String>();
        List<FieldPermissions> rows = new List<FieldPermissions>(added);
        rows.addAll(changed);
        List<Database.SaveResult> results = Database.insert(added, false, AccessLevel.SYSTEM_MODE);
        results.addAll(Database.update(changed, false, AccessLevel.SYSTEM_MODE));
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                skipped.add(
                    String.format(
                        Label.Core_ImportNewField_AccessSkipped,
                        new List<String>{
                            field,
                            labelById.get(rows[i].ParentId),
                            results[i].getErrors()[0].getMessage()
                        }
                    )
                );
            }
        }
        if (!skipped.isEmpty()) {
            ErrorLogger.logMessages(skipped, logContext, ErrorLogger.SEVERITY_WARNING);
        }
    }

    // -------------------------------------------------------------------------------------
    // Polling
    // -------------------------------------------------------------------------------------

    /** Where the job is: still running, created (with the field as the picker shows it), or failed. */
    public static Outcome check(Id jobId, String objectApiName, String apiName) {
        enforce();
        Outcome result = new Outcome();
        List<AsyncApexJob> jobs = [
            SELECT Status
            FROM AsyncApexJob
            WHERE Id = :jobId AND CreatedById = :UserInfo.getUserId()
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (jobs.isEmpty() || jobs[0].Status == 'Failed' || jobs[0].Status == 'Aborted') {
            result.state = FAILED;
            result.message = Label.Core_ImportNewField_JobFailed;
            return result;
        }
        if (jobs[0].Status != 'Completed') {
            return result;
        }
        result = find(objectApiName, apiName);
        if (result.state == CREATED) {
            return result;
        }
        // createMetadata is synchronous, so a finished job whose field is not in describe failed.
        // The job's Error Log entry arrives through ErrorLogger's event, possibly after this poll;
        // until it does, the generic message stands in for it.
        result.state = FAILED;
        result.message = Label.Core_ImportNewField_JobFailed;
        String logContext = LOG_CONTEXT + jobId;
        List<Error_Log__c> logged = [
            SELECT Message__c
            FROM Error_Log__c
            WHERE Context__c = :logContext AND Severity__c = :ErrorLogger.SEVERITY_ERROR
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (!logged.isEmpty()) {
            result.message = logged[0].Message__c;
        }
        return result;
    }

    /**
     * The field once it is in describe (Created), else Running. Refresh Fields uses it after the
     * admin creates the field in Setup; the wizard's own field lists are cached, so it adds this one.
     */
    public static Outcome find(String objectApiName, String apiName) {
        enforce();
        Outcome result = new Outcome();
        Schema.SObjectType objectType = NamespaceUtil.objectType(objectApiName);
        Schema.SObjectField field = objectType == null || String.isBlank(apiName)
            ? null
            : objectType.getDescribe(SObjectDescribeOptions.FULL)
                  .fields.getMap()
                  .get((apiName.removeEndIgnoreCase('__c') + '__c').toLowerCase());
        if (field != null) {
            Schema.DescribeFieldResult described = field.getDescribe();
            result.state = CREATED;
            result.fieldValue = described.getName();
            result.fieldLabel = described.getLabel();
        }
        return result;
    }
}
