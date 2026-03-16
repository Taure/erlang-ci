// Renders a unified GitHub PR comment from multiple CI tool outputs.
// Used by the summary job in ci.yml via actions/github-script.

const SEVERITY_ICON = {
  critical: ':red_circle:',
  high: ':orange_circle:',
  medium: ':yellow_circle:',
  low: ':green_circle:',
  negligible: ':white_circle:',
  unknown: ':white_circle:',
};

function severityLabel(sev) {
  const s = (sev || 'unknown').toLowerCase();
  const icon = SEVERITY_ICON[s] || ':white_circle:';
  const label = s.charAt(0).toUpperCase() + s.slice(1);
  return `${icon} ${label}`;
}

function renderAuditSection(auditJson) {
  if (!auditJson || !auditJson.trim()) return null;

  let audit;
  try { audit = JSON.parse(auditJson); } catch { return null; }

  const vulns = audit.vulnerabilities || [];
  const scanned = audit.dependencies_scanned || 0;
  const lines = [];

  if (vulns.length === 0) {
    lines.push('### :shield: Security Audit');
    lines.push(`No vulnerabilities found in ${scanned} dependencies.`);
  } else {
    lines.push(`### :rotating_light: Security Audit — ${vulns.length} ${vulns.length === 1 ? 'vulnerability' : 'vulnerabilities'} found`);
    lines.push('');
    lines.push('| Severity | Package | Version | Advisory | Fix |');
    lines.push('|:---:|---|---|---|---|');

    for (const v of vulns) {
      const advisory = v.cve_id
        ? `[${v.ghsa_id}](${v.url}) (${v.cve_id})`
        : `[${v.ghsa_id}](${v.url})`;
      const fix = v.patched_version
        ? `Upgrade to \`${v.patched_version}\``
        : 'No fix available';
      lines.push(`| ${severityLabel(v.severity)} | **${v.package}** | \`${v.current_version}\` | ${advisory} | ${fix} |`);
    }

    lines.push('');

    for (const v of vulns) {
      lines.push(`<details><summary>${v.ghsa_id} — ${v.package}</summary>`);
      lines.push('');
      lines.push(`> ${v.summary}`);
      lines.push(`>`);
      lines.push(`> **Vulnerable range:** \`${v.vulnerable_range}\``);
      lines.push('');
      lines.push('</details>');
      lines.push('');
    }

    lines.push(`${scanned} dependencies scanned.`);
  }

  return lines;
}

function renderSbomSection(scanJson) {
  if (!scanJson || !scanJson.trim()) return null;

  let scan;
  try { scan = JSON.parse(scanJson); } catch { return null; }

  const vulns = scan.vulnerabilities || [];

  if (vulns.length === 0) {
    return ['### :package: SBOM Scan', 'No vulnerabilities found.'];
  }

  // Deduplicate by vulnerability id + package name
  const seen = new Set();
  const unique = [];
  for (const v of vulns) {
    const key = `${v.id}:${v.package}`;
    if (!seen.has(key)) {
      seen.add(key);
      unique.push(v);
    }
  }

  const lines = [];
  lines.push(`### :package: SBOM Scan — ${unique.length} ${unique.length === 1 ? 'vulnerability' : 'vulnerabilities'} found`);
  lines.push('');
  lines.push('| Severity | Package | Version | Vulnerability | Fix |');
  lines.push('|:---:|---|---|---|---|');

  for (const v of unique) {
    const fix = v.fixed_version
      ? `Upgrade to \`${v.fixed_version}\``
      : 'No fix available';
    const vuln = v.url ? `[${v.id}](${v.url})` : v.id;
    lines.push(`| ${severityLabel(v.severity)} | **${v.package}** | \`${v.version}\` | ${vuln} | ${fix} |`);
  }

  return lines;
}

function renderIgnoredSection(ignoredJson) {
  if (!ignoredJson || !ignoredJson.trim()) return null;

  let data;
  try { data = JSON.parse(ignoredJson); } catch { return null; }

  const ignored = data.ignored || [];
  if (ignored.length === 0) return null;

  const lines = [];
  lines.push('<details><summary>:information_source: ' +
    `${ignored.length} OTP ${ignored.length === 1 ? 'CVE' : 'CVEs'} auto-ignored ` +
    '(already fixed in running version)</summary>');
  lines.push('');
  lines.push('These CVEs are patched in the installed OTP version but NVD data');
  lines.push('has not been updated to reflect this. They are excluded from the');
  lines.push('scan via an auto-generated `.trivyignore`.');
  lines.push('');
  lines.push('| CVE | Details |');
  lines.push('|---|---|');

  for (const entry of ignored) {
    const cveLink = `[${entry.id}](https://nvd.nist.gov/vuln/detail/${entry.id})`;
    lines.push(`| ${cveLink} | ${entry.reason || ''} |`);
  }

  lines.push('');
  lines.push('</details>');

  return lines;
}

function coverageBadge(pct) {
  if (pct >= 90) return ':green_circle:';
  if (pct >= 70) return ':yellow_circle:';
  if (pct >= 50) return ':orange_circle:';
  return ':red_circle:';
}

function renderCoverageSection(coverageJson) {
  if (!coverageJson || !coverageJson.trim()) return null;

  let cov;
  try { cov = JSON.parse(coverageJson); } catch { return null; }

  const pct = cov.line_rate;
  if (pct === undefined || pct === null) return null;

  const badge = coverageBadge(pct);
  const covered = cov.lines_covered || 0;
  const valid = cov.lines_valid || 0;

  return [`### ${badge} Code Coverage — ${pct}%`, `${covered} of ${valid} lines covered.`];
}

function mutateBadge(score) {
  if (score >= 80) return ':green_circle:';
  if (score >= 60) return ':yellow_circle:';
  if (score >= 40) return ':orange_circle:';
  return ':red_circle:';
}

function renderMutateSection(mutateJson) {
  if (!mutateJson || !mutateJson.trim()) return null;

  let data;
  try { data = JSON.parse(mutateJson); } catch { return null; }

  const score = data.score;
  if (score === undefined || score === null) return null;

  const total = data.total || 0;
  const killed = data.killed || 0;
  const survived = data.survived || 0;
  const timedOut = data.timed_out || 0;

  const badge = mutateBadge(score);
  const pct = Number.isInteger(score) ? `${score}%` : `${score.toFixed(1)}%`;

  const details = [];
  details.push(`${killed} killed`);
  if (survived > 0) details.push(`${survived} survived`);
  if (timedOut > 0) details.push(`${timedOut} timed out`);

  return [
    `### ${badge} Mutation Testing — ${pct}`,
    `${total} mutants tested. ${details.join(', ')}.`,
  ];
}

function renderSummary({ audit, sbom, ignored, coverage, mutate } = {}) {
  const auditLines = renderAuditSection(audit);
  const sbomLines = renderSbomSection(sbom);
  const ignoredLines = renderIgnoredSection(ignored);
  const coverageLines = renderCoverageSection(coverage);
  const mutateLines = renderMutateSection(mutate);

  if (!auditLines && !sbomLines && !ignoredLines && !coverageLines && !mutateLines) return null;

  const sections = [];
  if (coverageLines) sections.push(coverageLines);
  if (mutateLines) sections.push(mutateLines);
  if (auditLines) sections.push(auditLines);
  if (sbomLines) {
    const combined = [...sbomLines];
    if (ignoredLines) {
      combined.push('');
      combined.push(...ignoredLines);
    }
    sections.push(combined);
  } else if (ignoredLines) {
    sections.push(ignoredLines);
  }

  const lines = ['<!-- erlang-ci-summary -->'];
  for (let i = 0; i < sections.length; i++) {
    if (i > 0) lines.push('', '---', '');
    lines.push(...sections[i]);
  }

  return lines.join('\n');
}

// Backward-compatible wrapper
function renderAuditSummary(auditJson) {
  return renderSummary({ audit: auditJson });
}

module.exports = { renderAuditSummary, renderAuditSection, renderSbomSection, renderIgnoredSection, renderCoverageSection, renderMutateSection, renderSummary };
