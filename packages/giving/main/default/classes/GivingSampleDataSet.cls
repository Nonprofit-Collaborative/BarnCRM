/**
 * The parsed and validated Giving sample data payload (C-10): funds, appeals, commitments,
 * gifts with their allocations, hand-entered soft credits, tributes, and asks (G-26).
 *
 * parse() is the only way to build one and it refuses a payload that is missing what the
 * loader needs, rather than letting a null reach an insert and surface as "Attempt to
 * de-reference a null object". The static resource is generated, so this guards the
 * hand-edited, truncated, or half-regenerated copy.
 *
 * Dates in the payload are day offsets rather than calendar dates: see dateFor().
 */
public with sharing class GivingSampleDataSet {
    /** Funds, in file order. */
    public final List<Map<String, Object>> funds;

    /** Appeals, in file order; a child appeal names its parent by key. */
    public final List<Map<String, Object>> appeals;

    /** Pledges and recurring commitments, in file order. */
    public final List<Map<String, Object>> commitments;

    /** Gifts, in file order, each carrying its own allocations. */
    public final List<Map<String, Object>> gifts;

    /** Tributes, each naming the gift it belongs to. */
    public final List<Map<String, Object>> tributes;

    /** Soft credits staff would have entered by hand, each naming its gift. */
    public final List<Map<String, Object>> softCredits;

    /** Asks in the solicitation pipeline (G-26), each naming its donor; optional. */
    public List<Map<String, Object>> asks { get; private set; }

    private GivingSampleDataSet(
        List<Map<String, Object>> funds,
        List<Map<String, Object>> appeals,
        List<Map<String, Object>> commitments,
        List<Map<String, Object>> gifts,
        List<Map<String, Object>> tributes,
        List<Map<String, Object>> softCredits
    ) {
        this.funds = funds;
        this.appeals = appeals;
        this.commitments = commitments;
        this.gifts = gifts;
        this.tributes = tributes;
        this.softCredits = softCredits;
        this.asks = new List<Map<String, Object>>();
    }

    /**
     * Parses the Giving sample data JSON body. Throws GivingSampleData.SampleDataException
     * when a required list, key, or amount is missing.
     */
    public static GivingSampleDataSet parse(String jsonBody) {
        Map<String, Object> root = parseRoot(jsonBody);
        GivingSampleDataSet data = new GivingSampleDataSet(
            asMapList(root.get('funds')),
            asMapList(root.get('appeals')),
            asMapList(root.get('commitments')),
            asMapList(root.get('gifts')),
            asMapList(root.get('tributes')),
            asMapList(root.get('softCredits'))
        );
        data.asks = asMapList(root.get('asks'));
        data.validate();
        return data;
    }

    private void validate() {
        for (Map<String, Object> fund : funds) {
            requireKey(fund);
            if (String.isBlank(asString(fund.get('name')))) {
                throw invalidData();
            }
        }
        for (Map<String, Object> appeal : appeals) {
            requireKey(appeal);
            if (String.isBlank(asString(appeal.get('name')))) {
                throw invalidData();
            }
        }
        for (Map<String, Object> commitment : commitments) {
            requireKey(commitment);
            if (
                String.isBlank(asString(commitment.get('donor'))) ||
                commitment.get('amount') == null ||
                String.isBlank(asString(commitment.get('type')))
            ) {
                throw invalidData();
            }
        }
        for (Map<String, Object> gift : gifts) {
            requireKey(gift);
            if (
                String.isBlank(asString(gift.get('donor'))) ||
                gift.get('amount') == null ||
                gift.get('daysAgo') == null
            ) {
                throw invalidData();
            }
        }
        for (Map<String, Object> tribute : tributes) {
            if (String.isBlank(asString(tribute.get('gift')))) {
                throw invalidData();
            }
        }
        for (Map<String, Object> credit : softCredits) {
            if (String.isBlank(asString(credit.get('gift')))) {
                throw invalidData();
            }
        }
        for (Map<String, Object> ask : asks) {
            requireKey(ask);
            if (String.isBlank(asString(ask.get('donor')))) {
                throw invalidData();
            }
        }
    }

    /** How many gift chunks the payload needs, at GivingSampleData.GIFT_CHUNK_SIZE each. */
    public Integer chunkCount() {
        if (gifts.isEmpty()) {
            return 0;
        }
        Integer size = GivingSampleData.GIFT_CHUNK_SIZE;
        return (gifts.size() + size - 1) / size;
    }

    /** The gifts of one zero-based chunk; an empty list past the last chunk. */
    public List<Map<String, Object>> giftsInChunk(Integer chunkIndex) {
        List<Map<String, Object>> chunk = new List<Map<String, Object>>();
        if (chunkIndex == null || chunkIndex < 0) {
            return chunk;
        }
        Integer size = GivingSampleData.GIFT_CHUNK_SIZE;
        Integer stop = Math.min(chunkIndex * size + size, gifts.size());
        for (Integer index = chunkIndex * size; index < stop; index++) {
            chunk.add(gifts[index]);
        }
        return chunk;
    }

    /** The tributes and soft credits belonging to a set of gift keys. */
    public List<Map<String, Object>> tributesFor(Set<String> giftKeys) {
        return rowsFor(tributes, giftKeys);
    }

    public List<Map<String, Object>> softCreditsFor(Set<String> giftKeys) {
        return rowsFor(softCredits, giftKeys);
    }

    private static List<Map<String, Object>> rowsFor(
        List<Map<String, Object>> rows,
        Set<String> giftKeys
    ) {
        List<Map<String, Object>> matching = new List<Map<String, Object>>();
        for (Map<String, Object> row : rows) {
            if (giftKeys.contains(asString(row.get('gift')))) {
                matching.add(row);
            }
        }
        return matching;
    }

    /**
     * A payload offset as a real date: the day the set is loaded, less that many days.
     *
     * The offsets are what keep the set honest over time. A file of fixed dates loaded a
     * year from now would show an empty current year on every rollup and dashboard.
     */
    public static Date dateFor(Object daysAgo) {
        if (daysAgo == null) {
            return null;
        }
        return Date.today().addDays(-toInteger(daysAgo));
    }

    public static Integer toInteger(Object value) {
        if (value == null) {
            return null;
        }
        return value instanceof Integer ? (Integer) value : Integer.valueOf(String.valueOf(value));
    }

    public static Decimal toDecimal(Object value) {
        if (value == null) {
            return null;
        }
        return value instanceof Decimal ? (Decimal) value : Decimal.valueOf(String.valueOf(value));
    }

    public static String asString(Object value) {
        return value instanceof String ? (String) value : null;
    }

    private static void requireKey(Map<String, Object> row) {
        if (String.isBlank(asString(row.get('key')))) {
            throw invalidData();
        }
    }

    private static Map<String, Object> parseRoot(String jsonBody) {
        if (String.isBlank(jsonBody)) {
            throw invalidData();
        }
        Object parsed;
        try {
            parsed = JSON.deserializeUntyped(jsonBody);
        } catch (Exception unparseable) {
            throw invalidData();
        }
        if (!(parsed instanceof Map<String, Object>)) {
            throw invalidData();
        }
        return (Map<String, Object>) parsed;
    }

    private static List<Map<String, Object>> asMapList(Object value) {
        if (value == null) {
            return new List<Map<String, Object>>();
        }
        if (!(value instanceof List<Object>)) {
            throw invalidData();
        }
        List<Map<String, Object>> result = new List<Map<String, Object>>();
        for (Object entry : (List<Object>) value) {
            if (!(entry instanceof Map<String, Object>)) {
                throw invalidData();
            }
            result.add((Map<String, Object>) entry);
        }
        return result;
    }

    public static List<Map<String, Object>> allocationsOf(Map<String, Object> gift) {
        return asMapList(gift.get('allocations'));
    }

    private static GivingSampleData.SampleDataException invalidData() {
        return new GivingSampleData.SampleDataException(
            System.Label.Giving_SampleData_ErrorInvalidData
        );
    }
}
