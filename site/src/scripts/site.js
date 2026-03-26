// Star field — renders stars + nebula + grid onto a single canvas.
// One GPU layer instead of 4+ DOM elements with box-shadows.
(function() {
  let canvas = document.querySelector('.star-field');
  if (!canvas) return;

  let dpr = Math.min(window.devicePixelRatio || 1, 2);
  let w = window.innerWidth;
  let h = window.innerHeight;

  canvas.width = w * dpr;
  canvas.height = h * dpr;
  canvas.style.width = w + 'px';
  canvas.style.height = h + 'px';

  let ctx = canvas.getContext('2d');
  ctx.scale(dpr, dpr);

  // Seeded PRNG for consistent star positions
  let seed = 42;
  function rand() {
    seed = (seed * 16807) % 2147483647;
    return (seed - 1) / 2147483646;
  }

  // Nebula gradients
  let nebulae = [
    { x: w * 0.1, y: h * 0.15, rx: 450, ry: 300, color: '84,174,229', alpha: 0.05 },
    { x: w * 0.9, y: h * 0.55, rx: 300, ry: 450, color: '179,115,242', alpha: 0.04 },
    { x: w * 0.55, y: h * 0.85, rx: 250, ry: 200, color: '242,140,107', alpha: 0.025 },
    { x: w * 0.75, y: h * 0.05, rx: 400, ry: 250, color: '89,209,140', alpha: 0.02 },
  ];

  nebulae.forEach(function(n) {
    let grad = ctx.createRadialGradient(n.x, n.y, 0, n.x, n.y, Math.max(n.rx, n.ry));
    grad.addColorStop(0, 'rgba(' + n.color + ',' + n.alpha + ')');
    grad.addColorStop(0.7, 'rgba(' + n.color + ',0)');
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, w, h);
  });

  // Coordinate grid with radial mask
  ctx.save();
  // Create radial mask via globalCompositeOperation
  let maskCanvas = document.createElement('canvas');
  maskCanvas.width = w * dpr;
  maskCanvas.height = h * dpr;
  let mctx = maskCanvas.getContext('2d');
  mctx.scale(dpr, dpr);

  // Draw grid lines
  mctx.strokeStyle = 'rgba(84,174,229,0.018)';
  mctx.lineWidth = 1;
  for (let x = 0; x < w; x += 80) {
    mctx.beginPath();
    mctx.moveTo(x + 0.5, 0);
    mctx.lineTo(x + 0.5, h);
    mctx.stroke();
  }
  for (let y = 0; y < h; y += 80) {
    mctx.beginPath();
    mctx.moveTo(0, y + 0.5);
    mctx.lineTo(w, y + 0.5);
    mctx.stroke();
  }

  // Apply radial fade mask
  mctx.globalCompositeOperation = 'destination-in';
  let mask = mctx.createRadialGradient(w * 0.5, h * 0.35, 0, w * 0.5, h * 0.35, w * 0.5);
  mask.addColorStop(0, 'rgba(0,0,0,0.5)');
  mask.addColorStop(1, 'rgba(0,0,0,0)');
  mctx.fillStyle = mask;
  mctx.fillRect(0, 0, w, h);

  ctx.drawImage(maskCanvas, 0, 0, w, h);
  ctx.restore();

  // Stars
  let layers = [
    { count: 150, size: 0.8, minO: 0.15, maxO: 0.45 },
    { count: 60, size: 1.2, minO: 0.25, maxO: 0.6 },
    { count: 20, size: 1.8, minO: 0.5, maxO: 0.9, glow: true },
  ];

  let tints = [
    [200, 220, 255],
    [180, 200, 255],
    [220, 200, 255],
    [200, 240, 255],
  ];

  layers.forEach(function(layer) {
    for (let i = 0; i < layer.count; i++) {
      let x = rand() * w;
      let y = rand() * h;
      let opacity = layer.minO + rand() * (layer.maxO - layer.minO);
      let r = layer.size;

      if (layer.glow) {
        let tint = tints[Math.floor(rand() * tints.length)];
        ctx.fillStyle = 'rgba(' + tint[0] + ',' + tint[1] + ',' + tint[2] + ',' + opacity + ')';
        ctx.shadowColor = 'rgba(' + tint[0] + ',' + tint[1] + ',' + tint[2] + ',' + (opacity * 0.6) + ')';
        ctx.shadowBlur = 3;
      } else {
        ctx.fillStyle = 'rgba(255,255,255,' + opacity + ')';
        ctx.shadowColor = 'transparent';
        ctx.shadowBlur = 0;
      }

      ctx.beginPath();
      ctx.arc(x, y, r, 0, Math.PI * 2);
      ctx.fill();
    }
  });

  // Reset shadow state
  ctx.shadowBlur = 0;
  ctx.shadowColor = 'transparent';
})();

// Scroll reveal
(function() {
  let els = document.querySelectorAll('.reveal, .reveal-stagger');
  if (!els.length) return;

  let observer = new IntersectionObserver(function(entries) {
    entries.forEach(function(entry) {
      if (entry.isIntersecting) {
        entry.target.classList.add('visible');
        observer.unobserve(entry.target);
      }
    });
  }, { threshold: 0.08, rootMargin: '0px 0px -40px 0px' });

  els.forEach(function(el) { observer.observe(el); });
})();
