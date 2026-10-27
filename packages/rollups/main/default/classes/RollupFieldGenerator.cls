/**
 * Writes the definition of a field for a rollup to fill (Rollup Builder ease of use U8,
 * ADR-0136). Step 1 of the Builder used to say "create it in Setup and come back". Apex cannot
 * create a field without a Metadata API deploy, which BarnCRM does not run on its own (as with
 * the generated instant-total triggers, ADR-0138), so this class writes the field instead:
 *
 * - the exact Setup steps, with the type, label and field name to enter;
 * - the field's source (`objects/<Object>/fields/<Field>.field-meta.xml`) to copy;
 * - a Metadata API package (`package.xml` and `objects/<Object>.object`) to download and deploy
 *   with the Salesforce CLI.
 *
 * Nothing is created or saved. The administrator creates the field, clicks Refresh Fields, and
 * chooses it.
 */
public with sharing class RollupFieldGenerator {
    private static final String API_VERSION = '67.0';
    private static final String METADATA_NAMESPACE = 'http://soap.sforce.com/2006/04/metadata';
    /** The longest field name Salesforce takes, without `__c`. */
    private static final Integer NAME_LENGTH = 40;

    /** The field types a rollup can fill, as Setup names them. */
    @TestVisible
    private static final Map<String, String> KINDS = new Map<String, String>{
        'NUMBER' => Label.Core_RollupEase_KindNumber,
        'CURRENCY' => Label.Core_RollupEase_KindCurrency,
        'DATE' => Label.Core_RollupEase_KindDate,
        'DATETIME' => Label.Core_RollupEase_KindDateTime,
        'TEXT' => Label.Core_RollupEase_KindText,
        'LONGTEXT' => Label.Core_RollupEase_KindLongText,
        'CHECKBOX' => Label.Core_RollupEase_KindCheckbox
    };

    /** What the Create a Field panel shows. */
    public class GeneratedField {
        @AuraEnabled
        public String apiName { get; set; }
        @AuraEnabled
        public List<String> steps { get; set; }
        /** The field's source, as `sf project` keeps it. */
        @AuraEnabled
        public String fieldXml { get; set; }
        @AuraEnabled
        public String fieldPath { get; set; }
        /** Base64 Metadata API zip: package.xml and the object with the field. */
        @AuraEnabled
        public String deployPackage { get; set; }
        @AuraEnabled
        public String fileName { get; set; }
    }

    /**
     * Writes a field for a rollup to fill. Refused when the object is not one a rollup can fill,
     * the label is blank or too long, the type is not one a rollup fills, or the object already
     * has a field of that name.
     *
     * @param objectApiName the object that shows the total
     * @param fieldLabel the field's label, as the administrator typed it
     * @param kind one of the keys of `KINDS`
     */
    @AuraEnabled
    public static GeneratedField generate(String objectApiName, String fieldLabel, String kind) {
        try {
            if (!FeatureManagement.checkPermission('Manage_BarnCRM_Settings')) {
                throw new RollupService.RollupServiceException(
                    Label.Core_Rollups_ErrorNoPermission
                );
            }
            Schema.SObjectType targetType = String.isBlank(objectApiName)
                ? null
                : SettingsService.typeByName(objectApiName);
            String trimmed = fieldLabel == null ? '' : fieldLabel.trim();
            if (targetType == null || String.isBlank(trimmed) || trimmed.length() > NAME_LENGTH) {
                throw new RollupService.RollupServiceException(
                    Label.Core_RollupEase_FieldLabelProblem
                );
            }
            if (String.isBlank(kind) || !KINDS.containsKey(kind)) {
                throw new RollupService.RollupServiceException(
                    Label.Core_RollupEase_FieldKindProblem
                );
            }
            Schema.DescribeSObjectResult described = targetType.getDescribe(
                SObjectDescribeOptions.DEFERRED
            );
            String name = nameFor(trimmed);
            if (String.isBlank(name)) {
                throw new RollupService.RollupServiceException(
                    Label.Core_RollupEase_FieldLabelProblem
                );
            }
            String apiName = name + '__c';
            if (described.fields.getMap().containsKey(apiName.toLowerCase())) {
                throw new RollupService.RollupServiceException(
                    String.format(Label.Core_RollupEase_FieldExists, new List<String>{ apiName })
                );
            }
            String objectName = described.getName();
            String body = bodyOf(trimmed, kind);
            GeneratedField field = new GeneratedField();
            field.apiName = apiName;
            field.fieldPath = 'objects/' + objectName + '/fields/' + apiName + '.field-meta.xml';
            field.fieldXml =
                '<?xml version="1.0" encoding="UTF-8"?>\n<CustomField xmlns="' +
                METADATA_NAMESPACE +
                '">\n    <fullName>' +
                apiName +
                '</fullName>\n' +
                body +
                '</CustomField>\n';
            field.deployPackage = EncodingUtil.base64Encode(packageOf(objectName, apiName, body));
            field.fileName = 'BarnRollupField_' + objectName + '_' + apiName + '.zip';
            field.steps = new List<String>{
                String.format(
                    Label.Core_RollupEase_FieldStepOpen,
                    new List<String>{ described.getLabel() }
                ),
                String.format(
                    Label.Core_RollupEase_FieldStepType,
                    new List<String>{ KINDS.get(kind), trimmed, name }
                ),
                Label.Core_RollupEase_FieldStepAccess,
                String.format(Label.Core_RollupEase_FieldStepBack, new List<String>{ trimmed })
            };
            return field;
        } catch (Exception caught) {
            String message = caught instanceof RollupService.RollupServiceException
                ? caught.getMessage()
                : Label.Core_Rollups_UnexpectedError;
            if (!(caught instanceof RollupService.RollupServiceException)) {
                ErrorLogger.log(caught, 'RollupFieldGenerator');
            }
            AuraHandledException reported = new AuraHandledException(message);
            reported.setMessage(message);
            throw reported;
        }
    }

    /**
     * A field name from a label: letters, digits and single underscores, starting with a letter,
     * at most `NAME_LENGTH` characters, as Setup suggests one. Blank when the label has no letter
     * or digit to start from.
     */
    @TestVisible
    private static String nameFor(String fieldLabel) {
        String name = fieldLabel.replaceAll('[^A-Za-z0-9]+', '_').replaceAll('^_+|_+$', '');
        if (String.isBlank(name)) {
            return '';
        }
        if (!name.left(1).isAlpha()) {
            name = 'X' + name;
        }
        return name.left(NAME_LENGTH).replaceAll('_+$', '');
    }

    /** The field's elements after its name, the same in the source and the package. */
    @TestVisible
    private static String bodyOf(String fieldLabel, String kind) {
        String body =
            '    <label>' +
            fieldLabel.escapeXml() +
            '</label>\n    <description>' +
            Label.Core_RollupEase_FieldDescription.escapeXml() +
            '</description>\n    <externalId>false</externalId>\n';
        if (kind == 'NUMBER' || kind == 'CURRENCY') {
            body +=
                '    <precision>18</precision>\n    <required>false</required>\n    <scale>' +
                (kind == 'NUMBER' ? '0' : '2') +
                '</scale>\n    <type>' +
                (kind == 'NUMBER' ? 'Number' : 'Currency') +
                '</type>\n    <unique>false</unique>\n';
        } else if (kind == 'DATE' || kind == 'DATETIME') {
            body +=
                '    <required>false</required>\n    <type>' +
                (kind == 'DATE' ? 'Date' : 'DateTime') +
                '</type>\n';
        } else if (kind == 'TEXT') {
            body += '    <length>255</length>\n    <required>false</required>\n    <type>Text</type>\n    <unique>false</unique>\n';
        } else if (kind == 'LONGTEXT') {
            body += '    <length>32768</length>\n    <type>LongTextArea</type>\n    <visibleLines>3</visibleLines>\n';
        } else {
            body += '    <defaultValue>false</defaultValue>\n    <type>Checkbox</type>\n';
        }
        return body;
    }

    /** A Metadata API package holding the field, deployable with `--single-package`. */
    private static Blob packageOf(String objectName, String apiName, String body) {
        String packageXml =
            '<?xml version="1.0" encoding="UTF-8"?>\n<Package xmlns="' +
            METADATA_NAMESPACE +
            '">\n    <types>\n        <members>' +
            objectName +
            '.' +
            apiName +
            '</members>\n        <name>CustomField</name>\n    </types>\n    <version>' +
            API_VERSION +
            '</version>\n</Package>\n';
        String objectXml =
            '<?xml version="1.0" encoding="UTF-8"?>\n<CustomObject xmlns="' +
            METADATA_NAMESPACE +
            '">\n    <fields>\n        <fullName>' +
            apiName +
            '</fullName>\n' +
            body.replaceAll('(?m)^    ', '        ') +
            '    </fields>\n</CustomObject>\n';
        Compression.ZipWriter zip = new Compression.ZipWriter();
        zip.addEntry('package.xml', Blob.valueOf(packageXml));
        zip.addEntry('objects/' + objectName + '.object', Blob.valueOf(objectXml));
        return zip.getArchive();
    }
}
