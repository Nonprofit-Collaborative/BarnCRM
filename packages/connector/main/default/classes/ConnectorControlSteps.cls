/**
 * For Each, Wait and Change Data (CN-05; canonical model R-CR1, R-CR10; design Section 3.4): the
 * save rules of the three steps, and the Wait and Change Data work. The For Each loop itself
 * lives in `ConnectorStepRunner`, which owns the run's progress.
 *
 * Inherited sharing: called by the step runner in the run's own access mode.
 */
public inherited sharing class ConnectorControlSteps {
	public static final Set<String> KINDS = new Set<String>{ 'forEach', 'wait', 'transform' };
	/** Steps a For Each may not hold, at any depth: a loop inside a loop, a pause, a data job. */
	public static final Set<String> NOT_IN_LOOP = new Set<String>{ 'forEach', 'wait', 'importRows' };
	public static final Integer MAX_ITEMS = 1000;
	/** Items one transaction works through before the run continues in the next. */
	public static final Integer CHECKPOINT_ITEMS = 200;
	public static final Integer LEAST_WAIT_MINUTES = 5;
	public static final Integer MOST_WAIT_MINUTES = 43200;
	private static final Map<String, Integer> UNIT_MINUTES = new Map<String, Integer>{
		'minutes' => 1,
		'hours' => 60,
		'days' => 1440
	};

	/** What is wrong with one For Each, Wait or Change Data step, in words naming it, or null. */
	public static String problem(String kind, Map<String, Object> step, List<Object> at) {
		if (kind == 'forEach') {
			return ConnectorRecipeDocument.isPath(ConnectorRecipeDocument.textOf(step.get('items')))
				? null
				: BarnHelp.text('Connector', 'Connector_Recipe_ErrorItems', at);
		}
		if (kind == 'wait') {
			return minutesOf(step) == null ? BarnHelp.text('Connector', 'Connector_Recipe_ErrorWait', at) : null;
		}
		if (!ConnectorRecipeDocument.isId(ConnectorRecipeDocument.textOf(step.get('map')))) {
			return BarnHelp.text('Connector', 'Connector_Recipe_ErrorMap', at);
		}
		String input = ConnectorRecipeDocument.textOf(step.get('input'));
		return String.isNotBlank(input) && !ConnectorRecipeDocument.isPath(input)
			? BarnHelp.text('Connector', 'Connector_Recipe_ErrorPath', at)
			: null;
	}

	/** A Wait's length in minutes, 5 minutes to 30 days, or null when it is not one. */
	public static Integer minutesOf(Map<String, Object> step) {
		Object amount = step.get('amount');
		Integer unit = UNIT_MINUTES.get(ConnectorRecipeDocument.textOf(step.get('unit')));
		if (
			!(amount instanceof Integer) ||
			unit == null ||
			(Integer) amount < 1 ||
			(Integer) amount > MOST_WAIT_MINUTES
		) {
			return null;
		}
		Long minutes = ((Integer) amount) * (Long) unit;
		return minutes < LEAST_WAIT_MINUTES || minutes > MOST_WAIT_MINUTES ? null : minutes.intValue();
	}

	/** A For Each's items: the list its path reads, at most 1,000; a blank list has none. */
	public static List<Object> itemsOf(Object value) {
		if (value == null) {
			return new List<Object>();
		}
		if (!(value instanceof List<Object>)) {
			throw new ConnectorStepRunner.StepFailureException(
				BarnHelp.text('Connector', 'Connector_Run_ErrorNotList')
			);
		}
		List<Object> items = (List<Object>) value;
		if (items.size() > MAX_ITEMS) {
			throw new ConnectorStepRunner.StepFailureException(
				BarnHelp.text(
					'Connector',
					'Connector_Run_ErrorTooManyItems',
					new List<Object>{ items.size(), MAX_ITEMS }
				)
			);
		}
		return items;
	}

	/**
	 * A Wait (R-CR10): the first time, the run waits until now plus the step's minutes; when the
	 * clock wakes it at or after that time, the step is done. A Test run does not wait. The time
	 * is kept in the step's progress, so waking early only waits again for the rest.
	 */
	public static Map<String, Object> waitFor(Map<String, Object> step, Map<String, Object> progress, Boolean isTest) {
		Integer minutes = minutesOf(step);
		if (isTest) {
			return new Map<String, Object>{
				'summary' => BarnHelp.text('Connector', 'Connector_Run_WouldWait', new List<Object>{ minutes })
			};
		}
		Long now = Datetime.now().getTime();
		Long until = progress.get('at') == null
			? now + (Long) minutes * 60000
			: Long.valueOf(String.valueOf(progress.get('at')));
		if (now >= until) {
			return new Map<String, Object>{ 'until' => Datetime.newInstance(until) };
		}
		ConnectorStepRunner.WaitException waiting = new ConnectorStepRunner.WaitException();
		waiting.progress = new Map<String, Object>{ 'at' => until, 'until' => Datetime.newInstance(until) };
		waiting.minutes = Math.max(1, Math.ceil((until - now) / 60000.0).intValue());
		throw waiting;
	}

	/**
	 * Change Data (R-CR10): the object a saved JSON map builds from its input, read in the run's
	 * access mode; nothing is written. A record map is refused.
	 */
	public static Map<String, Object> transform(Map<String, Object> step, Object input, AccessLevel access) {
		ConnectorMapRuntime.SavedMap saved = ConnectorMapRuntime.load(
			ConnectorRecipeDocument.textOf(step.get('map')),
			access
		);
		if (String.isNotBlank(ConnectorMapRuntime.objectOf(saved.document))) {
			throw new ConnectorStepRunner.StepFailureException(
				BarnHelp.text('Connector', 'Connector_Publish_MapKind', new List<Object>{ step.get('id'), saved.name })
			);
		}
		Map<String, Object> built = ConnectorMapRuntime.buildJson(saved.document, input);
		built.put('mapVersion', saved.version);
		return built;
	}
}
