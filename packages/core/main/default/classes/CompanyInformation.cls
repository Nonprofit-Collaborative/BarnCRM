/**
 * What Salesforce Setup's Company Information holds about the organization, offered on the
 * BarnCRM Settings Organization page as a value to use when BarnCRM's own setting is blank.
 *
 * It is a suggestion only: nothing here is saved, and no reader falls back to it. A blank
 * legal name or address stays blank (receipts refuse a blank legal name on purpose) until an
 * administrator chooses to use the suggestion and saves it.
 */
public with sharing class CompanyInformation {
    /** Injected by the tests, since the org's own Company Information cannot be changed. */
    @TestVisible
    private static Organization companyOverride;

    /** The company name, or null when there is none. */
    public static String name() {
        Organization company = company();
        String name = company == null ? '' : clean(company.Name);
        return name == '' ? null : name;
    }

    /**
     * The company address as the six organization address parts, keyed by settings field name,
     * or an empty map unless street, city, state and postal code are all present (the rule a
     * saved organization address has to meet, R-OA1). The first street line is Street, and any
     * further lines are Street 2.
     */
    public static Map<String, String> addressParts() {
        Map<String, String> parts = new Map<String, String>();
        Organization company = company();
        if (company == null) {
            return parts;
        }
        List<String> streetLines = new List<String>();
        for (String line : clean(company.Street).split('\n')) {
            if (String.isNotBlank(line)) {
                streetLines.add(line.trim());
            }
        }
        String city = clean(company.City);
        String state = clean(company.State);
        String postalCode = clean(company.PostalCode);
        if (streetLines.isEmpty() || city == '' || state == '' || postalCode == '') {
            return parts;
        }
        parts.put('Organization_Street__c', streetLines.remove(0));
        parts.put('Organization_Street_2__c', String.join(streetLines, ', '));
        parts.put('Organization_City__c', city);
        parts.put('Organization_State__c', state);
        parts.put('Organization_Postal_Code__c', postalCode);
        parts.put('Organization_Country__c', clean(company.Country));
        return parts;
    }

    private static Organization company() {
        if (companyOverride != null || Test.isRunningTest()) {
            return companyOverride;
        }
        // Company Information is org-wide setup data every user may see in Setup; reading it
        // shows nothing beyond that, and only to an administrator on the settings page.
        List<Organization> companies = [
            SELECT Name, Street, City, State, PostalCode, Country
            FROM Organization
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return companies.isEmpty() ? null : companies[0];
    }

    private static String clean(String value) {
        return value == null ? '' : value.trim();
    }
}
