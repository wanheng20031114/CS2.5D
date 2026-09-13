"""Faithful low-poly Mirage transformation from the user's installed CS2 assets.
Run after Source2Viewer exports source_world_materials.glb. The source's indexed
geometry and all object transforms are preserved; only tessellation and surface
rendering change. Source textures are sampled offline, never used at runtime.
"""
from pathlib import Path
import json,struct,math,argparse,collections,time,os,tempfile
import numpy as np
from PIL import Image
import trimesh as tm
from scipy.spatial import cKDTree
from shapely.geometry import Polygon,box
from shapely.ops import unary_union
from shapely import constrained_delaunay_triangles
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'assets/map'
SOURCE_DIR=Path(os.environ.get('CS25D_MAP_SOURCE_DIR',Path(tempfile.gettempdir())/'cs25d-map-tools'))
SOURCE=SOURCE_DIR/'source_world_materials.glb'
RNG=np.random.default_rng(231220)
T=np.array([[0,0,1,17.018],[0,1,0,6.5024],[-1,0,0,-21.5138],[0,0,0,1]],float)

def write(path,content):
 path=Path(path);tmp=path.with_suffix(path.suffix+'.tmp')
 tmp.write_bytes(content.encode('utf-8') if isinstance(content,str) else content);tmp.replace(path)

class GLB:
 def __init__(self,path):
  self.path=Path(path);b=self.path.read_bytes();n=struct.unpack_from('<I',b,12)[0];self.j=json.loads(b[20:20+n]);self.bin=b[28+n:];self.cache={}
  self.matrices={};self.parents={c:i for i,n in enumerate(self.j['nodes']) for c in n.get('children',[])}
 def access(self,index):
  if index in self.cache:return self.cache[index]
  a=self.j['accessors'][index];v=self.j['bufferViews'][a['bufferView']];types={5126:np.float32,5125:np.uint32,5123:np.uint16,5121:np.uint8,5122:np.int16,5120:np.int8};dim={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}[a['type']];dtype=np.dtype(types[a['componentType']]);stride=v.get('byteStride',dim*dtype.itemsize)
  x=np.ndarray((a['count'],dim),dtype=dtype,buffer=self.bin,offset=v.get('byteOffset',0)+a.get('byteOffset',0),strides=(stride,dtype.itemsize))
  if a.get('normalized'):x=x.astype(float)/np.iinfo(dtype).max
  self.cache[index]=x;return x
 def matrix(self,i):
  if i in self.matrices:return self.matrices[i]
  node=self.j['nodes'][i]
  if 'matrix' in node:m=np.array(node['matrix']).reshape(4,4).T
  else:
   q=node.get('rotation',[0,0,0,1]);m=tm.transformations.quaternion_matrix([q[3],*q[:3]]);m[:3,:3]@=np.diag(node.get('scale',[1,1,1]));m[:3,3]=node.get('translation',[0,0,0])
  if i in self.parents:m=self.matrix(self.parents[i])@m
  self.matrices[i]=m;return m

textures={};masks={}
def material_texture(g,material):
 pbr=material.get('pbrMetallicRoughness',{});tx=pbr.get('baseColorTexture')
 if not tx:return np.ones((1,1,4),float)
 image=g.j['images'][g.j['textures'][tx['index']]['source']];key=image.get('uri',str(tx))
 if key not in textures:
  try:textures[key]=np.asarray(Image.open(g.path.parent/key).convert('RGBA').resize((128,128)),float)/255
  except:textures[key]=np.ones((1,1,4),float)
 return textures[key]

def sample(texture,uv):
 h,w=texture.shape[:2];uv=np.mod(uv,1);x=np.minimum((uv[:,0]*w).astype(int),w-1);y=np.minimum((uv[:,1]*h).astype(int),h-1)
 return texture[y,x]

def palette_color(material,texture,uv,family=None):
 name=material.get('name','');pixels=sample(texture,uv);factor=np.array(material.get('pbrMetallicRoughness',{}).get('baseColorFactor',[1,1,1,1]))
 rgb=pixels[:,:3]
 # Architectural palette deliberately drops photo noise but keeps each source
 # material's original region (blue paint, pale plaster, warm sandstone).
 architectural=any(t in name for t in ['plaster','mirage_base','mirage_top','mirage_mid','stonestep','stonewall','brick','ground_tile','tilefloor','dirtfloor','stonefloor','sandfloor'])
 if family=='Ground':
  opaque=texture[texture[:,:,3]>.5,:3];mean=np.median(opaque,axis=0) if len(opaque) else np.array([.72,.61,.43])
  rgb=rgb*.04+mean*.96
 elif architectural:
  opaque=texture[texture[:,:,3]>.5,:3];mean=np.median(opaque,axis=0) if len(opaque) else np.array([.72,.61,.43])
  if 'blue' in name:mean=np.array([.32,.57,.64])
  elif 'salmon' in name:mean=np.array([.77,.48,.38])
  else:mean=mean*.82+np.array([.80,.72,.57])*.18
  rgb=rgb*.12+mean*.88
 else:
  # A small local average retains the yellow rounds and dark metal frames of
  # the actual ammo racks while removing fine scratches and photographic grit.
  mean=texture[:,:,:3].mean(axis=(0,1));rgb=rgb*.80+mean*.20
 levels=64 if family=='Ground' else 24
 rgb=np.clip(np.round(rgb*levels)/levels,0,1)
 rgb=np.where(rgb<=.04045,rgb/12.92,((rgb+.055)/1.055)**2.4)*factor[:3]
 return np.clip(rgb,0,1)

def classify(material,name):
 n=material.get('name','').lower();shader=material.get('extras',{}).get('vmat',{}).get('ShaderName','')
 if n.startswith('tools') or 'blocklight' in name or any(t in n for t in ['wrongway_timer','nav_attribute','postprocessingvolume']):return None
 # Source dust sheets use animated opacity/fresnel masks, but the exporter
 # labels these shader-effect quads as glTF OPAQUE. Never turn them into walls.
 if n=='dust_002' and shader=='csgo_effects.vfx':return None
 if n=='bomb_site_tarp':return 'Canopy'
 if any(t in n for t in ['branches','trees_branches']):return 'Foliage'
 if material.get('alphaMode')=='BLEND':
  if any(t in n for t in ['bombsite','rug','graffiti_noscope','poster','sign_','window_','win_square','win_rectang','flammable','manhole','decalmetal']):return 'Decal'
  if 'glass' in n:return 'Glass'
  return None
 if any(t in n for t in ['ground_tile','tilefloor','dirtfloor','sandfloor','stonefloor','ground','blend_blacktop','tile_mall_floor','woodfloor']):return 'Ground'
 if shader=='csgo_lightmappedgeneric.vfx' or any(t in n for t in ['wall','plaster','mirage_base','mirage_mid','mirage_top','brick_ext','dust_arch','tower','woodsteps','stonestep','woodbeam','sitebwall','window','door','roof_','curbs','stoop','stairs','base_trim']):return 'Architecture'
 if any(t in n for t in ['metal','iron','bomb_tanks','lamp','electri','fence','wires','rail','telephone','cannon','canister','fan']):return 'PropsMetal'
 return 'Props'

def alpha_polygon(texture):
 key=id(texture)
 if key not in masks:
  # Coarse silhouettes are deliberate: broad faceted leaves, not opaque quads.
  mask=np.asarray(Image.fromarray(np.uint8(texture[:,:,3]*255)).resize((20,20)))>110
  polys=[box(x/20,y/20,(x+1)/20,(y+1)/20) for y,x in np.argwhere(mask)]
  masks[key]=unary_union(polys).simplify(.017,preserve_topology=True) if polys else Polygon()
 return masks[key]

def clip_alpha(vertices,faces,uv,texture):
 mask=alpha_polygon(texture);vv=[];ff=[];tt=[]
 for face in faces:
  tex=uv[face];points=vertices[face]
  if tex.max()>1.001 or tex.min()<-.001:
   if sample(texture,np.mean(tex,axis=0)[None,:])[0,3]>.35:
    k=len(vv);vv.extend(points);tt.extend(tex);ff.append([k,k+1,k+2])
   continue
  tri=Polygon(tex)
  if tri.area<1e-8:continue
  clipped=tri.intersection(mask)
  matrix=np.stack([tex[1]-tex[0],tex[2]-tex[0]],axis=1)
  for p in (clipped.geoms if hasattr(clipped,'geoms') else [clipped]):
   if p.geom_type!='Polygon' or p.area<.001:continue
   for t in constrained_delaunay_triangles(p).geoms:
    coords=np.array(list(t.exterior.coords)[:3]);weights=np.linalg.solve(matrix,(coords-tex[0]).T).T
    world=points[0]+weights[:,0,None]*(points[1]-points[0])+weights[:,1,None]*(points[2]-points[0])
    # Keep orientation consistent with the original card.
    if np.dot(np.cross(world[1]-world[0],world[2]-world[0]),np.cross(points[1]-points[0],points[2]-points[0]))<0:world=world[::-1];coords=coords[::-1]
    k=len(vv);vv.extend(world);tt.extend(coords);ff.append([k,k+1,k+2])
 return np.array(vv),np.array(ff,dtype=int),np.array(tt)

def main():
 parser=argparse.ArgumentParser();parser.add_argument('--source',default=str(SOURCE));args=parser.parse_args();g=GLB(args.source);parts=collections.defaultdict(list);manifest=[];excluded_effects=[];skipped=collections.Counter();source_count=0;retained_source_count=0;start=time.time()
 reference=json.loads((OUT/'source_props.json').read_text(encoding='utf-8'))
 disabled_stems={Path(e['model']).stem for e in reference['entities_with_models'] if e.get('startdisabled') is True}
 for ni,node in enumerate(g.j['nodes']):
  if 'mesh' not in node:continue
  if any(node.get('name','').startswith(stem+'.') or node.get('name','')==stem for stem in disabled_stems):
   skipped['disabled_entity_geometry']+=sum(g.j['accessors'][p['indices']]['count']//3 for p in g.j['meshes'][node['mesh']]['primitives']);continue
  m=g.j['meshes'][node['mesh']];matrix=T@g.matrix(ni)
  for pi,pr in enumerate(m['primitives']):
   material=g.j['materials'][pr.get('material',0)];family=classify(material,node.get('name',''))
   faces=g.access(pr['indices']).reshape(-1,3).astype(int);source_count+=len(faces)
   if family is None:
    skipped[material.get('name','')]+=len(faces)
    if material.get('name')=='dust_002' and material.get('extras',{}).get('vmat',{}).get('ShaderName')=='csgo_effects.vfx':
     excluded_effects.append({'node_index':ni,'primitive_index':pi,'material':'dust_002','source_shader':'csgo_effects.vfx','source_triangles':len(faces),'reason':'Animated atmospheric dust sheet with opacity masks, depth feather and no-shadow flag; exporter omitted alphaMode. Not a solid architectural surface.'})
    continue
   # Shared POSITION accessors can contain an entire map's aggregate. Restrict
   # to this primitive's indices before measuring or simplifying any object.
   used,inverse=np.unique(faces,return_inverse=True);vertices=g.access(pr['attributes']['POSITION'])[used].astype(float);faces=inverse.reshape(-1,3)
   vertices=tm.transform_points(vertices,matrix)
   if len(vertices)<3:continue
   uv=g.access(pr['attributes']['TEXCOORD_0'])[used] if 'TEXCOORD_0' in pr['attributes'] else np.zeros((len(vertices),2))
   tex=material_texture(g,material);orig_bounds=np.array([vertices.min(axis=0),vertices.max(axis=0)]);retained_source_count+=len(faces);original_triangles=len(faces)
   alpha_applied=material.get('alphaMode') in ['MASK','BLEND'] and np.min(tex[:,:,3])<.95
   if alpha_applied:
    vertices,faces,uv=clip_alpha(vertices,faces,uv,tex)
    if len(faces)==0:continue
   mesh=tm.Trimesh(vertices=vertices,faces=faces,process=False);mesh.remove_unreferenced_vertices();mesh.merge_vertices(digits_vertex=5)
   original_centers=vertices[faces].mean(axis=1);original_uv=uv[faces].mean(axis=1)
   target=max(16,int(len(faces)*(.28 if family in ['Props','PropsMetal'] else .4 if family=='Foliage' else .65)))
   if len(faces)>100 and family=='Foliage':
    try:
     simplified=mesh.simplify_quadric_decimation(face_count=target,aggression=5)
     # Geometry cannot lose a visible object or move beyond its source bounds.
     if len(simplified.faces)>0 and np.all(simplified.bounds[0]>=orig_bounds[0]-.08) and np.all(simplified.bounds[1]<=orig_bounds[1]+.08):mesh=simplified
    except Exception:pass
   nearest=cKDTree(original_centers).query(mesh.triangles_center)[1]
   rgb=palette_color(material,tex,original_uv[nearest],family)
   if family=='Foliage':
    rgb=rgb*.35+np.array([.13,.23,.075])*.65
   # Deterministic modest per-facet shading, not raised triangular terrain.
   rgb*=RNG.uniform(.98,1.02,(len(rgb),1))
   if family=='Decal':mesh.vertices+=mesh.vertex_normals*.008
   baked=tm.Trimesh(vertices=mesh.vertices[mesh.faces].reshape(-1,3),faces=np.arange(len(mesh.faces)*3).reshape(-1,3),process=False)
   rgba=np.uint8(np.c_[np.clip(rgb,0,1),np.ones(len(rgb))]*255);baked.visual.vertex_colors=np.repeat(rgba,3,axis=0)
   # Spatial chunks avoid forcing the full scene through the GPU every frame.
   center=orig_bounds.mean(axis=0);cx=int(math.floor(center[0]/24));cz=int(math.floor(center[2]/24));group=f'{family}_{cx}_{cz}'
   parts[group].append(baked)
   manifest.append({'node_index':ni,'primitive_index':pi,'alpha_silhouette_applied':bool(alpha_applied),'output_bounds':np.round(baked.bounds,6).tolist(),'node':node.get('name',''),'material':material.get('name',''),'group':family,'source_triangles':original_triangles,'triangles':len(baked.faces),'bounds':np.round(orig_bounds,4).tolist()})
  if ni%500==0:print('nodes',ni,'of',len(g.j['nodes']),'elapsed',round(time.time()-start,1),flush=True)
 scene=tm.Scene()
 for group,items in parts.items():
  merged=tm.util.concatenate(items);family=group.split('_')[0]
  merged.visual.material=tm.visual.material.PBRMaterial(name=group,baseColorFactor=[255,255,255,255],metallicFactor=.45 if family=='PropsMetal' else 0,roughnessFactor=.88,doubleSided=True)
  scene.add_geometry(merged,geom_name=group,node_name=group)
 write(OUT/'source_environment.glb',scene.export(file_type='glb',include_normals=True))
 report={'source':str(g.path),'source_mesh_triangles':source_count,'retained_source_triangles':retained_source_count,'output_triangles':sum(x['triangles'] for x in manifest),'mesh_groups':len(parts),'objects':manifest,'omitted_nonvisible_or_surface_decals':dict(skipped),'excluded_shader_effects':excluded_effects,'transform':T.tolist(),'textures_in_runtime':0}
 write(OUT/'source_geometry_manifest.json',json.dumps(report,ensure_ascii=False,separators=(',',':')))
 print('COMPLETE', {k:v for k,v in report.items() if k not in ['objects','omitted_nonvisible_or_surface_decals']},'elapsed',round(time.time()-start,1))
if __name__=='__main__':main()
