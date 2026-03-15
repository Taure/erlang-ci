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

function renderSbomSection(grypeJson) {
  if (!grypeJson || !grypeJson.trim()) return null;

  let grype;
  try { grype = JSON.parse(grypeJson); } catch { return null; }

  const matches = grype.matches || [];

  if (matches.length === 0) {
    return ['### :package: SBOM Scan', 'No vulnerabilities found.'];
  }

  // Deduplicate by vulnerability id + package name
  const seen = new Set();
  const unique = [];
  for (const m of matches) {
    const key = `${m.id}:${m.package}`;
    if (!seen.has(key)) {
      seen.add(key);
      unique.push(m);
    }
  }

  const lines = [];
  lines.push(`### :package: SBOM Scan — ${unique.length} ${unique.length === 1 ? 'vulnerability' : 'vulnerabilities'} found`);
  lines.push('');
  lines.push('| Severity | Package | Version | Vulnerability | Fix |');
  lines.push('|:---:|---|---|---|---|');

  for (const m of unique) {
    const fix = m.fix_state === 'fixed' && m.fix_versions && m.fix_versions.length > 0
      ? `Upgrade to \`${m.fix_versions[0]}\``
      : 'No fix available';
    const vuln = m.url ? `[${m.id}](${m.url})` : m.id;
    lines.push(`| ${severityLabel(m.severity)} | **${m.package}** | \`${m.version}\` | ${vuln} | ${fix} |`);
  }

  return lines;
}

function renderSummary({ audit, sbom } = {}) {
  const auditLines = renderAuditSection(audit);
  const sbomLines = renderSbomSection(sbom);

  if (!auditLines && !sbomLines) return null;

  const lines = ['<!-- erlang-ci-summary -->'];
  if (auditLines) lines.push(...auditLines);
  if (auditLines && sbomLines) lines.push('', '---', '');
  if (sbomLines) lines.push(...sbomLines);

  return lines.join('\n');
}

// Backward-compatible wrapper
function renderAuditSummary(auditJson) {
  return renderSummary({ audit: auditJson });
}

module.exports = { renderAuditSummary, renderAuditSection, renderSbomSection, renderSummary };
