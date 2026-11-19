import { MAX_CATEGORIES, chartModel, niceScale, niceStep, seriesOf } from 'c/reportingChartModel';
import { arrangeGroups, normalizeReport } from 'c/reportingModel';

const fmt = (value) => String(value);

function report(type, extra = {}) {
  return normalizeReport({
    object: 'Gift__c',
    groups: [{ field: 'Fund__c', type: 'reference' }],
    measures: [{ fn: 'sum', path: 'Amount__c', label: 'Amount', type: 'currency' }],
    view: { type },
    sort: { by: 'g0', direction: 'asc' },
    ...extra
  });
}

function arranged(definition, rows) {
  return arrangeGroups(definition, { groups: rows }, { blank: '(Blank)' });
}

const ROWS = [
  { keys: [['a']], labels: ['Alpha'], values: [10] },
  { keys: [['b']], labels: ['Beta'], values: [30] },
  { keys: [['c']], labels: ['Gamma'], values: [-5] }
];

describe('reportingChartModel', () => {
  it('picks nice steps and scales with zero on the axis', () => {
    expect(niceStep(0)).toBe(1);
    expect(niceStep(10)).toBe(2);
    expect(niceStep(37)).toBe(10);
    expect(niceStep(900)).toBe(200);
    const scale = niceScale([12, 47]);
    expect(scale.min).toBe(0);
    expect(scale.max).toBe(50);
    expect(scale.ticks[0]).toBe(0);
    expect(niceScale([-8, 3]).min).toBeLessThan(0);
    expect(niceScale([]).max).toBeGreaterThan(0);
  });

  it('splits two groupings into categories and series', () => {
    const definition = report('column', {
      groups: [
        { field: 'Fund__c', type: 'reference' },
        { field: 'Status__c', type: 'picklist' }
      ]
    });
    const data = seriesOf(
      definition,
      arranged(definition, [
        { keys: [['a'], ['Paid']], labels: ['Alpha', null], values: [1] },
        { keys: [['a'], ['Open']], labels: ['Alpha', null], values: [2] },
        { keys: [['b'], ['Paid']], labels: ['Beta', null], values: [3] }
      ])
    );
    expect(data.categories.map((category) => category.label)).toEqual(['Alpha', 'Beta']);
    expect(data.series.map((entry) => entry.label).sort()).toEqual(['Open', 'Paid']);
    expect(data.values.flat().reduce((sum, value) => sum + value, 0)).toBe(6);
    expect(data.measureIndex(1)).toBe(0);
  });

  it('cuts to the largest categories a chart can show', () => {
    const definition = report('column', { limit: 100 });
    const rows = Array.from({ length: MAX_CATEGORIES + 5 }, (unused, index) => ({
      keys: [[`k${index}`]],
      labels: [`L${index}`],
      values: [index]
    }));
    const chart = chartModel(definition, arranged(definition, rows), fmt);
    expect(chart.cut).toBe(true);
    expect(chart.categories).toBe(MAX_CATEGORIES);
  });

  it.each(['column', 'line', 'bar'])('draws a %s chart with a title on every mark', (type) => {
    const definition = report(type);
    const chart = chartModel(definition, arranged(definition, ROWS), fmt);
    expect(chart.kind).toBe(type);
    expect(chart.viewBox).toMatch(/^0 0 \d+ \d+$/);
    const marks = type === 'line' ? chart.circles : chart.rects;
    expect(marks).toHaveLength(3);
    marks.forEach((mark) => expect(mark.title).toBeTruthy());
    expect(chart.texts.length).toBeGreaterThan(0);
    expect(chart.largest).toBe('Beta: 30');
    expect(chart.legend).toEqual([]);
  });

  it('stacks the series of a column chart and shows a legend', () => {
    const definition = report('column', {
      groups: [
        { field: 'Fund__c', type: 'reference' },
        { field: 'Status__c', type: 'picklist' }
      ],
      view: { type: 'column', stacked: true }
    });
    const chart = chartModel(
      definition,
      arranged(definition, [
        { keys: [['a'], ['Paid']], labels: ['Alpha', null], values: [1] },
        { keys: [['a'], ['Open']], labels: ['Alpha', null], values: [2] }
      ]),
      fmt
    );
    expect(chart.rects).toHaveLength(2);
    expect(chart.legend).toHaveLength(2);
    expect(chart.legend[0].swatch).toMatch(/^swatch tone\d$/);
  });

  it('draws a donut with an Other slice and the total in the middle', () => {
    const definition = report('donut', { limit: 50 });
    const rows = Array.from({ length: 13 }, (unused, index) => ({
      keys: [[`k${index}`]],
      labels: [`L${index}`],
      values: [index + 1]
    }));
    const chart = chartModel(definition, arranged(definition, rows), fmt, { other: 'Other' });
    expect(chart.kind).toBe('donut');
    expect(chart.paths.length).toBeLessThanOrEqual(11);
    expect(chart.legend.some((entry) => entry.label.startsWith('Other'))).toBe(true);
    expect(chart.texts.find((text) => text.css === 'total').text).toBe('91');
  });

  it('gives a metric its first total', () => {
    const definition = report('metric', { groups: [] });
    expect(chartModel(definition, arranged(definition, [{ keys: [], values: [42] }]), fmt)).toEqual(
      {
        kind: 'metric',
        value: 42,
        label: 'Amount'
      }
    );
    expect(chartModel(definition, { items: [] }, fmt).value).toBeNull();
  });
});
