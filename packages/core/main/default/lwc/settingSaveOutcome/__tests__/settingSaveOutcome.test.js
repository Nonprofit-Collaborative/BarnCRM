import { waitForSave } from 'c/settingSaveOutcome';
import getSaveOutcome from '@salesforce/apex/SettingsController.getSaveOutcome';

jest.mock('@salesforce/apex/SettingsController.getSaveOutcome', () => ({ default: jest.fn() }), {
  virtual: true
});

describe('c-setting-save-outcome', () => {
  const realTimeout = global.setTimeout;

  beforeEach(() => {
    jest.spyOn(global, 'setTimeout').mockImplementation((fn) => realTimeout(fn, 0));
  });

  afterEach(() => {
    global.setTimeout.mockRestore();
    jest.clearAllMocks();
  });

  it('treats a save with no deployment as done', async () => {
    expect(await waitForSave(null)).toEqual({ status: 'Succeeded' });
    expect(getSaveOutcome).not.toHaveBeenCalled();
  });

  it('asks until the deployment succeeds', async () => {
    getSaveOutcome
      .mockResolvedValueOnce({ status: 'Pending' })
      .mockResolvedValueOnce({ status: 'Succeeded' });
    const outcome = await waitForSave('0Af000000000001');
    expect(outcome.status).toBe('Succeeded');
    expect(getSaveOutcome).toHaveBeenCalledTimes(2);
    expect(getSaveOutcome).toHaveBeenCalledWith({ deploymentId: '0Af000000000001' });
  });

  it('passes on the reason a deployment failed', async () => {
    getSaveOutcome.mockResolvedValue({ status: 'Failed', message: 'Turn on the Setup switch.' });
    expect(await waitForSave('0Af000000000002')).toEqual({
      status: 'Failed',
      message: 'Turn on the Setup switch.'
    });
  });

  it('stops asking after the attempts it was given', async () => {
    getSaveOutcome.mockResolvedValue({ status: 'Pending' });
    expect(await waitForSave('0Af000000000003', 3)).toEqual({ status: 'Pending' });
    expect(getSaveOutcome).toHaveBeenCalledTimes(3);
  });
});
