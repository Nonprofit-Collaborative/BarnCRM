import { loadStyle } from 'lightning/platformResourceLoader';
import { printPage } from 'c/fundersPrint';

jest.mock('lightning/platformResourceLoader', () => ({ loadStyle: jest.fn() }), {
  virtual: true
});

describe('c/fundersPrint', () => {
  let print;

  beforeEach(() => {
    print = jest.spyOn(window, 'print').mockImplementation(() => undefined);
  });

  afterEach(() => {
    jest.restoreAllMocks();
    loadStyle.mockReset();
  });

  it('loads the print stylesheet, then opens the print dialog', async () => {
    loadStyle.mockResolvedValue(undefined);
    const page = {};
    await printPage(page);
    expect(loadStyle).toHaveBeenCalledWith(page, expect.anything());
    expect(print).toHaveBeenCalledTimes(1);
  });

  it('still prints when the stylesheet cannot load', async () => {
    loadStyle.mockRejectedValue(new Error('blocked'));
    await printPage({});
    expect(print).toHaveBeenCalledTimes(1);
  });
});
