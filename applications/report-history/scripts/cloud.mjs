// All administration goes through clickhousectl; no Cloud API secrets are copied.
import { execFileSync } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { setTimeout } from 'node:timers/promises';
import { isIP } from 'node:net';

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const stateFile = join(root, '.cloud-service.json');
const intentFile = join(root, '.cloud-create-intent.json');
const credentialFile = join(root, '.env');
function cli(args, input, timeout = 120_000) {
  const intent = existsSync(intentFile) ? JSON.parse(readFileSync(intentFile, 'utf8')) : {};
  if (intent.orgId && !args.includes('--org-id')) args = [...args, '--org-id', intent.orgId];
  try {
    return execFileSync('clickhousectl', ['cloud', 'service', ...args], {
      encoding: 'utf8', input, stdio: ['pipe', 'pipe', 'pipe'], timeout,
    });
  } catch (error) {
    // Query SQL can contain a password; never print command/argv on failure.
    const detail = String(error.stderr ?? '').replace(/IDENTIFIED BY '[^']*'/gi, "IDENTIFIED BY '[redacted]'")
      .replace(/[a-f0-9]{64}/g, '[redacted]');
    throw new Error(`clickhousectl ${args[0]} failed (exit ${error.status ?? 'unknown'}). ` +
      `Credential files were retained. ${detail}`);
  }
}
function save(path, value) {
  writeFileSync(path, JSON.stringify(value, null, 2) + '\n', { mode: 0o600, flag: 'wx' });
}
function state() { return JSON.parse(readFileSync(stateFile, 'utf8')); }
function query(id, sql) {
  return cli(['query', '--id', id, '--queries-file', '-', '--json'], sql);
}
async function waitRunning(id) {
  const deadline = Date.now() + 600_000;
  while (Date.now() < deadline) {
    const service = JSON.parse(cli(['get', id, '--json'], undefined, Math.min(120_000, deadline - Date.now())));
    console.log(`Service ${id}: ${service.state}`);
    if (service.state === 'running') return service;
    if (['failed', 'deleted', 'terminated', 'stopped'].includes(service.state)) {
      throw new Error(`Service is ${service.state}; inspect it before retrying.`);
    }
    await setTimeout(Math.min(10_000, Math.max(0, deadline - Date.now())));
  }
  throw new Error('Service did not become running within ten minutes. State file retained.');
}

try {
  const command = process.argv[2];
  if (command === 'create') {
    if (existsSync(stateFile) || existsSync(intentFile) || existsSync(join(root, '.cloud-create-response.json'))) {
      throw new Error('A service creation was already attempted. Use setup if its ID was saved. Otherwise inspect ' +
        '`clickhousectl cloud service list` and run `node scripts/cloud.mjs recover <service-id>`; do not blindly create another service.');
    }
    const ip = process.env.REPORT_DEMO_IP;
    if (!ip || !isIP(ip)) throw new Error('Set REPORT_DEMO_IP to your public IPv4 or IPv6 address (no CIDR).');
    const name = process.env.REPORT_DEMO_SERVICE_NAME || 'report-history-example';
    const org = process.env.REPORT_DEMO_ORG_ID;
    const args = ['create', '--name', name, '--provider', 'aws', '--region', 'eu-west-1',
      '--min-replica-memory-gb', '8', '--max-replica-memory-gb', '8', '--num-replicas', '1',
      '--idle-scaling', 'true', '--idle-timeout-minutes', '5',
      '--ip-allow', `${ip}/${isIP(ip) === 4 ? 32 : 128}`,
      '--tag', 'example=report-history', '--json'];
    if (org) args.push('--org-id', org);
    console.log('Creating AWS eu-west-1 service: one 8 GiB replica, fixed size, 5-minute minimum idle timeout.');
    console.log('This incurs Cloud charges. The script does not delete the service.');
    // A timeout is ambiguous: the API may have created the service. Block a duplicate create.
    save(intentFile, { name, orgId: org, provider: 'aws', region: 'eu-west-1', attemptedAt: new Date().toISOString() });
    const response = JSON.parse(cli(args));
    save(join(root, '.cloud-create-response.json'), response); // includes one-time default password
    if (!response.service?.id) throw new Error('Create response lacks a service ID; response securely retained.');
    save(stateFile, { id: response.service.id, name, orgId: org,
      provider: 'aws', region: 'eu-west-1', replicas: 1, memoryGiB: 8,
      idleScaling: true, idleTimeoutMinutes: 5 });
    console.log(`Created ${response.service.id}; one-time admin response saved privately. Run cloud:setup next.`);
  } else if (command === 'recover') {
    if (existsSync(stateFile)) throw new Error('Service ID already saved; use setup.');
    const intent = JSON.parse(readFileSync(intentFile, 'utf8'));
    const id = process.argv[3];
    if (!/^[a-f0-9-]{36}$/.test(id ?? '')) throw new Error('Provide the service ID confirmed in cloud service list.');
    const service = JSON.parse(cli(['get', id, '--json']));
    if (service.name !== intent.name || service.region !== intent.region) {
      throw new Error('Service does not match the saved creation intent; refusing recovery.');
    }
    save(stateFile, { id, ...intent });
    console.log(`Recovered ${id}; run cloud:setup. The initial admin password may require a manual reset if needed.`);
  } else if (command === 'setup') {
    const { id } = state();
    const service = await waitRunning(id);
    for (const file of ['01-database.sql', '02-results.sql', '03-runs.sql', '04-status.sql']) {
      query(id, readFileSync(join(root, 'sql', file), 'utf8'));
      console.log(`Applied ${file}`);
    }
    let password;
    if (existsSync(credentialFile)) {
      password = /^CLICKHOUSE_PASSWORD=(Aa1![a-f0-9]{64})$/m.exec(readFileSync(credentialFile, 'utf8'))?.[1];
      if (!password) throw new Error('Existing .env was not generated by this script; refusing to overwrite it.');
    } else {
      password = `Aa1!${randomBytes(32).toString('hex')}`;
      const endpoint = service.endpoints?.find((endpoint) => endpoint.protocol === 'https');
      if (!endpoint?.host || !endpoint?.port) throw new Error('No HTTPS endpoint in service response.');
      writeFileSync(credentialFile,
        `CLICKHOUSE_URL=https://${endpoint.host}:${endpoint.port}\n` +
        `CLICKHOUSE_USER=report_history_app\nCLICKHOUSE_PASSWORD=${password}\nCLICKHOUSE_DATABASE=report_history\n`,
        { mode: 0o600, flag: 'wx' });
    }
    // Persist credentials BEFORE the CREATE USER request, so setup is resumable.
    query(id, `CREATE USER IF NOT EXISTS report_history_app IDENTIFIED BY '${password}'`);
    for (const table of ['report_runs', 'report_results', 'run_status']) {
      query(id, `GRANT SELECT, INSERT ON report_history.${table} TO report_history_app`);
    }
    console.log('Created SELECT/INSERT-only application user. Credentials are in gitignored .env.');
    console.log(query(id, 'SHOW GRANTS FOR report_history_app').trim());
  } else if (command === 'stop') {
    const { id } = state();
    const accepted = JSON.parse(cli(['stop', id, '--json']));
    console.log(`Stop accepted for ${id}: ${accepted.state}`);
    const deadline = Date.now() + 600_000;
    let confirmed = false;
    while (Date.now() < deadline) {
      const service = JSON.parse(cli(['get', id, '--json'], undefined, Math.min(120_000, deadline - Date.now())));
      console.log(`Service ${id}: ${service.state}`);
      if (['stopped', 'idle'].includes(service.state)) { confirmed = true; break; }
      await setTimeout(Math.min(10_000, Math.max(0, deadline - Date.now())));
    }
    if (!confirmed) throw new Error(`Stop not confirmed within ten minutes; inspect ${id} before assuming compute is off.`);
    console.log('Service retained. Storage/backup or other applicable charges can continue.');
  } else {
    throw new Error('Usage: node scripts/cloud.mjs create|setup|stop|recover <service-id>');
  }
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
