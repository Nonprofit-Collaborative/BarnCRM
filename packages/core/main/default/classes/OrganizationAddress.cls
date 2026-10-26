/**
 * The organization's mailing address: six settings (street, street 2, city, state, postal code,
 * country) read and printed in one place.
 *
 * Giving receipts and Volunteers letters print the address through here, so every document
 * writes it the same way. The address may be blank. Once any part is filled in, street, city,
 * state and postal code are all required (canonical model R-OA1); street 2 and country stay
 * optional. `SettingsService` enforces that on every save, through `refusal`.
 */
@NamespaceAccessible
public with sharing class OrganizationAddress {
    /** The six parts, in the order they are printed. */
    private static List<Schema.SObjectField> parts() {
        return new List<Schema.SObjectField>{
            BarnCRM_Settings__c.Organization_Street__c,
            BarnCRM_Settings__c.Organization_Street_2__c,
            BarnCRM_Settings__c.Organization_City__c,
            BarnCRM_Settings__c.Organization_State__c,
            BarnCRM_Settings__c.Organization_Postal_Code__c,
            BarnCRM_Settings__c.Organization_Country__c
        };
    }

    /** The settings fields that make up the address, for the code that saves them. */
    public static List<Schema.SObjectField> partFields() {
        return parts();
    }

    /** The saved address as printable lines: blanks skipped, `City, State Zip` on one line. */
    @NamespaceAccessible
    public static List<String> lines() {
        return lines(BarnCRM_Settings__c.getOrgDefaults());
    }

    /** The saved address on one line, the lines joined with commas. Empty when none is saved. */
    @NamespaceAccessible
    public static String oneLine() {
        return oneLine(BarnCRM_Settings__c.getOrgDefaults());
    }

    @NamespaceAccessible
    public static List<String> lines(BarnCRM_Settings__c settings) {
        List<String> printable = new List<String>();
        if (settings == null) {
            return printable;
        }
        addIfPresent(printable, settings.Organization_Street__c);
        addIfPresent(printable, settings.Organization_Street_2__c);
        addIfPresent(printable, localityLine(settings));
        addIfPresent(printable, settings.Organization_Country__c);
        return printable;
    }

    @NamespaceAccessible
    public static String oneLine(BarnCRM_Settings__c settings) {
        return String.join(lines(settings), ', ');
    }

    /**
     * The saved parts keyed by their settings field name, for the screens that edit them. A part
     * that is not saved is an empty string, so a screen never has to tell null from blank.
     */
    public static Map<String, String> savedParts() {
        BarnCRM_Settings__c saved = BarnCRM_Settings__c.getOrgDefaults();
        Map<String, String> result = new Map<String, String>();
        for (Schema.SObjectField part : parts()) {
            String text = (String) saved.get(part);
            result.put(part.getDescribe().getLocalName(), text == null ? '' : text);
        }
        return result;
    }

    /**
     * The message that refuses this address, or null when it may be saved: blank, or filled in
     * with street, city, state and postal code all present. The message names what is missing.
     */
    public static String refusal(BarnCRM_Settings__c candidate) {
        Boolean anyFilled = false;
        for (Schema.SObjectField part : parts()) {
            anyFilled = anyFilled || isFilled((String) candidate.get(part));
        }
        if (!anyFilled) {
            return null;
        }
        List<String> missing = new List<String>();
        addIfBlank(
            missing,
            candidate.Organization_Street__c,
            System.Label.Core_OrganizationAddress_Street
        );
        addIfBlank(
            missing,
            candidate.Organization_City__c,
            System.Label.Core_OrganizationAddress_City
        );
        addIfBlank(
            missing,
            candidate.Organization_State__c,
            System.Label.Core_OrganizationAddress_State
        );
        addIfBlank(
            missing,
            candidate.Organization_Postal_Code__c,
            System.Label.Core_OrganizationAddress_PostalCode
        );
        if (missing.isEmpty()) {
            return null;
        }
        return String.format(
            System.Label.Core_OrganizationAddress_IncompleteError,
            new List<Object>{ String.join(missing, ', ') }
        );
    }

    private static String localityLine(BarnCRM_Settings__c settings) {
        String line = clean(settings.Organization_City__c);
        String state = clean(settings.Organization_State__c);
        String postal = clean(settings.Organization_Postal_Code__c);
        if (state != '') {
            line = line == '' ? state : line + ', ' + state;
        }
        if (postal != '') {
            line = line == '' ? postal : line + ' ' + postal;
        }
        return line;
    }

    private static String clean(String text) {
        return text == null ? '' : text.trim();
    }

    private static Boolean isFilled(String text) {
        return String.isNotBlank(text);
    }

    private static void addIfPresent(List<String> target, String text) {
        if (isFilled(text)) {
            target.add(text.trim());
        }
    }

    private static void addIfBlank(List<String> target, String text, String name) {
        if (!isFilled(text)) {
            target.add(name);
        }
    }
}
