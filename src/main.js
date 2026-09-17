import * as THREE from 'three';
import { loadAll, loaded } from './assets.js';
import { World } from './world.js';
import { Player } from './player.js';
import { Weapons } from './weapons.js';
import { Zombies } from './zombies.js';
import { Barricades } from './barricades.js';
import { Waves } from './waves.js';
import { hud } from './hud.js';
import { audio } from './audio.js';

const app = document.getElementById('app');
const renderer = new THREE.WebGLRenderer({ antialias: true, powerPreference: 'high-performance' });
renderer.setPixelRatio(Math.min(window.devicePixelRatio, 1.5));
renderer.setSize(innerWidth, innerHeight);
renderer.shadowMap.enabled = true; renderer.shadowMap.type = THREE.PCFSoftShadowMap;
renderer.toneMapping = THREE.ACESFilmicToneMapping; renderer.toneMappingExposure = 1.1;
app.appendChild(renderer.domElement);

const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(75, innerWidth / innerHeight, 0.05, 260);
scene.add(camera);
addEventListener('resize', () => { camera.aspect = innerWidth / innerHeight; camera.updateProjectionMatrix(); renderer.setSize(innerWidth, innerHeight); });

const loadingEl = document.getElementById('loading');
const startBtn = document.getElementById('startBtn');
startBtn.disabled = true;

let world, player, weapons, zombies, barricades, waves, started = false, over = false;

async function init() {
  await loadAll((d, n) => (loadingEl.textContent = `Lade Modelle ${d}/${n}`));
  world = new World(scene); await world.build();
  player = new Player(camera, renderer.domElement, world);
  player.controls.onUnlock = pause;
  scene.add(player.obj);
  zombies = new Zombies(scene, world, player);
  weapons = new Weapons(camera, scene, player, zombies, world);
  barricades = new Barricades(scene, player, world);
  waves = new Waves(zombies, player, weapons);
  const real = Object.values(loaded).filter(Boolean).length, total = Object.keys(loaded).length;
  loadingEl.textContent = real === total ? 'Bereit.' : `Bereit. ${real}/${total} Modelle geladen, Rest als Platzhalter.`;
  startBtn.disabled = false;
  renderer.render(scene, camera);
  // debug / test hook: step the simulation without relying on requestAnimationFrame
  window.remz = { scene, world, player, weapons, zombies, barricades, waves, step(dt = 1 / 60, n = 1) { for (let i = 0; i < n; i++) tick(dt); renderer.render(scene, camera); } };
}

function tick(dt) {
  player.update(dt); weapons.update(dt); zombies.update(dt, barricades); barricades.update(); waves.update(dt);
  if (!player.alive) gameOver();
}

startBtn.addEventListener('click', () => {
  audio.init();
  if (over) { location.reload(); return; }
  document.getElementById('overlay').style.display = 'none';
  player.controls.lock(); started = true;
});
function pause() { if (started && !over) { document.getElementById('overlay').style.display = 'flex'; startBtn.textContent = 'Weiter'; } }

const clock = new THREE.Clock();
function loop() {
  requestAnimationFrame(loop);
  const dt = Math.min(0.05, clock.getDelta());
  const t = clock.elapsedTime;
  if (world) world.update(t, player?.position);
  if (started && !over && player.controls.isLocked) tick(dt);
  if (world) renderer.render(scene, camera);
}

function gameOver() {
  over = true; player.controls.unlock();
  const ov = document.getElementById('overlay'); ov.style.display = 'flex';
  ov.querySelector('h1').innerHTML = 'GESTORBEN<small>AM BIRKENHOF</small>';
  ov.querySelector('p').textContent = `Du hast ${waves.wave} Welle${waves.wave === 1 ? '' : 'n'} überstanden mit ${player.score} Punkten.`;
  ov.querySelector('table').style.display = 'none';
  startBtn.textContent = 'Nochmal';
}

init().catch(e => { console.error(e); loadingEl.textContent = 'Fehler: ' + e.message; });
loop();
