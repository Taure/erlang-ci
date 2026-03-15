const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const { renderAuditSummary, renderAuditSection, renderSbomSection, renderSummary } = require('./ci-summary');

describe('renderAuditSection', () => {
  it('returns null for empty input', () => {
    assert.equal(renderAuditSection(''), null);
    assert.equal(renderAuditSection(null), null);
    assert.equal(renderAuditSection(undefined), null);
    assert.equal(renderAuditSection('   '), null);
  });

  it('returns null for invalid JSON', () => {
    assert.equal(renderAuditSection('not json'), null);
  });

  it('renders clean audit', () => {
    const json = JSON.stringify({ vulnerabilities: [], dependencies_scanned: 5 });
    const lines = renderAuditSection(json);
    assert.ok(Array.isArray(lines));
    const text = lines.join('\n');
    assert.ok(text.includes(':shield:'));
    assert.ok(text.includes('No vulnerabilities found in 5 dependencies'));
  });

  it('renders vulnerabilities', () => {
    const json = JSON.stringify({
      vulnerabilities: [{
        ghsa_id: 'GHSA-1234-5678-9abc',
        cve_id: 'CVE-2025-1234',
        package: 'cowboy',
        current_version: '2.10.0',
        severity: 'high',
        vulnerable_range: '< 2.12.0',
        patched_version: '2.12.0',
        summary: 'HTTP request smuggling in cowboy',
        url: 'https://github.com/advisories/GHSA-1234-5678-9abc'
      }],
      dependencies_scanned: 8
    });
    const lines = renderAuditSection(json);
    const text = lines.join('\n');
    assert.ok(text.includes(':rotating_light:'));
    assert.ok(text.includes('1 vulnerability found'));
    assert.ok(text.includes(':orange_circle: High'));
    assert.ok(text.includes('**cowboy**'));
    assert.ok(text.includes('`2.10.0`'));
    assert.ok(text.includes('[GHSA-1234-5678-9abc]'));
    assert.ok(text.includes('(CVE-2025-1234)'));
    assert.ok(text.includes('Upgrade to `2.12.0`'));
    assert.ok(text.includes('HTTP request smuggling'));
    assert.ok(text.includes('`< 2.12.0`'));
    assert.ok(text.includes('8 dependencies scanned'));
  });
});

describe('renderSbomSection', () => {
  it('returns null for empty input', () => {
    assert.equal(renderSbomSection(''), null);
    assert.equal(renderSbomSection(null), null);
    assert.equal(renderSbomSection(undefined), null);
    assert.equal(renderSbomSection('   '), null);
  });

  it('returns null for invalid JSON', () => {
    assert.equal(renderSbomSection('not json'), null);
  });

  it('renders clean scan', () => {
    const json = JSON.stringify({ matches: [] });
    const lines = renderSbomSection(json);
    assert.ok(Array.isArray(lines));
    const text = lines.join('\n');
    assert.ok(text.includes(':package: SBOM Scan'));
    assert.ok(text.includes('No vulnerabilities found'));
  });

  it('renders single vulnerability', () => {
    const json = JSON.stringify({
      matches: [{
        id: 'CVE-2025-9999',
        severity: 'Critical',
        package: 'pgo',
        version: '0.14.0',
        fix_versions: ['0.15.0'],
        fix_state: 'fixed',
        url: 'https://nvd.nist.gov/vuln/detail/CVE-2025-9999'
      }]
    });
    const lines = renderSbomSection(json);
    const text = lines.join('\n');
    assert.ok(text.includes('1 vulnerability found'));
    assert.ok(text.includes(':red_circle: Critical'));
    assert.ok(text.includes('**pgo**'));
    assert.ok(text.includes('`0.14.0`'));
    assert.ok(text.includes('[CVE-2025-9999]'));
    assert.ok(text.includes('Upgrade to `0.15.0`'));
  });

  it('renders vulnerability with no fix', () => {
    const json = JSON.stringify({
      matches: [{
        id: 'CVE-2025-0001',
        severity: 'High',
        package: 'cowlib',
        version: '2.12.0',
        fix_versions: [],
        fix_state: 'not-fixed',
        url: ''
      }]
    });
    const lines = renderSbomSection(json);
    const text = lines.join('\n');
    assert.ok(text.includes('No fix available'));
    assert.ok(text.includes('CVE-2025-0001'));
    assert.ok(!text.includes('[CVE-2025-0001](')); // no link when url is empty
  });

  it('deduplicates matches by id + package', () => {
    const json = JSON.stringify({
      matches: [
        { id: 'CVE-2025-1111', severity: 'High', package: 'cowboy', version: '2.10.0', fix_versions: ['2.12.0'], fix_state: 'fixed', url: 'https://example.com/1' },
        { id: 'CVE-2025-1111', severity: 'High', package: 'cowboy', version: '2.10.0', fix_versions: ['2.12.0'], fix_state: 'fixed', url: 'https://example.com/2' },
        { id: 'CVE-2025-2222', severity: 'Medium', package: 'ranch', version: '1.8.0', fix_versions: [], fix_state: 'not-fixed', url: '' },
      ]
    });
    const lines = renderSbomSection(json);
    const text = lines.join('\n');
    assert.ok(text.includes('2 vulnerabilities found'));
    // Should keep first occurrence
    assert.ok(text.includes('https://example.com/1'));
    assert.ok(!text.includes('https://example.com/2'));
  });

  it('renders multiple severities', () => {
    const json = JSON.stringify({
      matches: [
        { id: 'CVE-1', severity: 'Critical', package: 'a', version: '1.0', fix_versions: [], fix_state: 'unknown', url: '' },
        { id: 'CVE-2', severity: 'Low', package: 'b', version: '2.0', fix_versions: ['2.1'], fix_state: 'fixed', url: '' },
        { id: 'CVE-3', severity: 'Negligible', package: 'c', version: '3.0', fix_versions: [], fix_state: 'unknown', url: '' },
      ]
    });
    const lines = renderSbomSection(json);
    const text = lines.join('\n');
    assert.ok(text.includes(':red_circle: Critical'));
    assert.ok(text.includes(':green_circle: Low'));
    assert.ok(text.includes(':white_circle: Negligible'));
  });
});

describe('renderSummary', () => {
  it('returns null when no data', () => {
    assert.equal(renderSummary({}), null);
    assert.equal(renderSummary({ audit: '', sbom: '' }), null);
    assert.equal(renderSummary(), null);
  });

  it('renders audit only', () => {
    const audit = JSON.stringify({ vulnerabilities: [], dependencies_scanned: 3 });
    const result = renderSummary({ audit });
    assert.ok(result.startsWith('<!-- erlang-ci-summary -->'));
    assert.ok(result.includes(':shield:'));
    assert.ok(!result.includes(':package:'));
    assert.ok(!result.includes('---'));
  });

  it('renders sbom only', () => {
    const sbom = JSON.stringify({ matches: [] });
    const result = renderSummary({ sbom });
    assert.ok(result.startsWith('<!-- erlang-ci-summary -->'));
    assert.ok(result.includes(':package:'));
    assert.ok(!result.includes(':shield:'));
    assert.ok(!result.includes('---'));
  });

  it('renders both with separator', () => {
    const audit = JSON.stringify({ vulnerabilities: [], dependencies_scanned: 5 });
    const sbom = JSON.stringify({ matches: [] });
    const result = renderSummary({ audit, sbom });
    assert.ok(result.startsWith('<!-- erlang-ci-summary -->'));
    assert.ok(result.includes(':shield:'));
    assert.ok(result.includes(':package:'));
    assert.ok(result.includes('---'));
  });

  it('includes marker exactly once', () => {
    const audit = JSON.stringify({ vulnerabilities: [], dependencies_scanned: 1 });
    const sbom = JSON.stringify({ matches: [] });
    const result = renderSummary({ audit, sbom });
    const markerCount = (result.match(/<!-- erlang-ci-summary -->/g) || []).length;
    assert.equal(markerCount, 1);
  });

  it('skips section with invalid JSON', () => {
    const sbom = JSON.stringify({ matches: [] });
    const result = renderSummary({ audit: 'broken', sbom });
    assert.ok(result.includes(':package:'));
    assert.ok(!result.includes(':shield:'));
    assert.ok(!result.includes('---'));
  });
});

describe('renderAuditSummary (backward compat)', () => {
  it('returns full comment body with marker', () => {
    const json = JSON.stringify({ vulnerabilities: [], dependencies_scanned: 5 });
    const result = renderAuditSummary(json);
    assert.ok(result.startsWith('<!-- erlang-ci-summary -->'));
    assert.ok(result.includes('No vulnerabilities found in 5 dependencies'));
  });

  it('returns null for empty input', () => {
    assert.equal(renderAuditSummary(''), null);
    assert.equal(renderAuditSummary(null), null);
  });
});
