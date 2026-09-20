"""Three resumable Meshy models requested for RemZ; credentials never logged."""
import json, os, sys, threading
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
ROOT = Path(__file__).resolve().parents[1]
os.chdir(ROOT)
sys.path.insert(0,str(ROOT/'.claude/skills/meshy-3d-generation/scripts'))
import meshy_task as api
from progression_assets import authenticate
SPECS = {
'raven_real': ('Photoreal anatomically accurate common raven, Corvus corax, single complete living bird with both wings fully extended horizontally in a symmetrical gliding flight pose. Long separated primary flight feathers with rounded tapered tips, overlapping layered secondary feathers, broad tapered wedge-shaped tail, compact feathered body, shaggy throat feathers, robust gently curved black beak, small dark eyes, two small feet tucked against belly. Wings span sideways along X axis, head faces forward, back upward. Natural realistic bird anatomy and proportions. No pedestal, no environment, no cartoon, no accessories.', 'Natural black raven plumage with subtle blue charcoal iridescence, individually layered feather vanes and fine barbs, dark charcoal beak and scaly feet, small glossy black eyes. Photoreal wildlife PBR, no baked highlights or shadows.', 16000),
'knife_real': ('A single realistic full tang fixed blade bushcraft knife, upright with blade tip pointing up and handle down. 30 cm total length, 17 cm drop point blade and 13 cm ergonomic grip. Thick steel spine narrowing to a sharp continuous cutting bevel, restrained finger guard, black textured micarta handle scales fixed with three flush steel rivets, exposed metal tang and small lanyard hole in pommel. Practical premium survival tool with natural proportions, modeled bevel and contoured handle. One knife only, no hand, no sheath, no stand, no text, no decorations, no fantasy shapes.', 'Photoreal satin brushed hardened steel blade with subtle directional grinding marks, polished cutting bevel, worn black charcoal micarta grip with fine woven fibers and three steel rivets. Realistic metal roughness and restrained use marks. No painted lighting.', 16000),
'hatchet_real': ('A single realistic traditional European forestry hatchet, upright handle down and axe head at top, cutting edge facing right along X axis. 55 cm curved hickory wood handle with oval cross section, narrow waist and flared ergonomic butt. Compact asymmetric hand forged steel axe head, thick rectangular hammer poll left, oval handle eye with visible wedged wooden tenon, broad gently convex thin sharpened cutting edge right. Natural working tool proportions, visibly three dimensional head taper and cutting bevel. Single complete axe only, no hand, no sheath, no stand, no text, no fantasy details.', 'Photoreal oiled honey brown hickory handle with longitudinal woodgrain and darker worn grip, charcoal forged steel axe head with subtle hammer marks and patina, bright ground steel cutting bevel, visible end grain and metal wedge in eye. Realistic roughness and normal maps, no baked lighting.', 18000)
}
ENDPOINT='/openapi/v2/text-to-3d'
HISTORY_LOCK=threading.Lock()
def generate(name, spec):
 folder=ROOT/'meshy_output'/'raven_melee'/name
 folder.mkdir(parents=True,exist_ok=True)
 statefile=folder/'state.json'
 state=json.loads(statefile.read_text()) if statefile.exists() else {}
 def save(): statefile.write_text(json.dumps(state,indent=2),encoding='utf-8')
 if 'preview' not in state:
  state['preview']=api.create_task(ENDPOINT,dict(mode='preview',prompt=spec[0],ai_model='meshy-7.1',geometry_resolution='2k',should_remesh=True,topology='triangle',target_polycount=spec[2],target_formats=['glb']))
  save()
 for stage in ['preview','refine']:
  if stage=='refine' and stage not in state:
   state[stage]=api.create_task(ENDPOINT,dict(mode='refine',preview_task_id=state['preview'],enable_pbr=True,texture_resolution='4k',texture_prompt=spec[1],target_formats=['glb']))
   save()
  receipt_path=folder/(stage+'_task.json')
  receipt=json.loads(receipt_path.read_text()) if receipt_path.exists() else api.poll_task(ENDPOINT,state[stage],timeout=1800)
  receipt_path.write_text(json.dumps(receipt,indent=2),encoding='utf-8')
  target=folder/(stage+'.glb')
  if not target.exists(): api.download(receipt['model_urls']['glb'],str(target))
  thumb=folder/(stage+'.png')
  if receipt.get('thumbnail_url') and not thumb.exists(): api.download(receipt['thumbnail_url'],str(thumb))
  print(name,stage,'credits',receipt.get('consumed_credits'),flush=True)
  with HISTORY_LOCK:
   api.record_task(str(folder),state[stage],'text-to-3d',stage,spec[0],[target.name])
 print('MODEL_READY',name,str(folder),flush=True)
if __name__=='__main__':
 authenticate()
 with ThreadPoolExecutor(max_workers=3) as pool:
  jobs=[pool.submit(generate,name,spec) for name,spec in SPECS.items()]
  for job in jobs: job.result()
