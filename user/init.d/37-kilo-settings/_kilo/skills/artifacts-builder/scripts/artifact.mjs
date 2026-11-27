import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { createHash } from 'node:crypto';
import { gunzipSync } from 'node:zlib';
import { spawnSync } from 'node:child_process';

const here = path.dirname(fileURLToPath(import.meta.url));
class AdmissionError extends Error {}
const fail = (message) => { throw new AdmissionError(message); };
const sha = (bytes) => createHash('sha256').update(bytes).digest('hex');
const samePins = (a, b) => a && b && JSON.stringify(Object.entries(a).sort()) === JSON.stringify(Object.entries(b).sort());
const exists = (name) => { try { fs.lstatSync(name); return true; } catch (e) { if (e.code === 'ENOENT') return false; throw e; } };

// Check every lexical ancestor: realpath alone would silently accept redirects.
function admit(name, kind = 'file') {
  if (name.split(path.sep).includes('..')) fail('Parent traversal rejected.');
  const full = path.resolve(name);
  let current = path.parse(full).root;
  const parts = full.slice(current.length).split(path.sep).filter(Boolean);
  for (const [i, part] of parts.entries()) {
    current = path.join(current, part);
    const stat = fs.lstatSync(current);
    if (stat.isSymbolicLink() || (i < parts.length - 1 && !stat.isDirectory())) fail('Redirected path rejected.');
    if (i === parts.length - 1 && (kind === 'directory' ? !stat.isDirectory() : !stat.isFile() || stat.nlink !== 1)) fail('Unexpected path type or hard-linked file.');
  }
  return full;
}

function tree(root, dependencyTree = false) {
  for (const entry of fs.readdirSync(root, { withFileTypes: true })) {
    const name = path.join(root, entry.name);
    if (entry.isSymbolicLink()) {
      const resolved = fs.realpathSync(name);
      if (!dependencyTree || !resolved.startsWith(`${rootOfDependencies}${path.sep}`)) fail('Redirected workspace entry rejected.');
    } else if (entry.isDirectory()) tree(name, dependencyTree);
    else if (!entry.isFile() || fs.lstatSync(name).nlink !== 1) fail('Special or hard-linked workspace entry rejected.');
  }
}
let rootOfDependencies;

function read(name) { return fs.readFileSync(admit(name)); }
function json(name) { return JSON.parse(read(name).toString('utf8')); }
function write(name, bytes) { fs.writeFileSync(name, bytes, { flag: 'wx', mode: 0o600 }); }
function identity(name) { const s = fs.lstatSync(admit(name, 'directory')); return `${s.dev}:${s.ino}`; }

// Parse in memory before any destination creation. Reject all tar link/extension
// types rather than delegating extraction semantics to an external tar process.
function archive(bytes) {
  const tar = gunzipSync(bytes, { maxOutputLength: 16 * 1024 * 1024 });
  const entries = new Map();
  const field = (header, start, length) => {
    const raw = header.subarray(start, start + length);
    const end = raw.indexOf(0);
    if (end !== -1 && raw.subarray(end).some((x) => x !== 0)) fail('Invalid tar field.');
    return raw.subarray(0, end === -1 ? length : end).toString('utf8');
  };
  const octal = (header, start, length) => {
    const value = header.subarray(start, start + length).toString('ascii').replace(/\0/g, '').trim();
    if (!/^[0-7]+$/.test(value)) fail('Invalid tar number.');
    return Number.parseInt(value, 8);
  };
  let offset = 0;
  for (; offset + 512 <= tar.length; ) {
    const h = tar.subarray(offset, offset + 512);
    if (h.every((x) => x === 0)) break;
    const checksum = h.reduce((sum, byte, i) => sum + (i >= 148 && i < 156 ? 32 : byte), 0);
    if (checksum !== octal(h, 148, 8)) fail('Tar checksum mismatch.');
    const prefix = field(h, 345, 155);
    const raw = `${prefix ? `${prefix}/` : ''}${field(h, 0, 100)}`;
    const type = String.fromCharCode(h[156]);
    const directory = type === '5';
    const name = directory ? raw.replace(/\/$/, '') : raw;
    if (!['0', '\0', '5'].includes(type) || field(h, 157, 100)) fail('Tar links and special entries rejected.');
    if (!/^(components(?:\/ui)?|lib|hooks)(?:\/[a-z0-9-]+\.(?:ts|tsx))?$/.test(name) || path.posix.normalize(name) !== name) fail('Archive path outside component inventory.');
    if (directory !== ['components', 'components/ui', 'lib', 'hooks'].includes(name) || entries.has(name)) fail('Duplicate or conflicting archive entry.');
    const size = octal(h, 124, 12);
    if ((directory && size !== 0) || size > 1024 * 1024 || offset + 512 + size > tar.length) fail('Invalid archive size.');
    entries.set(name, directory ? null : Buffer.from(tar.subarray(offset + 512, offset + 512 + size)));
    offset += 512 + Math.ceil(size / 512) * 512;
  }
  if (tar.length - offset < 1024 || tar.subarray(offset).some((x) => x !== 0)) fail('Truncated archive or trailing data.');
  for (const name of ['components/ui/button.tsx', 'lib/utils.ts', 'hooks/use-toast.ts']) if (!entries.get(name)) fail('Required component asset missing.');
  for (const name of entries.keys()) {
    let parent = path.posix.dirname(name);
    while (parent !== '.') {
      if (!entries.has(parent) || entries.get(parent) !== null) fail('Missing archive directory.');
      parent = path.posix.dirname(parent);
    }
  }
  return entries;
}

function stackAdmission() {
  const stack = json(path.join(here, 'stack.json'));
  const actual = process.versions.node.split('.').map(Number);
  if (actual[0] < 22 || (actual[0] === 22 && actual[1] < 9)) fail('Node >=22.9 required; select the configured host toolchain, do not upgrade implicitly.');
  if (stack.schema !== 1 || stack.nodeMinimum !== '22.9.0' || !/^\d+\.\d+\.\d+$/.test(stack.npmVersion)) fail('Invalid stack contract.');
  for (const group of ['dependencies', 'devDependencies']) {
    if (!stack[group] || typeof stack[group] !== 'object' || Array.isArray(stack[group])) fail('Missing stack pins.');
    for (const [name, version] of Object.entries(stack[group])) {
      if (!/^(?:@[a-z0-9-]+\/)?[a-z0-9-]+$/.test(name) || !/^\d+\.\d+\.\d+$/.test(version)) fail('Invalid package pin.');
    }
  }
  return stack;
}

const npmrc = 'engine-strict=true\nsave-exact=true\naudit=false\nfund=false\n';
const npmConfigs = ['.artifact-output/user.npmrc', '.artifact-output/global.npmrc'];
const configs = ['package.json', 'package-lock.json', 'tsconfig.json', 'vite.config.ts', 'postcss.config.cjs', 'tailwind.config.cjs', ...npmConfigs];
function fingerprints(root) { return Object.fromEntries(configs.map((name) => [name, sha(read(path.join(root, name)))])); }

function scaffold(name, stack) {
  const pkg = {
    name, private: true, version: '0.0.0', type: 'module',
    engines: { node: '>=22.9.0', npm: stack.npmVersion }, packageManager: `npm@${stack.npmVersion}`,
    scripts: { dev: 'vite', check: 'tsc --noEmit', build: 'tsc --noEmit && vite build' },
    dependencies: stack.dependencies, devDependencies: stack.devDependencies,
  };
  return {
    '.gitignore': 'node_modules/\n.artifact-output/\ndist/\n.env\n.env.*\n!.env.example\n',
    'package.json': JSON.stringify(pkg, null, 2) + '\n',
    'index.html': '<!doctype html>\n<html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><title>' + name + '</title></head><body><div id="root"></div><script type="module" src="/src/main.tsx"></script></body></html>\n',
    'src/main.tsx': 'import React from "react";\nimport ReactDOM from "react-dom/client";\nimport { App } from "./App";\nimport "./index.css";\nReactDOM.createRoot(document.getElementById("root")!).render(<React.StrictMode><App /></React.StrictMode>);\n',
    'src/vite-env.d.ts': '/// <reference types="vite/client" />\n',
    'src/App.tsx': 'import { Button } from "@/components/ui/button";\nexport function App() { return <main className="p-8"><h1 className="text-2xl font-semibold">New artifact</h1><Button className="mt-4">Start here</Button></main>; }\n',
    'tsconfig.json': JSON.stringify({ compilerOptions: { target: 'ES2022', lib: ['ES2022', 'DOM', 'DOM.Iterable'], module: 'ESNext', moduleResolution: 'Bundler', jsx: 'react-jsx', strict: true, skipLibCheck: true, noEmit: true, esModuleInterop: true, allowSyntheticDefaultImports: true, baseUrl: '.', paths: { '@/*': ['./src/*'] } }, include: ['src'] }, null, 2) + '\n',
    'vite.config.ts': 'import { defineConfig } from "vite";\nimport react from "@vitejs/plugin-react";\nimport { fileURLToPath } from "node:url";\nexport default defineConfig({ plugins: [react()], resolve: { alias: { "@": fileURLToPath(new URL("./src", import.meta.url)) } } });\n',
    'postcss.config.cjs': 'module.exports = { plugins: { tailwindcss: {}, autoprefixer: {} } };\n',
    'tailwind.config.cjs': `module.exports = {
  darkMode: ["class"], content: { relative: true, files: ["./index.html", "./src/**/*.{js,ts,jsx,tsx}"] },
  theme: { extend: {
    colors: Object.fromEntries(["border", "input", "ring", "background", "foreground", "primary", "secondary", "destructive", "muted", "accent", "popover", "card"].map(name => [name, ["primary", "secondary", "destructive", "muted", "accent", "popover", "card"].includes(name) ? { DEFAULT: "hsl(var(--" + name + "))", foreground: "hsl(var(--" + name + "-foreground))" } : "hsl(var(--" + name + "))"])),
    borderRadius: { lg: "var(--radius)", md: "calc(var(--radius) - 2px)", sm: "calc(var(--radius) - 4px)" },
    keyframes: { "accordion-down": { from: { height: "0" }, to: { height: "var(--radix-accordion-content-height)" } }, "accordion-up": { from: { height: "var(--radix-accordion-content-height)" }, to: { height: "0" } } },
    animation: { "accordion-down": "accordion-down 0.2s ease-out", "accordion-up": "accordion-up 0.2s ease-out" }
  } }, plugins: [require("tailwindcss-animate")]
};\n`,
    'src/index.css': `@tailwind base;
@tailwind components;
@tailwind utilities;
@layer base {
  :root {
    --background: 0 0% 100%; --foreground: 0 0% 3.9%;
    --card: 0 0% 100%; --card-foreground: 0 0% 3.9%;
    --popover: 0 0% 100%; --popover-foreground: 0 0% 3.9%;
    --primary: 0 0% 9%; --primary-foreground: 0 0% 98%;
    --secondary: 0 0% 96.1%; --secondary-foreground: 0 0% 9%;
    --muted: 0 0% 96.1%; --muted-foreground: 0 0% 45.1%;
    --accent: 0 0% 96.1%; --accent-foreground: 0 0% 9%;
    --destructive: 0 84.2% 60.2%; --destructive-foreground: 0 0% 98%;
    --border: 0 0% 89.8%; --input: 0 0% 89.8%; --ring: 0 0% 3.9%; --radius: 0.5rem;
  }
  .dark {
    --background: 0 0% 3.9%; --foreground: 0 0% 98%;
    --card: 0 0% 3.9%; --card-foreground: 0 0% 98%;
    --popover: 0 0% 3.9%; --popover-foreground: 0 0% 98%;
    --primary: 0 0% 98%; --primary-foreground: 0 0% 9%;
    --secondary: 0 0% 14.9%; --secondary-foreground: 0 0% 98%;
    --muted: 0 0% 14.9%; --muted-foreground: 0 0% 63.9%;
    --accent: 0 0% 14.9%; --accent-foreground: 0 0% 98%;
    --destructive: 0 62.8% 30.6%; --destructive-foreground: 0 0% 98%;
    --border: 0 0% 14.9%; --input: 0 0% 14.9%; --ring: 0 0% 83.1%;
  }
  * { @apply border-border; }
  body { @apply bg-background text-foreground; }
}\n`,
  };
}

function initialize(name, stack) {
  if (!/^[a-z][a-z0-9-]{0,62}$/.test(name)) fail('Expected a simple new project name, not a path.');
  const parent = admit(process.env.PWD || process.cwd(), 'directory');
  if (parent !== process.cwd()) fail('Logical and physical working directories differ.');
  const root = path.join(parent, name);
  if (exists(root)) fail('Destination must be absent, including empty directories and dangling links.');
  const bytes = read(path.join(here, 'shadcn-components.tar.gz'));
  const inventory = archive(bytes);
  if (sha(bytes) !== stack.archiveSha256) fail('Archive differs from the reviewed original.');
  const npm = spawnSync('npm', ['--version'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  if (npm.error || npm.status !== 0 || npm.stdout.trim() !== stack.npmVersion) fail(`Existing npm ${stack.npmVersion} required; no automatic/global installation.`);
  // No writes/preparation precede the complete argument/engine/asset preflight.
  fs.mkdirSync(root, { mode: 0o700 });
  const output = path.join(root, '.artifact-output');
  fs.mkdirSync(output, { mode: 0o700 });
  fs.mkdirSync(path.join(root, 'src'), { mode: 0o700 });
  for (const [file, content] of Object.entries(scaffold(name, stack))) write(path.join(root, file), content);
  for (const [file, content] of inventory) {
    if (content === null) fs.mkdirSync(path.join(root, 'src', file), { mode: 0o700 });
    else write(path.join(root, 'src', file), content);
  }
  for (const name of npmConfigs) write(path.join(root, name), npmrc);
  fs.mkdirSync(path.join(output, 'install-cache'), { mode: 0o700 });
  fs.mkdirSync(path.join(output, 'install-tmp'), { mode: 0o700 });
  const env = Object.fromEntries(Object.entries(process.env).filter(([key]) => !/^npm_config_/i.test(key) && key !== 'NODE_OPTIONS'));
  for (const key of ['TMPDIR', 'TMP', 'TEMP']) env[key] = path.join(output, 'install-tmp');
  const install = spawnSync('npm', ['install', '--prefix', root, '--workspaces=false', '--include=dev', '--no-audit', '--no-fund', '--cache', path.join(output, 'install-cache'), '--userconfig', path.join(root, npmConfigs[0]), '--globalconfig', path.join(root, npmConfigs[1])], { cwd: root, env, stdio: ['ignore', 'ignore', 'ignore'] });
  if (install.error || install.status !== 0) fail('Local preparation failed. Incomplete destination retained for inspection; no prepared receipt written.');
  rootOfDependencies = admit(path.join(root, 'node_modules'), 'directory');
  tree(rootOfDependencies, true);
  const receipt = { schema: 1, root, rootIdentity: identity(root), outputIdentity: identity(output), stackHash: sha(read(path.join(here, 'stack.json'))), configs: fingerprints(root), bundleHash: null };
  admission(root, stack, receipt);
  write(path.join(output, 'prepared.json'), JSON.stringify(receipt, null, 2) + '\n');
  console.log(`Prepared ${name}. Edit src; bundle using the skill's absolute script path and this project directory.`);
}

function admission(root, stack, initializingReceipt) {
  admit(root, 'directory');
  const output = admit(path.join(root, '.artifact-output'), 'directory');
  if ((fs.lstatSync(root).mode & 0o077) || (fs.lstatSync(output).mode & 0o077)) fail('Workspace and owned state must remain private.');
  const receipt = initializingReceipt ?? json(path.join(output, 'prepared.json'));
  if (!initializingReceipt && (fs.lstatSync(path.join(output, 'prepared.json')).mode & 0o077)) fail('Prepared receipt must remain private.');
  if (receipt.schema !== 1 || receipt.root !== root || receipt.rootIdentity !== identity(root) || receipt.outputIdentity !== identity(output) || receipt.stackHash !== sha(read(path.join(here, 'stack.json')))) fail('Workspace does not match its initialization baseline.');
  if (JSON.stringify(receipt.configs) !== JSON.stringify(fingerprints(root))) fail('Prepared manifest, lock or configuration changed; reinitialization into a new absent workspace is required.');
  rootOfDependencies = admit(path.join(root, 'node_modules'), 'directory');
  for (const entry of fs.readdirSync(root, { withFileTypes: true })) {
    const full = path.join(root, entry.name);
    if (entry.name === 'node_modules') tree(full, true);
    else if (entry.name === '.artifact-output') continue; // Unknown output extras are not read, followed or deleted.
    else if (entry.isDirectory()) { admit(full, 'directory'); tree(full); }
    else admit(full);
  }
  const pkg = json(path.join(root, 'package.json'));
  if (typeof pkg.name !== 'string' || !/^[a-z][a-z0-9-]{0,62}$/.test(pkg.name)) fail('Invalid prepared project name.');
  const expected = scaffold(pkg.name, stack);
  for (const name of configs.filter((name) => name !== 'package-lock.json')) {
    const content = npmConfigs.includes(name) ? npmrc : expected[name];
    if (sha(read(path.join(root, name))) !== sha(content)) fail('Configuration is not the reviewed scaffold; a marker alone is insufficient.');
  }
  const lock = json(path.join(root, 'package-lock.json'));
  if (lock.lockfileVersion !== 3 || lock.name !== pkg.name || !lock.packages?.['']) fail('Missing prepared npm lock inventory.');
  for (const group of ['dependencies', 'devDependencies']) {
    if (!samePins(pkg[group], stack[group])) fail('Package pins differ from prepared stack.');
    if (!samePins(lock.packages[''][group], stack[group])) fail('Lock root differs from prepared stack.');
    for (const [name, version] of Object.entries(stack[group])) {
      if (lock.packages[`node_modules/${name}`]?.version !== version || json(path.join(rootOfDependencies, name, 'package.json')).version !== version) fail('Missing or mismatched prepared dependency; no installation during bundling.');
    }
  }
  const bundle = path.join(output, 'bundle.html');
  if (receipt.bundleHash !== null && !/^[a-f0-9]{64}$/.test(receipt.bundleHash)) fail('Invalid bundle baseline.');
  if (exists(bundle) ? receipt.bundleHash === null || sha(read(bundle)) !== receipt.bundleHash : receipt.bundleHash !== null) fail('Unknown, modified or missing prior bundle; preserved without replacement.');
  admit(path.join(root, 'index.html'));
  return { output, receipt, bundle };
}

async function bundleProject(input, stack) {
  if (input.split(path.sep).includes('..')) fail('Parent traversal rejected.');
  const root = path.resolve(input);
  const baseline = admission(root, stack);
  // Resolve only prepared local packages. Import failures precede staging writes.
  const vite = await import(pathToFileURL(admit(path.join(rootOfDependencies, 'vite/dist/node/index.js'))).href);
  const react = (await import(pathToFileURL(admit(path.join(rootOfDependencies, '@vitejs/plugin-react/dist/index.js'))).href)).default;
  const singlefile = await import(pathToFileURL(admit(path.join(rootOfDependencies, 'vite-plugin-singlefile/dist/esm/index.js'))).href);
  const tailwind = (await import(pathToFileURL(admit(path.join(rootOfDependencies, 'tailwindcss/lib/index.js'))).href)).default;
  const autoprefixer = (await import(pathToFileURL(admit(path.join(rootOfDependencies, 'autoprefixer/lib/autoprefixer.js'))).href)).default;
  const tsc = admit(path.join(rootOfDependencies, 'typescript/bin/tsc'));
  admission(root, stack);
  const prior = exists(baseline.bundle) ? read(baseline.bundle) : null;
  const priorReceipt = read(path.join(baseline.output, 'prepared.json'));
  let published = false;
  let nextHash;
  let stageIdentity;
  const stage = fs.mkdtempSync(path.join(baseline.output, 'stage-'));
  try {
    stageIdentity = identity(stage);
    fs.mkdirSync(path.join(stage, 'tmp'), { mode: 0o700 });
    const tempEnvironment = Object.fromEntries(['TMPDIR', 'TMP', 'TEMP'].map((key) => [key, process.env[key]]));
    try {
      for (const key of Object.keys(tempEnvironment)) process.env[key] = path.join(stage, 'tmp');
      const checkEnvironment = { ...process.env };
      delete checkEnvironment.NODE_OPTIONS;
      const check = spawnSync(process.execPath, [tsc, '--project', path.join(root, 'tsconfig.json'), '--noEmit'], { cwd: root, env: checkEnvironment, stdio: ['ignore', 'ignore', 'ignore'] });
      if (check.error || check.status !== 0) fail('Prepared local all-source type check failed; prior bundle preserved. Reproduce diagnostics only with authorized, screened project tooling.');
      await vite.build({ root, configFile: false, envDir: false, publicDir: false, cacheDir: path.join(stage, 'cache'), logLevel: 'silent',
        plugins: [react(), singlefile.viteSingleFile()], resolve: { alias: { '@': path.join(root, 'src') } },
        css: { postcss: { plugins: [tailwind(path.join(root, 'tailwind.config.cjs')), autoprefixer()] } },
        build: { outDir: path.join(stage, 'dist'), emptyOutDir: false, sourcemap: false, assetsInlineLimit: Number.MAX_SAFE_INTEGER, rollupOptions: { output: { inlineDynamicImports: true } } },
      });
    } finally {
      for (const [key, value] of Object.entries(tempEnvironment)) { if (value === undefined) delete process.env[key]; else process.env[key] = value; }
    }
    const dist = admit(path.join(stage, 'dist'), 'directory');
    tree(dist);
    if (JSON.stringify(fs.readdirSync(dist)) !== JSON.stringify(['index.html'])) fail('Build emitted additional assets; single-file publication refused.');
    const html = read(path.join(dist, 'index.html'));
    if (!html.length || !/<html[\s>]/i.test(html.toString())) fail('Invalid inlined HTML.');
    // This is a conservative reference check, not proof that arbitrary app code
    // cannot fetch remote resources. Offline browser qualification is separate.
    const text = html.toString();
    if (/\b(?:src|href)\s*=\s*["']\s*(?!data:|#)[^"']+["']/i.test(text) || /url\(\s*["']?\s*(?!data:|#)[^\s)"']+/i.test(text)) fail('Remaining asset/navigation URL requires review; publication refused.');
    const fresh = admission(root, stack);
    if (JSON.stringify(fresh.receipt) !== JSON.stringify(baseline.receipt)) fail('Baseline changed during build.');
    nextHash = sha(html);
    write(path.join(stage, 'prepared.json'), JSON.stringify({ ...baseline.receipt, bundleHash: nextHash }, null, 2) + '\n');
    fs.renameSync(path.join(dist, 'index.html'), baseline.bundle);
    published = true;
    fs.renameSync(path.join(stage, 'prepared.json'), path.join(baseline.output, 'prepared.json'));
    console.log(`Bundle published: ${path.join(baseline.output, 'bundle.html')} (${html.length} bytes). Offline and UI qualification remain required.`);
  } catch (error) {
    // A normal receipt-publish failure restores only our just-published bytes.
    // Concurrent user changes are never overwritten to manufacture rollback.
    if (published && exists(baseline.bundle) && sha(read(baseline.bundle)) === nextHash) {
      if (prior === null) fs.unlinkSync(baseline.bundle);
      else { write(path.join(stage, 'prior.html'), prior); fs.renameSync(path.join(stage, 'prior.html'), baseline.bundle); }
      if (sha(read(path.join(baseline.output, 'prepared.json'))) !== sha(priorReceipt)) fail('Receipt changed concurrently; manual baseline review required.');
    }
    throw error;
  } finally {
    if (stageIdentity !== undefined && exists(stage) && identity(stage) === stageIdentity) { tree(stage); fs.rmSync(stage, { recursive: true }); }
  }
}

try {
  const [action, input, ...extra] = process.argv.slice(2);
  if (!['init', 'bundle'].includes(action) || !input || extra.length) fail('Expected init <new-name> or bundle <prepared-directory>.');
  const stack = stackAdmission();
  if (action === 'init') initialize(input, stack);
  else await bundleProject(input, stack);
} catch (error) {
  // Do not relay dependency/compiler exceptions or install logs containing
  // application source, environment values, URLs or registry credentials.
  console.error(error instanceof AdmissionError ? error.message : 'Artifact operation failed. Review prerequisites, admission and prepared state; no successful bundle is claimed.');
  process.exitCode = 1;
}
