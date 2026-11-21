/**
 * The Flow action Apply a Saved Map (CN-06; canonical model R-MAP1 to R-MAP3, R-ST5; design
 * Section 2.3, "Linked"). Applies a saved record map to a source record or to JSON and saves the
 * map's target record: Create or Update through the map's match when it has one, an update of
 * the record Id given, or a create. It runs as the flow's running user in user mode, so it can
 * read and write only what that person could, and saves one record per request.
 */
global with sharing class ConnectorApplyMapAction {
	private static final Pattern FIELD_PATH = Pattern.compile('[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z][A-Za-z0-9_]*)?');

	/** One map to apply. */
	global class Request {
		@InvocableVariable(
			label='Map Name'
			description='The name of a saved map whose target is a record.'
			required=true
		)
		global String mapName;

		@InvocableVariable(
			label='Source Record Id'
			description='The record the map reads from (a map from the fields of a record). Leave blank to use Data (JSON).'
		)
		global Id sourceRecordId;

		@InvocableVariable(label='Data (JSON)' description='A JSON object the map reads from (a map from a payload).')
		global String dataJson;

		@InvocableVariable(
			label='Record Id to Update'
			description='Optional. The record to update. Leave blank to create one, or to let the map\'s match find it.'
		)
		global Id targetRecordId;
	}

	/** What the request in the same position did. */
	global class Result {
		@InvocableVariable(label='Record Id' description='The record created or updated.')
		global Id recordId;

		@InvocableVariable(label='Action' description='created, updated or skipped.')
		global String action;

		@InvocableVariable(label='Message' description='Why nothing was saved, in plain words.')
		global String message;
	}

	@InvocableMethod(
		label='Apply a Saved Map'
		description='Builds a record from a saved BarnCRM map, reading a source record or JSON, and saves it as the person running the flow: created, updated, or found and updated through the map\'s match.'
		category='BarnCRM'
	)
	global static List<Result> apply(List<Request> requests) {
		List<Result> results = new List<Result>();
		Map<String, ConnectorMapRuntime.SavedMap> maps = new Map<String, ConnectorMapRuntime.SavedMap>();
		for (Request request : requests == null ? new List<Request>() : requests) {
			Result result = new Result();
			results.add(result);
			// In order, each save seeing the ones before it (a later request's match finds an
			// earlier one's record); one statement each, so a bulk flow runs to the limits.
			if (
				Limits.getDmlStatements() >= Limits.getLimitDmlStatements() - 5 ||
				Limits.getQueries() >= Limits.getLimitQueries() - 5
			) {
				result.message = BarnHelp.text('Connector', 'Connector_Flow_TooMany');
				continue;
			}
			try {
				String name = request.mapName == null ? '' : request.mapName.trim();
				if (!maps.containsKey(name.toLowerCase())) {
					maps.put(name.toLowerCase(), byName(name));
				}
				ConnectorMapRuntime.SavedMap saved = maps.get(name.toLowerCase());
				if (String.isBlank(ConnectorMapRuntime.objectOf(saved.document))) {
					throw new ConnectorMapRuntime.MapException(
						BarnHelp.text('Connector', 'Connector_Flow_NotRecordMap')
					);
				}
				Object input = request.sourceRecordId != null
					? source(request.sourceRecordId, saved.document)
					: (String.isBlank(request.dataJson)
							? new Map<String, Object>()
							: JSON.deserializeUntyped(request.dataJson));
				Boolean matches = !ConnectorRecipeDocument.mapOf(saved.document.get('match')).isEmpty();
				String kind = request.targetRecordId != null ? 'update' : (matches ? 'upsert' : 'create');
				// One insert or update, atomic on its own: nothing to roll back when it is refused.
				ConnectorMapRuntime.Saved done = ConnectorMapRuntime.save(
					kind,
					saved.document,
					input,
					request.targetRecordId,
					null,
					AccessLevel.USER_MODE,
					false
				);
				result.recordId = done.recordId;
				result.action = done.action;
			} catch (Exception refused) {
				result.message = words(refused);
			}
		}
		return results;
	}

	private static String words(Exception refused) {
		if (refused instanceof DmlException) {
			return ((DmlException) refused).getDmlMessage(0);
		}
		return refused instanceof ConnectorMapRuntime.MapException
			? refused.getMessage()
			: BarnHelp.text('Connector', 'Connector_Run_ErrorUnexpected', new List<Object>{ refused.getTypeName() });
	}

	/** A saved map by name, read as the person (R-ST5). */
	private static ConnectorMapRuntime.SavedMap byName(String name) {
		List<Saved_Transform__c> rows = [
			SELECT Id
			FROM Saved_Transform__c
			WHERE Name = :name AND Kind__c = :ConnectorMapRuntime.KIND_MAP
			WITH USER_MODE
			LIMIT 1
		];
		if (rows.isEmpty()) {
			throw new ConnectorMapRuntime.MapException(BarnHelp.text('Connector', 'Connector_Run_ErrorMapGone'));
		}
		return ConnectorMapRuntime.load(rows[0].Id, AccessLevel.USER_MODE);
	}

	/** The source record's fields the map's columns name (one lookup hop), read as the person. */
	private static Object source(Id recordId, Map<String, Object> document) {
		Set<String> fields = new Set<String>{ 'Id' };
		for (Object raw : ConnectorRecipeDocument.listOf(document.get('columns'))) {
			String path = ConnectorRecipeDocument.textOf(ConnectorRecipeDocument.mapOf(raw).get('source'));
			if (FIELD_PATH.matcher(path).matches()) {
				fields.add(path);
			}
		}
		List<SObject> rows = Database.queryWithBinds(
			'SELECT ' +
				String.join(new List<String>(fields), ', ') +
				' FROM ' +
				recordId.getSObjectType().getDescribe().getName() +
				' WHERE Id = :recordId',
			new Map<String, Object>{ 'recordId' => recordId },
			AccessLevel.USER_MODE
		);
		if (rows.isEmpty()) {
			throw new ConnectorMapRuntime.MapException(BarnHelp.text('Connector', 'Connector_Flow_NoSource'));
		}
		return JSON.deserializeUntyped(JSON.serialize(rows[0]));
	}
}
