/**
 * DLRS rollups for tests. DLRS cannot be installed in a test, so a test hands `RollupDlrs` rows
 * shaped like DLRS's through its reader seam, built with the same `fromValues` the org reader
 * uses (canonical model R-R16).
 */
@IsTest
public class RollupDlrsFake implements RollupDlrs.Reader {
    private List<RollupDlrs.Definition> rows;

    private RollupDlrsFake(List<RollupDlrs.Definition> rows) {
        this.rows = rows;
    }

    public List<RollupDlrs.Definition> read() {
        return rows;
    }

    /** Makes `RollupDlrs` read these rows from now on in this test. */
    public static void use(List<RollupDlrs.Definition> rows) {
        RollupDlrs.reader = new RollupDlrsFake(rows);
        RollupDlrs.reset();
    }

    /** A DLRS custom metadata rollup from its field values, named without the namespace. */
    public static RollupDlrs.Definition rollup(String developerName, Map<String, Object> values) {
        return RollupDlrs.fromValues(
            developerName,
            developerName.replace('_', ' '),
            RollupDlrs.SOURCE_METADATA,
            values
        );
    }

    /** An active DLRS Count rollup on this field, counting child accounts. */
    public static RollupDlrs.Definition activeOn(String parentObject, String field) {
        return rollup(
            'Child_Count',
            new Map<String, Object>{
                'Active__c' => true,
                'ParentObject__c' => parentObject,
                'ChildObject__c' => 'Account',
                'RelationshipField__c' => 'ParentId',
                'AggregateOperation__c' => 'Count',
                'AggregateResultField__c' => field
            }
        );
    }
}
