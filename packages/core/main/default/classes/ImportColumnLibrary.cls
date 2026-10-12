/**
 * The library of column names automatic mapping suggests from (plan Section 4.9).
 *
 * A header is normalized (lower case, punctuation and spacing removed) and looked up. The
 * entries cover what actually appears at the top of a nonprofit's spreadsheet: the wording
 * used by NPSP exports, by the common payment processors, and by a list somebody typed
 * themselves. A header nobody recognizes is suggested as "do not load", never guessed at,
 * because a wrong guess that looks confident is worse than an empty box.
 *
 * This is a lookup table and nothing else: no SOQL, no describe, no settings. It is the one
 * place a new column name is added.
 */
@NamespaceAccessible
public with sharing class ImportColumnLibrary {
    private static final String C1 = ImportMapping.ENTITY_CONTACT_1 + '.';
    private static final String C2 = ImportMapping.ENTITY_CONTACT_2 + '.';
    private static final String ORG = ImportMapping.ENTITY_ORGANIZATION + '.';
    private static final String HH = ImportMapping.ENTITY_HOUSEHOLD + '.';
    private static final String GIFT = 'Gift.';

    /**
     * Normalized header to target. Built once per transaction. Every key is already
     * normalized, so a lookup is a single map read.
     */
    private static Map<String, String> knownTargets;

    /** The target BarnCRM suggests for one header, or null when it recognizes none. */
    @NamespaceAccessible
    public static String suggest(String header) {
        if (String.isBlank(header)) {
            return null;
        }
        return library().get(normalize(header));
    }

    /**
     * A whole mapping suggested from a file's header row. Columns nobody recognizes are
     * present with the ignore target, so the picker shows every column in the file and the
     * administrator can see what was skipped.
     */
    @NamespaceAccessible
    public static ImportMapping suggestMapping(List<String> headers) {
        ImportMapping mapping = new ImportMapping();
        if (headers == null) {
            return mapping;
        }
        Set<String> usedTargets = new Set<String>();
        for (String header : headers) {
            String target = suggest(header);
            // A second column suggesting the same target would silently overwrite the first,
            // so only the first wins and the rest are left for the administrator to set.
            if (target == null || usedTargets.contains(target)) {
                target = ImportMapping.TARGET_IGNORE;
            } else {
                usedTargets.add(target);
            }
            mapping.columns.add(new ImportMapping.Column(header, target));
        }
        return mapping;
    }

    /** Lower case, with everything that is not a letter or a digit removed. */
    @NamespaceAccessible
    public static String normalize(String header) {
        if (header == null) {
            return '';
        }
        return header.toLowerCase().replaceAll('[^a-z0-9]', '');
    }

    private static Map<String, String> library() {
        if (knownTargets != null) {
            return knownTargets;
        }
        knownTargets = new Map<String, String>();
        add(
            C1 + 'FirstName',
            new List<String>{
                'First Name',
                'Firstname',
                'Given Name',
                'Donor First Name',
                'Contact First Name',
                'Fname'
            }
        );
        add(
            C1 + 'LastName',
            new List<String>{
                'Last Name',
                'Lastname',
                'Surname',
                'Family Name',
                'Donor Last Name',
                'Contact Last Name',
                'Lname'
            }
        );
        add(
            C1 + ImportMapping.ATTRIBUTE_FULL_NAME,
            new List<String>{
                'Full Name',
                'Name',
                'Donor Name',
                'Contact Name',
                'Donor',
                'Constituent Name'
            }
        );
        add(C1 + 'Salutation', new List<String>{ 'Salutation', 'Title Prefix', 'Prefix' });
        add(
            C1 + 'Email',
            new List<String>{
                'Email',
                'Email Address',
                'Donor Email',
                'Personal Email',
                'Home Email',
                'Primary Email',
                'Contact Email'
            }
        );
        add(
            C1 + 'Phone',
            new List<String>{
                'Phone',
                'Phone Number',
                'Home Phone',
                'Mobile',
                'Mobile Phone',
                'Cell',
                'Cell Phone',
                'Telephone'
            }
        );
        add(C1 + 'Title', new List<String>{ 'Job Title', 'Position' });
        add(
            C1 + 'MailingStreet',
            new List<String>{
                'Street',
                'Address',
                'Address 1',
                'Address Line 1',
                'Mailing Street',
                'Home Street',
                'Street Address'
            }
        );
        add(C1 + 'MailingCity', new List<String>{ 'City', 'Town', 'Mailing City', 'Home City' });
        add(
            C1 + 'MailingState',
            new List<String>{
                'State',
                'Province',
                'County',
                'Region',
                'Mailing State',
                'State Province'
            }
        );
        add(
            C1 + 'MailingPostalCode',
            new List<String>{
                'Postal Code',
                'Postcode',
                'Zip',
                'Zip Code',
                'Mailing Zip',
                'Mailing Postal Code'
            }
        );
        add(C1 + 'MailingCountry', new List<String>{ 'Country', 'Mailing Country' });

        add(
            C2 + 'FirstName',
            new List<String>{
                'Spouse First Name',
                'Partner First Name',
                'Second First Name',
                'Contact 2 First Name'
            }
        );
        add(
            C2 + 'LastName',
            new List<String>{
                'Spouse Last Name',
                'Partner Last Name',
                'Second Last Name',
                'Contact 2 Last Name'
            }
        );
        add(
            C2 + ImportMapping.ATTRIBUTE_FULL_NAME,
            new List<String>{ 'Spouse Name', 'Partner Name', 'Spouse', 'Partner', 'Second Contact' }
        );
        add(C2 + 'Email', new List<String>{ 'Spouse Email', 'Partner Email', 'Second Email' });
        add(C2 + 'Phone', new List<String>{ 'Spouse Phone', 'Partner Phone' });

        add(
            HH + 'Name',
            new List<String>{
                'Household Name',
                'Household',
                'Family Name As Addressed',
                'Account Name Household'
            }
        );

        add(
            ORG + 'Name',
            new List<String>{
                'Organization',
                'Organisation',
                'Organization Name',
                'Company',
                'Company Name',
                'Employer',
                'Account Name',
                'Business Name'
            }
        );
        add(
            ORG + 'Phone',
            new List<String>{
                'Organization Phone',
                'Company Phone',
                'Work Phone',
                'Business Phone'
            }
        );
        add(
            ORG + 'Website',
            new List<String>{ 'Website', 'Web Site', 'Url', 'Organization Website' }
        );
        add(
            ORG + 'BillingStreet',
            new List<String>{
                'Organization Street',
                'Company Street',
                'Billing Street',
                'Work Street'
            }
        );
        add(
            ORG + 'BillingCity',
            new List<String>{ 'Organization City', 'Company City', 'Billing City' }
        );
        add(
            ORG + 'BillingState',
            new List<String>{ 'Organization State', 'Company State', 'Billing State' }
        );
        add(
            ORG + 'BillingPostalCode',
            new List<String>{
                'Organization Postal Code',
                'Company Zip',
                'Billing Zip',
                'Billing Postal Code'
            }
        );
        add(
            ORG + 'BillingCountry',
            new List<String>{ 'Organization Country', 'Company Country', 'Billing Country' }
        );

        // Recognized so the picker can say what the column is, and staged with the row.
        // Nothing in Core writes them (R-IR6).
        add(
            GIFT + 'Amount__c',
            new List<String>{
                'Amount',
                'Gift Amount',
                'Donation Amount',
                'Total Amount',
                'Gross Amount'
            }
        );
        add(
            GIFT + 'Gift_Date__c',
            new List<String>{
                'Date',
                'Gift Date',
                'Donation Date',
                'Transaction Date',
                'Payment Date'
            }
        );
        add(
            GIFT + 'Type__c',
            new List<String>{ 'Payment Method', 'Gift Type', 'Payment Type', 'Method' }
        );
        add(
            GIFT + 'Payment_Reference__c',
            new List<String>{
                'Check Number',
                'Cheque Number',
                'Reference',
                'Payment Reference',
                'Transaction Id'
            }
        );
        add(
            'Allocation.Fund',
            new List<String>{
                'Fund',
                'Designation',
                'Restriction',
                'Gau',
                'General Accounting Unit'
            }
        );
        return knownTargets;
    }

    private static void add(String target, List<String> headers) {
        for (String header : headers) {
            knownTargets.put(normalize(header), target);
        }
    }
}
