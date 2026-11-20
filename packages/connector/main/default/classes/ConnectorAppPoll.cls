/**
 * The App Poll trigger, "When an app has new items" (CN-13; canonical model R-CR1, R-CR6, R-CR16;
 * design Section 3.2; security review F1, F4, F7). Every 15 minutes it asks a connection's list
 * endpoint for its items, through `callout:` under Call an App's request rules, and queues one run
 * per new item, or one run for the batch.
 *
 * The clock cannot call out (its beat has written by then), so a due recipe gets one poll run: a
 * Queued run with no Input, marked by its Event Key. The runner, which may call out, makes the
 * poll run's GET, keeps the items whose stamp is after the recipe's Watermark, oldest first, at
 * most the trigger's limit, queues their runs, moves the Watermark and deletes the poll run, so
 * Run History lists only item runs. A poll that fails stays as a failed run: it is retried,
 * counted and logged as any run (R-CR7). The first poll after Publish only sets the Watermark.
 *
 * With sharing: it reads and writes runs only through `ConnectorRunStore`.
 */
public with sharing class ConnectorAppPoll {
	public static final String APP_POLL = 'AppPoll';
	public static final String KIND = 'appPoll';
	/** The one value path a poll's request may read: the recipe's Watermark. */
	public static final String WATERMARK_PATH = 'trigger.watermark';
	/** A poll run's Event Key holds this after the recipe Id, so a poll run is told from item runs. */
	public static final String POLL_KEY = ':poll:';
	/** The Watermark field holds 60 characters. */
	public static final Integer MOST_STAMP = 60;
	/** Items sharing the last stamp are kept together past the limit, up to this many in all. */
	public static final Integer MOST_ITEMS = 1000;
	private static final Integer BATCH_TEXT = 120000;
	private static final Pattern ITEM_PATH = Pattern.compile(
		'[A-Za-z0-9_-]{1,80}(\\[[0-9]{1,3}\\])?(\\.[A-Za-z0-9_-]{1,80}(\\[[0-9]{1,3}\\])?){0,9}'
	);
	private static final Pattern NUMERIC = Pattern.compile('-?[0-9]{1,18}(\\.[0-9]{1,18})?');

	/** Set after `poll` when the poll failed for a reason that may pass, for the runner's retry. */
	public ConnectorStepRunner.StepFailureException passingFailure;
	private List<Connector_Run__c> found = new List<Connector_Run__c>();
	private Map<Id, Connector_Recipe__c> moved = new Map<Id, Connector_Recipe__c>();
	private List<Connector_Run__c> spent = new List<Connector_Run__c>();

	/** One item of the app's list, with its id and stamp as text. */
	@TestVisible
	private class Item implements Comparable {
		Object data;
		String id;
		String stamp;

		public Integer compareTo(Object other) {
			return compareStamps(stamp, ((Item) other).stamp);
		}
	}

	/** True for a poll run the clock queued, as opposed to an item run or a test. */
	public static Boolean isPoll(Connector_Run__c run) {
		return run.Started_By__c == APP_POLL &&
			run.Is_Test__c != true &&
			run.Event_Key__c != null &&
			run.Event_Key__c.contains(POLL_KEY);
	}

	/** What is wrong with an `appPoll` trigger, in words, or null (R-CR16). */
	public static String problem(Map<String, Object> starter) {
		Object most = starter.get('limit');
		Boolean bad =
			ConnectorRecipeDocument.callStepProblem(requestOf(starter, true)) != null ||
			!itemPathOk(starter.get('items'), true) ||
			!itemPathOk(starter.get('id'), false) ||
			!itemPathOk(starter.get('stamp'), false) ||
			(starter.get('mode') != null && !ConnectorTriggers.MODES.contains(text(starter.get('mode')))) ||
			(most != null &&
			!(most instanceof Integer &&
			(Integer) most >= 1 &&
			(Integer) most <= ConnectorTriggers.MAX_POLLED));
		// A poll has no run data yet: its values are fixed, or the Watermark.
		for (String entries : new List<String>{ 'pathValues', 'query', 'headers' }) {
			for (Object raw : ConnectorRecipeDocument.listOf(starter.get(entries))) {
				String path = text(ConnectorRecipeDocument.mapOf(raw).get('path'));
				bad |= String.isNotBlank(path) && path != WATERMARK_PATH;
			}
		}
		return bad ? BarnHelp.text('Connector', 'Connector_Recipe_ErrorAppPoll') : null;
	}

	private static Boolean itemPathOk(Object raw, Boolean blankOk) {
		String path = text(raw);
		return String.isBlank(path) ? blankOk : ITEM_PATH.matcher(path).matches();
	}

	/**
	 * The trigger's request as a GET Call an App step. Before the first Watermark, query values
	 * that read it are left out, since an app may refuse a blank "since".
	 */
	private static Map<String, Object> requestOf(Map<String, Object> starter, Boolean withWatermark) {
		List<Object> query = new List<Object>();
		for (Object raw : ConnectorRecipeDocument.listOf(starter.get('query'))) {
			if (withWatermark || text(ConnectorRecipeDocument.mapOf(raw).get('path')) != WATERMARK_PATH) {
				query.add(raw);
			}
		}
		return new Map<String, Object>{
			'id' => 'trigger',
			'kind' => 'callApp',
			'method' => 'GET',
			'connection' => starter.get('connection'),
			'path' => starter.get('path'),
			'pathValues' => starter.get('pathValues'),
			'query' => query,
			'headers' => starter.get('headers')
		};
	}

	/** The clock's due App Poll recipe (R-CR6): one poll run, unless one is still waiting its turn. */
	public static List<Connector_Run__c> pollRun(Connector_Recipe__c recipe) {
		if (ConnectorRunStore.pollPending(recipe.Id)) {
			return new List<Connector_Run__c>();
		}
		Connector_Run__c run = ConnectorTriggers.newRun(recipe, APP_POLL, null);
		run.Event_Key__c = recipe.Id + POLL_KEY + Datetime.now().getTime();
		return new List<Connector_Run__c>{ run };
	}

	/**
	 * Makes one poll run's request and keeps what it found for `save`. Returns null when the poll
	 * run is spent; otherwise the run itself, left Queued when a record was written earlier in this
	 * transaction (a callout cannot follow it), or Failed with the reason in plain words.
	 */
	public Connector_Run__c poll(Connector_Run__c run, ConnectorStepRunner.Budget budget) {
		passingFailure = null;
		if (budget.wrote || budget.low()) {
			return run;
		}
		if (moved.containsKey(run.Recipe__c)) {
			// A second poll run of a recipe this job already polled finds nothing new.
			spent.add(run);
			return null;
		}
		run.Started_At__c = Datetime.now();
		Long started = System.currentTimeMillis();
		try {
			Map<String, Object> starter = ConnectorRecipeDocument.mapOf(
				ConnectorRecipeDocument.parse(run.Recipe__r.Definition_JSON__c).get('trigger')
			);
			String mark = run.Recipe__r.Watermark__c;
			Map<String, Object> answer = (Map<String, Object>) new ConnectorStepRunner(run, budget)
				.request(
					requestOf(starter, String.isNotBlank(mark)),
					new Map<String, Object>{ 'watermark' => String.isBlank(mark) ? '' : mark }
				);
			List<Item> fresh = newItems(answer.get('body'), starter, mark);
			if (!fresh.isEmpty()) {
				String last = fresh[fresh.size() - 1].stamp;
				if (last.length() > MOST_STAMP) {
					throw new ConnectorStepRunner.StepFailureException(
						BarnHelp.text('Connector', 'Connector_Poll_ErrorStamp', new List<Object>{ MOST_STAMP })
					);
				}
				if (String.isNotBlank(mark)) {
					found.addAll(runsFor(run, starter, fresh));
				}
				moved.put(run.Recipe__c, new Connector_Recipe__c(Id = run.Recipe__c, Watermark__c = last));
			}
			spent.add(run);
			return null;
		} catch (Exception problem) {
			ConnectorStepRunner.StepFailureException failed = problem instanceof ConnectorStepRunner.StepFailureException
				? (ConnectorStepRunner.StepFailureException) problem
				: new ConnectorStepRunner.StepFailureException(plain(problem));
			passingFailure = failed.passing ? failed : null;
			run.Status__c = ConnectorRunStore.FAILED;
			run.Failed_Step__c = 'trigger';
			run.Error_Message__c = failed.getMessage().left(1000);
			run.Finished_At__c = Datetime.now();
			run.Step_Log_JSON__c = JSON.serialize(
				new List<Object>{
					new Map<String, Object>{
						'step' => 'trigger',
						'kind' => KIND,
						'outcome' => 'failed',
						'ms' => System.currentTimeMillis() - started,
						'message' => run.Error_Message__c,
						'status' => failed.status,
						'response' => failed.response == null ? null : failed.response.left(ConnectorStepRunner.TRIMMED)
					}
				}
			);
			return run;
		}
	}

	/** After every callout of the transaction: the item runs, the moved Watermarks, the spent poll runs. */
	public void save() {
		if (!spent.isEmpty()) {
			ConnectorRunStore.pollSave(found, moved.values(), spent);
		}
	}

	/**
	 * The items after the Watermark, oldest first: at most the trigger's limit, with any more
	 * sharing the last one's stamp, so the next poll misses none of them. With no Watermark yet,
	 * every item, so the newest stamp becomes the first Watermark. Items with no id or stamp are
	 * left out.
	 */
	@TestVisible
	private static List<Item> newItems(Object body, Map<String, Object> starter, String mark) {
		String itemsPath = text(starter.get('items'));
		Object listed = String.isBlank(itemsPath) ? body : ConnectorMapRuntime.read(body, itemsPath);
		if (!(listed instanceof List<Object>)) {
			throw new ConnectorStepRunner.StepFailureException(
				BarnHelp.text(
					'Connector',
					'Connector_Poll_ErrorItems',
					new List<Object>{ String.isBlank(itemsPath) ? '-' : itemsPath }
				)
			);
		}
		List<Item> items = new List<Item>();
		for (Object raw : (List<Object>) listed) {
			Item item = new Item();
			item.data = raw;
			item.id = ConnectorMapRuntime.text(ConnectorMapRuntime.read(raw, text(starter.get('id'))));
			item.stamp = ConnectorMapRuntime.text(ConnectorMapRuntime.read(raw, text(starter.get('stamp'))));
			if (
				String.isNotBlank(item.id) &&
				String.isNotBlank(item.stamp) &&
				(String.isBlank(mark) || compareStamps(item.stamp, mark) > 0)
			) {
				items.add(item);
			}
		}
		items.sort();
		if (String.isBlank(mark)) {
			return items;
		}
		Object limitValue = starter.get('limit');
		Integer most = limitValue instanceof Integer ? (Integer) limitValue : ConnectorTriggers.MAX_POLLED;
		List<Item> kept = new List<Item>();
		for (Item item : items) {
			Boolean sameStamp = !kept.isEmpty() && compareStamps(item.stamp, kept[kept.size() - 1].stamp) == 0;
			if (kept.size() >= MOST_ITEMS || (kept.size() >= most && !sameStamp)) {
				break;
			}
			kept.add(item);
		}
		return kept;
	}

	/**
	 * Two stamps in order: as numbers when both are numbers (a growing id or a time in seconds),
	 * otherwise as text, which orders times written in one format (ISO 8601).
	 */
	@TestVisible
	private static Integer compareStamps(String left, String right) {
		if (NUMERIC.matcher(left).matches() && NUMERIC.matcher(right).matches()) {
			Decimal a = Decimal.valueOf(left);
			Decimal b = Decimal.valueOf(right);
			return a == b ? 0 : (a < b ? -1 : 1);
		}
		return left.compareTo(right);
	}

	/** One run per item, or one per chunk of a batch, as the recipe's identity runs them. */
	private static List<Connector_Run__c> runsFor(
		Connector_Run__c poll,
		Map<String, Object> starter,
		List<Item> items
	) {
		Connector_Recipe__c recipe = new Connector_Recipe__c(
			Id = poll.Recipe__c,
			Run_As__c = poll.Ran_As__c,
			Version__c = poll.Recipe_Version__c
		);
		List<Connector_Run__c> runs = new List<Connector_Run__c>();
		if (text(starter.get('mode')) != 'batch') {
			for (Item item : items) {
				runs.add(itemRun(recipe, new Map<String, Object>{ 'itemId' => item.id, 'item' => item.data }));
			}
			return runs;
		}
		List<Object> ids = new List<Object>();
		List<Object> chunk = new List<Object>();
		Integer size = 0;
		for (Item item : items) {
			Integer length = JSON.serialize(item.data).length();
			if (!chunk.isEmpty() && size + length > BATCH_TEXT) {
				runs.add(itemRun(recipe, new Map<String, Object>{ 'itemIds' => ids, 'items' => chunk }));
				ids = new List<Object>();
				chunk = new List<Object>();
				size = 0;
			}
			ids.add(item.id);
			chunk.add(item.data);
			size += length;
		}
		runs.add(itemRun(recipe, new Map<String, Object>{ 'itemIds' => ids, 'items' => chunk }));
		return runs;
	}

	private static Connector_Run__c itemRun(Connector_Recipe__c recipe, Map<String, Object> input) {
		String inputJson = JSON.serialize(input);
		if (inputJson.length() > ConnectorRunStore.MAX_TEXT) {
			throw new ConnectorStepRunner.StepFailureException(
				BarnHelp.text('Connector', 'Connector_Run_ErrorTooLarge')
			);
		}
		return ConnectorTriggers.newRun(recipe, APP_POLL, inputJson);
	}

	/** A fixed message naming only the exception type (F7): a raw message could echo a request. */
	private static String plain(Exception problem) {
		if (problem instanceof ConnectorRecipeDocument.DocumentException) {
			return problem.getMessage();
		}
		return BarnHelp.text('Connector', 'Connector_Run_ErrorUnexpected', new List<Object>{ problem.getTypeName() });
	}

	private static String text(Object value) {
		return ConnectorRecipeDocument.textOf(value);
	}
}
