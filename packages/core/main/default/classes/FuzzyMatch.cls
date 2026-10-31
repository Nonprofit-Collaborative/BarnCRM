/**
 * The one fuzzy string scorer BarnCRM uses (C-51, ADR-0145 advanced duplicate management):
 * the duplicate scan scores people's names with it (R-DP7) and the importer's header matching
 * (C-49e) scores column headers with it, so both agree on what "alike" means.
 *
 * A value is normalized first (lower case, punctuation turned into spaces, spacing collapsed),
 * then two values are scored from 0 (nothing alike) to 1 (the same): 1 when the normalized
 * values are equal, or equal once their spaces are removed ("FirstName" and "First Name",
 * "O'Brien" and "OBrien"); otherwise their Jaro-Winkler similarity, which rewards characters
 * in common, in order, and most of all a shared start.
 *
 * It reads no data and holds no state.
 */
public inherited sharing class FuzzyMatch {
    /** Jaro-Winkler's standard weight for a shared start, and the longest start it counts. */
    private static final Double PREFIX_WEIGHT = 0.1;
    private static final Integer MAX_PREFIX = 4;

    /** Lower case, every run of characters that is not a letter or a digit as one space. */
    public static String normalize(String value) {
        if (value == null) {
            return '';
        }
        return value.toLowerCase().replaceAll('[^\\p{L}\\p{N}]+', ' ').normalizeSpace();
    }

    /** How alike two values are, from 0 to 1, after normalizing both; 0 when either is blank. */
    public static Double score(String first, String second) {
        String a = normalize(first);
        String b = normalize(second);
        if (String.isEmpty(a) || String.isEmpty(b)) {
            return 0;
        }
        if (a.equals(b) || a.deleteWhitespace().equals(b.deleteWhitespace())) {
            return 1;
        }
        return jaroWinkler(a, b);
    }

    /** True when the two values score at or above the threshold (0 to 1). */
    public static Boolean matches(String first, String second, Double threshold) {
        return score(first, second) >= threshold;
    }

    /**
     * The candidate most like the value, scoring at or above the threshold (0 to 1), or null.
     * On a tie the earlier candidate wins, so the caller's order decides.
     */
    public static String bestMatch(String value, List<String> candidates, Double threshold) {
        String best;
        Double bestScore = -1;
        if (candidates == null) {
            return null;
        }
        for (String candidate : candidates) {
            Double candidateScore = score(value, candidate);
            if (candidateScore >= threshold && candidateScore > bestScore) {
                best = candidate;
                bestScore = candidateScore;
            }
        }
        return best;
    }

    /** Jaro-Winkler similarity of the two values exactly as given (case counts). */
    public static Double jaroWinkler(String first, String second) {
        if (String.isEmpty(first) || String.isEmpty(second)) {
            return 0;
        }
        if (first.equals(second)) {
            return 1;
        }
        Double jaro = jaro(first.getChars(), second.getChars());
        Integer prefix = 0;
        Integer shorter = Math.min(MAX_PREFIX, Math.min(first.length(), second.length()));
        while (prefix < shorter && first.charAt(prefix) == second.charAt(prefix)) {
            prefix++;
        }
        return jaro + prefix * PREFIX_WEIGHT * (1 - jaro);
    }

    private static Double jaro(List<Integer> s, List<Integer> t) {
        Integer window = Math.max(0, Math.max(s.size(), t.size()) / 2 - 1);
        List<Boolean> sMatched = falses(s.size());
        List<Boolean> tMatched = falses(t.size());
        Integer matches = 0;
        for (Integer i = 0; i < s.size(); i++) {
            Integer last = Math.min(t.size() - 1, i + window);
            for (Integer j = Math.max(0, i - window); j <= last; j++) {
                if (!tMatched[j] && s[i] == t[j]) {
                    sMatched[i] = true;
                    tMatched[j] = true;
                    matches++;
                    break;
                }
            }
        }
        if (matches == 0) {
            return 0;
        }
        Double halfTranspositions = 0;
        Integer k = 0;
        for (Integer i = 0; i < s.size(); i++) {
            if (!sMatched[i]) {
                continue;
            }
            while (!tMatched[k]) {
                k++;
            }
            if (s[i] != t[k]) {
                halfTranspositions += 1;
            }
            k++;
        }
        Double m = matches;
        return (m / s.size() + m / t.size() + (m - halfTranspositions / 2) / m) / 3;
    }

    private static List<Boolean> falses(Integer size) {
        List<Boolean> result = new List<Boolean>();
        for (Integer i = 0; i < size; i++) {
            result.add(false);
        }
        return result;
    }
}
