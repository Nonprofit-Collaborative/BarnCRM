import { startPolling } from '../jobPoller';

async function advance(milliseconds) {
  jest.advanceTimersByTime(milliseconds);
  // Let the awaited tick settle and the next one be scheduled.
  await Promise.resolve();
  await Promise.resolve();
}

describe('jobPoller', () => {
  beforeEach(() => {
    jest.useFakeTimers();
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  it('polls every 3 seconds, then every 10 seconds after the first minute', async () => {
    const tick = jest.fn().mockResolvedValue(false);
    const stop = startPolling(tick, jest.fn());

    await advance(2999);
    expect(tick).not.toHaveBeenCalled();
    await advance(1);
    expect(tick).toHaveBeenCalledTimes(1);

    // 20 ticks fit in the first minute at 3 seconds each.
    for (let i = 0; i < 19; i++) {
      // eslint-disable-next-line no-await-in-loop
      await advance(3000);
    }
    expect(tick).toHaveBeenCalledTimes(20);

    await advance(3000);
    expect(tick).toHaveBeenCalledTimes(20);
    await advance(7000);
    expect(tick).toHaveBeenCalledTimes(21);
    stop();
  });

  it('stops when the tick says the job is finished', async () => {
    const tick = jest.fn().mockResolvedValue(true);
    startPolling(tick, jest.fn());

    await advance(3000);
    await advance(30000);

    expect(tick).toHaveBeenCalledTimes(1);
  });

  it('retries once after a failed call, and tells the caller after a second one', async () => {
    const tick = jest.fn().mockRejectedValue(new Error('network'));
    const onFail = jest.fn();
    startPolling(tick, onFail);

    await advance(3000);
    expect(onFail).not.toHaveBeenCalled();
    await advance(3000);

    expect(tick).toHaveBeenCalledTimes(2);
    expect(onFail).toHaveBeenCalledTimes(1);
    await advance(30000);
    expect(tick).toHaveBeenCalledTimes(2);
  });

  it('forgives one failure when the next call works', async () => {
    const tick = jest
      .fn()
      .mockRejectedValueOnce(new Error('blip'))
      .mockResolvedValueOnce(false)
      .mockRejectedValueOnce(new Error('blip'))
      .mockResolvedValue(true);
    const onFail = jest.fn();
    startPolling(tick, onFail);

    for (let i = 0; i < 4; i++) {
      // eslint-disable-next-line no-await-in-loop
      await advance(3000);
    }

    expect(tick).toHaveBeenCalledTimes(4);
    expect(onFail).not.toHaveBeenCalled();
  });

  it('does nothing more once stopped', async () => {
    const tick = jest.fn().mockResolvedValue(false);
    const stop = startPolling(tick, jest.fn());
    stop();

    await advance(60000);

    expect(tick).not.toHaveBeenCalled();
  });
});
