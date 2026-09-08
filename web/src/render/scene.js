import * as THREE from '../../vendor/three.module.js';

// Three.js scene, lights and the side-on framing camera.
export class SceneView {
  constructor(canvas) {
    this.renderer = new THREE.WebGLRenderer({ canvas, antialias: true, powerPreference: 'high-performance' });
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    this.renderer.shadowMap.enabled = true;
    this.renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    this.renderer.outputColorSpace = THREE.SRGBColorSpace;
    this.scene = new THREE.Scene();
    this.scene.background = new THREE.Color('#E7F3F6');
    this.camera = new THREE.PerspectiveCamera(42, 16 / 9, 1, 800);
    this.camera.position.set(0, 12, 110);
    this.camTarget = new THREE.Vector3(0, 10, 0);
    this.camPos = new THREE.Vector3(0, 12, 110);
    this.shake = 0;

    this.hemi = new THREE.HemisphereLight('#ffffff', '#6b7a5a', 0.9);
    this.scene.add(this.hemi);
    this.sun = new THREE.DirectionalLight('#fff4d6', 1.6);
    this.sun.position.set(-40, 80, 60);
    this.sun.castShadow = true;
    this.sun.shadow.mapSize.set(2048, 2048);
    const sc = this.sun.shadow.camera;
    sc.left = -130; sc.right = 130; sc.top = 110; sc.bottom = -70; sc.near = 10; sc.far = 300;
    this.sun.shadow.bias = -0.0005;
    this.scene.add(this.sun);
    this.scene.add(this.sun.target);
    this.fill = new THREE.DirectionalLight('#cfe6ff', 0.5);
    this.fill.position.set(50, 30, -40);
    this.scene.add(this.fill);

    this.resize();
    window.addEventListener('resize', () => this.resize());
  }

  resize() {
    const w = window.innerWidth || 1280, h = window.innerHeight || 720;
    this.renderer.setSize(w, h, false);
    this.camera.aspect = w / h;
    this.camera.updateProjectionMatrix();
  }

  setBackground(hex) { this.scene.background = new THREE.Color(hex); }

  // Frame all alive fighters with padding; zoom between a minimum width and the blast-zone width.
  frame(fighters, stage, dt, instant) {
    let x1 = Infinity, x2 = -Infinity, y1 = Infinity, y2 = -Infinity, n = 0;
    for (const f of fighters) {
      if (!f.alive || f.state === 'ko') continue;
      x1 = Math.min(x1, f.x); x2 = Math.max(x2, f.x); y1 = Math.min(y1, f.y); y2 = Math.max(y2, f.y + f.h); n++;
    }
    if (n === 0) { x1 = -20; x2 = 20; y1 = 0; y2 = 20; }
    y1 = Math.min(y1, stage.main.top - 4); x1 = Math.min(x1, stage.main.x1 + 10); x2 = Math.max(x2, stage.main.x2 - 10);
    const pad = 9;
    x1 -= pad; x2 += pad; y1 -= pad; y2 += pad + 4;
    const b = stage.blast;
    x1 = Math.max(x1, b.left - 6); x2 = Math.min(x2, b.right + 6); y1 = Math.max(y1, b.bottom - 4); y2 = Math.min(y2, b.top + 4);
    const minW = 62;
    let w = Math.max(x2 - x1, minW), h = Math.max(y2 - y1, minW / this.camera.aspect * 0.9);
    const cx = (x1 + x2) / 2, cy = (y1 + y2) / 2;
    const vFov = (this.camera.fov * Math.PI) / 180;
    const hFov = 2 * Math.atan(Math.tan(vFov / 2) * this.camera.aspect);
    const dist = Math.max((w / 2) / Math.tan(hFov / 2), (h / 2) / Math.tan(vFov / 2));
    if (!isFinite(dist)) return;
    const target = new THREE.Vector3(cx, cy, 0);
    const pos = new THREE.Vector3(cx, cy + dist * 0.06, dist);
    if (![this.camPos.x, this.camPos.y, this.camPos.z].every(isFinite)) { this.camPos.copy(pos); this.camTarget.copy(target); }
    const k = instant ? 1 : 1 - Math.pow(0.02, dt || 0);
    this.camTarget.lerp(target, k);
    this.camPos.lerp(pos, k);
    let sx = 0, sy = 0;
    if (this.shake > 0) { sx = (Math.random() - 0.5) * this.shake; sy = (Math.random() - 0.5) * this.shake; this.shake *= 0.85; if (this.shake < 0.05) this.shake = 0; }
    this.camera.position.set(this.camPos.x + sx, this.camPos.y + sy, this.camPos.z);
    this.camera.lookAt(this.camTarget.x + sx, this.camTarget.y + sy, 0);
    this.sun.target.position.set(cx, 0, 0);
  }

  project(x, y, z = 0) {
    const v = new THREE.Vector3(x, y, z).project(this.camera);
    return { x: (v.x + 1) / 2 * window.innerWidth, y: (1 - v.y) / 2 * window.innerHeight, visible: v.z < 1 };
  }

  render() { this.renderer.render(this.scene, this.camera); }
}
