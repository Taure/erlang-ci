const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const { renderAuditSummary, renderAuditSection, renderSbomSection, renderIgnoredSection, renderCoverageSection, renderSummary } = require('./ci-summary');

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
    const json = JSON.stringify({ vulnerabilities: [] });
    const lines = renderSbomSection(json);
    assert.ok(Array.isArray(lines));
    const text = lines.join('\n');
    assert.ok(text.includes(':package: SBOM Scan'));
    assert.ok(text.includes('No vulnerabilities found'));
  });

  it('renders single vulnerability', () => {
    const json = JSON.stringify({
      vulnerabilities: [{
        id: 'CVE-2025-9999',
        severity: 'Critical',
        package: 'pgo',
        version: '0.14.0',
        fixed_version: '0.15.0',
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
      vulnerabilities: [{
        id: 'CVE-2025-0001',
        severity: 'High',
        package: 'cowlib',
        version: '2.12.0',
        fixed_version: '',
        url: ''
      }]
    });
    const lines = renderSbomSection(json);
    const text = lines.join('\n');
    assert.ok(text.includes('No fix available'));
    assert.ok(text.includes('CVE-2025-0001'));
    assert.ok(!text.includes('[CVE-2025-0001](')); // no link when url is empty
  });

  it('deduplicates by id + package', () => {
    const json = JSON.stringify({
      vulnerabilities: [
        { id: 'CVE-2025-1111', severity: 'High', package: 'cowboy', version: '2.10.0', fixed_version: '2.12.0', url: 'https://example.com/1' },
        { id: 'CVE-2025-1111', severity: 'High', package: 'cowboy', version: '2.10.0', fixed_version: '2.12.0', url: 'https://example.com/2' },
        { id: 'CVE-2025-2222', severity: 'Medium', package: 'ranch', version: '1.8.0', fixed_version: '', url: '' },
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
      vulnerabilities: [
        { id: 'CVE-1', severity: 'Critical', package: 'a', version: '1.0', fixed_version: '', url: '' },
        { id: 'CVE-2', severity: 'Low', package: 'b', version: '2.0', fixed_version: '2.1', url: '' },
        { id: 'CVE-3', severity: 'Negligible', package: 'c', version: '3.0', fixed_version: '', url: '' },
      ]
    });
    const lines = renderSbomSection(json);
    const text = lines.join('\n');
    assert.ok(text.includes(':red_circle: Critical'));
    assert.ok(text.includes(':green_circle: Low'));
    assert.ok(text.includes(':white_circle: Negligible'));
  });
});

describe('renderIgnoredSection', () => {
  it('returns null for empty input', () => {
    assert.equal(renderIgnoredSection(''), null);
    assert.equal(renderIgnoredSection(null), null);
    assert.equal(renderIgnoredSection('   '), null);
  });

  it('returns null for empty ignored list', () => {
    const json = JSON.stringify({ ignored: [] });
    assert.equal(renderIgnoredSection(json), null);
  });

  it('renders ignored CVEs in collapsible section', () => {
    const json = JSON.stringify({
      ignored: [
        { id: 'CVE-2025-48041', reason: 'Fixed in 28.0.3, running 28.4.1 — SSH_FXP_OPENDIR issue' },
        { id: 'CVE-2025-4748', reason: 'Fixed in 28.0.1, running 28.4.1 — Absolute Path in Zip Module' },
      ]
    });
    const lines = renderIgnoredSection(json);
    const text = lines.join('\n');
    assert.ok(text.includes('2 OTP CVEs auto-ignored'));
    assert.ok(text.includes('already fixed in running version'));
    assert.ok(text.includes('<details>'));
    assert.ok(text.includes('[CVE-2025-48041]'));
    assert.ok(text.includes('[CVE-2025-4748]'));
    assert.ok(text.includes('NVD data'));
    assert.ok(text.includes('.trivyignore'));
  });

  it('uses singular for single CVE', () => {
    const json = JSON.stringify({
      ignored: [{ id: 'CVE-2025-1234', reason: 'Fixed in 28.0.1' }]
    });
    const lines = renderIgnoredSection(json);
    const text = lines.join('\n');
    assert.ok(text.includes('1 OTP CVE auto-ignored'));
  });
});

describe('renderCoverageSection', () => {
  it('returns null for empty input', () => {
    assert.equal(renderCoverageSection(''), null);
    assert.equal(renderCoverageSection(null), null);
    assert.equal(renderCoverageSection('   '), null);
  });

  it('renders high coverage with green badge', () => {
    const json = JSON.stringify({ line_rate: 92.5, lines_covered: 1285, lines_valid: 1390 });
    const lines = renderCoverageSection(json);
    const text = lines.join('\n');
    assert.ok(text.includes(':green_circle:'));
    assert.ok(text.includes('92.5%'));
    assert.ok(text.includes('1285 of 1390 lines'));
  });

  it('renders medium coverage with yellow badge', () => {
    const json = JSON.stringify({ line_rate: 75.0, lines_covered: 750, lines_valid: 1000 });
    const lines = renderCoverageSection(json);
    const text = lines.join('\n');
    assert.ok(text.includes(':yellow_circle:'));
    assert.ok(text.includes('75%'));
  });

  it('renders low coverage with orange badge', () => {
    const json = JSON.stringify({ line_rate: 55.0, lines_covered: 55, lines_valid: 100 });
    const lines = renderCoverageSection(json);
    const text = lines.join('\n');
    assert.ok(text.includes(':orange_circle:'));
  });

  it('renders very low coverage with red badge', () => {
    const json = JSON.stringify({ line_rate: 30.0, lines_covered: 30, lines_valid: 100 });
    const lines = renderCoverageSection(json);
    const text = lines.join('\n');
    assert.ok(text.includes(':red_circle:'));
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
    const sbom = JSON.stringify({ vulnerabilities: [] });
    const result = renderSummary({ sbom });
    assert.ok(result.startsWith('<!-- erlang-ci-summary -->'));
    assert.ok(result.includes(':package:'));
    assert.ok(!result.includes(':shield:'));
    assert.ok(!result.includes('---'));
  });

  it('renders both with separator', () => {
    const audit = JSON.stringify({ vulnerabilities: [], dependencies_scanned: 5 });
    const sbom = JSON.stringify({ vulnerabilities: [] });
    const result = renderSummary({ audit, sbom });
    assert.ok(result.startsWith('<!-- erlang-ci-summary -->'));
    assert.ok(result.includes(':shield:'));
    assert.ok(result.includes(':package:'));
    assert.ok(result.includes('---'));
  });

  it('includes marker exactly once', () => {
    const audit = JSON.stringify({ vulnerabilities: [], dependencies_scanned: 1 });
    const sbom = JSON.stringify({ vulnerabilities: [] });
    const result = renderSummary({ audit, sbom });
    const markerCount = (result.match(/<!-- erlang-ci-summary -->/g) || []).length;
    assert.equal(markerCount, 1);
  });

  it('skips section with invalid JSON', () => {
    const sbom = JSON.stringify({ vulnerabilities: [] });
    const result = renderSummary({ audit: 'broken', sbom });
    assert.ok(result.includes(':package:'));
    assert.ok(!result.includes(':shield:'));
    assert.ok(!result.includes('---'));
  });

  it('renders ignored section alongside sbom', () => {
    const sbom = JSON.stringify({ vulnerabilities: [] });
    const ignored = JSON.stringify({ ignored: [{ id: 'CVE-2025-48041', reason: 'Fixed in 28.0.3' }] });
    const result = renderSummary({ sbom, ignored });
    assert.ok(result.includes(':package:'));
    assert.ok(result.includes('1 OTP CVE auto-ignored'));
    assert.ok(result.includes('<details>'));
  });

  it('renders ignored section alone', () => {
    const ignored = JSON.stringify({ ignored: [{ id: 'CVE-2025-48041', reason: 'Fixed in 28.0.3' }] });
    const result = renderSummary({ ignored });
    assert.ok(result.startsWith('<!-- erlang-ci-summary -->'));
    assert.ok(result.includes('1 OTP CVE auto-ignored'));
  });

  it('renders coverage section', () => {
    const coverage = JSON.stringify({ line_rate: 85.3, lines_covered: 1285, lines_valid: 1506 });
    const result = renderSummary({ coverage });
    assert.ok(result.startsWith('<!-- erlang-ci-summary -->'));
    assert.ok(result.includes('85.3%'));
    assert.ok(result.includes(':yellow_circle:'));
  });

  it('renders coverage first then audit', () => {
    const coverage = JSON.stringify({ line_rate: 95.0, lines_covered: 950, lines_valid: 1000 });
    const audit = JSON.stringify({ vulnerabilities: [], dependencies_scanned: 5 });
    const result = renderSummary({ audit, coverage });
    const coveragePos = result.indexOf('95%');
    const auditPos = result.indexOf(':shield:');
    assert.ok(coveragePos < auditPos, 'coverage should appear before audit');
    assert.ok(result.includes('---'));
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
