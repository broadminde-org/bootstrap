// UNRUN regression source. No dependency preparation is performed by this file.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { gzipSync, gunzipSync } from 'node:zlib';
import { spawnSync } from 'node:child_process';

const scripts = fileURLToPath(new URL('../scripts/', import.meta.url));
const digest = (bytes) => createHash('sha256').update(bytes).digest('hex');
const runnerVersion = process.versions.node.split('.').map(Number);
const runnerSupported = runnerVersion[0] > 22 || (runnerVersion[0] === 22 && runnerVersion[1] >= 9);
const bash = '/bin/bash';
assert.equal(typeof process.getuid, 'function', 'Linux non-root executor required.');
assert.notEqual(process.getuid(), 0, 'Run isolated qualification as a non-root user.');

// Snapshot link targets without following them. Assertions emit hashes, never
// compiler output or application contents. All fixtures must be synthetic.
function snapshot(root, omitDependencies = false) {
  const result = {};
  function visit(name, relative) {
    const stat = fs.lstatSync(name);
    // Directory link counts change when expected children are created; file
    // counts remain snapshot state so unexpected hard links are still caught.
    result[relative] = [stat.mode, stat.isDirectory() ? null : stat.nlink, stat.ino, stat.isFile() ? stat.mtimeMs : null, stat.isSymbolicLink() ? fs.readlinkSync(name) : stat.isFile() ? digest(fs.readFileSync(name)) : 'directory'];
    if (stat.isDirectory() && !(omitDependencies && relative === 'node_modules')) {
      for (const entry of fs.readdirSync(name).sort()) visit(path.join(name, entry), path.posix.join(relative, entry));
    }
  }
  visit(root, '.');
  return result;
}

function fixture(t) {
  assert.ok(runnerSupported, 'Regression executor requires existing Node >=22.9.');
  const root = fs.mkdtempSync(path.join(fs.realpathSync(os.tmpdir()), 'artifact-regression-'));
  const ino = fs.lstatSync(root).ino;
  t.after(() => { if (fs.lstatSync(root).ino === ino) fs.rmSync(root, { recursive: true }); });
  const tools = path.join(root, 'tools');
  fs.mkdirSync(tools);
  fs.symlinkSync(process.execPath, path.join(tools, 'node'));
  fs.symlinkSync('/usr/bin/dirname', path.join(tools, 'dirname'));
  fs.writeFileSync(path.join(tools, 'npm'), '#!/bin/sh\nif [ "$ARTIFACT_TEST_NO_PACKAGE_MANAGER" != "1" ] && [ "$1" = "--version" ]; then printf "0.0.0\\n"; exit 0; fi\nprintf "unexpected installer" > "$ARTIFACT_TEST_COMMAND_LOG"\nexit 91\n', { mode: 0o700 });
  for (const command of ['npx', 'pnpm']) fs.copyFileSync(path.join(tools, 'npm'), path.join(tools, command));
  const home = path.join(root, 'home');
  fs.mkdirSync(home);
  const env = { ...process.env, PATH: tools, PWD: root, HOME: home, XDG_CACHE_HOME: home, XDG_CONFIG_HOME: home, XDG_DATA_HOME: home, TMPDIR: home, TMP: home, TEMP: home, NODE_OPTIONS: '', ARTIFACT_TEST_NO_PACKAGE_MANAGER: '0', ARTIFACT_TEST_COMMAND_LOG: path.join(root, 'unexpected-installer') };
  // Deliberately request an outside-output cache: production wrappers must
  // disable it before startup, including on failed admission and npm probes.
  env.NODE_COMPILE_CACHE = path.join(root, 'ambient-node-cache');
  env.NODE_DISABLE_COMPILE_CACHE = '0';
  return { root, tools, env };
}

function invoke(f, script, args, location = scripts) {
  return spawnSync(bash, [path.join(location, script), ...args], { cwd: f.root, env: f.env, encoding: 'utf8', timeout: 120000, maxBuffer: 1024 * 1024 });
}

function refusedWithoutMutation(f, script, args, pattern, location = scripts, target = f.root, omitDependencies = false) {
  const before = snapshot(target, omitDependencies);
  const privateBefore = target === f.root ? null : snapshot(f.root);
  const result = invoke(f, script, args, location);
  assert.equal(result.error, undefined, 'Production invocation did not complete normally.');
  assert.ok(result.status !== 0, 'Production helper must reject this fixture.');
  assert.ok(pattern.test(result.stderr), 'Expected screened rejection category.');
  assert.deepEqual(snapshot(target, omitDependencies), before, 'Rejected invocation mutated its fixture.');
  if (privateBefore) assert.deepEqual(snapshot(f.root), privateBefore, 'Rejected invocation mutated HOME/tool scratch.');
  assert.ok(!fs.existsSync(f.env.ARTIFACT_TEST_COMMAND_LOG), 'An installer command was attempted.');
}

test('production initializer prerequisites, arguments and destinations reject without mutation', async (t) => {
  for (const args of [[], ['one', 'two'], ['../escape'], ['absolute/path'], ['-flag']]) {
    await t.test(`invalid arguments ${JSON.stringify(args)}`, (t) => refusedWithoutMutation(fixture(t), 'init-artifact.sh', args, /Usage:/));
  }
  await t.test('missing node', (t) => {
    const f = fixture(t);
    fs.unlinkSync(path.join(f.tools, 'node'));
    refusedWithoutMutation(f, 'init-artifact.sh', ['new-artifact'], /Node >=22.9/);
  });
  for (const missing of [false, true]) await t.test(missing ? 'missing npm' : 'wrong npm version', (t) => {
    const f = fixture(t);
    if (missing) fs.unlinkSync(path.join(f.tools, 'npm'));
    refusedWithoutMutation(f, 'init-artifact.sh', ['new-artifact'], /Existing npm/);
  });
  for (const kind of ['empty directory', 'dangling link']) await t.test(kind, (t) => {
    const f = fixture(t);
    const dest = path.join(f.root, 'new-artifact');
    if (kind === 'empty directory') fs.mkdirSync(dest);
    else fs.symlinkSync(path.join(f.root, 'absent'), dest);
    refusedWithoutMutation(f, 'init-artifact.sh', ['new-artifact'], /Destination must be absent/);
  });
  await t.test('below-minimum real Node', (t) => {
    assert.ok(process.env.ARTIFACT_TEST_OLD_NODE, 'Required engine-rejection qualification is blocked: supply an existing Node <22.9 binary; no automatic install.');
    const f = fixture(t);
    fs.unlinkSync(path.join(f.tools, 'node'));
    fs.symlinkSync(fs.realpathSync(process.env.ARTIFACT_TEST_OLD_NODE), path.join(f.tools, 'node'));
    refusedWithoutMutation(f, 'init-artifact.sh', ['new-artifact'], /Node >=22.9/);
  });
});

test('initializer installer arguments and scaffold are isolated from synthetic ancestors (stub only)', async (t) => {
  const stack = JSON.parse(fs.readFileSync(path.join(scripts, 'stack.json')));
  for (const ancestorWorkspace of [false, true]) await t.test(ancestorWorkspace ? 'ancestor workspace sentinel' : 'standalone parent', (t) => {
    const f = fixture(t);
    if (ancestorWorkspace) {
      fs.writeFileSync(path.join(f.root, 'package.json'), JSON.stringify({ name: 'synthetic-ancestor', private: true, workspaces: ['new-artifact'], scripts: { preinstall: 'printf synthetic > ancestor-executed' } }));
      fs.writeFileSync(path.join(f.root, 'package-lock.json'), '{"synthetic":"ancestor-lock-sentinel"}\n');
      fs.writeFileSync(path.join(f.root, '.npmrc'), 'workspaces=true\n');
      fs.mkdirSync(path.join(f.root, 'node_modules'));
      fs.writeFileSync(path.join(f.root, 'node_modules/sentinel'), 'synthetic ancestor dependency');
    }
    // This stub records the production spawn contract and deliberately fails.
    // It does not resolve packages or qualify real npm workspace behavior.
    fs.writeFileSync(path.join(f.tools, 'npm'), `#!${process.execPath}
import fs from 'node:fs';
import path from 'node:path';
const args = process.argv.slice(2);
if (args.length === 1 && args[0] === '--version') { console.log(${JSON.stringify(stack.npmVersion)}); process.exit(0); }
const configs = ['user.npmrc', 'global.npmrc'].map(name => {
  const file = path.join(process.cwd(), '.artifact-output', name);
  const stat = fs.lstatSync(file);
  return { file, content: fs.readFileSync(file, 'utf8'), mode: stat.mode & 0o777, ino: stat.ino };
});
fs.writeFileSync(path.join(process.cwd(), '.artifact-output/install-contract.json'), JSON.stringify({ args, cwd: process.cwd(), configs, npmEnvironmentKeys: Object.keys(process.env).filter(key => /^npm_config_/i.test(key)), viteEnv: fs.readFileSync('src/vite-env.d.ts', 'utf8'), tsconfig: JSON.parse(fs.readFileSync('tsconfig.json')), pkg: JSON.parse(fs.readFileSync('package.json')) }));
process.exit(91);
`, { mode: 0o700 });
    f.env.npm_config_prefix = path.join(f.root, 'ancestor-target');
    f.env.NPM_CONFIG_WORKSPACES = 'true';
    const before = snapshot(f.root);
    const result = invoke(f, 'init-artifact.sh', ['new-artifact']);
    assert.equal(result.error, undefined);
    assert.notEqual(result.status, 0, 'Stub installer must not manufacture prepared success.');
    assert.match(result.stderr, /Local preparation failed/);
    const root = path.join(f.root, 'new-artifact');
    const output = path.join(root, '.artifact-output');
    const contract = JSON.parse(fs.readFileSync(path.join(output, 'install-contract.json')));
    assert.deepEqual(contract.args, ['install', '--prefix', root, '--workspaces=false', '--include=dev', '--no-audit', '--no-fund', '--cache', path.join(output, 'install-cache'), '--userconfig', path.join(output, 'user.npmrc'), '--globalconfig', path.join(output, 'global.npmrc')]);
    assert.equal(contract.cwd, root);
    assert.deepEqual(contract.npmEnvironmentKeys, []);
    assert.notEqual(contract.configs[0].file, contract.configs[1].file);
    assert.notEqual(contract.configs[0].ino, contract.configs[1].ino);
    for (const config of contract.configs) {
      assert.equal(config.mode, 0o600);
      assert.equal(config.content, 'engine-strict=true\nsave-exact=true\naudit=false\nfund=false\n');
    }
    assert.equal(contract.viteEnv, '/// <reference types="vite/client" />\n');
    assert.deepEqual(contract.tsconfig.include, ['src']);
    assert.deepEqual(contract.pkg.dependencies, stack.dependencies);
    assert.deepEqual(contract.pkg.devDependencies, stack.devDependencies);
    assert.ok(!fs.existsSync(path.join(output, 'prepared.json')));
    const after = snapshot(f.root);
    for (const name of Object.keys(after)) if (name === 'new-artifact' || name.startsWith('new-artifact/')) delete after[name];
    assert.deepEqual(after, before, 'Stub-contract initialization changed ancestor sentinels or private scratch.');
    assert.ok(!fs.existsSync(path.join(f.root, 'ancestor-executed')));
  });
});

// Small synthetic tar writer for hostile archive fixtures, not an extractor.
function tar(entries) {
  const blocks = [];
  for (const [name, type = '5', link = ''] of entries) {
    const h = Buffer.alloc(512);
    h.write(name, 0, 100);
    h.write('0000700\0', 100); h.write('0000000\0', 108); h.write('0000000\0', 116);
    h.write('00000000000\0', 124); h.write('00000000000\0', 136);
    h.fill(32, 148, 156); h.write(type, 156); h.write(link, 157, 100);
    h.write('ustar\0', 257); h.write('00', 263);
    h.write(h.reduce((a, b) => a + b, 0).toString(8).padStart(6, '0') + '\0 ', 148);
    blocks.push(h);
  }
  return Buffer.concat([...blocks, Buffer.alloc(1024)]);
}

test('production archive admission rejects before destination or preparation writes', async (t) => {
  const original = fs.readFileSync(path.join(scripts, 'shadcn-components.tar.gz'));
  const raw = gunzipSync(original);
  const changed = Buffer.from(raw);
  changed[1024] ^= 1; // First regular-file header: a checksum failure, not an API reproduction.
  const changedContent = Buffer.from(raw);
  changedContent[1536] ^= 1; // File data change retains the tar header checksum.
  const cases = [
    ['absolute', gzipSync(tar([['/escape', '0']])), /Archive path/],
    ['traversal', gzipSync(tar([['../escape', '0']])), /Archive path/],
    ['symlink', gzipSync(tar([['components', '2', '../escape']])), /Tar links/],
    ['hardlink', gzipSync(tar([['components', '1', 'escape']])), /Tar links/],
    ['PAX extension', gzipSync(tar([['extension', 'x']])), /Tar links/],
    ['duplicate directory', gzipSync(tar([['components'], ['components']])), /Duplicate/],
    ['file-directory conflict', gzipSync(tar([['components', '0']])), /conflicting/],
    ['required assets absent', gzipSync(tar([['components']])), /Required component/],
    ['bad checksum', gzipSync(changed), /checksum/],
    ['changed original content digest', gzipSync(changedContent), /reviewed original/],
    ['truncated tar', gzipSync(raw.subarray(0, 1025)), /Truncated|Invalid archive|operation failed/],
    ['invalid gzip', Buffer.from('not gzip'), /operation failed/],
  ];
  for (const [name, bytes, pattern] of cases) await t.test(name, (t) => {
    const f = fixture(t);
    const copy = path.join(f.root, 'scripts');
    fs.cpSync(scripts, copy, { recursive: true });
    fs.writeFileSync(path.join(copy, 'shadcn-components.tar.gz'), bytes);
    refusedWithoutMutation(f, 'init-artifact.sh', ['new-artifact'], pattern, copy);
  });
  await t.test('archive absent', (t) => {
    const f = fixture(t);
    const copy = path.join(f.root, 'scripts');
    fs.cpSync(scripts, copy, { recursive: true });
    fs.unlinkSync(path.join(copy, 'shadcn-components.tar.gz'));
    refusedWithoutMutation(f, 'init-artifact.sh', ['new-artifact'], /operation failed/, copy);
  });
});

test('production workspace admission is not marker-only and refuses redirects', async (t) => {
  await t.test('fake prepared marker', (t) => {
    const f = fixture(t);
    const root = path.join(f.root, 'fake');
    fs.mkdirSync(root, { mode: 0o700 });
    fs.mkdirSync(path.join(root, '.artifact-output'), { mode: 0o700 });
    fs.writeFileSync(path.join(root, '.artifact-output/prepared.json'), '{"schema":1}', { mode: 0o600 });
    refusedWithoutMutation(f, 'bundle-artifact.sh', [root], /initialization baseline/);
  });
  await t.test('redirected root', (t) => {
    const f = fixture(t);
    fs.symlinkSync(f.root, path.join(f.root, 'redirect'));
    refusedWithoutMutation(f, 'bundle-artifact.sh', [path.join(f.root, 'redirect')], /Redirected/);
  });
  await t.test('parent traversal', (t) => {
    const f = fixture(t);
    refusedWithoutMutation(f, 'bundle-artifact.sh', [path.join(f.root, 'child') + '/../fake'], /Parent traversal/);
  });
});

test('prepared offline production bundle lifecycle', async (t) => {
  // The operator must supply a fresh, genuinely initialized disposable workspace
  // and a network-denied executor. A flag is a declaration, not isolation proof.
  assert.equal(process.env.ARTIFACT_TEST_OFFLINE_EXECUTOR, '1', 'Run only within a separately authorized network-denied executor.');
  const input = process.env.ARTIFACT_TEST_PREPARED_WORKSPACE;
  assert.ok(input, 'Explicit already-prepared workspace required; tests never install or initialize it.');
  const root = fs.realpathSync(input);
  assert.equal(root, path.resolve(input), 'Prepared fixture cannot be a redirected path.');
  assert.equal(path.dirname(root), fs.realpathSync(os.tmpdir()), 'Prepared fixture must be directly under disposable temp.');
  assert.ok(path.basename(root).startsWith('artifact-regression-prepared-'), 'Use the documented dedicated fixture name.');
  const output = path.join(root, '.artifact-output');
  const receiptPath = path.join(output, 'prepared.json');
  const initialReceipt = JSON.parse(fs.readFileSync(receiptPath));
  assert.equal(initialReceipt.root, root, 'Do not copy or fabricate preparation receipts.');
  assert.equal(initialReceipt.bundleHash, null, 'Supply a fresh prepared fixture without a prior bundle.');
  const f = fixture(t);
  f.env.ARTIFACT_TEST_NO_PACKAGE_MANAGER = '1';
  const out = path.join(output, 'bundle.html');
  const app = path.join(root, 'src/App.tsx');
  const originalApp = fs.readFileSync(app);
  assert.ok(originalApp.toString().includes('New artifact'), 'Prepared fixture must retain the generated synthetic App.');
  const originalManifestLock = ['package.json', 'package-lock.json', 'tsconfig.json', 'vite.config.ts', 'postcss.config.cjs', 'tailwind.config.cjs', '.artifact-output/user.npmrc', '.artifact-output/global.npmrc'].map((name) => [name, digest(fs.readFileSync(path.join(root, name)))]);
  for (const name of ['.artifact-output/user.npmrc', '.artifact-output/global.npmrc']) assert.equal(initialReceipt.configs[name], digest(fs.readFileSync(path.join(root, name))), 'Both owned npm configurations must be fingerprinted.');

  await t.test('unknown first output is not adopted', () => {
    const unknown = Buffer.from('synthetic unknown output');
    fs.writeFileSync(out, unknown, { flag: 'wx' });
    try { refusedWithoutMutation(f, 'bundle-artifact.sh', [root], /Unknown, modified/, scripts, root, true); }
    finally { if (fs.readFileSync(out).equals(unknown)) fs.unlinkSync(out); }
  });
  const extras = [path.join(output, 'user-extra.txt'), path.join(root, 'bundle.html')];
  for (const file of extras) fs.writeFileSync(file, 'synthetic extra', { flag: 'wx' });
  const unknownLink = path.join(output, 'unknown-link');
  fs.symlinkSync('user-extra.txt', unknownLink);
  fs.mkdirSync(path.join(root, 'dist'));
  fs.writeFileSync(path.join(root, 'dist/user-extra.txt'), 'synthetic extra', { flag: 'wx' });
  const dependenciesBefore = snapshot(path.join(root, 'node_modules'));
  function successfulBundle() {
    const before = snapshot(root, true);
    const privateHomeBefore = snapshot(f.root);
    const result = invoke(f, 'bundle-artifact.sh', [root]);
    assert.equal(result.error, undefined, 'Bundle process did not complete normally.');
    assert.equal(result.status, 0, 'Prepared production bundle failed; API/runtime qualification remains blocked until diagnosed.');
    assert.ok(fs.statSync(out).size > 0, 'Successful bundle must be nonempty.');
    assert.equal(JSON.parse(fs.readFileSync(receiptPath)).bundleHash, digest(fs.readFileSync(out)));
    assert.ok(!fs.readdirSync(output).some((name) => name.startsWith('stage-')), 'Owned staging leaked.');
    assert.ok(!fs.existsSync(f.env.ARTIFACT_TEST_COMMAND_LOG), 'Installer command attempted.');
    const after = snapshot(root, true);
    for (const state of [before, after]) for (const name of ['.artifact-output/bundle.html', '.artifact-output/prepared.json']) delete state[name];
    assert.deepEqual(after, before, 'Successful bundle mutated paths outside its owned output and receipt.');
    assert.deepEqual(snapshot(f.root), privateHomeBefore, 'Bundle wrote incidental HOME/tool scratch state.');
  }
  successfulBundle();
  await t.test('Vite client declarations admit imported assets and URL/raw queries', () => {
    const files = {
      'regression-image.svg': '<svg xmlns="http://www.w3.org/2000/svg" width="1" height="1"><path d="M0 0h1v1H0z"/></svg>',
      // Synthetic bytes test URL processing, not font decoding/rendering.
      'regression-font.woff2': 'synthetic-font-url-fixture',
      'regression-assets.css': '@font-face { font-family: synthetic-artifact-font; src: url("./regression-font.woff2") format("woff2"); }\n',
    };
    for (const name of Object.keys(files)) assert.ok(!fs.existsSync(path.join(root, 'src', name)), 'Asset fixture must be absent.');
    try {
      for (const [name, content] of Object.entries(files)) fs.writeFileSync(path.join(root, 'src', name), content, { flag: 'wx' });
      fs.writeFileSync(app, 'import image from "./regression-image.svg";\nimport imageUrl from "./regression-image.svg?url";\nimport raw from "./regression-image.svg?raw";\nimport font from "./regression-font.woff2";\nimport "./regression-assets.css";\nexport function App() { return <main><img src={image} alt="synthetic asset" /><img src={imageUrl} alt="synthetic URL asset" /><output>{raw} {font.slice(0, 5)}</output></main>; }\n');
      successfulBundle();
      assert.match(fs.readFileSync(out, 'utf8'), /data:image\/svg\+xml/);
      assert.match(fs.readFileSync(out, 'utf8'), /data:font\/woff2/);
    } finally {
      fs.writeFileSync(app, originalApp);
      for (const [name, content] of Object.entries(files)) {
        const file = path.join(root, 'src', name);
        if (fs.existsSync(file) && fs.readFileSync(file, 'utf8') === content) fs.unlinkSync(file);
      }
    }
  });
  await t.test('second bundle replaces only unchanged owned output', () => {
    const priorHash = digest(fs.readFileSync(out));
    fs.writeFileSync(app, originalApp.toString().replace('New artifact', 'Second artifact'));
    try { successfulBundle(); assert.notEqual(digest(fs.readFileSync(out)), priorHash, 'Edited app was not rebuilt.'); }
    finally { fs.writeFileSync(app, originalApp); }
  });
  await t.test('modified owned output remains untouched', () => {
    const prior = fs.readFileSync(out);
    fs.appendFileSync(out, '\nsynthetic user edit');
    try { refusedWithoutMutation(f, 'bundle-artifact.sh', [root], /Unknown, modified/, scripts, root, true); }
    finally { fs.writeFileSync(out, prior); }
  });
  for (const name of ['tailwind.config.cjs', '.artifact-output/user.npmrc', '.artifact-output/global.npmrc', '.artifact-output/prepared.json', '.artifact-output/bundle.html', 'src']) await t.test(`redirected ${name} rejects without writes`, () => {
    const file = path.join(root, name);
    const held = file + '.held-by-regression';
    assert.throws(() => fs.lstatSync(held), { code: 'ENOENT' }, 'Regression backup must be absent.');
    fs.renameSync(file, held);
    fs.symlinkSync(held, file);
    try { refusedWithoutMutation(f, 'bundle-artifact.sh', [root], /Redirected/, scripts, root, true); }
    finally { fs.unlinkSync(file); fs.renameSync(held, file); }
  });
  await t.test('missing recorded output is not regenerated', () => {
    const held = out + '.held-by-regression';
    assert.throws(() => fs.lstatSync(held), { code: 'ENOENT' }, 'Regression backup must be absent.');
    fs.renameSync(out, held);
    try { refusedWithoutMutation(f, 'bundle-artifact.sh', [root], /missing prior bundle/, scripts, root, true); }
    finally { fs.renameSync(held, out); }
  });
  await t.test('type failure preserves prior', () => {
    fs.writeFileSync(app, 'export function App() { return <broken');
    try { refusedWithoutMutation(f, 'bundle-artifact.sh', [root], /all-source type check failed/, scripts, root, true); }
    finally { fs.writeFileSync(app, originalApp); }
  });
  for (const [index, target] of ['bundle.html', 'prepared.json', 'stage-tmp'].entries()) await t.test(`early ${target} failure leaves no owned stage`, () => {
    const copy = path.join(f.root, `fault-scripts-${index}`);
    fs.cpSync(scripts, copy, { recursive: true });
    const helper = path.join(copy, 'artifact.mjs');
    const source = fs.readFileSync(helper, 'utf8');
    // Fault injection in a private helper copy, not a production test hook.
    // The third baseline read is the rollback snapshot after both admissions.
    const needle = target === 'stage-tmp' ? "fs.mkdirSync(path.join(stage, 'tmp'), { mode: 0o700 });" : 'function read(name) { return fs.readFileSync(admit(name)); }';
    const replacement = target === 'stage-tmp' ? 'throw new Error("synthetic stage setup failure");' : `let syntheticReads = 0;\nfunction read(name) { if (path.basename(name) === ${JSON.stringify(target)} && ++syntheticReads === 3) throw new Error("synthetic rollback read failure"); return fs.readFileSync(admit(name)); }`;
    assert.equal(source.split(needle).length, 2, 'Fault injection must match one exact source seam.');
    fs.writeFileSync(helper, source.replace(needle, replacement));
    refusedWithoutMutation(f, 'bundle-artifact.sh', [root], /operation failed/, copy, root, true);
    assert.ok(!fs.readdirSync(output).some((name) => name.startsWith('stage-')), 'Early failure leaked a reserved stage.');
  });
  await t.test('post-inlining HTML URL refusal preserves prior', () => {
    const entry = path.join(root, 'index.html');
    const prior = fs.readFileSync(entry);
    // A literal HTML reference exercises the helper's conservative check;
    // remote URLs compiled into React props need the still-pending browser case.
    assert.ok(prior.toString().includes('</body>'), 'Fixture needs an HTML body.');
    fs.writeFileSync(entry, prior.toString().replace('</body>', '<img src="https://fixture.invalid/image.png" alt="synthetic"></body>'));
    try { refusedWithoutMutation(f, 'bundle-artifact.sh', [root], /Remaining asset/, scripts, root, true); }
    finally { fs.writeFileSync(entry, prior); }
  });
  await t.test('Vite entry build failure preserves prior bundle', () => {
    const entry = path.join(root, 'index.html');
    const prior = fs.readFileSync(entry);
    assert.ok(prior.toString().includes('/src/main.tsx'), 'Fixture must retain generated HTML entry.');
    fs.writeFileSync(entry, prior.toString().replace('/src/main.tsx', '/src/missing-entry.tsx'));
    try { refusedWithoutMutation(f, 'bundle-artifact.sh', [root], /operation failed/, scripts, root, true); }
    finally { fs.writeFileSync(entry, prior); }
  });
  await t.test('missing prepared dependency does not trigger install', () => {
    const dep = path.join(root, 'node_modules/vite');
    const held = path.join(root, 'node_modules/held-vite');
    assert.throws(() => fs.lstatSync(held), { code: 'ENOENT' }, 'Regression backup must be absent.');
    fs.renameSync(dep, held);
    try { refusedWithoutMutation(f, 'bundle-artifact.sh', [root], /operation failed|Missing or mismatched/, scripts, root, true); }
    finally { fs.renameSync(held, dep); }
  });
  for (const name of ['package.json', 'tailwind.config.cjs', '.artifact-output/user.npmrc', '.artifact-output/global.npmrc']) await t.test(`changed ${name} rejects without writes`, () => {
    const file = path.join(root, name);
    const prior = fs.readFileSync(file);
    fs.appendFileSync(file, '\n');
    try { refusedWithoutMutation(f, 'bundle-artifact.sh', [root], /configuration changed/, scripts, root, true); }
    finally { fs.writeFileSync(file, prior); }
  });
  for (const name of ['tailwind.config.cjs', '.artifact-output/user.npmrc', '.artifact-output/global.npmrc']) await t.test(`forged receipt cannot bless changed ${name}`, () => {
    const config = path.join(root, name);
    const priorConfig = fs.readFileSync(config);
    const priorReceipt = fs.readFileSync(receiptPath);
    fs.appendFileSync(config, '\n');
    const forged = JSON.parse(priorReceipt);
    forged.configs[name] = digest(fs.readFileSync(config));
    fs.writeFileSync(receiptPath, JSON.stringify(forged));
    try { refusedWithoutMutation(f, 'bundle-artifact.sh', [root], /not the reviewed scaffold/, scripts, root, true); }
    finally { fs.writeFileSync(config, priorConfig); fs.writeFileSync(receiptPath, priorReceipt); }
  });
  for (const file of [...extras, path.join(root, 'dist/user-extra.txt')]) assert.equal(fs.readFileSync(file, 'utf8'), 'synthetic extra', 'Unknown extra was changed.');
  assert.equal(fs.readlinkSync(unknownLink), 'user-extra.txt', 'Unknown output link was altered or followed.');
  for (const [name, hash] of originalManifestLock) assert.equal(digest(fs.readFileSync(path.join(root, name))), hash, 'Managed config/manifest/lock mutated.');
  assert.deepEqual(snapshot(path.join(root, 'node_modules')), dependenciesBefore, 'Prepared dependency tree mutated.');
  // Leave the supplied workspace and last valid bundle for operator inspection.
});
