/**
 * The adapter ADR-0015 asks for: a BarnCRM rollup expressed to the vendored engine, with the
 * administrator never seeing the engine's own configuration.
 *
 * These tests have not been executed: no Salesforce org exists in this environment, so nothing
 * here has run. They assert the mapping the ADR names, attribute by attribute.
 */
@IsTest
private class RollupAdapterTest {
    private static Rollup_Definition__c givingTotal() {
        return new Rollup_Definition__c(
            Name = 'Household total giving',
            Definition_Key__c = 'Household_Total_Giving',
            Source_Object__c = 'Gift__c',
            Target_Object__c = 'Account',
            Relationship_Path__c = 'Household__c',
            Aggregate__c = 'SUM',
            Source_Field__c = 'Amount__c',
            Target_Field__c = 'Total_Giving__c',
            Mode__c = 'Both',
            Fiscal_Year_Aware__c = false,
            Active__c = true
        );
    }

    @IsTest
    static void everyAttributeGoesWhereTheDecisionSaysItGoes() {
        Rollup__mdt meta = RollupAdapter.toMetadata(givingTotal());

        System.Assert.areEqual('Gift__c', meta.CalcItemText__c, 'Source entity is the calc item');
        System.Assert.areEqual(
            'Account',
            meta.LookupObjectText__c,
            'Target entity is the lookup object'
        );
        System.Assert.areEqual(
            'Household__c',
            meta.LookupFieldOnCalcItemText__c,
            'One hop is a plain lookup'
        );
        System.Assert.areEqual(
            'Id',
            meta.LookupFieldOnLookupObjectText__c,
            'The parent is matched on its id'
        );
        System.Assert.areEqual(
            'Amount__c',
            meta.RollupFieldOnCalcItemText__c,
            'The source attribute is aggregated'
        );
        System.Assert.areEqual(
            'Total_Giving__c',
            meta.RollupFieldOnLookupObjectText__c,
            'The target attribute receives the result'
        );
        System.Assert.areEqual('SUM', meta.RollupOperation__c, 'The aggregate is the operation');
        System.Assert.isTrue(
            meta.ShouldRunWithoutCustomSettingEnabled__c,
            'BarnCRM Active is the switch, not the engine custom setting'
        );
        System.Assert.isFalse(meta.IsDisabled__c, 'An active definition is not disabled');
    }

    /**
     * The engine returns a rollup's default in place of a sum of exactly zero, so a sum with no
     * default left a fully refunded donor's total blank instead of zero (ADR-0022). A count has
     * no such rule, so it keeps no default.
     */
    @IsTest
    static void aSumDefaultsToZeroAndACountDoesNot() {
        Rollup__mdt sum = RollupAdapter.toMetadata(givingTotal());
        System.Assert.areEqual(
            0,
            sum.FullRecalculationDefaultNumberValue__c,
            'A sum of nothing left is zero, which the engine only writes when zero is the default'
        );

        Rollup_Definition__c countDefinition = givingTotal();
        countDefinition.Aggregate__c = 'COUNT';
        Rollup__mdt count = RollupAdapter.toMetadata(countDefinition);
        System.Assert.isNull(
            count.FullRecalculationDefaultNumberValue__c,
            'A count gets no default: only a sum has a rule that says nothing left is zero'
        );
    }

    @IsTest
    static void anAverageBecomesTheOperationTheEngineCallsIt() {
        Rollup_Definition__c definition = givingTotal();
        definition.Aggregate__c = 'AVG';

        System.Assert.areEqual(
            'AVERAGE',
            RollupAdapter.toMetadata(definition).RollupOperation__c,
            'AVG is the only aggregate whose name differs'
        );
    }

    @IsTest
    static void aCountReadsTheRecordItselfRatherThanAnAttribute() {
        Rollup_Definition__c definition = givingTotal();
        definition.Aggregate__c = 'COUNT';
        definition.Source_Field__c = null;
        definition.Target_Field__c = 'Gift_Count__c';

        Rollup__mdt meta = RollupAdapter.toMetadata(definition);

        System.Assert.areEqual('COUNT', meta.RollupOperation__c, 'A count is a count');
        System.Assert.areEqual(
            'Id',
            meta.RollupFieldOnCalcItemText__c,
            'A count reads nothing in particular'
        );
    }

    @IsTest
    static void firstAndLastCarryTheirOrderByAttribute() {
        Rollup_Definition__c definition = givingTotal();
        definition.Aggregate__c = 'FIRST';
        definition.Source_Field__c = 'Amount__c';
        definition.Order_By_Field__c = 'Gift_Date__c';

        Rollup__mdt meta = RollupAdapter.toMetadata(definition);

        System.Assert.areEqual('FIRST', meta.RollupOperation__c, 'First is first');
        System.Assert.areEqual(
            'Gift_Date__c',
            meta.OrderByFirstLast__c,
            'The attribute that decides which record is first travels with it'
        );
    }

    @IsTest
    static void aTwoHopPathBecomesAGrandparentChain() {
        Rollup_Definition__c definition = givingTotal();
        definition.Source_Object__c = 'Gift_Allocation__c';
        definition.Relationship_Path__c = 'Gift__c > Appeal__c';
        definition.Target_Object__c = 'Appeal__c';
        definition.Target_Field__c = 'Total_Raised__c';

        Rollup__mdt meta = RollupAdapter.toMetadata(definition);

        System.Assert.areEqual(
            'Gift__r.Appeal__r.Id',
            meta.GrandparentRelationshipFieldPath__c,
            'Two or more hops are a grandparent chain'
        );
        System.Assert.areEqual(
            'Gift__c',
            meta.LookupFieldOnCalcItemText__c,
            'The first hop is still named'
        );
    }

    @IsTest
    static void mapsTwoHopHouseholdPathInBothMembershipModes() {
        Rollup_Definition__c definition = givingTotal();
        definition.Relationship_Path__c = 'Donor_Contact__c > {Household}';

        SettingsService.saveSystemValue('Household_Membership_Mode__c', 'Contact');
        SettingsService.clearCaches();
        Rollup__mdt contactMode = RollupAdapter.toMetadata(definition);

        SettingsService.saveSystemValue(
            'Household_Membership_Mode__c',
            HouseholdService.MODE_JUNCTION
        );
        SettingsService.clearCaches();
        Rollup__mdt junctionMode = RollupAdapter.toMetadata(definition);

        // The household abstraction is resolved by HouseholdService and handed to the engine as
        // parent ids, so the metadata is the same shape in both modes and the definition an
        // administrator wrote is correct in either (ADR-0015, R-R1).
        for (Rollup__mdt meta : new List<Rollup__mdt>{ contactMode, junctionMode }) {
            System.Assert.isTrue(
                meta.IsRollupStartedFromParent__c,
                'A household path is started from the resolved parent, not walked'
            );
            System.Assert.isNull(
                meta.GrandparentRelationshipFieldPath__c,
                'There is no single relationship to walk in junction mode, so none is claimed in either'
            );
        }
    }

    @IsTest
    static void alternativesWithoutATokenBecomeOneMetadataRecordEach() {
        Rollup_Definition__c definition = givingTotal();
        definition.Relationship_Path__c = 'Household__c | Donor_Account__c';

        List<Rollup__mdt> metadata = RollupAdapter.toMetadata(
            new List<Rollup_Definition__c>{ definition }
        );

        System.Assert.areEqual(2, metadata.size(), 'The engine walks one relationship at a time');
        System.Assert.areEqual(
            'Household__c',
            metadata[0].LookupFieldOnCalcItemText__c,
            'In the order the administrator wrote them'
        );
        System.Assert.areEqual(
            'Donor_Account__c',
            metadata[1].LookupFieldOnCalcItemText__c,
            'Then the second'
        );
    }

    @IsTest
    static void theFilterAndTheFiscalWindowBothReachTheWhereClause() {
        SettingsService.saveSystemValue('Fiscal_Year_Start_Month__c', 1);
        SettingsService.clearCaches();
        RollupDateWindow.todayOverride = Date.newInstance(2026, 5, 1);

        Rollup_Definition__c definition = givingTotal();
        definition.Filter_JSON__c = '{"version": 1, "conditions": [{"id": 1, "field": "Status__c", "operator": "equals", "value": "Received"}]}';
        definition.Fiscal_Year_Aware__c = true;
        definition.Fiscal_Year_Offset__c = -1;
        definition.Fiscal_Date_Field__c = 'Gift_Date__c';

        String clause = RollupAdapter.toMetadata(definition).CalcItemWhereClause__c;

        System.Assert.isTrue(
            clause.contains('Status__c = \'Received\''),
            'The administrator filter is applied'
        );
        System.Assert.isTrue(
            clause.contains('Gift_Date__c >= 2025-01-01'),
            'The window starts last fiscal year'
        );
        System.Assert.isTrue(
            clause.contains('Gift_Date__c < 2026-01-01'),
            'And ends where this one begins'
        );
        System.Assert.isTrue(clause.contains(' AND '), 'Both conditions apply');
    }

    @IsTest
    static void aDefinitionThatCannotBeBuiltIsRefusedRatherThanGuessed() {
        Rollup_Definition__c noAggregate = givingTotal();
        noAggregate.Aggregate__c = 'MEDIAN';
        Integer refusedCount = assertRefused(noAggregate, 'an aggregate the engine does not have')
            ? 1
            : 0;

        Rollup_Definition__c noSourceField = givingTotal();
        noSourceField.Source_Field__c = null;
        refusedCount += assertRefused(noSourceField, 'a sum with nothing to sum') ? 1 : 0;

        Rollup_Definition__c noOrderBy = givingTotal();
        noOrderBy.Aggregate__c = 'LAST';
        refusedCount += assertRefused(noOrderBy, 'a last with no order (R-R10)') ? 1 : 0;

        Rollup_Definition__c noTargetField = givingTotal();
        noTargetField.Target_Field__c = null;
        refusedCount += assertRefused(noTargetField, 'a rollup with nowhere to put the answer')
            ? 1
            : 0;

        System.Assert.areEqual(
            4,
            refusedCount,
            'every unbuildable definition above must be refused'
        );
    }

    /**
     * Asserts that building metadata for the given definition is refused with a message, and
     * returns whether it was, so the calling test method also carries its own assertion on the
     * outcome rather than trusting a shared helper silently.
     */
    private static Boolean assertRefused(Rollup_Definition__c definition, String why) {
        try {
            RollupAdapter.toMetadata(definition);
            System.Assert.fail('Expected a refusal for ' + why);
        } catch (RollupAdapter.RollupAdapterException expected) {
            System.Assert.isNotNull(expected.getMessage(), 'The message names the problem');
            return true;
        }
        return false;
    }
}
