/**
 * The package owned counter that hands out receipt numbers (ADR-0016, canonical model 25B).
 *
 * Not a Salesforce auto-number, for three reasons that all matter to an auditor: an auto-number
 * cannot carry an organization's own prefix, cannot restart per statement year, and cannot be read
 * back, so there would be no way to ask which numbers have been consumed.
 *
 * **A number is consumed once and never reused.** Gaplessness is not attempted at the database
 * level, because a transaction that rolls back cannot un-consume a number another transaction has
 * already moved past, and a design that pretends otherwise produces two receipts carrying the same
 * number, which is the one outcome nobody can recover from. Instead every consumed number is
 * accounted for: `reconcile` records any number with no surviving receipt as a Void receipt with
 * the reason "Generation failed", so an auditor asking what happened to number N gets a record
 * rather than silence (R-RC2, R-RC3).
 *
 * **The two series are accounted for by different mechanisms, and only one of them is
 * `reconcile`.** The statement series is reconciled by `ReceiptStatementBatch.finish`, which is
 * the only caller of `reconcile` there is. The per gift series has no reconciliation pass at all:
 * it is accounted for by being all or nothing inside one transaction, which is an invariant its
 * callers have to keep. See `allocateOne` and `ReceiptService.issueForGift`.
 *
 * `without sharing` under ADR-0021: the sequence is package owned data that no permission set
 * grants anyone write access to. See `ReceiptWriter` for the conditions this meets.
 */
public without sharing class ReceiptNumberSequence {
    public static final String TYPE_PER_GIFT = 'Per gift';
    public static final String TYPE_STATEMENT = 'Consolidated statement';

    /** The reason a reconciled number carries, quoted in the admin guide and in ADR-0016. */
    public static final String VOID_REASON_GENERATION_FAILED = 'Generation failed';

    private static final Integer COUNTER_DIGITS = 6;
    private static final String DEFAULT_PREFIX = 'R';

    public class ReceiptNumberSequenceException extends Exception {
    }

    /**
     * The series a receipt of this type and year is numbered from. A series is a receipt type
     * plus a statement year, so per gift receipts and year end statements never interleave and a
     * new year starts at the organization's chosen counter.
     */
    public static String seriesKeyFor(String receiptType, Integer statementYear) {
        if (String.isBlank(receiptType) || statementYear == null) {
            throw new ReceiptNumberSequenceException(Label.Giving_Receipt_SeriesIncomplete);
        }
        return receiptType + '-' + String.valueOf(statementYear);
    }

    /**
     * Consumes a block of numbers and returns them in order.
     *
     * One `FOR UPDATE` select, one update, whatever the size of the block: a batch chunk takes its
     * twenty five numbers in a single round trip rather than locking the row twenty five times.
     *
     * **The lock is held until the transaction ends, not until this method returns.** An Apex
     * `FOR UPDATE` row lock is released at commit or rollback, so every caller holds the sequence
     * row for the rest of its request: `ReceiptService.issueForGift` holds it through rendering,
     * the `ContentVersion` insert and the gift update, and `ReceiptStatementBatch` holds it while
     * a chunk renders and stores twenty five documents. Uniqueness is not at risk, which is what
     * the lock is for. Throughput is: two people issuing receipts at the same moment serialize for
     * the whole request, and the second sees `UNABLE_TO_LOCK_ROW` after ten seconds. Taking a
     * block per chunk is still worth it, because it makes that one wait per chunk rather than one
     * per document, but it does not make the wait short.
     *
     * Allocating, committing, and only then rendering would remove the contention. It is a design
     * change, not a tuning knob: a committed allocation whose document then fails leaves a number
     * that only a reconciliation pass can account for, and the per gift series has no such pass
     * (see `reconcile`). ADR-0016 records it as an open item for the v0.4 performance baseline,
     * which is where the contention can actually be measured.
     */
    public static List<String> allocate(
        String receiptType,
        Integer statementYear,
        Integer howMany
    ) {
        if (howMany == null || howMany < 1) {
            return new List<String>();
        }
        String key = seriesKeyFor(receiptType, statementYear);
        Receipt_Number_Sequence__c series = lockSeries(key);
        if (series == null) {
            createSeries(key, receiptType, statementYear);
            series = lockSeries(key);
        }
        if (series == null) {
            throw new ReceiptNumberSequenceException(Label.Giving_Receipt_SeriesUnavailable);
        }

        Integer first = series.Next_Counter__c.intValue();
        series.Next_Counter__c = first + howMany;
        ReceiptWriter.updateSequence(series);

        List<String> numbers = new List<String>();
        for (Integer offset = 0; offset < howMany; offset++) {
            numbers.add(format(series.Prefix__c, statementYear, first + offset));
        }
        return numbers;
    }

    /**
     * One number, for a person issuing one receipt from a gift.
     *
     * **The caller must be all or nothing in one transaction.** Nothing reconciles the per gift
     * series: `reconcile` is called from `ReceiptStatementBatch.finish` for the statement series
     * and from nowhere else, and `ReceiptGenerationFailureSelector`, which Health Check reads,
     * counts only the records `reconcile` wrote. So a number taken here is accounted for by the
     * receipt insert happening in the same transaction and by the whole transaction rolling back
     * when anything fails. A caller that catches the failure and commits anyway consumes a number
     * that no pass will ever explain, and the Health Check will report zero. If a bulk action, an
     * async retry wrapper, or an allocate-commit-render redesign ever needs to swallow a failure,
     * a per gift reconciliation pass has to be built first (ADR-0016, "Numbering").
     */
    public static String allocateOne(String receiptType, Integer statementYear) {
        return allocate(receiptType, statementYear, 1)[0];
    }

    /**
     * `{prefix}-{statement year}-{counter zero padded to six digits}` (R-RS2). The shape is fixed
     * on purpose: a receipt number that changes shape mid year is a number nobody can follow.
     */
    public static String format(String prefix, Integer statementYear, Integer counter) {
        String padded = String.valueOf(counter);
        while (padded.length() < COUNTER_DIGITS) {
            padded = '0' + padded;
        }
        return (String.isBlank(prefix) ? DEFAULT_PREFIX : prefix.trim()) +
            '-' +
            String.valueOf(statementYear) +
            '-' +
            padded;
    }

    /**
     * Accounts for every number this series has consumed (R-RC3).
     *
     * Walks the consumed range, which is First Counter up to but not including Next Counter,
     * subtracts the numbers a surviving receipt carries, and writes what is left as Void receipts
     * with the reason "Generation failed". Nothing is reissued and no number is handed out again:
     * this step exists to answer a question, not to close a gap.
     *
     * Returns how many numbers it had to account for, which is normally zero.
     *
     * It accounts for the series it is given and no other. `ReceiptStatementBatch.finish` is its
     * only caller, so today only the statement series is reconciled; the per gift series relies on
     * the transactional invariant `allocateOne` states.
     */
    public static Integer reconcile(String receiptType, Integer statementYear, Id runId) {
        String key = seriesKeyFor(receiptType, statementYear);
        Receipt_Number_Sequence__c series = readSeries(key);
        if (series == null || series.Next_Counter__c <= series.First_Counter__c) {
            return 0;
        }

        Set<String> issued = new Set<String>();
        for (Receipt__c receipt : ReceiptSelector.numbersInSeries(key)) {
            issued.add(receipt.Receipt_Number__c);
        }

        List<Receipt__c> missing = new List<Receipt__c>();
        Integer first = series.First_Counter__c.intValue();
        Integer beyond = series.Next_Counter__c.intValue();
        for (Integer counter = first; counter < beyond; counter++) {
            String candidate = format(series.Prefix__c, statementYear, counter);
            if (issued.contains(candidate)) {
                continue;
            }
            missing.add(
                new Receipt__c(
                    Receipt_Number__c = candidate,
                    Type__c = receiptType,
                    Status__c = ReceiptService.STATUS_VOID,
                    Statement_Year__c = statementYear,
                    Series_Key__c = key,
                    Issue_Date__c = Date.today(),
                    Total_Amount__c = 0,
                    Void_Reason__c = VOID_REASON_GENERATION_FAILED,
                    Voided_On__c = System.now(),
                    Receipt_Run__c = runId
                )
            );
        }
        ReceiptWriter.insertReceipts(missing);
        return missing.size();
    }

    // ------------------------------------------------------------------------ internals

    /**
     * The series row, locked. `FOR UPDATE` is the whole mechanism: two runs that ask for numbers
     * at the same moment queue rather than both reading the same counter.
     */
    private static Receipt_Number_Sequence__c lockSeries(String key) {
        List<Receipt_Number_Sequence__c> rows = [
            SELECT Id, Series_Key__c, Prefix__c, First_Counter__c, Next_Counter__c
            FROM Receipt_Number_Sequence__c
            WHERE Series_Key__c = :key
            WITH SYSTEM_MODE
            LIMIT 1
            FOR UPDATE
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    private static Receipt_Number_Sequence__c readSeries(String key) {
        List<Receipt_Number_Sequence__c> rows = [
            SELECT Id, Series_Key__c, Prefix__c, First_Counter__c, Next_Counter__c
            FROM Receipt_Number_Sequence__c
            WHERE Series_Key__c = :key
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    /**
     * A series is created the first time a number is asked for, taking the prefix and the starting
     * counter the organization set. It keeps them afterwards: changing the setting later starts the
     * next year's series differently and leaves this one alone, which is what the admin guide says
     * and what stops a mid year settings edit renumbering documents donors already hold.
     */
    private static void createSeries(String key, String receiptType, Integer statementYear) {
        Giving_Settings__c settings = Giving_Settings__c.getOrgDefaults();
        String prefix = String.isBlank(settings.Receipt_Number_Prefix__c)
            ? DEFAULT_PREFIX
            : settings.Receipt_Number_Prefix__c.trim();
        Integer start = settings.Receipt_Next_Counter__c == null
            ? 1
            : Math.max(1, settings.Receipt_Next_Counter__c.intValue());
        try {
            ReceiptWriter.insertSequence(
                new Receipt_Number_Sequence__c(
                    Name = key,
                    Series_Key__c = key,
                    Receipt_Type__c = receiptType,
                    Statement_Year__c = statementYear,
                    Prefix__c = prefix,
                    First_Counter__c = start,
                    Next_Counter__c = start
                )
            );
        } catch (DmlException duplicate) {
            // Two transactions can reach here at once; the unique external id decides which one
            // wins and the loser simply reads what the winner created. This is not an error path.
            ErrorLogger.logMessage(
                'Receipt number series ' + key + ' was created concurrently.',
                'ReceiptNumberSequence',
                ErrorLogger.SEVERITY_INFO
            );
        }
    }
}
