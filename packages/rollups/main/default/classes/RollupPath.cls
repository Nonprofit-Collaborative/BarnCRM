/**
 * The Relationship Path notation of canonical model R-R1, read.
 *
 * A path is a sequence of segments separated by ` > `. Each segment is either a reference
 * attribute on the entity reached so far, or one of the two mode-resolved tokens `{Household}`
 * and `{HouseholdMembers}`. Alternatives are separated by ` | ` and are tried in order.
 *
 * Two facts decide the shape of this class.
 *
 * 1. The mode-resolved tokens are not relationships. In contact mode `{Household}` happens to be
 *    `Account` on a Contact, but in junction mode it is a row on `Household_Member__c` and no
 *    single relationship path exists at all (ADR-0015). So a path holding a token is resolved by
 *    `HouseholdService` (`RollupChanges` when marking targets, `RollupAggregator` when
 *    calculating) rather than as a relationship the engine walks itself. `HouseholdService`
 *    stays the only class that knows which membership mode is in use (plan Section 4.6).
 * 2. Everything else is a relationship the engine can walk. One reference attribute is a plain
 *    lookup; two or more are a grandparent path, which the engine expresses as a dot-separated
 *    chain ending in the attribute on the ultimate parent.
 *
 * Nothing here reads `Contact.AccountId` or `Household_Member__c`, and no packaged definition
 * names a person account attribute in metadata, so the same definition is correct in both modes
 * and on both org shapes.
 */
public with sharing class RollupPath {
    /** Raised when a path cannot be read. */
    public class RollupPathException extends Exception {
    }

    public static final String TOKEN_HOUSEHOLD = '{Household}';
    public static final String TOKEN_HOUSEHOLD_MEMBERS = '{HouseholdMembers}';

    private static final String ALTERNATIVE_SEPARATOR = '|';
    private static final String SEGMENT_SEPARATOR = '>';
    private static final Pattern REFERENCE_SEGMENT = Pattern.compile('^[A-Za-z][A-Za-z0-9_]*$');

    /** One alternative of a path: the segments to walk, in order. */
    public class Branch {
        public List<String> segments = new List<String>();

        /** True when any segment is a mode-resolved token, so the engine cannot walk this alone. */
        public Boolean needsHouseholdResolution() {
            for (String segment : this.segments) {
                if (isToken(segment)) {
                    return true;
                }
            }
            return false;
        }

        /**
         * The reference attributes before the first mode-resolved token. In `Donor_Contact__c >
         * {Household}` that is the one attribute that reaches the person, which is what has to be
         * read off a source record before `HouseholdService` can take over.
         */
        public List<String> referencePrefix() {
            List<String> prefix = new List<String>();
            for (String segment : this.segments) {
                if (isToken(segment)) {
                    return prefix;
                }
                prefix.add(segment);
            }
            return prefix;
        }
    }

    /** A whole path: its alternatives, in the order they are tried. */
    public class Parsed {
        public List<Branch> branches = new List<Branch>();

        public Boolean needsHouseholdResolution() {
            for (Branch branch : this.branches) {
                if (branch.needsHouseholdResolution()) {
                    return true;
                }
            }
            return false;
        }
    }

    public static Boolean isToken(String segment) {
        return TOKEN_HOUSEHOLD.equalsIgnoreCase(segment) ||
            TOKEN_HOUSEHOLD_MEMBERS.equalsIgnoreCase(segment);
    }

    /**
     * Reads a path, refusing anything that is not a reference attribute or a known token so that
     * nothing an administrator can type reaches a query as a relationship name.
     */
    public static Parsed parse(String path) {
        if (String.isBlank(path)) {
            throw new RollupPathException(System.Label.Core_Rollups_ErrorInvalidFilter);
        }
        Parsed parsed = new Parsed();
        for (String rawBranch : path.split('\\' + ALTERNATIVE_SEPARATOR)) {
            String trimmedBranch = rawBranch.trim();
            if (String.isBlank(trimmedBranch)) {
                continue;
            }
            Branch branch = new Branch();
            for (String rawSegment : trimmedBranch.split(SEGMENT_SEPARATOR)) {
                String segment = rawSegment.trim();
                if (String.isBlank(segment)) {
                    continue;
                }
                if (!isToken(segment) && !REFERENCE_SEGMENT.matcher(segment).matches()) {
                    throw new RollupPathException(System.Label.Core_Rollups_ErrorInvalidFilter);
                }
                branch.segments.add(segment);
            }
            if (!branch.segments.isEmpty()) {
                parsed.branches.add(branch);
            }
        }
        if (parsed.branches.isEmpty()) {
            throw new RollupPathException(System.Label.Core_Rollups_ErrorInvalidFilter);
        }
        return parsed;
    }

    /**
     * The relationship name of a reference attribute: a custom one with `__c` replaced by `__r`,
     * a standard one such as `AccountId` without its `Id` suffix.
     */
    public static String relationshipNameFor(String referenceField) {
        if (String.isBlank(referenceField)) {
            return referenceField;
        }
        if (referenceField.endsWith('__c')) {
            return referenceField.removeEnd('__c') + '__r';
        }
        return referenceField.endsWith('Id') && referenceField.length() > 2
            ? referenceField.removeEnd('Id')
            : referenceField;
    }
}
