/**
 * Automatic column mapping: the headings an organization's file actually carries, and the
 * deliberate refusal to guess at one nobody recognizes.
 */
// runs-as: deploying user (pure logic: matches column headings in memory, no DML or SOQL)
@IsTest
private class ImportColumnLibraryTest {
    @IsTest
    static void recognizesTheUsualHeadings() {
        Assert.areEqual('Contact1.FirstName', ImportColumnLibrary.suggest('First Name'), 'Plain.');
        Assert.areEqual('Contact1.LastName', ImportColumnLibrary.suggest('Surname'), 'A synonym.');
        Assert.areEqual('Contact1.Email', ImportColumnLibrary.suggest('Donor Email'), 'Processor.');
        Assert.areEqual(
            'Organization.Name',
            ImportColumnLibrary.suggest('Company Name'),
            'A business list heading.'
        );
    }

    @IsTest
    static void ignoresSpacingPunctuationAndCase() {
        Assert.areEqual(
            'Contact1.MailingPostalCode',
            ImportColumnLibrary.suggest('  ZIP/Code  '),
            'Spacing, case and punctuation are all normalized away.'
        );
    }

    @IsTest
    static void refusesToGuessAtAnUnknownHeading() {
        Assert.isNull(
            ImportColumnLibrary.suggest('Board seat expiry'),
            'A heading nobody recognizes is left for the administrator, never guessed at.'
        );
    }

    @IsTest
    static void aBlankHeadingSuggestsNothing() {
        Assert.isNull(ImportColumnLibrary.suggest(null), 'A null heading suggests nothing.');
        Assert.isNull(ImportColumnLibrary.suggest('   '), 'Nor does a blank one.');
    }

    @IsTest
    static void suggestsAWholeMappingAndKeepsEveryColumn() {
        ImportMapping mapping = ImportColumnLibrary.suggestMapping(
            new List<String>{ 'First Name', 'Last Name', 'Email', 'Board seat expiry' }
        );
        Assert.areEqual(4, mapping.columns.size(), 'Every column in the file is offered.');
        Assert.areEqual(
            ImportMapping.TARGET_IGNORE,
            mapping.columns[3].target,
            'The one nobody recognizes is set to load nothing, so it is visible in the picker.'
        );
        Assert.isTrue(mapping.identifiesSomebody(), 'The rest is enough to identify a person.');
    }

    @IsTest
    static void aSecondColumnSuggestingTheSameTargetIsLeftUnmapped() {
        ImportMapping mapping = ImportColumnLibrary.suggestMapping(
            new List<String>{ 'Email', 'Email Address' }
        );
        Assert.areEqual('Contact1.Email', mapping.columns[0].target, 'The first column wins.');
        Assert.areEqual(
            ImportMapping.TARGET_IGNORE,
            mapping.columns[1].target,
            'The second is left for the administrator rather than silently overwriting the first.'
        );
    }

    @IsTest
    static void suggestsGiftColumnsSoThePickerCanNameThem() {
        Assert.areEqual(
            'Gift.Amount__c',
            ImportColumnLibrary.suggest('Gift Amount'),
            'A gift column is recognized even though Core does not load it.'
        );
    }

    @IsTest
    static void aNullHeaderListIsAnEmptyMapping() {
        Assert.isTrue(
            ImportColumnLibrary.suggestMapping(null).columns.isEmpty(),
            'No headers, no mapping, no exception.'
        );
    }
}
