/**
 * The Giving fund a grant's money is booked to (canonical model 29ZH R-GN8, ADR-NEXT
 * `NEXT-funders-restricted-funds-schedules-calendar.md` decision 4): named by record identifier,
 * never looked up, so Funders installs without Giving.
 *
 * Giving's `Fund__c` is found by describe only. Every read of it runs in user mode, and only its
 * name and Active flag are read.
 */
public with sharing class GrantFundService {
    private static final String FUND_OBJECT = 'Fund__c';
    private static final String ACTIVE_FIELD = 'Active__c';
    private static final Integer FUND_LIMIT = 500;

    /**
     * R-GN8: stores each grant's fund in its 18-character form and refuses text that is not a
     * record identifier, or, where Giving's Fund object exists, an identifier of another object.
     *
     * @param grants the grants being saved
     */
    public static void checkFunds(List<Grant__c> grants) {
        Schema.SObjectType fundObject = null;
        Boolean looked = false;
        for (Grant__c grant : grants) {
            if (String.isBlank(grant.Fund_Id__c)) {
                grant.Fund_Id__c = null;
                continue;
            }
            Id fundId = asId(grant.Fund_Id__c);
            if (fundId != null && !looked) {
                fundObject = NamespaceUtil.packagedObjectType(FUND_OBJECT);
                looked = true;
            }
            if (fundId == null || (fundObject != null && fundId.getSObjectType() != fundObject)) {
                grant.Fund_Id__c.addError(Label.Funders_Grant_BadFund);
                continue;
            }
            grant.Fund_Id__c = String.valueOf(fundId);
        }
    }

    /** Giving's Fund object, or null where Giving is not installed or the user cannot read funds. */
    @TestVisible
    private static Schema.SObjectType fundType() {
        Schema.SObjectType type = NamespaceUtil.packagedObjectType(FUND_OBJECT);
        if (type == null || !type.getDescribe(SObjectDescribeOptions.DEFERRED).isAccessible()) {
            return null;
        }
        return type;
    }

    /** Whether funds can be chosen here: Giving is installed and the user can read funds. */
    public static Boolean fundsAvailable() {
        return fundType() != null;
    }

    /**
     * The active funds, by name, as value and label pairs. Empty without Giving.
     *
     * @return up to 500 funds the user can see
     */
    public static List<Map<String, String>> funds() {
        List<Map<String, String>> options = new List<Map<String, String>>();
        Schema.SObjectType type = fundType();
        if (type == null) {
            return options;
        }
        Schema.DescribeSObjectResult describe = type.getDescribe(SObjectDescribeOptions.DEFERRED);
        Schema.SObjectField active = describe.fields.getMap().get(ACTIVE_FIELD);
        // Object and field names come from describe, never from the user.
        String soql =
            'SELECT Id, Name FROM ' +
            describe.getName() +
            (active == null ? '' : ' WHERE ' + active.getDescribe().getName() + ' = true') +
            ' ORDER BY Name LIMIT :maxRows';
        for (
            SObject fund : Database.queryWithBinds(
                soql,
                new Map<String, Object>{ 'maxRows' => FUND_LIMIT },
                AccessLevel.USER_MODE
            )
        ) {
            options.add(
                new Map<String, String>{
                    'value' => (String) fund.Id,
                    'label' => (String) fund.get('Name')
                }
            );
        }
        return options;
    }

    /** The fund's name, or null when Giving is absent or the fund cannot be found. */
    public static String fundName(String fundId) {
        Schema.SObjectType type = fundType();
        if (type == null || String.isBlank(fundId)) {
            return null;
        }
        String soql =
            'SELECT Name FROM ' +
            type.getDescribe(SObjectDescribeOptions.DEFERRED).getName() +
            ' WHERE Id = :fundId LIMIT 1';
        List<SObject> rows = Database.queryWithBinds(
            soql,
            new Map<String, Object>{ 'fundId' => fundId },
            AccessLevel.USER_MODE
        );
        return rows.isEmpty() ? null : (String) rows[0].get('Name');
    }

    /**
     * Names the fund a grant's money is booked to, or clears it, as the person.
     *
     * @param grantId the grant
     * @param fundId a fund's record identifier, or blank for none
     */
    public static void setFund(Id grantId, String fundId) {
        String value = null;
        if (String.isNotBlank(fundId)) {
            Schema.SObjectType type = fundType();
            Id parsed = asId(fundId);
            if (type == null || parsed == null || parsed.getSObjectType() != type) {
                throw new GrantService.GrantException(Label.Funders_Grant_BadFund);
            }
            value = String.valueOf(parsed);
        }
        update as user new Grant__c(Id = grantId, Fund_Id__c = value);
    }

    private static Id asId(String text) {
        return GrantService.asId(text);
    }
}
