#!/usr/bin/env node

let fs = require('fs');
let path = require('path');
let http = require('http');

let SRC = path.join(__dirname, 'src');
let DIST = path.join(__dirname, 'dist');
let PAGES = path.join(SRC, 'pages');
let PARTIALS = path.join(SRC, 'partials');

function parseFrontmatter(content) {
  let match = content.match(/^---\n([\s\S]*?)\n---\n([\s\S]*)$/);
  if (!match) return { meta: {}, body: content };

  let meta = {};
  for (let line of match[1].split('\n')) {
    let idx = line.indexOf(':');
    if (idx === -1) continue;
    let key = line.slice(0, idx).trim();
    let val = line.slice(idx + 1).trim();
    if (val === 'true') val = true;
    else if (val === 'false') val = false;
    meta[key] = val;
  }

  return { meta, body: match[2] };
}

function build() {
  // Clean dist
  if (fs.existsSync(DIST)) fs.rmSync(DIST, { recursive: true });
  fs.mkdirSync(DIST, { recursive: true });

  // Read layout
  let layout = fs.readFileSync(path.join(SRC, 'layout.html'), 'utf8');

  // Read partials
  let partials = {};
  for (let file of fs.readdirSync(PARTIALS)) {
    if (!file.endsWith('.html')) continue;
    let name = path.basename(file, '.html');
    partials[name] = fs.readFileSync(path.join(PARTIALS, file), 'utf8');
  }

  // Build each page
  let pages = fs.readdirSync(PAGES).filter(f => f.endsWith('.html'));

  for (let file of pages) {
    let raw = fs.readFileSync(path.join(PAGES, file), 'utf8');
    let { meta, body } = parseFrontmatter(raw);

    let html = layout;

    // Inject content first (before variable replacement, so page content isn't mangled)
    html = html.replace('{{content}}', body);

    // Conditionals: {{#if key}}...{{/if}}
    html = html.replace(/\{\{#if (\w+)\}\}([\s\S]*?)\{\{\/if\}\}/g, (_, key, block) => {
      return meta[key] ? block : '';
    });

    // Variables from frontmatter
    html = html.replace(/\{\{(\w+)\}\}/g, (match, key) => {
      return meta[key] !== undefined ? meta[key] : '';
    });

    // Partials: {{> name}}
    html = html.replace(/\{\{> (\w+)\}\}/g, (_, name) => {
      let partial = partials[name] || '';

      // Resolve active nav markers: {{active:about}} -> class="active" or ""
      if (name === 'nav' && meta.active) {
        partial = partial.replace(
          new RegExp(`\\{\\{active:${meta.active}\\}\\}`, 'g'),
          'class="active"'
        );
      }
      // Clean remaining active markers
      partial = partial.replace(/\{\{active:\w+\}\}/g, '');

      return partial;
    });

    fs.writeFileSync(path.join(DIST, file), html);
    console.log(`  ${file}`);
  }

  // Copy styles.css
  fs.copyFileSync(path.join(SRC, 'styles.css'), path.join(DIST, 'styles.css'));
  console.log('  styles.css');

  // Copy scripts/
  let scriptsDir = path.join(SRC, 'scripts');
  if (fs.existsSync(scriptsDir)) {
    let distScripts = path.join(DIST, 'scripts');
    fs.mkdirSync(distScripts, { recursive: true });
    for (let file of fs.readdirSync(scriptsDir)) {
      fs.copyFileSync(path.join(scriptsDir, file), path.join(distScripts, file));
      console.log(`  scripts/${file}`);
    }
  }

  console.log('\nDone.');
}

function serve(port) {
  let mimeTypes = {
    '.html': 'text/html',
    '.css': 'text/css',
    '.js': 'application/javascript',
    '.png': 'image/png',
    '.jpg': 'image/jpeg',
    '.svg': 'image/svg+xml',
    '.ico': 'image/x-icon',
  };

  let server = http.createServer((req, res) => {
    let url = req.url === '/' ? '/index.html' : req.url;
    let filePath = path.join(DIST, url);
    let ext = path.extname(filePath);

    // If no extension, try .html
    if (!ext) {
      filePath += '.html';
      ext = '.html';
    }

    fs.readFile(filePath, (err, data) => {
      if (err) {
        res.writeHead(404, { 'Content-Type': 'text/plain' });
        res.end('404 Not Found');
        return;
      }
      res.writeHead(200, { 'Content-Type': mimeTypes[ext] || 'application/octet-stream' });
      res.end(data);
    });
  });

  server.listen(port, () => {
    console.log(`\nServing site/dist at http://localhost:${port}`);
  });
}

// Run
console.log('Building site...\n');
build();

if (process.argv.includes('--serve')) {
  let portIdx = process.argv.indexOf('--port');
  let port = portIdx !== -1 ? parseInt(process.argv[portIdx + 1], 10) : 3000;
  serve(port);
}
