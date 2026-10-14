/**
 * Polls a running data job without hammering the server (FINDB-19): every 3 seconds for the
 * first minute, every 10 seconds after that, and one retry when a call fails before it gives
 * up. A 48,000 record job is several hundred reads at a flat 3 seconds, and one network blip
 * used to stop the progress display for good.
 */

export const FAST_MILLISECONDS = 3000;
export const SLOW_MILLISECONDS = 10000;
export const FAST_PERIOD_MILLISECONDS = 60000;

/**
 * Starts polling and returns a function that stops it.
 *
 * @param {Function} tick async; resolves true when the job is finished and polling should stop
 * @param {Function} onFail called with the error when a second call in a row fails
 * @returns {Function} stops the polling
 */
export function startPolling(tick, onFail) {
  const startedAt = Date.now();
  let timer;
  let stopped = false;
  let failures = 0;
  let run;

  const schedule = () => {
    const delay =
      Date.now() - startedAt < FAST_PERIOD_MILLISECONDS ? FAST_MILLISECONDS : SLOW_MILLISECONDS;
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    timer = setTimeout(run, delay);
  };

  run = async () => {
    try {
      const finished = await tick();
      failures = 0;
      if (!stopped && !finished) {
        schedule();
      }
    } catch (error) {
      failures++;
      if (stopped) {
        return;
      }
      if (failures > 1) {
        onFail(error);
      } else {
        schedule();
      }
    }
  };

  schedule();
  return () => {
    stopped = true;
    clearTimeout(timer);
  };
}
