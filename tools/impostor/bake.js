#!/usr/bin/env node
// Renders the raw impostor views for every tree in <assets>/manifest.json into <assets>/.bake/.
//   cd tools/impostor && npm install && node bake.js ../../assets/fir
const fs = require('fs'), path = require('path'), http = require('http');
const {chromium} = require('playwright');

const repo = path.resolve(__dirname, '../..');
const assets = path.resolve(process.argv[2]);
const SS = 2;                       // supersampling; packed down by build_impostors.py
const MARGIN = 1.04;
const types = {'.html': 'text/html', '.js': 'text/javascript', '.json': 'application/json',
  '.gltf': 'model/gltf+json', '.bin': 'application/octet-stream', '.png': 'image/png', '.jpg': 'image/jpeg'};

const server = http.createServer((req, res) => {
  const f = path.join(repo, decodeURIComponent(req.url.split('?')[0]));
  if (!f.startsWith(repo) || !fs.existsSync(f)) { res.writeHead(404); return res.end(); }
  res.writeHead(200, {'Content-Type': types[path.extname(f)] || 'application/octet-stream'});
  fs.createReadStream(f).pipe(res);
});

(async () => {
  await new Promise(ok => server.listen(0, ok));
  const base = `http://localhost:${server.address().port}`;
  const browser = await chromium.launch({args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist']});
  const page = await browser.newPage();
  page.on('pageerror', e => console.error('page error:', e.message));
  await page.goto(`${base}/tools/impostor/bake.html`);
  await page.waitForFunction(() => document.title === 'ready');
  const manifest = JSON.parse(fs.readFileSync(path.join(assets, 'manifest.json')));
  const outDir = path.join(assets, '.bake');
  fs.mkdirSync(outDir, {recursive: true});
  const frames = {};
  for (const t of manifest) {
    const radius = t.radius * MARGIN, y0 = -0.02 * t.top, y1 = t.top * 1.02;
    const [vw, vh] = t.impostor_view || [256, 1024];   // texels per view in the atlas
    const W = vw * SS, H = vh * SS;
    const url = `${base}/${path.relative(repo, assets)}/${t.lods[0].file}`;
    const imgs = await page.evaluate(a => window.bake(...a), [url, radius, y0, y1, W, H]);
    ['color_z', 'normal_z', 'color_x', 'normal_x', 'color_a', 'normal_a', 'color_b', 'normal_b'].forEach((n, i) =>
      fs.writeFileSync(path.join(outDir, `${t.name}_${n}.png`), Buffer.from(imgs[i].split(',')[1], 'base64')));
    frames[t.name] = {radius, y0, y1};
    console.log('baked', t.name);
  }
  fs.writeFileSync(path.join(outDir, 'frames.json'), JSON.stringify(frames, null, 1));
  await browser.close(); server.close();
})();
