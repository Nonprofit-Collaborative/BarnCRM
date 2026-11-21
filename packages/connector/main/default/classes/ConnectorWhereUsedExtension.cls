/**
 * BarnCRM Connector's part of Where Used (CN-06; design Section 2.3 and 7; ADR-0159). Lists the
 * recipes that name the target:
 * - a saved map, when a Create, Update, Create or Update or Call an App step links it (R-ST5), so
 *   the Mapper warns before the map is changed;
 * - an object or field, when a Find step's query or a Record Change trigger's query names it as
 *   its object, a field it returns or a condition.
 * Both the published definition and the unpublished draft count. Core finds this class by name
 * (`WhereUsedExtensions`) and asks only someone who may manage settings, so it reads in system
 * mode.
 */
@NamespaceAccessible
public with sharing class ConnectorWhereUsedExtension implements WhereUsedExtension {
	public static final String KIND = 'connectorRecipe';

	@NamespaceAccessible
	public ConnectorWhereUsedExtension() {
		// Built by name from Core (WhereUsedExtensions), so it needs a public constructor.
	}

	public List<WhereUsedService.Reference> references(WhereUsedService.Target target) {
		List<WhereUsedService.Reference> found = new List<WhereUsedService.Reference>();
		String kindLabel = BarnHelp.text('Connector', 'Connector_WhereUsed_Kind');
		for (Connector_Recipe__c recipe : [
			SELECT Id, Name, Definition_JSON__c, Draft_JSON__c
			FROM Connector_Recipe__c
			WITH SYSTEM_MODE
			ORDER BY Name
			LIMIT 2000
		]) {
			WhereUsedService.Reference reference = new WhereUsedService.Reference(
				KIND,
				kindLabel,
				recipe.Name,
				recipe.Id
			);
			for (String source : new List<String>{ recipe.Definition_JSON__c, recipe.Draft_JSON__c }) {
				Map<String, Object> document = parsed(source);
				if (document != null) {
					addParts(reference, target, document);
				}
			}
			if (!reference.getParts().isEmpty()) {
				found.add(
					reference.withBreaks(BarnHelp.text('Connector', 'Connector_WhereUsed_Breaks'))
						.withEdit('Super_Connector', new Map<String, String>{ 'recipe' => recipe.Id })
				);
			}
		}
		return found;
	}

	/** Where in one document the target is named. */
	private static void addParts(
		WhereUsedService.Reference reference,
		WhereUsedService.Target target,
		Map<String, Object> document
	) {
		Map<String, Object> starter = ConnectorRecipeDocument.mapOf(document.get('trigger'));
		if (
			target.mapId == null &&
			ConnectorRecipeDocument.textOf(starter.get('kind')) == 'record' &&
			queryNames(target, ConnectorRecipeDocument.mapOf(starter.get('query')))
		) {
			reference.addPart(BarnHelp.text('Connector', 'Connector_WhereUsed_Trigger'));
		}
		for (Map<String, Object> step : ConnectorRecipeDocument.allSteps(document)) {
			String label = BarnHelp.text(
				'Connector',
				'Connector_WhereUsed_Step',
				new List<Object>{ ConnectorRecipeDocument.textOf(step.get('id')) }
			);
			if (target.mapId != null) {
				for (String key : new List<String>{ 'map', 'bodyMap' }) {
					String linked = ConnectorRecipeDocument.textOf(step.get(key));
					if (ConnectorRecipeDocument.isId(linked) && target.isMap(Id.valueOf(linked))) {
						reference.addPart(label);
					}
				}
				continue;
			}
			if (
				ConnectorRecipeDocument.textOf(step.get('kind')) == 'find' &&
				queryNames(target, ConnectorRecipeDocument.mapOf(step.get('query')))
			) {
				reference.addPart(label);
			}
		}
	}

	/** Whether a query names the target as its object, a field it returns or a condition. */
	private static Boolean queryNames(WhereUsedService.Target target, Map<String, Object> query) {
		String objectName = ConnectorRecipeDocument.textOf(query.get('object'));
		if (target.isObject() && target.isObject(objectName)) {
			return true;
		}
		Boolean named = target.matchesFilter(objectName, query.get('filter'));
		for (Object field : ConnectorRecipeDocument.listOf(query.get('fields'))) {
			named = named || target.matchesPath(objectName, ConnectorRecipeDocument.textOf(field));
		}
		return named;
	}

	private static Map<String, Object> parsed(String source) {
		if (String.isBlank(source)) {
			return null;
		}
		try {
			Object raw = JSON.deserializeUntyped(source);
			return raw instanceof Map<String, Object> ? (Map<String, Object>) raw : null;
		} catch (Exception unreadable) {
			return null;
		}
	}
}
