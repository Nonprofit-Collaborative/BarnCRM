/**
 * Conflicts between BarnCRM's own rollups, said on each row of the rollup list (Rollup Builder
 * ease of use U7, ADR-0136). Saving already refuses a second active rollup that writes the same
 * field for the same records (R-R8), but a pair can still arrive another way: a shipped rollup
 * restored, one switched on from the list, or a record edited outside the Builder. So the list
 * says, for each rollup:
 *
 * - **Overwrites**: it and another active rollup write the same field for the same records, so
 *   each overwrites the other's total;
 * - **Blocked**: it is off, and switching it on would be refused while the other fills that
 *   field for the same records;
 * - **Duplicate**: it calculates exactly what another active rollup calculates, into another
 *   field.
 *
 * Two rollups writing one field for different records (the household and the organization
 * giving totals) are fine and are not listed. Whether two target filters share a record is the
 * same test as the save's: either is blank, they are equal, or a record meets both, which costs
 * a query; at most `QUERIES` such queries are run per list, and a pair beyond that is not listed
 * rather than guessed.
 */
public with sharing class RollupConflicts {
    @TestVisible
    private static final Integer QUERIES = 20;

    private Integer queriesLeft = QUERIES;

    /**
     * Why this rollup cannot be switched on, or null: another active rollup fills its field for
     * the same records (R-R8). The list's Active switch asks it, as the Builder's save does.
     */
    public static String blockerOf(Rollup_Definition__c definition) {
        RollupConflicts checker = new RollupConflicts();
        Schema.SObjectType target = SettingsService.typeByName(definition.Target_Object__c);
        for (Rollup_Definition__c other : RollupSelector.selectAll()) {
            if (
                other.Id != definition.Id &&
                other.Active__c == true &&
                target != null &&
                target == SettingsService.typeByName(other.Target_Object__c) &&
                sameField(definition, other) &&
                checker.overlaps(target, definition, other)
            ) {
                return String.format(
                    Label.Core_RollupEase_ConflictBlocked,
                    new List<String>{ other.Name }
                );
            }
        }
        return null;
    }

    /** What to say about each definition that has a conflict, by its Id. */
    public static Map<Id, List<String>> of(List<Rollup_Definition__c> definitions) {
        return new RollupConflicts().find(definitions);
    }

    private Map<Id, List<String>> find(List<Rollup_Definition__c> definitions) {
        Map<Id, List<String>> found = new Map<Id, List<String>>();
        for (Integer i = 0; i < definitions.size(); i++) {
            for (Integer j = i + 1; j < definitions.size(); j++) {
                compare(definitions[i], definitions[j], found);
            }
        }
        return found;
    }

    private void compare(
        Rollup_Definition__c one,
        Rollup_Definition__c two,
        Map<Id, List<String>> found
    ) {
        if (one.Active__c != true && two.Active__c != true) {
            return;
        }
        Schema.SObjectType target = SettingsService.typeByName(one.Target_Object__c);
        if (target == null || target != SettingsService.typeByName(two.Target_Object__c)) {
            return;
        }
        if (sameField(one, two) && overlaps(target, one, two)) {
            if (one.Active__c == true && two.Active__c == true) {
                add(found, one, Label.Core_RollupEase_ConflictOverwrites, two);
                add(found, two, Label.Core_RollupEase_ConflictOverwrites, one);
            } else if (one.Active__c == true) {
                add(found, two, Label.Core_RollupEase_ConflictBlocked, one);
            } else {
                add(found, one, Label.Core_RollupEase_ConflictBlocked, two);
            }
            return;
        }
        if (one.Active__c == true && two.Active__c == true && sameCalculation(one, two)) {
            add(found, one, Label.Core_RollupEase_ConflictDuplicate, two);
            add(found, two, Label.Core_RollupEase_ConflictDuplicate, one);
        }
    }

    private static Boolean sameField(Rollup_Definition__c one, Rollup_Definition__c two) {
        return String.isNotBlank(one.Target_Field__c) &&
            one.Target_Field__c.equalsIgnoreCase(two.Target_Field__c);
    }

    /** The save's own overlap test (R-R8), within the query budget. */
    private Boolean overlaps(
        Schema.SObjectType target,
        Rollup_Definition__c one,
        Rollup_Definition__c two
    ) {
        String mine;
        String theirs;
        try {
            mine = RollupFilterParser.toWhereClause(one.Target_Filter_JSON__c, target);
            theirs = RollupFilterParser.toWhereClause(two.Target_Filter_JSON__c, target);
        } catch (Exception unreadable) {
            return false;
        }
        if (String.isBlank(mine) || String.isBlank(theirs) || mine == theirs) {
            return true;
        }
        if (this.queriesLeft <= 0) {
            return false;
        }
        this.queriesLeft--;
        // The entity comes from describe and both clauses from RollupFilterParser, which checks
        // every name and escapes every value.
        return Database.countQueryWithBinds(
                'SELECT COUNT() FROM ' +
                    String.valueOf(target) +
                    ' WHERE (' +
                    mine +
                    ') AND (' +
                    theirs +
                    ') LIMIT 1',
                new Map<String, Object>(),
                AccessLevel.USER_MODE
            ) > 0;
    }

    /** Everything that decides the value is the same; only the field written differs. */
    private static Boolean sameCalculation(Rollup_Definition__c one, Rollup_Definition__c two) {
        return same(one.Source_Object__c, two.Source_Object__c) &&
            same(one.Relationship_Path__c, two.Relationship_Path__c) &&
            same(one.Aggregate__c, two.Aggregate__c) &&
            same(one.Source_Field__c, two.Source_Field__c) &&
            same(one.Order_By_Field__c, two.Order_By_Field__c) &&
            same(one.Order_Direction__c, two.Order_Direction__c) &&
            one.Row_Limit__c == two.Row_Limit__c &&
            same(one.Delimiter__c, two.Delimiter__c) &&
            same(one.Custom_Delimiter__c, two.Custom_Delimiter__c) &&
            one.Include_Deleted__c == two.Include_Deleted__c &&
            same(one.Filter_JSON__c, two.Filter_JSON__c) &&
            same(one.Target_Filter_JSON__c, two.Target_Filter_JSON__c) &&
            one.Fiscal_Year_Aware__c == two.Fiscal_Year_Aware__c &&
            one.Fiscal_Year_Offset__c == two.Fiscal_Year_Offset__c &&
            same(one.Fiscal_Date_Field__c, two.Fiscal_Date_Field__c);
    }

    private static Boolean same(String one, String two) {
        return (String.isBlank(one) && String.isBlank(two)) ||
            (one != null && one.equalsIgnoreCase(two));
    }

    private static void add(
        Map<Id, List<String>> found,
        Rollup_Definition__c about,
        String words,
        Rollup_Definition__c other
    ) {
        if (!found.containsKey(about.Id)) {
            found.put(about.Id, new List<String>());
        }
        found.get(about.Id).add(String.format(words, new List<String>{ other.Name }));
    }
}
