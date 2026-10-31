/**
 * The shared fuzzy scorer (C-51): normalization, Jaro-Winkler against published values, and
 * the best-match pick the importer's header matching reuses.
 */
// runs-as: deploying user (pure logic: scores strings, no DML or SOQL)
@IsTest(testFor='ApexClass:FuzzyMatch')
private class FuzzyMatchTest {
    private static final Double TOLERANCE = 0.001;

    private static void assertNear(Double expected, Double actual) {
        Assert.isTrue(Math.abs(expected - actual) < TOLERANCE, expected + ' expected, ' + actual);
    }

    @IsTest
    static void normalizeFoldsCaseSpacingAndPunctuation() {
        Assert.areEqual('mary jo smith', FuzzyMatch.normalize('  Mary-Jo   SMITH. '));
        Assert.areEqual('first name', FuzzyMatch.normalize('First_Name'));
        Assert.areEqual('', FuzzyMatch.normalize(null), 'Null reads as empty.');
        Assert.areEqual('', FuzzyMatch.normalize(' - . '), 'Punctuation alone reads as empty.');
    }

    @IsTest
    static void jaroWinklerMatchesPublishedValues() {
        assertNear(0.961, FuzzyMatch.jaroWinkler('MARTHA', 'MARHTA'));
        assertNear(0.840, FuzzyMatch.jaroWinkler('DWAYNE', 'DUANE'));
        assertNear(0.813, FuzzyMatch.jaroWinkler('DIXON', 'DICKSONX'));
        Assert.areEqual(1, FuzzyMatch.jaroWinkler('same', 'same'));
        Assert.areEqual(0, FuzzyMatch.jaroWinkler('abc', 'xyz'), 'Nothing in common scores 0.');
        Assert.areEqual(0, FuzzyMatch.jaroWinkler('', 'abc'));
        Assert.areEqual(0, FuzzyMatch.jaroWinkler(null, 'abc'));
    }

    @IsTest
    static void scoreIgnoresCaseSpacingAndPunctuation() {
        Assert.areEqual(1, FuzzyMatch.score('First Name', 'first_name'));
        Assert.areEqual(1, FuzzyMatch.score('FirstName', 'First Name'), 'Spaces do not count.');
        Assert.areEqual(1, FuzzyMatch.score('O\'Brien', 'OBrien'));
        Assert.isTrue(FuzzyMatch.score('Jonathan Smith', 'Jonathon Smith') > 0.95);
        Assert.isTrue(FuzzyMatch.score('Jonathan Smith', 'Maria Garcia') < 0.6);
    }

    @IsTest
    static void scoreIsZeroForBlanksAndSymmetric() {
        Assert.areEqual(0, FuzzyMatch.score(null, 'x'));
        Assert.areEqual(0, FuzzyMatch.score('x', '  '));
        Assert.areEqual(
            FuzzyMatch.score('Katherine', 'Catherine'),
            FuzzyMatch.score('Catherine', 'Katherine'),
            'Order does not matter.'
        );
    }

    @IsTest
    static void matchesUsesTheThreshold() {
        Assert.isTrue(FuzzyMatch.matches('Robert Jones', 'Robert  Jones', 1));
        Assert.isTrue(FuzzyMatch.matches('Robert Jones', 'Robret Jones', 0.9));
        Assert.isFalse(FuzzyMatch.matches('Robert Jones', 'Bob Jones', 0.9));
    }

    @IsTest
    static void bestMatchPicksTheClosestAboveTheThreshold() {
        List<String> headers = new List<String>{ 'Email', 'First Name', 'Last Name', 'Phone' };
        Assert.areEqual('First Name', FuzzyMatch.bestMatch('first_name', headers, 0.85));
        Assert.areEqual('Last Name', FuzzyMatch.bestMatch('Lastname', headers, 0.85));
        Assert.areEqual('Email', FuzzyMatch.bestMatch('E-mail', headers, 0.85));
        Assert.isNull(FuzzyMatch.bestMatch('Gift Amount', headers, 0.85), 'Nothing close enough.');
        Assert.isNull(FuzzyMatch.bestMatch('Email', null, 0.5));
        Assert.areEqual(
            'Name',
            FuzzyMatch.bestMatch('name', new List<String>{ 'Name', 'NAME' }, 0.5),
            'A tie goes to the earlier candidate.'
        );
    }

    @IsTest
    static void scoresManyValuesWithinLimits() {
        List<String> candidates = new List<String>();
        for (Integer i = 0; i < 300; i++) {
            candidates.add('Candidate Header ' + i);
        }
        Integer cpuBefore = Limits.getCpuTime();
        Assert.areEqual(
            'Candidate Header 250',
            FuzzyMatch.bestMatch('candidate_header_250', candidates, 0.9)
        );
        Assert.isTrue(Limits.getCpuTime() - cpuBefore < 5000, '300 candidates score quickly.');
    }
}
