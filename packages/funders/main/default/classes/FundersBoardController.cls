/**
 * The Board Dashboard tab (F-07, canonical model 29ZH R-GN9, ADR-0163
 * `0163-funders-reporting-links.md` decisions 4 and 5): this fiscal year's awarded grants by
 * funding source and by funder, and, where Giving is installed and readable, the gifts designated
 * to funds, each organization's Giving This Year and the restricted funds. Thin: it returns plain
 * JSON shapes, and the shares and flags are worked out in the framework-free `fundersBoardModel`
 * (plan 9.9).
 *
 * Giving is read by describe only, so the dashboard compiles and runs without it. Object and field
 * names in the dynamic queries come from describe and constants, never from the user; every read
 * runs in user mode, so a person sees totals of what they can read. Nothing is stored.
 */
public with sharing class FundersBoardController {
    private static final String CONTEXT = 'FundersBoardController';
    /** How many organizations each side returns for the concentration list. */
    @TestVisible
    private static final Integer SOURCE_LIMIT = 50;
    private static final Integer RESTRICTED_LIMIT = 200;

    /** The dashboard. */
    public class Board {
        /** Awarded this fiscal year by funding source; a blank source has a null key. */
        @AuraEnabled
        public List<Slice> grantsBySource = new List<Slice>();
        /** Awarded this fiscal year by funder, largest first. */
        @AuraEnabled
        public List<Slice> grantsByFunder = new List<Slice>();
        /** Whether Giving's figures are included. */
        @AuraEnabled
        public Boolean givingAvailable = false;
        /** Gifts designated to funds this fiscal year (Giving). */
        @AuraEnabled
        public Decimal giftsThisYear = 0;
        /** Each organization's Giving This Year, largest first (Giving). */
        @AuraEnabled
        public List<Slice> givingByAccount = new List<Slice>();
        /** Active restricted funds and what each raised this fiscal year (Giving). */
        @AuraEnabled
        public List<Slice> restrictedFunds = new List<Slice>();
        /** Whether the fund ledger (F-03) is installed, so grant balances are read. */
        @AuraEnabled
        public Boolean ledgerAvailable = false;
        /** Restricted grants with a balance (F-03). */
        @AuraEnabled
        public List<Slice> restrictedGrants = new List<Slice>();
        @AuraEnabled
        public String currencyCode;
    }

    /** One named amount. */
    public class Slice {
        /** A record identifier, or a picklist value for a funding source. */
        @AuraEnabled
        public String key;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public Decimal amount;

        Slice(String key, String name, Object amount) {
            this.key = key;
            this.name = name;
            this.amount = amount == null ? 0 : (Decimal) amount;
        }
    }

    /** The dashboard for the current fiscal year. */
    @AuraEnabled
    public static Board getBoard() {
        try {
            Board board = new Board();
            board.currencyCode = UserInfo.getDefaultCurrency();
            addGrants(board);
            addGiving(board);
            restrictedFunds(board);
            return board;
        } catch (Exception e) {
            ErrorLogger.log(e, CONTEXT + '.getBoard');
            throw UserErrors.message(BarnHelp.text('Funders', 'Funders_Board_LoadFailed'));
        }
    }

    private static void addGrants(Board board) {
        Map<String, Object> binds = new Map<String, Object>{
            'awarded' => GrantService.STAGE_AWARDED,
            'sourceLimit' => SOURCE_LIMIT
        };
        String awardedThisYear =
            ' FROM Grant__c WHERE Stage__c = :awarded' +
            ' AND Decision_Date__c = THIS_FISCAL_YEAR AND Amount_Awarded__c > 0';

        Map<String, String> sourceLabels = new Map<String, String>();
        for (
            Schema.PicklistEntry entry : Schema.SObjectType.Grant__c.fields.Funding_Source__c.getPicklistValues()
        ) {
            sourceLabels.put(entry.getValue(), entry.getLabel());
        }
        for (
            AggregateResult row : (List<AggregateResult>) Database.queryWithBinds(
                'SELECT Funding_Source__c source, SUM(Amount_Awarded__c) amount' +
                    awardedThisYear +
                    ' GROUP BY Funding_Source__c ORDER BY SUM(Amount_Awarded__c) DESC',
                binds,
                AccessLevel.USER_MODE
            )
        ) {
            String source = (String) row.get('source');
            String name = sourceLabels.containsKey(source) ? sourceLabels.get(source) : source;
            board.grantsBySource.add(new Slice(source, name, row.get('amount')));
        }

        for (
            AggregateResult row : (List<AggregateResult>) Database.queryWithBinds(
                'SELECT Funder__c funder, Funder__r.Name name, SUM(Amount_Awarded__c) amount' +
                    awardedThisYear +
                    ' GROUP BY Funder__c, Funder__r.Name ORDER BY SUM(Amount_Awarded__c) DESC' +
                    ' LIMIT :sourceLimit',
                binds,
                AccessLevel.USER_MODE
            )
        ) {
            board.grantsByFunder.add(
                new Slice((String) row.get('funder'), (String) row.get('name'), row.get('amount'))
            );
        }
    }

    /** A Giving field on the object, when it exists and the person can read it. */
    private static Boolean readable(Schema.SObjectType type, String fieldName) {
        if (type == null || !type.getDescribe(SObjectDescribeOptions.DEFERRED).isAccessible()) {
            return false;
        }
        Schema.SObjectField field = type.getDescribe(SObjectDescribeOptions.DEFERRED)
            .fields.getMap()
            .get(NamespaceUtil.qualify(fieldName));
        return field != null && field.getDescribe().isAccessible();
    }

    private static Schema.SObjectType fundObject() {
        return NamespaceUtil.packagedObjectType('Fund__c');
    }

    private static void addGiving(Board board) {
        Schema.SObjectType fund = fundObject();
        if (!readable(fund, 'Total_Raised_This_Year__c')) {
            return;
        }
        String fundName = fund.getDescribe(SObjectDescribeOptions.DEFERRED).getName();
        String raised = NamespaceUtil.qualify('Total_Raised_This_Year__c');
        AggregateResult total = (AggregateResult) Database.queryWithBinds(
            'SELECT SUM(' + raised + ') amount FROM ' + fundName,
            new Map<String, Object>(),
            AccessLevel.USER_MODE
        )[0];
        board.givingAvailable = true;
        board.giftsThisYear = total.get('amount') == null ? 0 : (Decimal) total.get('amount');

        if (readable(Account.SObjectType, 'Giving_This_Year__c')) {
            String giving = NamespaceUtil.qualify('Giving_This_Year__c');
            for (
                SObject account : Database.queryWithBinds(
                    'SELECT Id, Name, ' +
                        giving +
                        ' FROM Account WHERE ' +
                        giving +
                        ' > 0 ORDER BY ' +
                        giving +
                        ' DESC LIMIT :sourceLimit',
                    new Map<String, Object>{ 'sourceLimit' => SOURCE_LIMIT },
                    AccessLevel.USER_MODE
                )
            ) {
                board.givingByAccount.add(
                    new Slice(account.Id, (String) account.get('Name'), account.get(giving))
                );
            }
        }
    }

    /**
     * The restricted balances, and the integration point with the fund ledger (F-03): with Giving,
     * each active restricted fund and what it raised this fiscal year; where the grant carries the
     * ledger's Restricted and Restricted Balance fields, each restricted grant with a balance. The
     * grant fields are read by describe, so this runs before and after F-03 is installed.
     */
    @TestVisible
    private static void restrictedFunds(Board board) {
        Map<String, Object> binds = new Map<String, Object>{
            'restrictedLimit' => RESTRICTED_LIMIT
        };
        Schema.SObjectType fund = fundObject();
        if (
            board.givingAvailable &&
            readable(fund, 'Restricted__c') &&
            readable(fund, 'Active__c')
        ) {
            String raised = NamespaceUtil.qualify('Total_Raised_This_Year__c');
            for (
                SObject row : Database.queryWithBinds(
                    'SELECT Id, Name, ' +
                        raised +
                        ' FROM ' +
                        fund.getDescribe(SObjectDescribeOptions.DEFERRED).getName() +
                        ' WHERE ' +
                        NamespaceUtil.qualify('Restricted__c') +
                        ' = true AND ' +
                        NamespaceUtil.qualify('Active__c') +
                        ' = true ORDER BY Name LIMIT :restrictedLimit',
                    binds,
                    AccessLevel.USER_MODE
                )
            ) {
                board.restrictedFunds.add(
                    new Slice(row.Id, (String) row.get('Name'), row.get(raised))
                );
            }
        }

        if (
            readable(Grant__c.SObjectType, 'Restricted__c') &&
            readable(Grant__c.SObjectType, 'Restricted_Balance__c')
        ) {
            board.ledgerAvailable = true;
            String balance = NamespaceUtil.qualify('Restricted_Balance__c');
            for (
                SObject row : Database.queryWithBinds(
                    'SELECT Id, Name, ' +
                        balance +
                        ' FROM Grant__c WHERE ' +
                        NamespaceUtil.qualify('Restricted__c') +
                        ' = true AND ' +
                        balance +
                        ' != 0 ORDER BY Name LIMIT :restrictedLimit',
                    binds,
                    AccessLevel.USER_MODE
                )
            ) {
                board.restrictedGrants.add(
                    new Slice(row.Id, (String) row.get('Name'), row.get(balance))
                );
            }
        }
    }
}
