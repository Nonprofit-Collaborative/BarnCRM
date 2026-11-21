/**
 * The Flow action Run a BarnCRM Connector Recipe (CN-06; canonical model R-CR4; design Section
 * 3.2, "Manually or from a Flow"). Queues one run of an Active recipe for each request, with the
 * record Ids and optional JSON the flow gives, and returns at once: the run itself executes as
 * the recipe's identity through the start event, never as the person whose flow asked (D-215),
 * so the flow needs no access to the recipe and the recipe gains none from the flow.
 */
global with sharing class ConnectorRunRecipeAction {
	/** One run to queue. */
	global class Request {
		@InvocableVariable(
			label='Recipe Name'
			description='The name of an Active BarnCRM Connector recipe, as shown on Super Connector.'
			required=true
		)
		global String recipeName;

		@InvocableVariable(
			label='Record Id'
			description='Optional. A record the recipe works on; its steps read it as trigger.recordId.'
		)
		global Id recordId;

		@InvocableVariable(
			label='Record Ids'
			description='Optional. Several records; the steps read them as trigger.recordIds.'
		)
		global List<Id> recordIds;

		@InvocableVariable(
			label='Data (JSON)'
			description='Optional. A JSON object or list the steps read as trigger.data.'
		)
		global String dataJson;
	}

	/** What happened to the request in the same position. */
	global class Result {
		@InvocableVariable(label='Queued' description='True when a run was queued.')
		global Boolean queued;

		@InvocableVariable(label='Run Id' description='The queued run, shown in Run History.')
		global Id runId;

		@InvocableVariable(label='Message' description='Why no run was queued, in plain words.')
		global String message;
	}

	@InvocableMethod(
		label='Run a BarnCRM Connector Recipe'
		description='Queues a run of an Active BarnCRM Connector recipe with the records or data you give. The recipe runs moments later as its own identity, never as the person running the flow; see Run History on Super Connector.'
		category='BarnCRM'
	)
	global static List<Result> run(List<Request> requests) {
		List<Result> results = new List<Result>();
		List<Connector_Run__c> runs = new List<Connector_Run__c>();
		List<Result> queuedResults = new List<Result>();
		Map<String, Connector_Recipe__c> recipes = new Map<String, Connector_Recipe__c>();
		for (Request request : requests == null ? new List<Request>() : requests) {
			Result result = new Result();
			result.queued = false;
			results.add(result);
			String name = request.recipeName == null ? '' : request.recipeName.trim();
			if (!recipes.containsKey(name.toLowerCase())) {
				recipes.put(name.toLowerCase(), String.isBlank(name) ? null : ConnectorRunStore.activeByName(name));
			}
			Connector_Recipe__c recipe = recipes.get(name.toLowerCase());
			if (recipe == null || recipe.Trigger_Kind__c != ConnectorRecipes.MANUAL) {
				result.message = BarnHelp.text('Connector', 'Connector_Flow_NoRecipe', new List<Object>{ name });
				continue;
			}
			Map<String, Object> input = new Map<String, Object>{
				'recordId' => request.recordId,
				'recordIds' => request.recordIds == null ? new List<Id>() : request.recordIds
			};
			if (String.isNotBlank(request.dataJson)) {
				try {
					input.put('data', JSON.deserializeUntyped(request.dataJson));
				} catch (Exception unreadable) {
					result.message = BarnHelp.text('Connector', 'Connector_Run_ErrorInput');
					continue;
				}
			}
			String inputJson = JSON.serialize(input);
			if (inputJson.length() > ConnectorRunStore.MAX_TEXT) {
				// Only this request is refused; the others are queued.
				result.message = BarnHelp.text('Connector', 'Connector_Run_ErrorTooLarge');
				continue;
			}
			runs.add(
				new Connector_Run__c(
					Recipe__c = recipe.Id,
					Started_By__c = 'Flow',
					Ran_As__c = recipe.Run_As__c,
					Recipe_Version__c = recipe.Version__c,
					Input_JSON__c = inputJson
				)
			);
			queuedResults.add(result);
		}
		if (!runs.isEmpty()) {
			ConnectorRunStore.queue(runs);
			for (Integer i = 0; i < runs.size(); i++) {
				queuedResults[i].queued = true;
				queuedResults[i].runId = runs[i].Id;
			}
		}
		return results;
	}
}
