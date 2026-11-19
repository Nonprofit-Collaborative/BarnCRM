import { createElement } from 'lwc';
import ReportingChart from 'c/reportingChart';
import { expectAccessible } from 'barn/a11y';

const CHART = {
  viewBox: '0 0 640 320',
  lines: [{ key: 'l0', x1: 0, x2: 640, y1: 300, y2: 300, css: 'axis' }],
  rects: [
    { key: 'r0', x: 10, y: 10, width: 20, height: 290, css: 'mark tone0', title: 'Alpha: 10' }
  ],
  paths: [{ key: 'p0', d: 'M0 0', css: 'mark tone1', title: 'Beta: 5' }],
  circles: [{ key: 'c0', cx: 1, cy: 1, r: 3, css: 'mark tone2', title: 'Gamma: 1' }],
  texts: [{ key: 't0', x: 5, y: 315, anchor: 'middle', css: 'category', text: 'Alpha' }],
  legend: [
    { key: 'k0', label: 'Paid', swatch: 'swatch tone0' },
    { key: 'k1', label: 'Open', swatch: 'swatch tone1' }
  ]
};

function mount(props) {
  const element = createElement('c-reporting-chart', { is: ReportingChart });
  Object.assign(element, props);
  document.body.appendChild(element);
  return element;
}

describe('c-reporting-chart', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('draws the shapes as one named image with a legend', async () => {
    const element = mount({ chart: CHART, summary: 'Amount by fund' });
    await Promise.resolve();
    const svg = element.shadowRoot.querySelector('[data-id="svg"]');
    expect(svg.getAttribute('role')).toBe('img');
    expect(svg.getAttribute('aria-label')).toBe('Amount by fund');
    expect(svg.querySelectorAll('rect')).toHaveLength(1);
    expect(svg.querySelector('rect title').textContent).toBe('Alpha: 10');
    expect(svg.querySelectorAll('path')).toHaveLength(1);
    expect(svg.querySelectorAll('circle')).toHaveLength(1);
    expect(svg.querySelector('text').textContent).toBe('Alpha');
    expect(element.shadowRoot.querySelectorAll('[data-id="legend"] li')).toHaveLength(2);
    await expectAccessible(element);
  });

  it('leaves the legend out for a single series', async () => {
    const element = mount({ chart: { ...CHART, legend: [] } });
    await Promise.resolve();
    expect(element.shadowRoot.querySelector('[data-id="legend"]')).toBeNull();
  });

  it('draws nothing before a chart arrives', async () => {
    const element = mount({});
    await Promise.resolve();
    expect(element.shadowRoot.querySelectorAll('rect')).toHaveLength(0);
  });
});
