"""Bake measured full-world collision and original-NAV gameplay metadata.
No architecture or obstacle is inferred from the edges of a navigation polygon.
"""
from pathlib import Path
import json,math,collections
import numpy as np
import trimesh as tm
from shapely.geometry import Polygon,Point
from shapely.ops import unary_union
from shapely import contains_xy
from shapely.strtree import STRtree
from scipy.spatial import cKDTree
from build_source_map import GLB,T,write,ROOT,OUT,SOURCE_DIR
TMP=SOURCE_DIR

def main():
 reference=json.loads((OUT/'source_props.json').read_text(encoding='utf-8'));chunks=collections.defaultdict(list);counts=collections.Counter();excluded=[]
 for filename,records in [('world_solidphysics_physics.glb',reference['world_physics']),('source_world_physics.glb',reference['entity_physics'])]:
  g=GLB(TMP/filename);lookup={r['node_index']:r for r in records}
  for ni,node in enumerate(g.j['nodes']):
   if 'mesh' not in node:continue
   info=lookup[ni];policy=info.get('collision_policy',{});role=policy.get('role','')
   if filename=='source_world_physics.glb':
    # Respect the original entity state. Retake barriers are exported as meshes
    # but start disabled; Never Solid brushes remain visible without collision.
    translation=(T@g.matrix(ni))[:3,3]
    candidates=[e for e in reference['entities_with_models'] if node.get('name','').startswith(e['classname'])]
    if candidates:
     entity=min(candidates,key=lambda e:np.linalg.norm(np.array(e['position_godot'])-translation))
     error=np.linalg.norm(np.array(entity['position_godot'])-translation)
     reason='startdisabled' if entity.get('startdisabled') is True else ('BRUSHSOLID_NEVER' if entity['classname']=='func_brush' and str(entity.get('solidity'))=='1' else ('SOLID_NONE' if entity['classname'].startswith('prop_') and str(entity.get('solid'))=='0' else ''))
     if error<.0001 and reason:
      excluded.append({'node':ni,'name':node.get('name'),'entity_index':entity['entity_index'],'reason':reason});continue

   if filename=='source_world_physics.glb' and any(node.get('name','').startswith(n) for n in ['func_bomb_target','func_buyzone','env_cs_place','post_processing_volume','func_nav_markup']):excluded.append(node.get('name'));continue
   if not policy.get('movement',True):
    if not policy.get('grenades',False):excluded.append(node.get('name'));continue
    layer=8
   else:layer=1 if policy.get('bullets',True) else 4
   matrix=T@g.matrix(ni)
   for pr in g.j['meshes'][node['mesh']]['primitives']:
    f=g.access(pr['indices']).reshape(-1,3).astype(int);v=g.access(pr['attributes']['POSITION']).astype(float);tri=tm_transform(v[f].reshape(-1,3),matrix).reshape(-1,3,3)
    valid=np.linalg.norm(np.cross(tri[:,1]-tri[:,0],tri[:,2]-tri[:,0]),axis=1)>1e-8;tri=tri[valid][:,[0,2,1]] # Godot triangle collision uses clockwise faces, glTF uses CCW.
    centers=tri.mean(axis=1);keys=np.floor(centers[:,[0,2]]/16).astype(int)
    for key in np.unique(keys,axis=0):
     group=tri[np.all(keys==key,axis=1)];chunks[(layer,int(key[0]),int(key[1]))].append(group)
    counts[role or node.get('name','')]+=len(tri)
 # Native triangle colliders preserve crates, arches, stairs and doors exactly.
 lines=['[gd_scene load_steps=%d format=3]'%(len(chunks)+2),'','[ext_resource type="PackedScene" path="res://assets/map/source_environment.glb" id="1"]','']
 chunk_list=[]
 for i,(key,items) in enumerate(sorted(chunks.items())):
  tri=np.concatenate(items);layer,cx,cz=key;center=np.array([cx*16+8,0,cz*16+8]);local=tri-center
  lines.extend([f'[sub_resource type="ConcavePolygonShape3D" id="Collision{i}"]','data = PackedVector3Array('+', '.join(format(float(v),'.5f') for v in local.reshape(-1))+')','backface_collision = false',''])
  chunk_list.append({'layer':layer,'position':center.tolist(),'triangles':len(tri)})
 lines.extend(['[node name="MirageBaked" type="Node3D"]','','[node name="SourceGeometry" parent="." instance=ExtResource("1")]',''])
 for i,c in enumerate(chunk_list):
  lines.extend([f'[node name="WorldCollision{i}" type="StaticBody3D" parent="."]','position = Vector3('+', '.join(str(x) for x in c['position'])+')','collision_layer = '+str(c['layer']),'collision_mask = 0','',f'[node name="Shape" type="CollisionShape3D" parent="WorldCollision{i}"]',f'shape = SubResource("Collision{i}")',''])
 write(OUT/'mirage_baked.tscn','\n'.join(lines))
 report={'source_world_groups':len(reference['world_physics']),'source_entity_groups':len(reference['entity_physics']),'triangles':sum(c['triangles'] for c in chunk_list),'chunks':chunk_list,'surface_roles':dict(counts),'excluded_triggers':excluded,'layers':{'1':'physical world, bullets and vision','4':'playerclip / passbullets movement only','8':'grenadeclip only'}}
 write(OUT/'collision_manifest.json',json.dumps(report,separators=(',',':')))
 # Build navigation only from original measured NAV triangles, with no invented
 # boxes, no wall-boundary subtraction and no flattening of upper/lower layers.
 measurement=json.loads((OUT/'measurements.json').read_text());tri=np.array(measurement['nav_triangles']);polys=[Polygon(t[:,[0,2]]) for t in tri];tree=STRtree(polys)
 footprint=unary_union([p for p in polys if p.area>1e-7]).buffer(.07,join_style=2)
 origin=np.array([-54.,-48.]);cell=.5;gw,gh=224,194;xs=np.arange(gw)*cell+origin[0]+cell/2;zs=np.arange(gh)*cell+origin[1]+cell/2;xx,zz=np.meshgrid(xs,zs);inside=contains_xy(footprint,xx,zz)
 nodes=[];cell_nodes={}
 for gz,gx in np.argwhere(inside):
  x,z=xs[gx],zs[gz];ids=tree.query(Point(x,z),predicate='intersects');ys=[]
  for i in ids:
   t=tri[i];a=t[0,[0,2]];mat=np.stack([t[1,[0,2]]-a,t[2,[0,2]]-a],axis=1)
   if abs(np.linalg.det(mat))<1e-8:continue
   uv=np.linalg.solve(mat,np.array([x,z])-a);y=t[0,1]+uv[0]*(t[1,1]-t[0,1])+uv[1]*(t[2,1]-t[0,1])
   if not any(abs(y-existing)<.12 for existing in ys):ys.append(float(y))
  if not ys:inside[gz,gx]=False;continue
  for y in sorted(ys):
   idx=len(nodes);nodes.append([round(x,4),round(y,4),round(z,4)]);cell_nodes.setdefault((int(gx),int(gz)),[]).append(idx)
 # Navigation polygons alone do not encode a standing capsule's clearance or
 # every adjacency restriction. Reject nodes and edges using the source's
 # actual collision triangles, rather than subtracting guessed 2-D boxes.
 solid_tri=np.concatenate([np.concatenate(items) for key,items in chunks.items() if key[0] in [1,4]])
 collision_mesh=tm.Trimesh(vertices=solid_tri.reshape(-1,3),faces=np.arange(len(solid_tri)*3).reshape(-1,3),process=False)
 collision_mesh.merge_vertices(digits_vertex=5)
 def clear_at(points,radius=.325):
  points=np.asarray(points,float);result=np.ones(len(points),bool)
  for offset in [.83,1.28]:
   for start in range(0,len(points),600):
    query=points[start:start+600]+np.array([0,offset,0])
    _,distance,_=tm.proximity.closest_point(collision_mesh,query)
    result[start:start+600]&=distance>radius
  return result
 node_clear=clear_at(nodes)
 for key in list(cell_nodes):
  cell_nodes[key]=[i for i in cell_nodes[key] if node_clear[i]]
  if not cell_nodes[key]:del cell_nodes[key]
 print('capsule-clear nodes',int(node_clear.sum()),'of',len(nodes),flush=True)
 edges=[]
 for (gx,gz),ids in cell_nodes.items():
  for dx,dz in [(1,0),(0,1),(1,1),(-1,1)]:
   if dx and dz and ((gx+dx,gz) not in cell_nodes or (gx,gz+dz) not in cell_nodes):continue
   for i in ids:
    for j in cell_nodes.get((gx+dx,gz+dz),[]):
     if abs(nodes[i][1]-nodes[j][1])<=(.46 if not(dx and dz) else .60):edges.append([i,j])
 edge_centers=[(np.array(nodes[i])+nodes[j])/2 for i,j in edges]
 edge_clear=clear_at(edge_centers,.325)
 edges=[edge for edge,ok in zip(edges,edge_clear) if ok]
 # Remove blocked lattice vertices, renumber graph IDs, preserve stacked Y.
 used=sorted({i for edge in edges for i in edge});mapping={old:new for new,old in enumerate(used)}
 nodes=[nodes[i] for i in used];edges=[[mapping[i],mapping[j]] for i,j in edges]
 inside[:]=False
 for x,y,z in nodes:
  gx=int((x-origin[0])/cell);gz=int((z-origin[1])/cell);inside[gz,gx]=True
 print('capsule-clear edges',len(edges),flush=True)
 nav={'nodes':nodes,'edges':edges,'triangles':measurement['nav_triangles']};write(OUT/'navigation.json',json.dumps(nav,separators=(',',':')))
 data=json.loads((OUT/'map_data.json').read_text(encoding='utf-8'));data['grid']={'origin':origin.tolist(),'cell':cell,'width':gw,'height':gh,'rows':[''.join('1' if v else '0' for v in row) for row in inside]};data['blockers']=[];data['labels']=[];data['spawn_points']={};data['site_regions']={}
 for team,points in reference['player_spawns'].items():
  data['spawn_points'][team]=[[p['position_godot'][0],p['position_godot'][1]+.08,p['position_godot'][2]] for p in points]
  data['spawns'][team]=data['spawn_points'][team][0]
 for site,region in reference['bombsite_regions'].items():
  print('site_regionkeys',site,list(region),flush=True)
  shape=region['region']
  mn=shape.get('bounds_min_godot');mx=shape.get('bounds_max_godot')
  if mn is None:
   records=reference['entity_physics'];shape=records[0 if site=='A' else 1];mn=shape['bounds_min_godot'];mx=shape['bounds_max_godot']
  data['site_regions'][site]={'min':mn,'max':mx,'polygon_xz':shape.get('polygon_xz',[[mn[0],mn[2]],[mx[0],mn[2]],[mx[0],mx[2]],[mn[0],mx[2]]])}
  data['sites'][site]=[(mn[0]+mx[0])/2,mn[1]+.1,(mn[2]+mx[2])/2]
 data['manifest']={'source':'Complete CS2 Source2Viewer world render+worldphysics, faithful indexed geometry transforms','visual_triangles':json.loads((OUT/'source_geometry_manifest.json').read_text())['output_triangles'],'physics_triangles':report['triangles'],'navigation_nodes':len(nodes),'navigation_edges':len(edges),'obstacles':'actual source collision; no inferred NAV-boundary walls'}
 write(OUT/'map_data.json',json.dumps(data,ensure_ascii=False,separators=(',',':')))
 print('COMPLETE',data['manifest'],'collider_chunks',len(chunk_list))

def tm_transform(vertices,m):return vertices@m[:3,:3].T+m[:3,3]
if __name__=='__main__':main()
