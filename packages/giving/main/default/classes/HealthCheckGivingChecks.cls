/**
 * The Giving questions Health Check asks, added to Core's one report through
 * `GivingHealthCheckExtension` (G-20 follow-up, ADR-0053, ADR-0057). Grouped the way
 * ADR-0039 groups Core's own checks, in its own class, so a second Giving check reads next to
 * this one rather than inside Core.
 *
 * Three questions. Whether receipt generation has been failing is asked of every viewer; who
 * holds the receipt lock override and which locked gifts are unposted are asked only of a
 * viewer who may manage settings. The first two moved here from Core with C-29 (ADR-0059),
 * with their keys, wording, severities, categories and fixes unchanged.
 *
 * Whether a gift is in the books, and what "locked" means, is `GiftPostingLock`'s rule
 * (ADR-0022, ADR-0053): a gift with a counting status (Received, Refunded or Written off, or a
 * blank status, which `GiftPostingLock.isInBooks` also reads as Received) and a type other than
 * In-kind. This class asks nothing about that rule Core does not already enforce; it only
 * reports what the rule finds, capped and linked the way `HealthCheckHouseholdChecks` reports
 * orphan records in Core.
 *
 * Only asked of a viewer who may manage settings (`HealthCheckService.canManageSettings()`):
 * posting and the close date are an administrator's business. `HealthCheckGivingSelector` reads
 * `without sharing`, unlike `HouseholdOrphanSelector`'s shared orphan reads in Core: Gift__c
 * ships with Private sharing (R-G14), so a viewer's own record sharing narrows which gifts they
 * own or share, not which gifts are actually locked and unposted, and a Health Check finding
 * that silently under-counts because the administrator does not happen to share every gift is a
 * wrong answer, not a narrower one. ADR-0021, amended by this ADR, keeps this as a named
 * exception to "reads that reach a user stay in user mode," so the gate matters twice as much
 * as it would for a shared read: `HealthCheckGivingSelector` asserts
 * `canManageSettings()` itself, not only this class, the same permission check that is the
 * access control that matters for every other Settings-category check that reads org-wide
 * state.
 */
public with sharing class HealthCheckGivingChecks {
    /** Counts stop here, and the finding says "more than" this many. A test lowers it. */
    @TestVisible
    private static Integer countCap = 1000;

    /** How many example gifts a finding links to. */
    private static final Integer LINKS_SHOWN = 5;

    /**
     * How many reconciled receipt numbers are ordinary. One number consumed by a failed run
     * is the mechanism working (R-RC3); more than one is generation failing repeatedly with
     * nobody watching.
     */
    private static final Integer RECEIPT_FAILURES_EXPECTED = 1;

    /** Injected by the tests, which cannot create a custom permission with DML. */
    @TestVisible
    private static CustomPermissionSelector.Holders holdersOverride;

    /** The check keys, which name a check that threw in its `check_failed_<key>` finding. */
    private static final String CHECK_RECEIPT_GENERATION = 'receipt_generation';
    private static final String CHECK_OVERRIDE_RECEIPT_LOCK = 'override_receipt_lock';
    private static final String CHECK_UNPOSTED_CLOSED_PERIOD = 'unposted_gifts_closed_period';

    /**
     * Every finding Giving adds to the Health Check report, for this viewer. Each check is
     * isolated the way Core isolates its own: one that throws becomes its own
     * `check_failed_<key>` finding, and the other Giving findings still stand.
     */
    public static List<HealthCheckService.Finding> findings() {
        List<String> checks = new List<String>{ CHECK_RECEIPT_GENERATION };
        if (HealthCheckService.canManageSettings()) {
            checks.add(CHECK_OVERRIDE_RECEIPT_LOCK);
            checks.add(CHECK_UNPOSTED_CLOSED_PERIOD);
        }

        List<HealthCheckService.Finding> findings = new List<HealthCheckService.Finding>();
        for (String check : checks) {
            try {
                addIfAny(findings, run(check));
            } catch (Exception e) {
                findings.add(HealthCheckService.checkFailed(check, e));
            }
        }
        return findings;
    }

    private static HealthCheckService.Finding run(String check) {
        if (check == CHECK_OVERRIDE_RECEIPT_LOCK) {
            return overrideReceiptLockFinding();
        }
        if (check == CHECK_UNPOSTED_CLOSED_PERIOD) {
            return unpostedClosedPeriodFinding();
        }
        return receiptGenerationFinding();
    }

    private static void addIfAny(
        List<HealthCheckService.Finding> findings,
        HealthCheckService.Finding finding
    ) {
        if (finding != null) {
            findings.add(finding);
        }
    }

    /**
     * Receipt numbers consumed by a run that failed (R-RC3). One is the reconciliation
     * mechanism doing its job and is reported as information; more than one is receipt
     * generation failing repeatedly, which is a warning because the donors are waiting. A
     * person who cannot read receipts is told nothing rather than told zero.
     */
    private static HealthCheckService.Finding receiptGenerationFinding() {
        ReceiptGenerationFailureSelector.Result failures = ReceiptGenerationFailureSelector.generationFailures();
        if (failures == null || failures.available != true || failures.count <= 0) {
            return null;
        }

        if (failures.count <= RECEIPT_FAILURES_EXPECTED) {
            return new HealthCheckService.Finding(
                    'receipt_generation_failed_once',
                    Label.Giving_HealthCheck_ReceiptFailedOneTitle,
                    Label.Giving_HealthCheck_ReceiptFailedOneDetail,
                    HealthCheckService.SEVERITY_INFO,
                    HealthCheckService.CATEGORY_SETTINGS
                )
                .withFix(Label.Giving_HealthCheck_ErrorLogFix, ErrorLogCountSelector.listViewUrl());
        }

        String counted = failures.capped == true
            ? String.format(
                  Label.Giving_HealthCheck_ReceiptFailedMoreThan,
                  new List<Object>{ failures.count.format() }
              )
            : String.valueOf(failures.count);
        List<Object> count = new List<Object>{ counted };
        return new HealthCheckService.Finding(
                'receipt_generation_failed',
                String.format(Label.Giving_HealthCheck_ReceiptFailedManyTitle, count),
                String.format(Label.Giving_HealthCheck_ReceiptFailedManyDetail, count),
                HealthCheckService.SEVERITY_WARNING,
                HealthCheckService.CATEGORY_SETTINGS
            )
            .withFix(Label.Giving_HealthCheck_ErrorLogFix, ErrorLogCountSelector.listViewUrl());
    }

    /**
     * Anyone holding the receipt lock override, by name (ADR-0024). Naming them is the point:
     * an administrator cannot take a permission away from "somebody". Salesforce shows a
     * person only their own access, which is why this is asked only of an administrator.
     */
    private static HealthCheckService.Finding overrideReceiptLockFinding() {
        CustomPermissionSelector.Holders holders = holdersOverride != null
            ? holdersOverride
            : CustomPermissionSelector.holders(GiftService.OVERRIDE_RECEIPT_LOCK_PERMISSION);
        if (holders == null || holders.readable != true || holders.total <= 0) {
            return null;
        }

        String detail = String.format(
            Label.Giving_HealthCheck_OverrideLockDetail,
            new List<Object>{ holderList(holders) }
        );
        return new HealthCheckService.Finding(
                'override_receipt_lock',
                Label.Giving_HealthCheck_OverrideLockTitle,
                detail,
                HealthCheckService.SEVERITY_WARNING,
                HealthCheckService.CATEGORY_ACCESS
            )
            .withFix(
                Label.Giving_HealthCheck_OverrideLockFix,
                HealthCheckService.FIX_CUSTOM_PERMISSIONS_URL
            );
    }

    /**
     * The holders as a sentence: the first few by name, then a count of the rest, so an org
     * that has granted the permission to a whole profile still produces a readable line.
     */
    private static String holderList(CustomPermissionSelector.Holders holders) {
        List<String> parts = new List<String>(holders.names);
        Integer unnamed = holders.total - holders.names.size();
        if (unnamed > 0) {
            parts.add(
                String.format(
                    Label.Giving_HealthCheck_OverrideLockMoreNames,
                    new List<Object>{ String.valueOf(unnamed) }
                )
            );
        }
        return String.join(parts, ', ');
    }

    /**
     * Gifts in the books, dated on or before Books Closed Through, that nothing has marked
     * posted (G-20 follow-up). They are already locked by the period, so nothing about them
     * can change until they are posted or the period is reopened; a bookkeeper who closed the
     * month without exporting and marking every gift is the ordinary way this happens.
     */
    private static HealthCheckService.Finding unpostedClosedPeriodFinding() {
        Date closed = GiftPostingLock.closedThrough();
        if (closed == null) {
            return null;
        }
        Integer count = HealthCheckGivingSelector.countUnpostedInClosedPeriod(closed, countCap + 1);
        if (count == null || count <= 0) {
            return null;
        }
        List<Gift__c> first = HealthCheckGivingSelector.unpostedInClosedPeriod(closed, LINKS_SHOWN);

        String counted = count > countCap
            ? String.format(
                  Label.Giving_HealthCheck_UnpostedClosedPeriodMoreThan,
                  new List<Object>{ countCap.format() }
              )
            : count.format();

        String text = Label.Giving_HealthCheck_UnpostedClosedPeriodDetail;
        if (!first.isEmpty()) {
            text +=
                ' ' +
                String.format(
                    Label.Giving_HealthCheck_UnpostedClosedPeriodFirstListed,
                    new List<Object>{ String.valueOf(first.size()) }
                );
        }

        List<HealthCheckService.Link> links = new List<HealthCheckService.Link>();
        for (Gift__c gift : first) {
            links.add(new HealthCheckService.Link(gift));
        }

        return new HealthCheckService.Finding(
                'unposted_gifts_closed_period',
                String.format(
                    Label.Giving_HealthCheck_UnpostedClosedPeriodTitle,
                    new List<Object>{ counted }
                ),
                text,
                HealthCheckService.SEVERITY_WARNING,
                HealthCheckService.CATEGORY_SETTINGS
            )
            .withFix(Label.Giving_HealthCheck_UnpostedClosedPeriodFix, SettingSections.GIVING)
            .withLinks(links);
    }
}
