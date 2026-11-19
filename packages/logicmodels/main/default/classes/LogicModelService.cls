/**
 * The Logic Model Builder's reads and writes (L-01, L-02; canonical model Sections 29ZC to 29ZG),
 * as plain JSON shapes so the same builder could call a WordPress endpoint (plan 9.9). Every query
 * and every write runs in user mode: the builder shows and changes only what the user may.
 *
 * The rules the platform enforces itself (the chain, R-LL1, R-LL2; indicators on outputs and
 * outcomes, R-IN1; one model per scope, R-LM1) surface as the save's own message. This class adds
 * the two the builder owns: one arrow per pair (R-LL3) and one row per period (R-IP2), and deletes
 * an element's arrows before the element (R-LE3).
 */
public with sharing class LogicModelService {
	private static final String PROGRAM_OBJECT = 'Program__c';
	private static final Integer PROGRAM_LIMIT = 500;

	/** Raised with a message the builder shows as it is. */
	public class BuilderException extends Exception {
	}

	// ------------------------------------------------------------------------------- reading

	/**
	 * The whole model as the builder draws it.
	 *
	 * @param modelId the logic model
	 * @return id, name, description, the program, what the user may do, and the elements, links
	 *         and indicators (each indicator with its periods)
	 */
	public static Map<String, Object> read(Id modelId) {
		List<Logic_Model__c> models = [
			SELECT Id, Name, Description__c, Program_Id__c, Periods__c
			FROM Logic_Model__c
			WHERE Id = :modelId
			WITH USER_MODE
		];
		if (models.isEmpty()) {
			throw new BuilderException(
				BarnHelp.text('LogicModels', 'LogicModels_Builder_NotFound')
			);
		}
		Logic_Model__c model = models[0];
		Schema.DescribeSObjectResult elements = Logic_Model_Element__c.SObjectType.getDescribe(
			SObjectDescribeOptions.DEFERRED
		);
		Map<String, Object> result = new Map<String, Object>{
			'id' => model.Id,
			'name' => model.Name,
			'description' => model.Description__c,
			'programId' => model.Program_Id__c,
			'programsAvailable' => programType() != null,
			'canEdit' => elements.isCreateable() && elements.isUpdateable(),
			'canDelete' => elements.isDeletable(),
			'canSetSource' => Schema.SObjectType.Indicator__c.fields.Source__c.isUpdateable(),
			'canRefresh' => Indicator_Period__c.SObjectType.getDescribe(
					SObjectDescribeOptions.DEFERRED
				)
				.isUpdateable(),
			'elements' => elementsOf(modelId),
			'links' => linksOf(modelId),
			'evidenceText' => evidenceText(),
			'indicators' => indicatorsOf(modelId),
			'periods' => LogicModelPeriodService.periodsOf(model.Periods__c),
			'canEditPeriods' => Schema.SObjectType.Logic_Model__c.fields.Periods__c.isUpdateable()
		};
		String programName = programName(model.Program_Id__c);
		result.put('programName', programName);
		result.put('programMissing', model.Program_Id__c != null && programName == null);
		return result;
	}

	private static List<Map<String, Object>> elementsOf(Id modelId) {
		List<Map<String, Object>> rows = new List<Map<String, Object>>();
		for (Logic_Model_Element__c element : [
			SELECT Id, Name, Type__c, Outcome_Term__c, Description__c, Sort_Order__c
			FROM Logic_Model_Element__c
			WHERE Logic_Model__c = :modelId
			WITH USER_MODE
			ORDER BY Sort_Order__c NULLS LAST, CreatedDate
		]) {
			rows.add(
				new Map<String, Object>{
					'id' => element.Id,
					'name' => element.Name,
					'type' => element.Type__c,
					'term' => element.Outcome_Term__c,
					'description' => element.Description__c,
					'sortOrder' => element.Sort_Order__c
				}
			);
		}
		return rows;
	}

	private static List<Map<String, Object>> linksOf(Id modelId) {
		List<Map<String, Object>> rows = new List<Map<String, Object>>();
		for (Logic_Model_Link__c link : [
			SELECT
				Id,
				From_Element__c,
				To_Element__c,
				Assumption__c,
				(
					SELECT Id, Summary__c, Source__c, Source_Url__c, Evidence_Date__c, Strength__c
					FROM Evidence__r
					ORDER BY Evidence_Date__c DESC NULLS LAST, CreatedDate
				)
			FROM Logic_Model_Link__c
			WHERE Logic_Model__c = :modelId
			WITH USER_MODE
			ORDER BY CreatedDate
		]) {
			rows.add(
				new Map<String, Object>{
					'id' => link.Id,
					'fromId' => link.From_Element__c,
					'toId' => link.To_Element__c,
					'assumption' => link.Assumption__c,
					'evidence' => evidenceOf(link.Evidence__r)
				}
			);
		}
		return rows;
	}

	/**
	 * The evidence log's words from the platform's describe, already in the user's language:
	 * the object's name, each field's label and the strengths in the field's order (R-AE2).
	 */
	private static Map<String, Object> evidenceText() {
		List<Map<String, String>> strengths = new List<Map<String, String>>();
		for (
			Schema.PicklistEntry entry : Schema.SObjectType.Assumption_Evidence__c.fields.Strength__c.getPicklistValues()
		) {
			if (entry.isActive()) {
				strengths.add(
					new Map<String, String>{
						'value' => entry.getValue(),
						'label' => entry.getLabel()
					}
				);
			}
		}
		return new Map<String, Object>{
			'title' => Schema.SObjectType.Assumption_Evidence__c.getLabelPlural(),
			'summary' => Schema.SObjectType.Assumption_Evidence__c.fields.Summary__c.getLabel(),
			'source' => Schema.SObjectType.Assumption_Evidence__c.fields.Source__c.getLabel(),
			'sourceUrl' => Schema.SObjectType.Assumption_Evidence__c.fields.Source_Url__c.getLabel(),
			'date' => Schema.SObjectType.Assumption_Evidence__c.fields.Evidence_Date__c.getLabel(),
			'strength' => Schema.SObjectType.Assumption_Evidence__c.fields.Strength__c.getLabel(),
			'strengths' => strengths
		};
	}

	/** An arrow's evidence log (L-05, R-AE1): newest first, undated last. */
	private static List<Map<String, Object>> evidenceOf(List<Assumption_Evidence__c> records) {
		List<Map<String, Object>> rows = new List<Map<String, Object>>();
		for (Assumption_Evidence__c evidence : records) {
			rows.add(
				new Map<String, Object>{
					'id' => evidence.Id,
					'summary' => evidence.Summary__c,
					'source' => evidence.Source__c,
					'sourceUrl' => evidence.Source_Url__c,
					'date' => evidence.Evidence_Date__c,
					'strength' => evidence.Strength__c
				}
			);
		}
		return rows;
	}

	/**
	 * Adds evidence to an arrow, or changes it (L-05, R-AE1, R-AE2). A blank strength is
	 * Moderate, the field's default.
	 *
	 * @param fields id (blank to add), linkId, summary, source, sourceUrl, date, strength
	 * @return the model the arrow belongs to
	 */
	public static Id saveEvidence(Map<String, Object> fields) {
		Assumption_Evidence__c evidence = new Assumption_Evidence__c(
			Id = idOf(fields, 'id'),
			Summary__c = text(fields, 'summary'),
			Source__c = text(fields, 'source'),
			Source_Url__c = text(fields, 'sourceUrl'),
			Evidence_Date__c = day(fields, 'date'),
			Strength__c = text(fields, 'strength') == null ? 'Moderate' : text(fields, 'strength')
		);
		if (evidence.Id == null) {
			evidence.Link__c = idOf(fields, 'linkId');
			insert as user evidence;
		} else {
			update as user evidence;
		}
		return [
			SELECT Link__r.Logic_Model__c
			FROM Assumption_Evidence__c
			WHERE Id = :evidence.Id
			WITH USER_MODE
		]
		.Link__r.Logic_Model__c;
	}

	private static List<Map<String, Object>> indicatorsOf(Id modelId) {
		List<Map<String, Object>> rows = new List<Map<String, Object>>();
		List<Indicator__c> indicators = [
			SELECT
				Id,
				Name,
				Element__c,
				Unit__c,
				Better_When__c,
				Baseline_Value__c,
				Baseline_Date__c,
				Description__c,
				Source__c,
				Source_Definition__c,
				Source_Status__c,
				Computed_At__c,
				(
					SELECT
						Id,
						Name,
						Start_Date__c,
						End_Date__c,
						Target_Value__c,
						Result_Value__c,
						Notes__c
					FROM Periods__r
					ORDER BY Start_Date__c, End_Date__c
				)
			FROM Indicator__c
			WHERE Element__r.Logic_Model__c = :modelId
			WITH USER_MODE
			ORDER BY CreatedDate
		];
		// The source query's Id in system mode: a person without access to Find's saved queries
		// cannot read the lookup, yet still sees the indicator. Its name is read as them.
		Map<Id, Id> queryByIndicator = new Map<Id, Id>();
		for (Indicator__c indicator : [
			SELECT Id, Source_Query__c
			FROM Indicator__c
			WHERE Id IN :indicators AND Source_Query__c != NULL
			WITH SYSTEM_MODE
		]) {
			queryByIndicator.put(indicator.Id, indicator.Source_Query__c);
		}
		Map<Id, String> queryNames = queryNames(new Set<Id>(queryByIndicator.values()));
		for (Indicator__c indicator : indicators) {
			List<Map<String, Object>> periods = new List<Map<String, Object>>();
			for (Indicator_Period__c period : indicator.Periods__r) {
				periods.add(
					new Map<String, Object>{
						'id' => period.Id,
						'name' => period.Name,
						'startDate' => period.Start_Date__c,
						'endDate' => period.End_Date__c,
						'targetValue' => period.Target_Value__c,
						'resultValue' => period.Result_Value__c,
						'notes' => period.Notes__c
					}
				);
			}
			rows.add(
				new Map<String, Object>{
					'id' => indicator.Id,
					'elementId' => indicator.Element__c,
					'name' => indicator.Name,
					'unit' => indicator.Unit__c,
					'betterWhen' => indicator.Better_When__c,
					'baselineValue' => indicator.Baseline_Value__c,
					'baselineDate' => indicator.Baseline_Date__c,
					'description' => indicator.Description__c,
					'source' => String.isBlank(indicator.Source__c)
						? IndicatorSourceService.MANUAL
						: indicator.Source__c,
					'queryId' => queryByIndicator.get(indicator.Id),
					'queryName' => queryNames.get(queryByIndicator.get(indicator.Id)),
					'definition' => definitionOf(indicator.Source_Definition__c),
					'status' => indicator.Source_Status__c,
					'computedAt' => indicator.Computed_At__c,
					'periods' => periods
				}
			);
		}
		return rows;
	}

	/** A computed source's choices as plain JSON, or null. */
	private static Map<String, Object> definitionOf(String stored) {
		IndicatorSourceService.Definition definition = IndicatorSourceService.parse(stored);
		return definition == null
			? null
			: new Map<String, Object>{
					'dateField' => definition.dateField,
					'function' => definition.function,
					'field' => definition.field,
					'dateLabel' => definition.dateLabel,
					'fieldLabel' => definition.fieldLabel
			  };
	}

	/**
	 * The names of the saved queries the person can open; a query they cannot open has no name
	 * here, and the builder says "a saved query".
	 */
	private static Map<Id, String> queryNames(Set<Id> queryIds) {
		Map<Id, String> names = new Map<Id, String>();
		if (
			queryIds.isEmpty() ||
			!Saved_Query__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).isAccessible()
		) {
			return names;
		}
		for (Saved_Query__c query : [
			SELECT Id, Name
			FROM Saved_Query__c
			WHERE Id IN :queryIds
			WITH USER_MODE
		]) {
			names.put(query.Id, query.Name);
		}
		return names;
	}

	// ------------------------------------------------------------------------------ programs

	/**
	 * The Programs module's Program object, found by describe only (ADR-0154 decision 5), or null
	 * where Programs is not installed or the user cannot read programs.
	 */
	@TestVisible
	private static Schema.SObjectType programType() {
		Schema.SObjectType type = NamespaceUtil.packagedObjectType(PROGRAM_OBJECT);
		if (type == null || !type.getDescribe(SObjectDescribeOptions.DEFERRED).isAccessible()) {
			return null;
		}
		return type;
	}

	/**
	 * The programs a model can be for, by name, as value and label pairs. Empty without Programs.
	 *
	 * @return up to 500 programs the user can see
	 */
	public static List<Map<String, String>> programs() {
		List<Map<String, String>> options = new List<Map<String, String>>();
		Schema.SObjectType type = programType();
		if (type == null) {
			return options;
		}
		// The object name comes from describe, never from the user.
		String soql =
			'SELECT Id, Name FROM ' +
			type.getDescribe(SObjectDescribeOptions.DEFERRED).getName() +
			' ORDER BY Name LIMIT :maxRows';
		for (
			SObject program : Database.queryWithBinds(
				soql,
				new Map<String, Object>{ 'maxRows' => PROGRAM_LIMIT },
				AccessLevel.USER_MODE
			)
		) {
			options.add(
				new Map<String, String>{
					'value' => (String) program.Id,
					'label' => (String) program.get('Name')
				}
			);
		}
		return options;
	}

	/** The program's name, or null when Programs is absent or the program cannot be found. */
	private static String programName(String programId) {
		Schema.SObjectType type = programType();
		if (type == null || String.isBlank(programId)) {
			return null;
		}
		String soql =
			'SELECT Name FROM ' +
			type.getDescribe(SObjectDescribeOptions.DEFERRED).getName() +
			' WHERE Id = :programId LIMIT 1';
		List<SObject> rows = Database.queryWithBinds(
			soql,
			new Map<String, Object>{ 'programId' => programId },
			AccessLevel.USER_MODE
		);
		return rows.isEmpty() ? null : (String) rows[0].get('Name');
	}

	/**
	 * Makes the model the organization's (blank) or a program's. The scope rule (R-LM1) refuses a
	 * scope another model holds.
	 *
	 * @param modelId the logic model
	 * @param programId a program's record identifier, or blank for the organization
	 */
	public static void setProgram(Id modelId, String programId) {
		String value = null;
		if (String.isNotBlank(programId)) {
			Schema.SObjectType type = programType();
			String key = LogicModelScope.keyFor(programId);
			if (
				type == null ||
				key == null ||
				key == LogicModelScope.ORGANIZATION ||
				Id.valueOf(key).getSObjectType() != type
			) {
				throw new BuilderException(
					BarnHelp.text('LogicModels', 'LogicModels_Scope_BadProgram')
				);
			}
			value = key;
		}
		update as user new Logic_Model__c(Id = modelId, Program_Id__c = value);
	}

	// ------------------------------------------------------------------------------- writing

	/**
	 * Adds or changes an element. On insert `modelId` places it; its model never changes after.
	 *
	 * @param fields id (blank to add), modelId, name, type, term, description, sortOrder
	 * @return the model the element belongs to
	 */
	public static Id saveElement(Map<String, Object> fields) {
		Logic_Model_Element__c element = new Logic_Model_Element__c(
			Name = text(fields, 'name'),
			Type__c = text(fields, 'type'),
			Outcome_Term__c = text(fields, 'type') == 'Outcome' ? text(fields, 'term') : null,
			Description__c = text(fields, 'description')
		);
		if (fields.containsKey('sortOrder')) {
			element.Sort_Order__c = number(fields, 'sortOrder');
		}
		Id elementId = idOf(fields, 'id');
		if (elementId == null) {
			element.Logic_Model__c = idOf(fields, 'modelId');
			insert as user element;
			return element.Logic_Model__c;
		}
		element.Id = elementId;
		refuseBackwardArrows(elementId, element.Type__c, element.Outcome_Term__c);
		update as user element;
		return modelOfElement(elementId);
	}

	/**
	 * The stage rank a type and term give, as the Stage_Rank__c formula computes it: Input 1 to
	 * Impact 7, 0 when unknown.
	 */
	@TestVisible
	private static Integer rankFor(String type, String term) {
		switch on type {
			when 'Input' {
				return 1;
			}
			when 'Activity' {
				return 2;
			}
			when 'Output' {
				return 3;
			}
			when 'Outcome' {
				return term == 'Intermediate Term' ? 5 : (term == 'Long Term' ? 6 : 4);
			}
			when 'Impact' {
				return 7;
			}
			when else {
				return 0;
			}
		}
	}

	/**
	 * Refuses a column change that would leave an attached arrow pointing backward (R-LL2). The
	 * arrow's own validation rule checks only when the arrow is saved, so without this a part
	 * could be moved past the parts it leads to. The message names every such arrow.
	 */
	private static void refuseBackwardArrows(Id elementId, String type, String term) {
		if (String.isBlank(type)) {
			return;
		}
		Integer rank = rankFor(type, term);
		List<String> backward = new List<String>();
		for (Logic_Model_Link__c link : [
			SELECT
				From_Element__c,
				From_Element__r.Name,
				From_Element__r.Stage_Rank__c,
				To_Element__c,
				To_Element__r.Name,
				To_Element__r.Stage_Rank__c
			FROM Logic_Model_Link__c
			WHERE From_Element__c = :elementId OR To_Element__c = :elementId
			WITH USER_MODE
			ORDER BY CreatedDate
		]) {
			Boolean outOfStep = link.From_Element__c == elementId
				? rank >= rankOf(link.To_Element__r)
				: rankOf(link.From_Element__r) >= rank;
			if (outOfStep) {
				backward.add(
					String.format(
						Label.Core_Address_DateRange,
						new List<String>{ link.From_Element__r.Name, link.To_Element__r.Name }
					)
				);
			}
		}
		if (!backward.isEmpty()) {
			throw new BuilderException(
				String.format(
					BarnHelp.text('LogicModels', 'LogicModels_Builder_BackwardArrows'),
					new List<String>{ String.join(backward, '; ') }
				)
			);
		}
	}

	private static Integer rankOf(Logic_Model_Element__c element) {
		if (element == null || element.Stage_Rank__c == null) {
			return 0;
		}
		return element.Stage_Rank__c.intValue();
	}

	/**
	 * Saves new sort orders for the elements of one column (Move Up and Move Down).
	 *
	 * @param orders each {id, sortOrder}
	 */
	public static void saveOrder(List<Object> orders) {
		List<Logic_Model_Element__c> changes = new List<Logic_Model_Element__c>();
		for (Object row : orders) {
			Map<String, Object> fields = (Map<String, Object>) row;
			changes.add(
				new Logic_Model_Element__c(
					Id = idOf(fields, 'id'),
					Sort_Order__c = number(fields, 'sortOrder')
				)
			);
		}
		update as user changes;
	}

	/**
	 * Adds an arrow, refusing a second one between the same two elements in the same direction
	 * (R-LL3), or changes an arrow's assumption.
	 *
	 * @param fields id (blank to add), modelId, fromId, toId, assumption
	 * @return the model
	 */
	public static Id saveLink(Map<String, Object> fields) {
		Id linkId = idOf(fields, 'id');
		if (linkId != null) {
			update as user new Logic_Model_Link__c(
				Id = linkId,
				Assumption__c = text(fields, 'assumption')
			);
			return [
				SELECT Logic_Model__c
				FROM Logic_Model_Link__c
				WHERE Id = :linkId
				WITH USER_MODE
			]
			.Logic_Model__c;
		}
		Id fromId = idOf(fields, 'fromId');
		Id toId = idOf(fields, 'toId');
		Integer existing = [
			SELECT COUNT()
			FROM Logic_Model_Link__c
			WHERE From_Element__c = :fromId AND To_Element__c = :toId
			WITH USER_MODE
		];
		if (existing > 0) {
			throw new BuilderException(
				BarnHelp.text('LogicModels', 'LogicModels_Builder_ArrowExists')
			);
		}
		Logic_Model_Link__c link = new Logic_Model_Link__c(
			Logic_Model__c = idOf(fields, 'modelId'),
			From_Element__c = fromId,
			To_Element__c = toId,
			Assumption__c = text(fields, 'assumption')
		);
		insert as user link;
		return link.Logic_Model__c;
	}

	/**
	 * Adds or changes an indicator on an output or outcome.
	 *
	 * @param fields id (blank to add), elementId, name, unit, betterWhen, baselineValue,
	 *        baselineDate, description
	 * @return the model
	 */
	public static Id saveIndicator(Map<String, Object> fields) {
		String betterWhen = text(fields, 'betterWhen');
		Indicator__c indicator = new Indicator__c(
			Name = text(fields, 'name'),
			Unit__c = text(fields, 'unit'),
			Better_When__c = String.isBlank(betterWhen) ? 'Higher' : betterWhen,
			Baseline_Value__c = number(fields, 'baselineValue'),
			Baseline_Date__c = day(fields, 'baselineDate'),
			Description__c = text(fields, 'description')
		);
		Id indicatorId = idOf(fields, 'id');
		Id elementId;
		if (indicatorId == null) {
			elementId = idOf(fields, 'elementId');
			indicator.Element__c = elementId;
			insert as user indicator;
		} else {
			indicator.Id = indicatorId;
			update as user indicator;
			elementId = [SELECT Element__c FROM Indicator__c WHERE Id = :indicatorId WITH USER_MODE]
			.Element__c;
		}
		return modelOfElement(elementId);
	}

	/**
	 * Adds or changes an indicator's period, refusing a second row with the same start and end
	 * dates for the same indicator (R-IP2).
	 *
	 * @param fields id (blank to add), indicatorId, name, startDate, endDate, targetValue,
	 *        resultValue, notes
	 * @return the model
	 */
	public static Id savePeriod(Map<String, Object> fields) {
		Id periodId = idOf(fields, 'id');
		Id indicatorId = periodId == null
			? idOf(fields, 'indicatorId')
			: [SELECT Indicator__c FROM Indicator_Period__c WHERE Id = :periodId WITH USER_MODE]
			  .Indicator__c;
		Date startDate = day(fields, 'startDate');
		Date endDate = day(fields, 'endDate');
		Integer same = [
			SELECT COUNT()
			FROM Indicator_Period__c
			WHERE
				Indicator__c = :indicatorId
				AND Start_Date__c = :startDate
				AND End_Date__c = :endDate
				AND Id != :periodId
			WITH USER_MODE
		];
		if (same > 0) {
			throw new BuilderException(
				BarnHelp.text('LogicModels', 'LogicModels_Builder_PeriodExists')
			);
		}
		Indicator__c indicator = [
			SELECT Element__c, Source__c
			FROM Indicator__c
			WHERE Id = :indicatorId
			WITH USER_MODE
		];
		Indicator_Period__c period = new Indicator_Period__c(
			Name = text(fields, 'name'),
			Start_Date__c = startDate,
			End_Date__c = endDate,
			Target_Value__c = number(fields, 'targetValue'),
			Notes__c = text(fields, 'notes')
		);
		// A computed indicator's results are written by its refresh only (R-IN3).
		if (indicator.Source__c != IndicatorSourceService.COMPUTED) {
			period.Result_Value__c = number(fields, 'resultValue');
		}
		if (periodId == null) {
			period.Indicator__c = indicatorId;
			insert as user period;
		} else {
			period.Id = periodId;
			update as user period;
		}
		return modelOfElement(indicator.Element__c);
	}

	/**
	 * Deletes an element (its arrows first, then it, with its indicators and their periods), an
	 * arrow (with its evidence), evidence, an indicator or a period.
	 *
	 * @param recordId the record to delete
	 * @return the model it belonged to
	 */
	public static Id remove(Id recordId) {
		Schema.SObjectType type = recordId.getSObjectType();
		Id modelId;
		if (type == Logic_Model_Element__c.SObjectType) {
			modelId = modelOfElement(recordId);
			delete as user [
				SELECT Id
				FROM Logic_Model_Link__c
				WHERE From_Element__c = :recordId OR To_Element__c = :recordId
				WITH USER_MODE
			];
		} else if (type == Logic_Model_Link__c.SObjectType) {
			modelId = [
				SELECT Logic_Model__c
				FROM Logic_Model_Link__c
				WHERE Id = :recordId
				WITH USER_MODE
			]
			.Logic_Model__c;
		} else if (type == Assumption_Evidence__c.SObjectType) {
			modelId = [
				SELECT Link__r.Logic_Model__c
				FROM Assumption_Evidence__c
				WHERE Id = :recordId
				WITH USER_MODE
			]
			.Link__r.Logic_Model__c;
		} else if (type == Indicator__c.SObjectType) {
			modelId = [
				SELECT Element__r.Logic_Model__c
				FROM Indicator__c
				WHERE Id = :recordId
				WITH USER_MODE
			]
			.Element__r.Logic_Model__c;
		} else if (type == Indicator_Period__c.SObjectType) {
			modelId = [
				SELECT Indicator__r.Element__r.Logic_Model__c
				FROM Indicator_Period__c
				WHERE Id = :recordId
				WITH USER_MODE
			]
			.Indicator__r.Element__r.Logic_Model__c;
		} else {
			throw new BuilderException(
				BarnHelp.text('LogicModels', 'LogicModels_Builder_NotFound')
			);
		}
		Database.delete(recordId, true, AccessLevel.USER_MODE);
		return modelId;
	}

	// ------------------------------------------------------------------------------- helpers

	private static Id modelOfElement(Id elementId) {
		return [
			SELECT Logic_Model__c
			FROM Logic_Model_Element__c
			WHERE Id = :elementId
			WITH USER_MODE
		]
		.Logic_Model__c;
	}

	private static String text(Map<String, Object> fields, String key) {
		Object value = fields.get(key);
		if (value == null) {
			return null;
		}
		String result = String.valueOf(value).trim();
		return String.isEmpty(result) ? null : result;
	}

	private static Id idOf(Map<String, Object> fields, String key) {
		String value = text(fields, key);
		return value == null ? null : Id.valueOf(value);
	}

	private static Decimal number(Map<String, Object> fields, String key) {
		String value = text(fields, key);
		return value == null ? null : Decimal.valueOf(value);
	}

	private static Date day(Map<String, Object> fields, String key) {
		String value = text(fields, key);
		return value == null ? null : Date.valueOf(value);
	}
}
