/**
 * The letter half of G-12: a spreadsheet an administrator merges with the letter she already
 * has (ADR-0032, R-AK11).
 *
 * It produces a CSV and nothing else. The package does not render a printable letter, because the
 * document an organization sends is theirs, is usually already written on their letterhead in
 * Word or Google Docs, and a half rendered replacement for it would be worse than the mail merge
 * they have been doing for years.
 *
 * The rows stay Queued until a person marks the run sent. Salesforce cannot tell whether anything
 * was printed, so it does not claim to know.
 */
public with sharing class AcknowledgmentLetterMerge {
    /** The columns, in the order they are written. */
    @TestVisible
    private static final List<String> HEADERS = new List<String>{
        'Gift',
        'Gift Date',
        'Amount',
        'Donor Name',
        'Greeting',
        'Street',
        'City',
        'State',
        'Postal Code',
        'Country',
        'Appeal',
        'Rule'
    };

    /** One CSV, one row per gift, with the header first. */
    public static String csvFor(
        List<Gift__c> gifts,
        List<AcknowledgmentRuleService.RuleMatch> matches
    ) {
        List<String> lines = new List<String>{ String.join(HEADERS, ',') };
        for (Integer index = 0; index < gifts.size(); index++) {
            Gift__c gift = gifts[index];
            String ruleName = index < matches.size() &&
                matches[index] != null
                ? matches[index].ruleName
                : '';
            lines.add(
                String.join(
                    new List<String>{
                        escape(gift.Name),
                        escape(gift.Gift_Date__c == null ? '' : String.valueOf(gift.Gift_Date__c)),
                        escape(gift.Amount__c == null ? '' : String.valueOf(gift.Amount__c)),
                        escape(donorNameOf(gift)),
                        escape(greetingOf(gift)),
                        escape(streetOf(gift)),
                        escape(cityOf(gift)),
                        escape(stateOf(gift)),
                        escape(postalCodeOf(gift)),
                        escape(countryOf(gift)),
                        escape(gift.Appeal__r == null ? '' : gift.Appeal__r.Name),
                        escape(ruleName)
                    },
                    ','
                )
            );
        }
        return String.join(lines, '\n');
    }

    /**
     * Characters that make a spreadsheet read a cell as a formula, the same set Mirror's
     * accounting export guards against (`AccountingExportService`).
     */
    private static final Set<String> FORMULA_STARTS = new Set<String>{
        '=',
        '+',
        '-',
        '@',
        '\t',
        '\r'
    };

    /** A plain number, such as a negative amount, which is a value and never a formula. */
    private static final Pattern PLAIN_NUMBER = Pattern.compile('^-?[0-9]+(\\.[0-9]+)?$');

    /**
     * CSV escaping, which is one rule and one exception: quote a value containing a comma, a
     * quote or a newline, and double the quotes inside it. A donor called "Smith, Jr." is exactly
     * the row that breaks a merge file written without this.
     *
     * First, a value a spreadsheet would run as a formula is prefixed with an apostrophe: donor
     * names and addresses can arrive from outside (imports, the inbound gift API), and a cell
     * starting with = runs when the merge file is opened (2026-10-28 security review, G-L1).
     */
    @TestVisible
    public static String escape(String value) {
        if (String.isBlank(value)) {
            return '';
        }
        String cell = FORMULA_STARTS.contains(value.left(1)) &&
            !PLAIN_NUMBER.matcher(value).matches()
            ? '\'' + value
            : value;
        Boolean needsQuoting =
            cell.contains(',') ||
            cell.contains('"') ||
            cell.contains('\n') ||
            cell.contains('\r');
        if (!needsQuoting) {
            return cell;
        }
        return '"' + cell.replace('"', '""') + '"';
    }

    /** The donor as they are addressed: the person, or the organization. */
    public static String donorNameOf(Gift__c gift) {
        if (gift.Donor_Contact__r != null && String.isNotBlank(gift.Donor_Contact__r.Name)) {
            return gift.Donor_Contact__r.Name;
        }
        if (gift.Donor_Account__r != null && String.isNotBlank(gift.Donor_Account__r.Name)) {
            return gift.Donor_Account__r.Name;
        }
        return '';
    }

    /**
     * How the letter opens. The household's informal greeting when there is one, because that is
     * the phrase the organization already agreed on for this household (Core household naming),
     * and the donor's first name or the organization's name when there is not.
     */
    public static String greetingOf(Gift__c gift) {
        if (
            gift.Household__r != null &&
            String.isNotBlank(gift.Household__r.Household_Informal_Greeting__c)
        ) {
            return gift.Household__r.Household_Informal_Greeting__c;
        }
        if (
            gift.Donor_Account__r != null &&
            String.isNotBlank(gift.Donor_Account__r.Household_Informal_Greeting__c)
        ) {
            return gift.Donor_Account__r.Household_Informal_Greeting__c;
        }
        if (gift.Donor_Contact__r != null && String.isNotBlank(gift.Donor_Contact__r.FirstName)) {
            return gift.Donor_Contact__r.FirstName;
        }
        return donorNameOf(gift);
    }

    private static String streetOf(Gift__c gift) {
        if (gift.Donor_Contact__r != null) {
            return gift.Donor_Contact__r.MailingStreet;
        }
        return gift.Donor_Account__r == null ? '' : gift.Donor_Account__r.BillingStreet;
    }

    private static String cityOf(Gift__c gift) {
        if (gift.Donor_Contact__r != null) {
            return gift.Donor_Contact__r.MailingCity;
        }
        return gift.Donor_Account__r == null ? '' : gift.Donor_Account__r.BillingCity;
    }

    private static String stateOf(Gift__c gift) {
        if (gift.Donor_Contact__r != null) {
            return gift.Donor_Contact__r.MailingState;
        }
        return gift.Donor_Account__r == null ? '' : gift.Donor_Account__r.BillingState;
    }

    private static String postalCodeOf(Gift__c gift) {
        if (gift.Donor_Contact__r != null) {
            return gift.Donor_Contact__r.MailingPostalCode;
        }
        return gift.Donor_Account__r == null ? '' : gift.Donor_Account__r.BillingPostalCode;
    }

    private static String countryOf(Gift__c gift) {
        if (gift.Donor_Contact__r != null) {
            return gift.Donor_Contact__r.MailingCountry;
        }
        return gift.Donor_Account__r == null ? '' : gift.Donor_Account__r.BillingCountry;
    }
}
