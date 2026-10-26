/**
 * The one fund a new Giving org starts with, so that the first gift does not fail with "No
 * default fund is set" before anybody has opened the Funds tab (R-F4).
 *
 * It creates an active, unrestricted fund named by the `Giving_Fund_DefaultName` label, with no
 * accounting code, and marks it as the default, which writes the Default Fund key in Giving's
 * settings through the fund trigger. It does that only for an org that has made no decision yet:
 * no fund exists at all and no default fund is set. An org with any fund, including an inactive
 * one, and an org whose Default Fund key is already filled in are left exactly as they are, so
 * running it again at every upgrade never adds a second fund and never overwrites a choice.
 *
 * The write is in system mode because it runs at install, where there is no user to check and a
 * shipped default is supposed to arrive (ADR-0029, ADR-0034). Nothing here throws on the install
 * path: a failure goes to the Error Log, and the Funds tab still lets an administrator create
 * the fund by hand.
 */
public with sharing class FundDefaultsService {
    @TestVisible
    private static final String INSTALL_CONTEXT = 'FundDefaultsService.installDefaultFund';

    /**
     * Creates the default fund when the org has no fund and no default fund setting.
     *
     * @return the fund created, or null when the org had already made its own choice
     */
    public static Fund__c ensureDefaultFund() {
        if (!hasMadeNoFundDecision()) {
            return null;
        }
        Fund__c fund = new Fund__c(
            Name = Label.Giving_Fund_DefaultName,
            Active__c = true,
            Restricted__c = false,
            Is_Default__c = true
        );
        // Marking it the default also saves the Default Fund key, in the same transaction.
        Database.insert(fund, true, AccessLevel.SYSTEM_MODE);
        return fund;
    }

    /**
     * The same work, for the post-install script and the source deploy: it never throws, so a
     * failure cannot abort an install.
     *
     * @param context the calling script, so the Error Log entry names it
     * @return the fund created, or null when none was created or the step failed
     */
    public static Fund__c installDefaultFundDuringInstall(String context) {
        try {
            return ensureDefaultFund();
        } catch (Exception failed) {
            ErrorLogger.log(failed, String.isBlank(context) ? INSTALL_CONTEXT : context);
            return null;
        }
    }

    /** True only when there is no fund of any kind and the Default Fund key is blank. */
    private static Boolean hasMadeNoFundDecision() {
        if (String.isNotBlank(Giving_Settings__c.getOrgDefaults().Default_Fund__c)) {
            return false;
        }
        Integer funds = [SELECT COUNT() FROM Fund__c WITH SYSTEM_MODE];
        return funds == 0;
    }
}
