/**
 * How many receipt numbers were consumed by a run that failed (feature C-11, ADR-0016), for
 * the Health Check finding Giving adds to Core's report (ADR-0059).
 *
 * Rule R-RC3: a number whose document never generated is reconciled into a receipt with
 * Status `Void` and Void Reason `Generation failed`, so an auditor asking what happened to
 * number 47 gets a record rather than silence. One of those is ordinary. A growing number of
 * them means receipt generation is failing over and over and nobody has looked.
 *
 * Until C-29 Core took this count as `ReceiptGapSelector`, with dynamic SOQL. `Receipt__c` is
 * Giving's own object, so the count is an ordinary query in user mode: a person who cannot
 * read receipts gets `available = false`, which Health Check reports as no finding rather
 * than as a zero.
 *
 * The count is capped: `COUNT()` counts every matching row against the 50,000-row query limit,
 * and that limit cannot be caught, so an org with a very long failure history would otherwise
 * lose every Giving finding. Past the cap, `capped` is true and `count` is the cap, and the
 * finding says "more than" it, the way `HealthCheckGivingSelector` reports unposted gifts.
 */
public with sharing class ReceiptGenerationFailureSelector {
    /** Injected by the tests, which choose the count rather than creating failed runs. */
    @TestVisible
    private static Result resultOverride;

    /** Counts stop here. A test lowers it. */
    @TestVisible
    private static Integer countCap = 1000;

    /** The count, and whether the running person could take it at all. */
    public class Result {
        public Boolean available;
        public Integer count;
        /** True when more than `count` matched and counting stopped at the cap. */
        public Boolean capped;

        public Result() {
            this.available = false;
            this.count = 0;
            this.capped = false;
        }
    }

    /** How many receipts stand as the record of a number a failed run consumed. */
    public static Result generationFailures() {
        if (resultOverride != null) {
            return resultOverride;
        }
        Result result = new Result();
        Integer rowLimit = countCap + 1;
        try {
            Integer counted = [
                SELECT COUNT()
                FROM Receipt__c
                WHERE
                    Status__c = :ReceiptService.STATUS_VOID
                    AND Void_Reason__c = :ReceiptNumberSequence.VOID_REASON_GENERATION_FAILED
                WITH USER_MODE
                LIMIT :rowLimit
            ];
            result.available = true;
            result.capped = counted > countCap;
            result.count = result.capped ? countCap : counted;
        } catch (System.SecurityException cannotRead) {
            // A user-mode static query without object access throws this, not a QueryException.
            result.available = false;
            result.count = 0;
        } catch (QueryException cannotRead) {
            result.available = false;
            result.count = 0;
        }
        return result;
    }
}
