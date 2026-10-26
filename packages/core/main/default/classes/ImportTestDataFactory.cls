/**
 * Test data for the import framework (C-14): a template, a batch, and staged rows.
 *
 * Test only, and namespace accessible for the same reason `TestDataFactory` is (ADR-0017):
 * the Giving package's own import tests will need to build a batch without duplicating this.
 */
@IsTest
@NamespaceAccessible
public class ImportTestDataFactory {
    /** The mapping the shipped generic contact list starts with, as a document. */
    @NamespaceAccessible
    public static String donorMapping() {
        ImportMapping mapping = new ImportMapping();
        mapping.columns.add(new ImportMapping.Column('First Name', 'Contact1.FirstName'));
        mapping.columns.add(new ImportMapping.Column('Last Name', 'Contact1.LastName'));
        mapping.columns.add(new ImportMapping.Column('Email', 'Contact1.Email'));
        mapping.columns.add(new ImportMapping.Column('City', 'Contact1.MailingCity'));
        mapping.columns.add(new ImportMapping.Column('Organization', 'Organization.Name'));
        return mapping.serialize();
    }

    /** A saved, active template using the given mapping and rule. */
    @NamespaceAccessible
    public static Import_Template__c template(String mappingDocument, String matchingRule) {
        Import_Template__c template = new Import_Template__c(
            Name = 'Test contact list',
            Template_Key__c = 'test_donor_list_' +
                String.valueOf(Math.abs(Crypto.getRandomInteger())),
            Column_Mapping_JSON__c = mappingDocument,
            Default_Values_JSON__c = '{"version":1,"defaults":[]}',
            Matching_Rule__c = ImportTemplateService.normalizedRule(matchingRule),
            Person_Mode__c = ImportTemplateService.PERSON_MODE_CONTACTS,
            Is_Package_Default__c = false,
            Is_Recurring__c = false,
            Active__c = true
        );
        insert template;
        return template;
    }

    /** A batch against the given template, ready to have rows staged on it. */
    @NamespaceAccessible
    public static Import_Batch__c batch(Import_Template__c template) {
        Import_Batch__c batch = new Import_Batch__c(
            Import_Template__c = template.Id,
            File_Name__c = 'donors.csv',
            Status__c = ImportBatchService.STATUS_DRAFT,
            Is_Dry_Run__c = true,
            Row_Count__c = 0,
            Rows_Created__c = 0,
            Rows_Updated__c = 0,
            Rows_Matched__c = 0,
            Rows_Rejected__c = 0,
            Chunk_Size__c = 200
        );
        insert batch;
        return batch;
    }

    /**
     * Stages rows on a batch from a list of column value maps, numbered from file row two,
     * and returns them read back, in file order.
     *
     * Read back rather than returned as inserted: the inserted records carry the master
     * detail link to the batch, which cannot be changed after insert, so a test that changed
     * a row's status and saved the inserted record was refused for a field it never touched.
     */
    @NamespaceAccessible
    public static List<Import_Row__c> rows(
        Import_Batch__c batch,
        List<Map<String, String>> values
    ) {
        List<Import_Row__c> staged = new List<Import_Row__c>();
        for (Integer i = 0; i < values.size(); i++) {
            staged.add(
                new Import_Row__c(
                    Import_Batch__c = batch.Id,
                    Row_Number__c = i + 2,
                    Raw_Values_JSON__c = JSON.serialize(values[i]),
                    Status__c = ImportRowProcessor.STATUS_PENDING
                )
            );
        }
        insert staged;
        batch.Row_Count__c = staged.size();
        update batch;
        return reload(batch.Id);
    }

    /** One row of a generic contact list. */
    @NamespaceAccessible
    public static Map<String, String> donorRow(
        String firstName,
        String lastName,
        String email,
        String organization
    ) {
        return new Map<String, String>{
            'First Name' => firstName,
            'Last Name' => lastName,
            'Email' => email,
            'City' => 'Portland',
            'Organization' => organization
        };
    }

    /** The staged rows of a batch, freshly read with the fields the import batch reads, in file order. */
    @NamespaceAccessible
    public static List<Import_Row__c> reload(Id batchId) {
        return [
            SELECT
                Id,
                Row_Number__c,
                Raw_Values_JSON__c,
                Status__c,
                Error_Message__c,
                Household__c,
                Contact_1__c,
                Person_1_Account__c,
                Contact_2__c,
                Person_2_Account__c,
                Organization__c,
                Gift_Id__c,
                Soft_Credit_Id__c
            FROM Import_Row__c
            WHERE Import_Batch__c = :batchId
            WITH SYSTEM_MODE
            ORDER BY Row_Number__c ASC
        ];
    }
}
