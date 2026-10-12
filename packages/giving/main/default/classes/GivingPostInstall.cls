/**
 * What BarnCRM Giving does for itself at install and at every upgrade.
 *
 * Three things, all of them shipped defaults that an org is supposed to arrive with.
 *
 * One: create the Rollup Definitions this package ships, so that a fresh install has
 * the giving totals on donors, funds, appeals, commitments and installments rather than a
 * page of blank currency attributes and a button labelled Restore that has never had
 * anything to restore (ADR-0029).
 *
 * Two: create the two receipt letters this package ships. They used to be created the first
 * time somebody opened the Receipts page, from a cacheable Apex method, which cannot perform
 * DML: the page threw instead. Install is the honest home for a shipped default, for the same
 * reasons ADR-0029 gives for rollups, and it is the one place where a system mode write to
 * package owned data is already justified (ADR-0021, ADR-0034).
 *
 * Three: create the Automation page's switch rows for the automations this package registers,
 * including the receipt lock, which always runs and is listed so the page can say why (ADR-0024).
 * Core's script ran before these registry rows existed, so it could not create them (C-21).
 *
 * Core cannot do this on Giving's behalf. Core installs first, and a package that is not
 * installed yet has no objects to describe, so `RollupService.ensureDefaults` correctly
 * skips every giving row when Core's own script runs (R-R6). Giving's script is the first
 * moment the org contains both the shipped rows and the objects they name.
 *
 * The work itself is Core's, which is deliberate: `Rollup_Definition__c` and the shipped
 * defaults are Core's, and a module that materialized its own rows would be a second
 * mechanism to keep in step with the Restore shipped rollups button.
 *
 * Safe on every install, every upgrade, and twice in a row: a definition that exists is
 * matched by Definition Key, and a switch by automation name, and each is left exactly as the
 * administrator left it, including one that has been edited or switched off. Nothing here throws: an install must never fail
 * because of a bootstrap step, so a failure is written to the Error Log instead, and the
 * Rollups page still offers the same button.
 */
public with sharing class GivingPostInstall implements InstallHandler {
    private static final String ROLLUP_CONTEXT = 'GivingPostInstall.ensureRollupDefaults';
    private static final String TEMPLATE_CONTEXT = 'GivingPostInstall.installReceiptTemplates';
    private static final String SWITCH_CONTEXT = 'GivingPostInstall.ensureAutomationSwitches';

    /**
     * Called by the platform after the package is installed or upgraded.
     *
     * @param context what the platform knows about this install, unused here because the
     *        definitions belong to the org rather than to whoever pressed Install
     */
    public void onInstall(InstallContext context) {
        // Nothing is caught here because nothing can be thrown: the entry point records its own
        // failure in the Error Log and returns, so an install is never aborted by this step, and
        // the Rollups page can still create the rows on demand.
        RollupService.ensureDefaultsDuringInstall(ROLLUP_CONTEXT);
        ReceiptTemplateService.installDefaultsDuringInstall(TEMPLATE_CONTEXT);
        AutomationControl.ensureDefaultsDuringInstall(SWITCH_CONTEXT);
    }
}
