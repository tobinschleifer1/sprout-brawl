import * as THREE from '../../vendor/three.module.js';

const basic = (color, opts = {}) => new THREE.MeshBasicMaterial({ color, transparent: true, ...opts });
const std = (color, opts = {}) => new THREE.MeshStandardMaterial({ color, roughness: 0.7, flatShading: true, transparent: true, ...opts });

// Particles, projectile/summon/item meshes and debug boxes.
export class Effects {
  constructor(scene) {
    this.scene = scene;
    this.particles = [];
    this.projMeshes = new Map();
    this.summonMeshes = new Map();
    this.itemMeshes = new Map();
    this.debug = false;
    this.debugGroup = new THREE.Group(); scene.add(this.debugGroup);
    this.debugPool = [];
    this.timeScale = 1;
  }

  spawn(mesh, opts) {
    mesh.castShadow = false;
    this.scene.add(mesh);
    this.particles.push({ mesh, life: opts.life, max: opts.life, vx: opts.vx || 0, vy: opts.vy || 0, grow: opts.grow || 0, fade: opts.fade !== false, gravity: opts.gravity || 0, spin: opts.spin || 0 });
    return mesh;
  }

  ring(x, y, color, size, life, thick = 0.25) {
    const m = new THREE.Mesh(new THREE.TorusGeometry(size, thick, 6, 20), basic(color));
    m.position.set(x, y, 2);
    return this.spawn(m, { life, grow: size * 0.12 });
  }
  burstDots(x, y, color, n, speed, life, size = 0.35) {
    for (let i = 0; i < n; i++) {
      const a = Math.random() * Math.PI * 2, s = speed * (0.5 + Math.random());
      const m = new THREE.Mesh(new THREE.BoxGeometry(size, size, size), basic(color));
      m.position.set(x, y, 1.5);
      this.spawn(m, { life, vx: Math.cos(a) * s, vy: Math.sin(a) * s, gravity: 60, spin: 0.3 });
    }
  }
  star(x, y, color, size, life) {
    const g = new THREE.Group();
    for (let i = 0; i < 4; i++) { const b = new THREE.Mesh(new THREE.BoxGeometry(size, size * 0.18, 0.2), basic(color)); b.rotation.z = (i / 4) * Math.PI; g.add(b); }
    g.position.set(x, y, 2.2);
    return this.spawn(g, { life, grow: 0.2, spin: 0.15 });
  }

  handle(e, match, view) {
    switch (e.type) {
      case 'hit': {
        const heavy = e.heavy || e.launch > 60;
        const col = e.launch > 100 ? '#DE621C' : heavy ? '#F4C531' : '#FFFFFF';
        this.star(e.x, e.y, col, heavy ? 3.2 : 2, 10);
        this.burstDots(e.x, e.y, col, heavy ? 10 : 5, heavy ? 30 : 18, 18);
        if (e.launch > 100) { this.ring(e.x, e.y, '#DE621C', 2, 14, 0.4); view.shake = Math.min(3, 1 + e.launch / 60); }
        else if (heavy) view.shake = 0.8;
        break;
      }
      case 'chip': this.burstDots(e.x, e.y, '#C6B8E0', 3, 8, 12, 0.2); break;
      case 'block': this.ring(e.x, e.y, e.perfect ? '#FFFFFF' : '#9FD1E8', 1.2, 10, 0.3); if (e.perfect) this.star(e.x, e.y, '#FFFFFF', 2.5, 12); break;
      case 'armor': this.ring(e.x, e.y, '#7BA05B', 1.4, 10, 0.4); break;
      case 'counter': this.ring(e.x, e.y, '#D64C8C', 2.5, 14, 0.5); this.burstDots(e.x, e.y, '#E8D9A8', 12, 26, 20, 0.25); break;
      case 'recoil': this.burstDots(e.x, e.y, '#E8D9A8', 3, 10, 10, 0.2); break;
      case 'ko': {
        this.ring(e.x, e.y, '#DE621C', 3, 26, 0.8); this.ring(e.x, e.y, '#F4C531', 1.5, 20, 0.6);
        this.star(e.x, e.y, '#FFFFFF', 8, 24); this.burstDots(e.x, e.y, '#DE621C', 26, 45, 34, 0.6); this.burstDots(e.x, e.y, '#F4C531', 16, 30, 30, 0.4);
        view.shake = 4; break;
      }
      case 'shieldbreak': this.ring(e.x, e.y, '#9FD1E8', 3, 18, 0.5); this.burstDots(e.x, e.y, '#9FD1E8', 14, 24, 24, 0.3); break;
      case 'dash': case 'land': this.burstDots(e.x, e.y - (e.type === 'land' ? 0 : 0), '#D9C9A3', e.hard ? 8 : 4, e.hard ? 20 : 8, 12, 0.25); break;
      case 'shock': this.ring(e.x, e.y, '#D9C9A3', 3.5, 12, 0.4); break;
      case 'jump': case 'doublejump': this.ring(e.x, e.y, '#FFFFFF', 0.9, 8, 0.15); break;
      case 'dodge': this.burstDots(e.x, e.y, '#FFFFFF', 4, 10, 10, 0.2); break;
      case 'ledge': this.burstDots(e.x, e.y, '#FFFFFF', 3, 8, 8, 0.2); break;
      case 'explosion': this.ring(e.x, e.y, '#E8862A', e.radius * 0.6, 14, 0.5); this.burstDots(e.x, e.y, '#F4C531', 14, 30, 22, 0.4); view.shake = 1.5; break;
      case 'beam': {
        const len = 36, w = 2.4;
        const b = new THREE.Mesh(new THREE.BoxGeometry(len, w * (0.6 + e.charge * 0.6), 2), basic('#FFF1A8', { opacity: 0.95 }));
        b.position.set(e.x + e.facing * (4 + len / 2), e.y, 0.5);
        this.spawn(b, { life: e.frames + 4, fade: true });
        const core = new THREE.Mesh(new THREE.BoxGeometry(len, w * 0.3, 2.2), basic('#FFFFFF')); core.position.copy(b.position); this.spawn(core, { life: e.frames + 2 });
        view.shake = 1 + e.charge; break;
      }
      case 'burst': this.ring(e.x, e.y, '#F4C531', e.radius, 12, 0.6); this.burstDots(e.x, e.y, '#FFF6DC', 12, 28, 20, 0.35); break;
      case 'pulse': for (const n of e.nodes) { this.ring(n.x, n.y + 1, '#9A7FB8', 5, 12, 0.5); } break;
      case 'freeze': this.ring(e.x, e.y, '#A9D8F0', 3, 16, 0.5); this.burstDots(e.x, e.y, '#FFFFFF', 12, 18, 24, 0.3); break;
      case 'frozen': break;
      case 'bloom': this.ring(e.x, e.y, '#C8365E', 3, 18, 0.4); break;
      case 'momentumready': this.burstDots(e.x, e.y, '#C9A85C', 6, 12, 12, 0.25); break;
      case 'light': this.ring(e.x, e.y + 2, '#F4C531', 1.5, 10, 0.2); break;
      case 'summonbreak': this.burstDots(e.x, e.y + 1, '#EDE6D2', 8, 16, 14, 0.3); break;
      case 'fruiting': this.ring(e.x, e.y, '#E39B2C', 4, 18, 0.5); break;
      case 'teleport': this.burstDots(e.x, e.y + 2, '#C6B8E0', 10, 14, 14, 0.25); break;
      case 'projectilebreak': this.burstDots(e.x, e.y, '#FFFFFF', 4, 10, 10, 0.2); break;
      case 'spray': if (Math.random() < 0.7) { const d = new THREE.Mesh(new THREE.SphereGeometry(0.3, 5, 4), basic('#9FD1E8', { opacity: 0.8 })); d.position.set(e.x, e.y, 0.5); this.spawn(d, { life: 16, vx: e.facing * (24 + Math.random() * 10), vy: 4 + Math.random() * 6, gravity: 50 }); } break;
      case 'vent': this.burstDots(e.x, e.y, '#F4EBDD', 6, 14, 14, 0.3); break;
      case 'catch': this.ring(e.x, e.y, '#6B8E23', 1.5, 10, 0.3); break;
      case 'itembreak': this.burstDots(e.x, e.y, '#B0B8C0', 6, 12, 12, 0.25); break;
      case 'tech': this.ring(e.x, e.y, '#FFFFFF', 1.5, 8, 0.2); break;
      case 'shrink': view.shake = 2; break;
    }
  }

  _projMesh(p) {
    const s = p.shape;
    let m;
    if (s === 'thorn') { m = new THREE.Mesh(new THREE.ConeGeometry(0.7, 2.2, 6), std('#C8365E', { emissive: '#C8365E', emissiveIntensity: 0.3 })); m.rotation.z = -Math.PI / 2; }
    else if (s === 'spine') { m = new THREE.Mesh(new THREE.ConeGeometry(0.28, 1.4, 5), std('#E8D9A8')); m.rotation.z = -Math.PI / 2; }
    else if (s === 'wave') { m = new THREE.Mesh(new THREE.BoxGeometry(2, 2.4, 3), std('#A9D8F0', { opacity: 0.85, emissive: '#A9D8F0', emissiveIntensity: 0.4 })); }
    else if (s === 'bomb') { m = new THREE.Mesh(new THREE.SphereGeometry(0.8, 8, 6), std('#6B8E23')); }
    else if (s === 'trowel') { m = new THREE.Mesh(new THREE.BoxGeometry(1.6, 0.6, 0.4), std('#B0B8C0')); }
    else if (s === 'can') { m = new THREE.Mesh(new THREE.BoxGeometry(1.5, 1.4, 1.2), std('#3F8A2E')); }
    else { m = new THREE.Mesh(new THREE.SphereGeometry(0.6, 7, 6), std('#FFFFFF')); }
    const g = new THREE.Group(); g.add(m); g.castShadow = true;
    this.scene.add(g);
    return g;
  }

  _summonMesh(s) {
    const g = new THREE.Group();
    if (s.type === 'wall') { const w = new THREE.Mesh(new THREE.BoxGeometry(s.w, s.h, 2.5), std('#3F7D3A')); w.position.y = s.h / 2; g.add(w); for (let i = 0; i < 6; i++) { const t = new THREE.Mesh(new THREE.ConeGeometry(0.18, 0.6, 5), std('#5A3A2E')); t.position.set((i % 2 ? 0.9 : -0.9), 0.6 + i * 0.9, 0); t.rotation.z = i % 2 ? -Math.PI / 2 : Math.PI / 2; g.add(t); } }
    else if (s.type === 'cloud') { for (let i = 0; i < 5; i++) { const c = new THREE.Mesh(new THREE.SphereGeometry(s.r * (0.5 + Math.random() * 0.4), 7, 6), std('#E39B2C', { opacity: 0.45, emissive: '#E39B2C', emissiveIntensity: 0.3 })); c.position.set((Math.random() - 0.5) * s.r, (Math.random() - 0.5) * s.r, (Math.random() - 0.5) * 2); g.add(c); } }
    else if (s.type === 'mine') { const m = new THREE.Mesh(new THREE.SphereGeometry(0.8, 8, 6), std('#F3E3C3')); m.position.y = 0.8; g.add(m); for (let i = 0; i < 4; i++) { const d = new THREE.Mesh(new THREE.SphereGeometry(0.18, 5, 4), std('#8C5A2B')); const a = i * 1.6; d.position.set(Math.cos(a) * 0.7, 0.9 + Math.sin(a) * 0.4, Math.sin(a) * 0.5); g.add(d); } }
    else if (s.type === 'node') { const st_ = new THREE.Mesh(new THREE.CylinderGeometry(0.25, 0.3, 1, 6), std('#EDE6D2')); st_.position.y = 0.5; const cap = new THREE.Mesh(new THREE.SphereGeometry(0.8, 8, 6, 0, Math.PI * 2, 0, Math.PI / 2), std('#9A7FB8', { emissive: '#9A7FB8', emissiveIntensity: 0.3 })); cap.position.y = 1; g.add(st_, cap); const ring = new THREE.Mesh(new THREE.TorusGeometry(s.radius, 0.08, 4, 20), basic('#C6B8E0', { opacity: 0.5 })); ring.rotation.x = Math.PI / 2; ring.position.y = 0.05; g.add(ring); }
    this.scene.add(g);
    return g;
  }

  _itemMesh(it) {
    const id = it.def.id;
    let m;
    if (id === 'SeedBomb') m = new THREE.Mesh(new THREE.SphereGeometry(0.9, 8, 6), std('#6B8E23'));
    else if (id === 'Trowel') { m = new THREE.Group(); const blade = new THREE.Mesh(new THREE.BoxGeometry(1.6, 0.7, 0.4), std('#B0B8C0')); const handle = new THREE.Mesh(new THREE.CylinderGeometry(0.2, 0.2, 1.2, 6), std('#8C5A2B')); handle.position.set(-1.2, 0, 0); handle.rotation.z = Math.PI / 2; m.add(blade, handle); }
    else { m = new THREE.Group(); const body = new THREE.Mesh(new THREE.BoxGeometry(1.6, 1.5, 1.2), std('#3F8A2E')); const spout = new THREE.Mesh(new THREE.CylinderGeometry(0.12, 0.2, 1.4, 6), std('#3F8A2E')); spout.position.set(1.0, 0.5, 0); spout.rotation.z = -1.0; m.add(body, spout); }
    const g = new THREE.Group(); g.add(m);
    this.scene.add(g);
    return g;
  }

  syncEntities(match, t) {
    const C = match.combat;
    // projectiles
    const seenP = new Set();
    for (const p of C.projectiles) {
      let m = this.projMeshes.get(p);
      if (!m) { m = this._projMesh(p); this.projMeshes.set(p, m); }
      seenP.add(p);
      m.position.set(p.x, p.y, 0);
      m.rotation.y = p.vx < 0 ? Math.PI : 0;
      if (p.shape === 'bomb' || p.shape === 'trowel' || p.shape === 'can') m.rotation.z += 0.25;
      if (p.shape === 'wave') m.scale.y = 1 + Math.sin(t * 30) * 0.15;
      if (p.bloom) m.scale.setScalar(1.3);
    }
    for (const [p, m] of this.projMeshes) if (!seenP.has(p)) { this.scene.remove(m); this.projMeshes.delete(p); }
    // summons
    const seenS = new Set();
    for (const s of C.summons) {
      let m = this.summonMeshes.get(s);
      if (!m) { m = this._summonMesh(s); this.summonMeshes.set(s, m); }
      seenS.add(s);
      m.position.set(s.x, s.y, 0);
      if (s.type === 'cloud') { m.rotation.z = t * 0.6; m.children.forEach((c, i) => { c.material.opacity = 0.3 + Math.sin(t * 3 + i) * 0.1; }); if (s.life < 40) m.scale.setScalar(s.life / 40); }
      if (s.type === 'mine') { m.children[0].material.emissive.set('#E39B2C'); m.children[0].material.emissiveIntensity = s.armed > 0 ? 0 : 0.2 + Math.sin(t * 6) * 0.2; }
      if (s.type === 'node') m.children[1].material.emissiveIntensity = 0.3 + Math.sin(t * 4) * 0.2;
      if (s.type === 'wall' && s.life < 20) m.scale.y = s.life / 20;
    }
    for (const [s, m] of this.summonMeshes) if (!seenS.has(s)) { this.scene.remove(m); this.summonMeshes.delete(s); }
    // items
    const seenI = new Set();
    for (const it of C.items) {
      let m = this.itemMeshes.get(it);
      if (!m) { m = this._itemMesh(it); this.itemMeshes.set(it, m); }
      seenI.add(it);
      if (it.held) { const f = it.held; m.position.set(f.x + f.facing * (f.r + 0.6), f.y + f.h * 0.5, 0.6); m.rotation.y = f.facing > 0 ? 0 : Math.PI; m.rotation.z = 0; }
      else { m.position.set(it.x, it.y + 0.9 + (it.onGround ? Math.sin(t * 3) * 0.15 : 0), 0); m.rotation.z = it.onGround ? 0 : m.rotation.z + 0.2; }
      const blink = !it.held && it.onGround && it.life < 240 && Math.floor(t * 8) % 2 === 0;
      m.visible = !blink;
    }
    for (const [it, m] of this.itemMeshes) if (!seenI.has(it)) { this.scene.remove(m); this.itemMeshes.delete(it); }
    // debug boxes
    this.debugGroup.visible = this.debug;
    if (this.debug) {
      let i = 0;
      const use = (rect, color) => {
        let b = this.debugPool[i];
        if (!b) { b = new THREE.Mesh(new THREE.BoxGeometry(1, 1, 1), basic('#ff0000', { opacity: 0.32, depthTest: false })); this.debugGroup.add(b); this.debugPool[i] = b; }
        b.visible = true; b.material.color.set(color);
        b.position.set((rect.x1 + rect.x2) / 2, (rect.y1 + rect.y2) / 2, 3);
        b.scale.set(rect.x2 - rect.x1, rect.y2 - rect.y1, 0.4);
        i++;
      };
      for (const f of match.fighters) if (f.alive && f.state !== 'ko') use(f.hurtbox, f.untouchable ? '#FFFFFF' : '#3FA0B0');
      for (const d of C.debugBoxes) use(d.rect, d.kind === 'hit' ? '#DE621C' : d.kind === 'grab' ? '#D64C8C' : d.kind === 'proj' ? '#F4C531' : d.kind === 'push' ? '#9FD1E8' : '#9A7FB8');
      for (let j = i; j < this.debugPool.length; j++) this.debugPool[j].visible = false;
    }
  }

  update(dt) {
    for (let i = this.particles.length - 1; i >= 0; i--) {
      const p = this.particles[i];
      p.life -= dt * 60;
      p.mesh.position.x += p.vx * dt; p.mesh.position.y += p.vy * dt; p.vy -= p.gravity * dt;
      if (p.grow) p.mesh.scale.addScalar(p.grow * dt * 60 * 0.2);
      if (p.spin) p.mesh.rotation.z += p.spin;
      const k = Math.max(0, p.life / p.max);
      if (p.fade) p.mesh.traverse((o) => { if (o.material) o.material.opacity = k; });
      if (p.life <= 0) { this.scene.remove(p.mesh); this.particles.splice(i, 1); }
    }
  }

  clear() {
    for (const p of this.particles) this.scene.remove(p.mesh); this.particles.length = 0;
    for (const m of this.projMeshes.values()) this.scene.remove(m); this.projMeshes.clear();
    for (const m of this.summonMeshes.values()) this.scene.remove(m); this.summonMeshes.clear();
    for (const m of this.itemMeshes.values()) this.scene.remove(m); this.itemMeshes.clear();
  }
}
