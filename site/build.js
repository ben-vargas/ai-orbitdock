#!/usr/bin/env node

let fs = require('fs');
let path = require('path');
let http = require('http');

let SRC = path.join(__dirname, 'src');
let DIST = path.join(__dirname, 'dist');
let PAGES = path.join(SRC, 'pages');
let PARTIALS = path.join(SRC, 'partials');

let GITHUB_REPO = 'Robdel12/OrbitDock';

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

function formatCount(n) {
  if (n >= 1000) return (n / 1000).toFixed(1).replace(/\.0$/, '') + 'k';
  return String(n);
}

function inlineMarkdown(text) {
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
    .replace(/`(.+?)`/g, '<code>$1</code>')
    .replace(/\[(.+?)\]\((.+?)\)/g, '<a href="$2" target="_blank" rel="noopener">$1</a>');
}

function renderReleaseBody(md) {
  if (!md) return '';
  let lines = md.split('\n');
  let html = '';
  let inList = false;

  for (let line of lines) {
    let trimmed = line.trim();
    if (!trimmed) {
      if (inList) { html += '</ul>'; inList = false; }
      continue;
    }
    if (trimmed.startsWith('## ')) {
      if (inList) { html += '</ul>'; inList = false; }
      html += '<h4>' + inlineMarkdown(trimmed.slice(3)) + '</h4>';
    } else if (trimmed.startsWith('### ')) {
      if (inList) { html += '</ul>'; inList = false; }
      html += '<h4>' + inlineMarkdown(trimmed.slice(4)) + '</h4>';
    } else if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
      if (!inList) { html += '<ul>'; inList = true; }
      html += '<li>' + inlineMarkdown(trimmed.slice(2)) + '</li>';
    } else {
      if (inList) { html += '</ul>'; inList = false; }
      html += '<p>' + inlineMarkdown(trimmed) + '</p>';
    }
  }
  if (inList) html += '</ul>';
  return html;
}

async function fetchGitHubData() {
  let headers = { 'User-Agent': 'OrbitDock-Site-Builder' };
  if (process.env.GITHUB_TOKEN) {
    headers['Authorization'] = 'token ' + process.env.GITHUB_TOKEN;
  }

  let defaults = {
    starCount: '',
    latestVersion: '',
    latestReleaseUrl: 'https://github.com/' + GITHUB_REPO + '/releases',
    latestReleaseDate: '',
    changelogContent: '<p class="empty-state">No releases yet. Check back soon.</p>',
    contributorAvatars: '',
  };

  try {
    let [repoRes, releasesRes, contributorsRes] = await Promise.all([
      fetch('https://api.github.com/repos/' + GITHUB_REPO, { headers }),
      fetch('https://api.github.com/repos/' + GITHUB_REPO + '/releases?per_page=30', { headers }),
      fetch('https://api.github.com/repos/' + GITHUB_REPO + '/contributors?per_page=20', { headers }),
    ]);

    let repo = await repoRes.json();
    let releases = await releasesRes.json();
    let contributors = await contributorsRes.json();

    // Star count
    let starCount = repo.stargazers_count || 0;

    // Latest release
    let latest = Array.isArray(releases) && releases.length > 0 ? releases[0] : null;

    // Contributors HTML
    let avatarHtml = '';
    if (Array.isArray(contributors)) {
      avatarHtml = contributors
        .filter(c => c.type === 'User')
        .slice(0, 12)
        .map(c =>
          '<a href="' + c.html_url + '" target="_blank" rel="noopener" title="' + c.login + '">' +
          '<img src="' + c.avatar_url + '&s=64" alt="' + c.login + '" width="32" height="32" loading="lazy">' +
          '</a>'
        )
        .join('\n            ');
    }

    // Changelog HTML
    let changelogHtml = '';
    if (Array.isArray(releases) && releases.length > 0) {
      changelogHtml = releases.map(r => {
        let date = new Date(r.published_at).toLocaleDateString('en-US', {
          year: 'numeric', month: 'long', day: 'numeric'
        });
        let prerelease = r.prerelease ? ' <span class="release-pre">pre-release</span>' : '';
        return (
          '<article class="release-card hud-panel">' +
            '<div class="release-header">' +
              '<a href="' + r.html_url + '" class="release-tag" target="_blank" rel="noopener">' + r.tag_name + '</a>' +
              prerelease +
              '<time class="release-date">' + date + '</time>' +
            '</div>' +
            '<h3 class="release-title">' + (r.name || r.tag_name) + '</h3>' +
            '<div class="release-body">' + renderReleaseBody(r.body) + '</div>' +
          '</article>'
        );
      }).join('\n');
    }

    console.log('  GitHub: ' + formatCount(starCount) + ' stars, ' +
      (Array.isArray(releases) ? releases.length : 0) + ' releases, ' +
      (Array.isArray(contributors) ? contributors.filter(c => c.type === 'User').length : 0) + ' contributors');

    return {
      starCount: formatCount(starCount),
      latestVersion: latest ? latest.tag_name : '',
      latestReleaseUrl: latest ? latest.html_url : defaults.latestReleaseUrl,
      latestReleaseDate: latest
        ? new Date(latest.published_at).toLocaleDateString('en-US', { month: 'short', day: 'numeric' })
        : '',
      changelogContent: changelogHtml || defaults.changelogContent,
      contributorAvatars: avatarHtml,
    };
  } catch (err) {
    console.warn('  ⚠ GitHub API fetch failed, using defaults:', err.message);
    return defaults;
  }
}

async function build() {
  // Clean dist
  if (fs.existsSync(DIST)) fs.rmSync(DIST, { recursive: true });
  fs.mkdirSync(DIST, { recursive: true });

  // Fetch GitHub data
  let github = await fetchGitHubData();

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

    // Partials: {{> name}} — resolve before variables so partials can use template vars
    html = html.replace(/\{\{> (\w+)\}\}/g, (_, name) => {
      let partial = partials[name] || '';

      // Resolve active nav markers: {{active:about}} -> class="active" or ""
      if (name === 'nav' && meta.active) {
        partial = partial.replace(
          new RegExp('\\{\\{active:' + meta.active + '\\}\\}', 'g'),
          'class="active"'
        );
      }
      // Clean remaining active markers
      partial = partial.replace(/\{\{active:\w+\}\}/g, '');

      return partial;
    });

    // Merge global (GitHub) data with page frontmatter
    let allVars = { ...github, ...meta };

    // Conditionals: {{#if key}}...{{/if}}
    html = html.replace(/\{\{#if (\w+)\}\}([\s\S]*?)\{\{\/if\}\}/g, (_, key, block) => {
      return allVars[key] ? block : '';
    });

    // Variables
    html = html.replace(/\{\{(\w+)\}\}/g, (match, key) => {
      return allVars[key] !== undefined ? allVars[key] : '';
    });

    fs.writeFileSync(path.join(DIST, file), html);
    console.log('  ' + file);
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
      console.log('  scripts/' + file);
    }
  }

  // Copy public/ (images, etc.)
  let publicDir = path.join(__dirname, 'public');
  if (fs.existsSync(publicDir)) {
    for (let file of fs.readdirSync(publicDir)) {
      fs.copyFileSync(path.join(publicDir, file), path.join(DIST, file));
      console.log('  ' + file);
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
    console.log('\nServing site/dist at http://localhost:' + port);
  });
}

// Run
console.log('Building site...\n');
build().then(() => {
  if (process.argv.includes('--serve')) {
    let portIdx = process.argv.indexOf('--port');
    let port = portIdx !== -1 ? parseInt(process.argv[portIdx + 1], 10) : 3000;
    serve(port);
  }
});
