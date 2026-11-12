/**
 * The Logic Model Builder panel's server side (L-01, L-02; ADR-0154 `0154-logic-models-module.md`,
 * decision 8). Thin: each method parses the panel's JSON, asks `LogicModelService`, and returns
 * the whole model again as plain JSON, so the panel redraws from one shape. A refused save comes
 * back as its own message.
 */
public with sharing class LogicModelBuilderController {
	/**
	 * The model as the builder draws it.
	 *
	 * @param modelId the logic model
	 * @return the model (see `LogicModelService.read`)
	 */
	@AuraEnabled
	public static Map<String, Object> getModel(Id modelId) {
		try {
			return LogicModelService.read(modelId);
		} catch (Exception e) {
			throw handled(e);
		}
	}

	/**
	 * The programs a model can be for, empty where Programs is not installed.
	 *
	 * @return value and label pairs
	 */
	@AuraEnabled
	public static List<Map<String, String>> getPrograms() {
		try {
			return LogicModelService.programs();
		} catch (Exception e) {
			throw handled(e);
		}
	}

	/**
	 * Makes the model the organization's (blank) or a program's.
	 *
	 * @param modelId the logic model
	 * @param programId the program's record identifier, or blank
	 * @return the model
	 */
	@AuraEnabled
	public static Map<String, Object> setProgram(Id modelId, String programId) {
		try {
			LogicModelService.setProgram(modelId, programId);
			return LogicModelService.read(modelId);
		} catch (Exception e) {
			throw handled(e);
		}
	}

	/**
	 * Adds or changes a part.
	 *
	 * @param elementJson id, modelId, name, type, term, description, sortOrder
	 * @return the model
	 */
	@AuraEnabled
	public static Map<String, Object> saveElement(String elementJson) {
		try {
			return LogicModelService.read(LogicModelService.saveElement(parse(elementJson)));
		} catch (Exception e) {
			throw handled(e);
		}
	}

	/**
	 * Saves a column's new order after Move Up or Move Down.
	 *
	 * @param modelId the logic model
	 * @param ordersJson a list of {id, sortOrder}
	 * @return the model
	 */
	@AuraEnabled
	public static Map<String, Object> saveOrder(Id modelId, String ordersJson) {
		try {
			LogicModelService.saveOrder((List<Object>) JSON.deserializeUntyped(ordersJson));
			return LogicModelService.read(modelId);
		} catch (Exception e) {
			throw handled(e);
		}
	}

	/**
	 * Adds an arrow or changes its assumption.
	 *
	 * @param linkJson id, modelId, fromId, toId, assumption
	 * @return the model
	 */
	@AuraEnabled
	public static Map<String, Object> saveLink(String linkJson) {
		try {
			return LogicModelService.read(LogicModelService.saveLink(parse(linkJson)));
		} catch (Exception e) {
			throw handled(e);
		}
	}

	/**
	 * Adds evidence to an arrow's assumption, or changes it (L-05).
	 *
	 * @param evidenceJson id, linkId, summary, source, sourceUrl, date, strength
	 * @return the model
	 */
	@AuraEnabled
	public static Map<String, Object> saveEvidence(String evidenceJson) {
		try {
			return LogicModelService.read(LogicModelService.saveEvidence(parse(evidenceJson)));
		} catch (Exception e) {
			throw handled(e);
		}
	}

	/**
	 * Adds or changes an indicator.
	 *
	 * @param indicatorJson id, elementId, name, unit, betterWhen, baselineValue, baselineDate,
	 *        description
	 * @return the model
	 */
	@AuraEnabled
	public static Map<String, Object> saveIndicator(String indicatorJson) {
		try {
			return LogicModelService.read(LogicModelService.saveIndicator(parse(indicatorJson)));
		} catch (Exception e) {
			throw handled(e);
		}
	}

	/**
	 * The Find saved queries the person can open, for a computed source (L-03).
	 *
	 * @return value, label and objectName
	 */
	@AuraEnabled
	public static List<Map<String, String>> getSourceQueries() {
		try {
			return IndicatorSourceService.queries();
		} catch (Exception e) {
			throw handled(e);
		}
	}

	/**
	 * The fields of a saved query's object a computed source may use.
	 *
	 * @param queryId the saved query
	 * @return objectName, objectLabel, dateFields, numberFields, uniqueFields
	 */
	@AuraEnabled
	public static Map<String, Object> getSourceFields(Id queryId) {
		try {
			return IndicatorSourceService.fields(queryId);
		} catch (Exception e) {
			throw handled(e);
		}
	}

	/**
	 * Saves where an indicator's results come from; a computed source starts working out its
	 * results at once.
	 *
	 * @param modelId the logic model
	 * @param sourceJson id, source, and for Computed: queryId, dateField, function, field
	 * @return the model
	 */
	@AuraEnabled
	public static Map<String, Object> saveSource(Id modelId, String sourceJson) {
		try {
			Map<String, Object> fields = parse(sourceJson);
			if (IndicatorSourceService.save(fields)) {
				IndicatorSourceService.refresh(Id.valueOf(String.valueOf(fields.get('id'))));
			}
			return LogicModelService.read(modelId);
		} catch (Exception e) {
			throw handled(e);
		}
	}

	/**
	 * The computed indicator starters this org can use (R-IN8).
	 *
	 * @return value, choiceLabel and choiceRequired
	 */
	@AuraEnabled
	public static List<Map<String, Object>> getSourceStarters() {
		try {
			return IndicatorStarterService.available();
		} catch (Exception e) {
			throw handled(e);
		}
	}

	/**
	 * The records a starter can be about: services, volunteer jobs or programs.
	 *
	 * @param starterKey the starter
	 * @return value and label pairs
	 */
	@AuraEnabled
	public static List<Map<String, String>> getStarterChoices(String starterKey) {
		try {
			return IndicatorStarterService.choices(starterKey);
		} catch (Exception e) {
			throw handled(e);
		}
	}

	/**
	 * Writes a starter's saved query and makes the indicator computed from it, then starts
	 * working out its results (R-IN8, R-IN4).
	 *
	 * @param modelId the logic model
	 * @param starterJson id (the indicator), starter, choiceId, queryName
	 * @return the model
	 */
	@AuraEnabled
	public static Map<String, Object> saveStarterSource(Id modelId, String starterJson) {
		try {
			Map<String, Object> fields = parse(starterJson);
			Map<String, Object> source = IndicatorStarterService.createQuery(
				(String) fields.get('starter'),
				(String) fields.get('choiceId'),
				(String) fields.get('queryName')
			);
			source.put('id', fields.get('id'));
			IndicatorSourceService.save(source);
			IndicatorSourceService.refresh(Id.valueOf(String.valueOf(fields.get('id'))));
			return LogicModelService.read(modelId);
		} catch (Exception e) {
			throw handled(e);
		}
	}

	/**
	 * Saves the model's shared reporting periods (R-LM4).
	 *
	 * @param modelId the logic model
	 * @param periodsJson a list of {name, startDate, endDate}
	 * @return the model
	 */
	@AuraEnabled
	public static Map<String, Object> savePeriods(Id modelId, String periodsJson) {
		try {
			Object rows = String.isBlank(periodsJson) ? null : JSON.deserializeUntyped(periodsJson);
			if (!(rows instanceof List<Object>)) {
				throw new LogicModelService.BuilderException(actionFailed());
			}
			LogicModelPeriodService.save(modelId, (List<Object>) rows);
			return LogicModelService.read(modelId);
		} catch (Exception e) {
			throw handled(e);
		}
	}

	/**
	 * Add Period to Every Indicator: the model period with these dates on every indicator that
	 * lacks it (R-LM4).
	 *
	 * @param modelId the logic model
	 * @param startDate the period's start (ISO date)
	 * @param endDate the period's end (ISO date)
	 * @return the model, with `added`: how many indicators got the period
	 */
	@AuraEnabled
	public static Map<String, Object> addPeriodToEveryIndicator(
		Id modelId,
		String startDate,
		String endDate
	) {
		try {
			Integer added = LogicModelPeriodService.addToEvery(modelId, startDate, endDate);
			Map<String, Object> model = LogicModelService.read(modelId);
			model.put('added', added);
			return model;
		} catch (Exception e) {
			throw handled(e);
		}
	}

	/**
	 * Use the Model's Periods: every model period the indicator lacks (R-LM4).
	 *
	 * @param modelId the logic model
	 * @param indicatorId the indicator
	 * @return the model, with `added`: how many periods were added
	 */
	@AuraEnabled
	public static Map<String, Object> useModelPeriods(Id modelId, Id indicatorId) {
		try {
			Integer added = LogicModelPeriodService.useForIndicator(modelId, indicatorId);
			Map<String, Object> model = LogicModelService.read(modelId);
			model.put('added', added);
			return model;
		} catch (Exception e) {
			throw handled(e);
		}
	}

	/**
	 * Starts working out a computed indicator's results now.
	 *
	 * @param modelId the logic model
	 * @param indicatorId the indicator
	 * @return the model
	 */
	@AuraEnabled
	public static Map<String, Object> refreshResults(Id modelId, Id indicatorId) {
		try {
			IndicatorSourceService.refresh(indicatorId);
			return LogicModelService.read(modelId);
		} catch (Exception e) {
			throw handled(e);
		}
	}

	/**
	 * Adds or changes a period's target and result.
	 *
	 * @param periodJson id, indicatorId, name, startDate, endDate, targetValue, resultValue, notes
	 * @return the model
	 */
	@AuraEnabled
	public static Map<String, Object> savePeriod(String periodJson) {
		try {
			return LogicModelService.read(LogicModelService.savePeriod(parse(periodJson)));
		} catch (Exception e) {
			throw handled(e);
		}
	}

	/**
	 * Deletes a part (with its arrows, indicators and periods), an arrow, an indicator or a
	 * period.
	 *
	 * @param recordId the record to delete
	 * @return the model
	 */
	@AuraEnabled
	public static Map<String, Object> remove(Id recordId) {
		try {
			return LogicModelService.read(LogicModelService.remove(recordId));
		} catch (Exception e) {
			throw handled(e);
		}
	}

	private static Map<String, Object> parse(String payload) {
		Object value = String.isBlank(payload) ? null : JSON.deserializeUntyped(payload);
		if (!(value instanceof Map<String, Object>)) {
			throw new LogicModelService.BuilderException(actionFailed());
		}
		return (Map<String, Object>) value;
	}

	/** The generic failure: what did not happen, then what to do (help catalog, a message). */
	@TestVisible
	private static String actionFailed() {
		return BarnHelp.text('LogicModels', 'LogicModels_Builder_ActionFailed');
	}

	/** The message the panel shows: a refused save's own words, or the generic one. */
	@TestVisible
	private static AuraHandledException handled(Exception e) {
		String message = actionFailed();
		if (e instanceof DmlException) {
			message = ((DmlException) e).getDmlMessage(0);
		} else if (e instanceof LogicModelService.BuilderException) {
			message = e.getMessage();
		} else if (e instanceof QueryException || e instanceof System.NoAccessException) {
			message = Label.LogicModels_Builder_NotFound;
		} else {
			ErrorLogger.log(e, 'LogicModelBuilderController');
		}
		return UserErrors.message(message);
	}
}
