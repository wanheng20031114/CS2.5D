"""Build an original, faceted Mirage interpretation from measured navigation outlines.
The first build can read a locally exported Valve navigation mesh. Further builds
need only assets/map/measurements.json. No Valve model or texture is packaged.
"""
from pathlib import Path
import argparse, json, math, re
from collections import defaultdict
import numpy as np
import trimesh as tm
from shapely import constrained_delaunay_triangles, contains_xy
from shapely.geometry import Polygon, Point, box, LineString
from shapely.ops import unary_union
ROOT=Path(__file__).resolve().parents[1]; OUT=ROOT/'assets/map';OUT.mkdir(parents=True,exist_ok=True)
rng=np.random.default_rng(76124)
C={'sand':(199,165,114),'paving':(213,190,147),'plaster':(224,197,151),'plaster2':(205,170,123),'stone':(169,137,94),'trim':(242,217,172),'blue':(97,158,173),'blue_dark':(52,104,126),'wood':(116,76,43),'wood_light':(159,111,62),'iron':(64,72,71),'metal':(105,119,116),'leaf':(101,130,64),'leaf_light':(138,151,74),'bark':(143,113,68),'glass':(48,81,87),'rust':(161,80,54),'canvas':(187,156,104),'white':(220,211,183),'mark':(189,69,40),'tile':(171,107,78)}
parts=defaultdict(list); blockers=[];labels=[];count=defaultdict(int)
height_tree=None
height_triangles=None
height_centers=None
height_kdtree=None
apply_height=True
height_override=None

def aligned(fn):
 def wrapped(x,z,*args,**kwargs):
  global height_override
  previous=height_override;r=2.6 if fn.__name__=="van" else .35
  height_override=min(ground(x+dx,z+dz) for dx,dz in [(-r,0),(r,0),(0,-r),(0,r)])
  try:return fn(x,z,*args,**kwargs)
  finally:height_override=previous
 return wrapped

def base_height(x,z):
 return height_override if height_override is not None else ground(x,z)

def init_height(data):
 global height_tree,height_triangles,height_centers,height_kdtree
 from shapely.strtree import STRtree
 from scipy.spatial import cKDTree
 height_triangles=np.array(data['nav_triangles'],float)
 height_tree=STRtree([Polygon(t[:,[0,2]]) for t in height_triangles])
 height_centers=height_triangles.mean(axis=1)
 height_kdtree=cKDTree(height_centers[:,[0,2]])

def heights(x,z):
 if height_tree is None:return [0.]
 q=Point(x,z);idx=height_tree.query(q,predicate='intersects');ys=[]
 for i in idx:
  t=height_triangles[i];a=t[0,[0,2]];v=t[1,[0,2]]-a;w=t[2,[0,2]]-a;d=np.linalg.det(np.stack([v,w],axis=1))
  if abs(d)<1e-8:continue
  uv=np.linalg.solve(np.stack([v,w],axis=1),np.array([x,z])-a)
  y=t[0,1]+uv[0]*(t[1,1]-t[0,1])+uv[1]*(t[2,1]-t[0,1])
  if not any(abs(y-existing)<.12 for existing in ys):ys.append(float(y))
 return sorted(ys)

def ground(x,z):
 ys=heights(x,z)
 if ys:return max(ys)
 if height_kdtree is None:return 0.
 _,i=height_kdtree.query([x,z]);return float(height_centers[i,1])

def write_text_atomic(path,text,encoding='utf-8'):
 path=Path(path);temporary=path.with_suffix(path.suffix+'.tmp')
 temporary.write_text(text,encoding=encoding);temporary.replace(path)

def rgba(col,variation=0):
 c=np.clip(np.array(C.get(col,col))/255*(1+variation),0,1);c=np.where(c<=.04045,c/12.92,((c+.055)/1.055)**2.4)
 return np.uint8(np.r_[c,1]*255)
def mesh_add(m,col,family=None):
 if apply_height and height_tree is not None:
  center=m.bounds.mean(axis=0);m.apply_translation([0,base_height(center[0],center[2]),0])
 family=family or ('Metal' if col in ['iron','metal'] else 'Foliage' if col.startswith('leaf') else 'Surface')
 # Unshared vertices preserve face normals and painterly facets in GLB.
 m=tm.Trimesh(vertices=m.vertices[m.faces].reshape(-1,3),faces=np.arange(len(m.faces)*3).reshape(-1,3),process=False)
 colors=np.array([rgba(col,rng.uniform(-.035,.035)) for _ in m.faces]);m.visual.vertex_colors=np.repeat(colors,3,axis=0)
 parts[family].append(m);return m

def block(p,s,col='plaster',rot=0,bevel=.035,family=None):
 s=np.array(s,float);p=np.array(p,float);b=min(bevel,float(s.min())*.24)
 if b>0:
  verts=[]
  for i in range(3):
   for a in [-1,1]:
    for j in [-1,1]:
     for k in [-1,1]:
      v=np.array([j*(s[0]/2-b),k*(s[1]/2-b),a*(s[2]/2-b)])
      # cuboid bevel through all axis permutations
  v=[]
  for a in [-1,1]:
   for bsign in [-1,1]:
    for c in [-1,1]:
     for axis in range(3):
      q=np.array([a,bsign,c])*(s/2-b);q[axis]=np.array([a,bsign,c])[axis]*s[axis]/2;v.append(q)
  m=tm.convex.convex_hull(np.array(v))
 else:m=tm.creation.box(extents=s)
 m.apply_transform(tm.transformations.rotation_matrix(rot,[0,1,0]));m.apply_translation(p);mesh_add(m,col,family);return m

def cylinder(p,r,h,col='iron',n=10,axis=(0,1,0),r2=None):
 if r2 is None:m=tm.creation.cylinder(radius=r,height=h,sections=n)
 else:
  vv=[]
  for y,rad in [(-h/2,r),(h/2,r2)]:
   vv.extend([[math.cos(i*math.tau/n)*rad,math.sin(i*math.tau/n)*rad,y] for i in range(n)])
  m=tm.convex.convex_hull(vv)
 m.apply_transform(tm.geometry.align_vectors([0,0,1],axis));m.apply_translation(p);mesh_add(m,col)

def beam(a,b,width,col):
 a=np.array(a);b=np.array(b);m=tm.creation.box(extents=[width,width,np.linalg.norm(b-a)]);m.apply_transform(tm.geometry.align_vectors([0,0,1],b-a));m.apply_translation((a+b)/2);mesh_add(m,col)

def polygon_mesh(poly,y,col,depth=0):
 verts=[];faces=[]
 for t in constrained_delaunay_triangles(poly).geoms:
  coords=list(t.exterior.coords)[:3];idx=len(verts);points=[(x,y,z) for x,z in coords];verts.extend(points);face=[idx,idx+1,idx+2]
  if np.cross(np.array(points[1])-points[0],np.array(points[2])-points[0])[1]<0:face.reverse()
  faces.append(face)
 if depth:
  for ring in [poly.exterior,*poly.interiors]:
   q=list(ring.coords)
   for a,b in zip(q,q[1:]):
    idx=len(verts);verts.extend([(a[0],y-depth,a[1]),(b[0],y-depth,b[1]),(b[0],y,b[1]),(a[0],y,a[1])]);faces.extend([[idx,idx+1,idx+2],[idx,idx+2,idx+3]])
 mesh_add(tm.Trimesh(vertices=verts,faces=faces,process=False),col)

def solid(p,s,rot=0,kind='wall'):
 p=list(p);p[1]+=base_height(p[0],p[2])
 blockers.append({'position':[round(float(v),4) for v in p],'size':[round(float(v),4) for v in s],'rotation':round(float(rot),5),'kind':kind})

@aligned
def crate(x,z,w=1.5,h=1.4,d=1.3,y=0,rot=0,collide=True):
 count['crates']+=1
 block((x,y+h/2,z),(w,h,d),'wood',rot,.055)
 # Slats, banding and diagonal braces are geometry, never textures.
 for yy in [.12,h-.12]:block((x,y+yy,z),(w+.045,.13,d+.045),'wood_light',rot,.015)
 for xx in [-w*.34,w*.34]:
  dx=xx*math.cos(rot);dz=-xx*math.sin(rot);block((x+dx,y+h/2,z+dz),(.11,h+.06,d+.09),'iron',rot,.01)
 for j in range(1,int(w/.24)):
  xx=-w/2+j*.24;dx=xx*math.cos(rot);dz=-xx*math.sin(rot)
  block((x+dx,y+h/2,z+dz),(.016,h-.25,d+.012),'wood_light',rot,0)
 if collide:solid((x,y+h/2,z),(w,h,d),rot,'crate')

@aligned
def barrel(x,z,col='blue_dark',y=0):
 count['barrels']+=1;cylinder((x,y+.55,z),.38,1.1,col,12)
 for yy in [.12,.55,1.02]:cylinder((x,y+yy,z),.393,.055,'iron',12)
 solid((x,y+.55,z),(.8,1.1,.8),0,'barrel')

@aligned
def palm(x,z,height=7):
 count['palms']+=1
 for j in range(6):cylinder((x+j*.055,(j+.5)*height/6,z),.22-j*.018,height/6+.08,'bark',8,r2=.20-j*.018)
 top=np.array([x+.3,height,z])
 for i in range(9):
  angle=i*math.tau/9+rng.uniform(-.2,.2);direction=np.array([math.cos(angle),0,math.sin(angle)]);side=np.array([-direction[2],0,direction[0]])
  length=rng.uniform(2.7,3.8);vv=[top,top+direction*length*.5+np.array([0,.65,0])+side*.55,top+direction*length-np.array([0,.8,0]),top+direction*length*.5+np.array([0,.65,0])-side*.55,top+direction*length*.53+np.array([0,.85,0])]
  mesh_add(tm.Trimesh(vertices=vv,faces=[[0,1,4],[1,2,4],[2,3,4],[3,0,4]],process=False),'leaf_light' if i%3==0 else 'leaf')
 solid((x,height*.5,z),(.5,height,.5),0,'palm')

def window(x,z,y,angle,blue=True):
 # Angle is wall tangent yaw. Offset face surfaces avoid z-fighting.
 block((x,y,z),(1.06,1.55,.11),'trim',angle,.045)
 normal=np.array([math.sin(angle),0,math.cos(angle)])
 p=np.array([x,y,z])+normal*.08;block(p,(.85,1.30,.12),'blue_dark' if blue else 'wood',angle,.018)
 for dx in [-.26,0,.26]:
  offset=np.array([math.cos(angle)*dx,0,-math.sin(angle)*dx]);block(p+offset+normal*.065,(.055,1.24,.04),'blue' if blue else 'wood_light',angle,.006)

def arch(x,z,width=3.0,height=3.0,angle=0):
 # Open gateway is clear below 2.25 m; its collision stays on its side piers.
 count['arches']+=1
 def world(xx,yy,zz=0):return (x+xx*math.cos(angle)+zz*math.sin(angle),yy,z-xx*math.sin(angle)+zz*math.cos(angle))
 for side in [-1,1]:
  p=world(side*(width/2+.18),(height-.6)/2);block(p,(.38,height-.6,.64),'trim',angle,.045);solid(p,(.38,height-.6,.64),angle,'arch')
 for i in range(11):
  t=math.pi*i/10;xx=math.cos(t)*(width/2+.2);yy=height-.65+math.sin(t)*width*.36
  block(world(xx,yy),(.44,.34,.66),'trim',angle,.055)

def rug(x,z,w=2.8,d=4,rot=0):
 block((x,.025,z),(w,.028,d),'rust',rot,0)
 for dx in [-w*.43,w*.43]:block((x+dx*math.cos(rot),.044,z-dx*math.sin(rot)),(.11,.011,d*.92),'canvas',rot,0)
 for zz in [-d*.42,d*.42]:block((x+zz*math.sin(rot),.045,z+zz*math.cos(rot)),(w*.9,.011,.12),'canvas',rot,0)
 for j in range(-2,3):block((x,.048,z+j*.46),(.45,.012,.45),'canvas',math.pi/4,0)

@aligned
def van(x,z):
 count['vehicles']+=1
 block((x,1.0,z),(2.15,1.5,4.55),'white',0,.18);block((x,1.7,z+.9),(2.1,.95,2.55),'white',0,.16)
 block((x,1.62,z-1.18),(1.85,.6,.09),'glass',0,.025)
 for xx in [-1.10,1.10]:
  for zz in [-1.42,1.4]:
   cylinder((x+xx,.50,z+zz),.46,.22,'iron',12,axis=(1,0,0));cylinder((x+xx*1.035,.50,z+zz),.21,.25,'metal',10,axis=(1,0,0))
  block((x+xx*.98,1.67,z-.5),(.06,.52,.82),'glass',0,.025)
 for xx in [-.72,.72]:block((x+xx,.84,z-2.30),(.39,.28,.09),'trim',0,.025)
 block((x,.48,z-2.33),(2.25,.19,.15),'iron',0,.025);solid((x,1.2,z),(2.35,2.4,4.8),0,'van')

@aligned
def bench(x,z,angle=0):
 count['benches']+=1
 block((x,.56,z),(2.1,.16,.65),'wood',angle,.045)
 block((x,1.0,z+.27),(2.1,.66,.13),'wood_light',angle,.035)
 for xx in [-.78,.78]:block((x+xx,.3,z),(.16,.6,.62),'iron',angle,.015)
 solid((x,.62,z),(2.15,1.24,.78),angle,'bench')

def source_measurements(nav):
 s=tm.load(nav);m=s.geometry['navmesh_hull_0'];v=m.vertices;points=np.stack([(v[:,0]+670)*.0254,(-v[:,1]-847)*.0254],axis=1)
 tris=[Polygon(points[f]) for f in m.faces];floor=unary_union(tris).buffer(.45,join_style=2).buffer(-.22,join_style=2).simplify(.16,preserve_topology=True)
 # Retain the main connected walkable footprint; isolated nav dots are unused ledges.
 polys=sorted(floor.geoms if hasattr(floor,'geoms') else [floor],key=lambda x:x.area,reverse=True)
 floor=polys[0]
 data={'source':'Locally installed Counter-Strike 2 build 25218825; de_mirage.nav measured via Source2Viewer CLI 20.0','scale_m_per_source_unit':.0254,'source_origin':[-670,-847],'exterior':list(floor.exterior.coords),'holes':[list(p.coords) for p in floor.interiors if Polygon(p).area>1.3],'nav_triangles':np.stack([(v[m.faces,0]+670)*.0254,(v[m.faces,2]+256)*.0254,(-v[m.faces,1]-847)*.0254],axis=2).round(5).tolist(),'source_floor_y_m_range':[float(v[:,2].min()*.0254),float(v[:,2].max()*.0254)],'lighting':{'sun_color':[255,223,179],'sky_color':[130,205,255],'brightness':3,'source_angles':[60,318,0]}}
 write_text_atomic(OUT/'measurements.json',json.dumps(data,separators=(',',':')))
 return data

def main():
 global apply_height
 parser=argparse.ArgumentParser();parser.add_argument('--nav');args=parser.parse_args()
 data=source_measurements(args.nav) if args.nav else json.loads((OUT/'measurements.json').read_text())
 init_height(data)
 floor=Polygon(data['exterior'],data['holes']);floor=floor.buffer(0)
 # Fill tiny navigational gaps and recreate meaningful boxes using readable silhouettes.
 large_holes=[h for h in floor.interiors if Polygon(h).area>5]
 floor=Polygon(floor.exterior.coords,[h.coords for h in large_holes])
 apply_height=False
 # Seal narrow nav-clearance margins and discarded small prop holes with
 # fitted terrain, while retaining every original sloped/stacked nav triangle.
 raw=np.array(data['nav_triangles'])
 footprint=unary_union([Polygon(t[:,[0,2]]) for t in raw if Polygon(t[:,[0,2]]).area>.0001])
 gaps=floor.difference(footprint)
 gap_tri=[]
 for poly in (gaps.geoms if hasattr(gaps,'geoms') else [gaps]):
  if poly.geom_type!='Polygon' or poly.area<.00001:continue
  for t in constrained_delaunay_triangles(poly).geoms:
   coords=list(t.exterior.coords)[:3];values=[ground(x,z) for x,z in coords]
   # Clearance fills beside a cover top must stay on the lower ground, not turn
   # the obstacle into an artificial sand pyramid.
   if max(values)-min(values)>.48:values=[min(values)]*3
   vv=np.array([[x,y,z] for (x,z),y in zip(coords,values)])
   if np.cross(vv[1]-vv[0],vv[2]-vv[0])[1]<0:vv=vv[::-1]
   gap_tri.append(vv)
 terrain_triangles=np.concatenate([raw,np.array(gap_tri)]) if gap_tri else raw
 nv=terrain_triangles.reshape(-1,3)
 mesh_add(tm.Trimesh(vertices=nv,faces=np.arange(len(nv)).reshape(-1,3),process=False),'paving','Ground')
 apply_height=True
 # Earth plinth establishes a warm diorama silhouette.
 expanded=Polygon(floor.exterior.coords).buffer(3,join_style=2).simplify(.8)
 apply_height=False
 polygon_mesh(expanded,-3.25,'sand',1.6)
 apply_height=True
 # Buildings share the measured footprint. Tall masses and cutaway perimeter walls
 # keep the original lanes legible from the orthographic camera.
 for index,ring in enumerate([floor.exterior,*floor.interiors]):
  shape=Polygon(ring);interior=index>0;area=shape.area
  if interior and area>80:
   h=3.2 if shape.centroid.x<0 else 4.6
   col='blue' if shape.centroid.x<0 and shape.centroid.y<18 else 'plaster'
   polygon_mesh(shape,h,col,h)
   # Recessed rooftop, parapets and roof services are wholly original geometry.
   roof=shape.buffer(-.35)
   if not roof.is_empty and roof.geom_type=='Polygon':polygon_mesh(roof,h+.035,'sand')
   rp=shape.representative_point();cx,cz=rp.x,rp.y
   cylinder((cx,h+.95,cz),.82,1.8,'white',12)
   for y in [h+.2,h+1.65]:cylinder((cx,y,cz),.84,.08,'stone',12)
   beam((cx+1.4,h,cz),(cx+1.4,h+2.8,cz),.055,'iron')
   for yy in [1.9,2.45]:beam((cx+.5,h+yy,cz),(cx+2.3,h+yy,cz),.035,'iron')
  else:
   h=1.55 if interior and area<25 else 2.65 if interior else 3.0;col='wood' if interior and area<25 else 'plaster2' if interior else 'plaster'
   if interior:polygon_mesh(shape,h,col,h)
  coords=list(ring.coords)
  for a,b in zip(coords,coords[1:]):
   a=np.array(a);b=np.array(b);delta=b-a;length=np.linalg.norm(delta)
   if length<.12:continue
   normal=np.array([-delta[1],delta[0]])/length
   midpoint=(a+b)/2
   if floor.contains(Point(*(midpoint+normal*.12))):normal=-normal
   a=a+normal*.30;b=b+normal*.30
   x,z=(a+b)/2;angle=-math.atan2(delta[1],delta[0]);wallh=h
   if interior and area<25:wallh=1.55;col='wood'
   block((x,wallh/2,z),(length+.075,wallh,.32),col,angle,.04)
   solid((x,wallh/2,z),(length+.07,wallh,.32),angle,'wall')
   block((x,wallh+.055,z),(length+.13,.18,.48),'trim' if col!='wood' else 'wood_light',angle,.035)
   if length>3.6:
    block((x,.28,z),(length+.07,.34,.39),'stone',angle,.025)
    for t in np.arange(1.8,length-1.1,3.5):
     q=a+delta*(t/length);normal=np.array([-delta[1],delta[0]])/length
     # Both sides of boundary carry recesses, so no viewpoint sees blank cubes.
     for side in [-1,1]:window(q[0]+normal[0]*.19,q[1]+normal[1]*.19,1.9,angle if side>0 else angle+math.pi,col=='blue')
   if length>7 and not interior:
    for t in np.arange(0,length,4):
     q=a+delta*(t/length);block((q[0],1.53,q[1]),(.5,3.12,.55),'plaster2',angle,.05)
 # Major bomb-site cover, authored from the familiar A triple/default and B stacks.
 for pos in [(4.6,32.4,1.5,1.5,1.5),(6.2,32.4,1.5,1.5,1.5),(4.6,32.4,1.5,1.35,1.5,1.5),(1.0,28.2,1.4,1.4,1.4),(2.6,27.8,1.4,1.4,1.4),(1.0,28.2,1.4,1.3,1.4,1.4),(-3.8,38.2,1.5,1.5,1.5),(-2.0,38.2,1.5,1.5,1.5),(12.6,36.9,1.2,1.3,1.2),(15.0,31.0,1.4,1.4,1.4),(-37.3,-30.1,1.5,1.5,1.5),(-35.7,-30.1,1.5,1.5,1.5),(-37.3,-30.1,1.5,1.3,1.5,1.5),(-31.9,-24.8,1.5,1.5,1.5),(-31.9,-24.8,1.5,1.3,1.5,1.5),(13.4,-3.9,1.6,1.3,1.5),(15.3,-3.8,1.6,1.3,1.5),(13.4,-3.9,1.6,1.3,1.5,1.3)]:crate(*pos)
 van(-41.5,-38.1);bench(-48.3,-27.6,math.pi/2)
 for x,z in [(-35,-18),(-34.1,-18),(42,-36),(42.8,-35.7),(47,-15),(-28,32),(26,32)]:barrel(x,z)
 for x,z,h in [(-45,-41,7.4),(-50,-32,7.8),(-32,-46,8),(30,40,8.8),(12,45,7.8),(-34,25,8),(57,-22,8.5),(25,-45,8.3)]:palm(x,z,h)
 for p in [(-23,-33,3,3,math.pi/2),(-14,-18,3,3,0),(0.4,14,3.2,3.0,0),(24,19,3.2,3.1,0),(-19,12,2.5,3.0,0),(-40,-13,3,3,0),(39,25,2.8,3.1,0)]:arch(*p)
 for x,z,w,d in [(-28,-39,3,3),(-2,-40,4,2.7),(34,33,3.3,4),(30,34,2.8,4),(-35,-11,3,2)]:rug(x,z,w,d)
 # Palace columns, B awning, market counters and individual supply silhouettes.
 for x in [28.5,33.2,37.7]:
  cylinder((x,1.5,34),.33,3,'trim',10);cylinder((x,.16,34),.5,.3,'stone',10);cylinder((x,2.85,34),.5,.3,'trim',10)
  solid((x,1.5,34),(.78,3,.78),0,'column')
 block((-36,3.0,-27.3),(6.5,.18,6.2),'canvas',0,.04)
 for x in [-39.1,-32.9]:
  for z in [-30.2,-24.4]:block((x,1.48,z),(.13,2.96,.13),'iron',0,.015)
 for x,z in [(-38,-8.6),(-34,-8.6)]:
  block((x,.66,z),(2.6,1.3,.9),'blue',0,.045);block((x,1.36,z),(2.8,.13,1.12),'wood_light',0,.03);solid((x,.7,z),(2.7,1.4,1.0),0,'counter')
  for j in range(4):cylinder((x-.85+j*.52,1.60,z),.17,.37,'rust',8,r2=.22)
 # Thin shallow step strips preserve ramp/underpass cues without hidden collisions.
 for cx,cz,w,d,ang in [(3,-7,7,4,0),(-10,-22,3,4,math.pi/2),(-26,37,8,4,0),(18,18,3,3,0),(40,-33,3.5,4,0)]:
  for i in range(8):block((cx,.024,cz-d/2+i*d/8),(w,.028,.065),'stone',ang,0)
 # Site paint is actual flat geometry with stencil-like segmented edges.
 sites={'A':[5.2,ground(5.2,33.81),33.81],'B':[-35.1,ground(-35.1,-28.61),-28.61]}
 for name,p in sites.items():
  x,_,z=p;w,d=(7.3,6.2) if name=='A' else (7,7)
  for dx in [-w/2,w/2]:block((x+dx,.045,z),(.10,.012,d),'mark',0,0)
  for dz in [-d/2,d/2]:block((x,.045,z+dz),(w,.012,.10),'mark',0,0)
  labels.append({'text':name,'position':[x,ground(x,z)+.065,z],'size':100,'color':[.68,.19,.095]})
 # Ground embellishment is deterministic and merged, excluding collision footprints.
 obstacle_polys=[]
 for b in blockers:
  if b['kind']=='wall':continue
  x,y,z=b['position'];w,h,d=b['size'];poly=box(-w/2,-d/2,w/2,d/2)
  from shapely.affinity import rotate,translate
  poly=translate(rotate(poly,-b['rotation']*180/math.pi,origin=(0,0)),x,z);obstacle_polys.append(poly)
 walk=floor.difference(unary_union(obstacle_polys)) if obstacle_polys else floor
 for _ in range(400):
  x=rng.uniform(-50,54);z=rng.uniform(-44,44)
  if walk.contains(Point(x,z)):
   block((x,.015,z),(rng.uniform(.14,.5),.015,rng.uniform(.11,.35)),'sand',rng.uniform(0,math.pi),0)
 # Compact runtime occupancy provides radius checks and consistent sight occlusion.
 grid_origin=(-54.,-48.);cell=.5;gw,gh=224,194
 xs=np.arange(gw)*cell+grid_origin[0]+cell*.5;zs=np.arange(gh)*cell+grid_origin[1]+cell*.5
 xx,zz=np.meshgrid(xs,zs);inside=contains_xy(walk.buffer(-.38),xx,zz)
 # Height-aware 0.5 m lattice retains stacked underpass/catwalk layers.
 nodes=[];cell_nodes={}
 for gz,gx in np.argwhere(inside):
  x,z=xs[gx],zs[gz];ys=heights(x,z)
  if not ys:ys=[ground(x,z)]
  for y in ys:
   index=len(nodes);nodes.append([round(x,4),round(y,4),round(z,4)])
   cell_nodes.setdefault((int(gx),int(gz)),[]).append(index)
 edges=[]
 for (gx,gz),ids in cell_nodes.items():
  for dx,dz in [(1,0),(0,1),(1,1),(-1,1)]:
   if dx and dz and ((gx+dx,gz) not in cell_nodes or (gx,gz+dz) not in cell_nodes):continue
   for i in ids:
    for j in cell_nodes.get((gx+dx,gz+dz),[]):
     if abs(nodes[i][1]-nodes[j][1])<=(.44 if not(dx and dz) else .60):edges.append([i,j])
 # A continuous ramp collider follows the measured graph heights. Raw NAV
 # encodes many small stair risers; CharacterBody3D should climb a ramp, not
 # catch its capsule on each 10 cm riser.
 ramps=[];ramp_polys=[]
 for (gx,gz),ids in cell_nodes.items():
  for i in ids:
   base=np.array(nodes[i]);quad=[base];valid=True
   for dx,dz in [(1,0),(1,1),(0,1)]:
    candidates=cell_nodes.get((gx+dx,gz+dz),[])
    if not candidates:valid=False;break
    j=min(candidates,key=lambda k:abs(nodes[k][1]-base[1]))
    if abs(nodes[j][1]-base[1])>.64:valid=False;break
    quad.append(np.array(nodes[j]))
   if not valid:continue
   quad=np.array(quad);ramp_polys.append(Polygon(quad[:,[0,2]]))
   for f in [[0,1,2],[0,2,3]]:
    tri=quad[f]
    if np.cross(tri[1]-tri[0],tri[2]-tri[0])[1]<0:tri=tri[::-1]
    ramps.append(tri)
 # Retain original terrain where the lattice has no coverage, so boundary
 # clearances and isolated cover tops never become fall-through gaps.
 covered=unary_union(ramp_polys)
 collision_triangles=list(ramps)
 for tri in terrain_triangles:
  poly=Polygon(tri[:,[0,2]])
  if poly.area<.00001:continue
  remainder=poly.difference(covered)
  for part in (remainder.geoms if hasattr(remainder,'geoms') else [remainder]):
   if part.geom_type!='Polygon' or part.area<.00001:continue
   for t in constrained_delaunay_triangles(part).geoms:
    vv=[]
    for x,z in list(t.exterior.coords)[:3]:
     aa=tri[0,[0,2]];mat=np.stack([tri[1,[0,2]]-aa,tri[2,[0,2]]-aa],1)
     uv=np.linalg.solve(mat,np.array([x,z])-aa);y=tri[0,1]+uv[0]*(tri[1,1]-tri[0,1])+uv[1]*(tri[2,1]-tri[0,1]);vv.append([x,y,z])
    vv=np.array(vv)
    if np.cross(vv[1]-vv[0],vv[2]-vv[0])[1]<0:vv=vv[::-1]
    collision_triangles.append(vv)
 collision_triangles=np.array(collision_triangles)
 # NAV leaves a clipped sliver at the A-ramp stair edge. Fit its collision to
 # the measured 0.49 rise/run across the full 2.4 m width, so a standing capsule
 # traverses the same ramp without catching a triangulation edge.
 for triangle in collision_triangles:
  for vertex in triangle:
   if 27.0<vertex[0]<31.0 and 17.6<vertex[2]<20.0 and -.4<vertex[1]<1.5:
    vertex[1]=max(-.09,.49*(29.25-vertex[0])+.08)

 write_text_atomic(OUT/'navigation.json',json.dumps({'nodes':nodes,'edges':edges,'triangles':data['nav_triangles']},separators=(',',':')))
 rows=[''.join('1' if v else '0' for v in row) for row in inside]
 floor_polys=[{'exterior':list(floor.exterior.coords),'holes':[list(h.coords) for h in floor.interiors]}]
 meta={'bounds':[-54,-48,112,97],'spawns':{'CT':[-28.0924,.5064,28.6766],'T':[51.9684,2.9448,-13.7922]},'sites':sites,'grid':{'origin':grid_origin,'cell':cell,'width':gw,'height':gh,'rows':rows},'polygons':floor_polys,'blockers':blockers,'labels':labels,'locations':[{'name':n,'point':[x,z]} for n,x,z in [('A 爆破点',5.2,33.8),('B 爆破点',-35.1,-28.6),('T 出生点',51,-17),('CT 出生点',-29,28),('中路',10,-6),('中路上段',24,-8),('拱门 / Connector',.4,9),('跳台 / Stairs',8,20),('丛林 / Jungle',-9,19),('VIP / Window',-18,4),('A 二楼 / Palace',34,33),('A 坡 / Ramp',25,20),('B 公寓',-24,-39),('后巷',9,-39),('B 小 / Short',-10,-21),('下水道 / Underpass',-18,-15),('超市 / Market',-34,-10),('沙发 / TV',12,-34),('白车 / Van',-41,-38),('长椅 / Bench',-48,-28)]],'manifest':{'triangles':sum(len(m.faces) for ms in parts.values() for m in ms),'mesh_groups':len(parts),'props':dict(count),'geometry':'original faceted colored geometry','floor':'meter-scale measured CS2 NAV with original slopes and stacked elevations','navigation_nodes':len(nodes),'navigation_edges':len(edges)}}
 write_text_atomic(OUT/'map_data.json',json.dumps(meta,ensure_ascii=False,separators=(',',':')),encoding='utf-8')
 scene=tm.Scene()
 for family,ms in parts.items():
  merged=tm.util.concatenate(ms)
  merged.visual.material=tm.visual.material.PBRMaterial(name=family,baseColorFactor=[255,255,255,255],metallicFactor=.5 if family=='Metal' else 0,roughnessFactor=.8,doubleSided=True)
  scene.add_geometry(merged,node_name=family,geom_name=family)
 temporary=OUT/'mirage_environment.glb.tmp'
 temporary.write_bytes(scene.export(file_type='glb',include_normals=True))
 temporary.replace(OUT/'mirage_environment.glb')
 # Save original collision geometry as native Godot objects, avoiding procedural
 # per-frame decoration creation and making the entire map editor-inspectable.
 lines=['[gd_scene load_steps=%d format=3]'%(len(blockers)+3),'','[ext_resource type="PackedScene" path="res://assets/map/mirage_environment.glb" id="1"]','','[sub_resource type="ConcavePolygonShape3D" id="FloorShape"]','data = PackedVector3Array(%s)'%', '.join(str(round(float(v),5)) for v in collision_triangles.reshape(-1)),'backface_collision = true','']
 for i,b in enumerate(blockers):
  lines.extend(['[sub_resource type="BoxShape3D" id="B%d"]'%i,'size = Vector3(%s)'%', '.join(map(str,b['size'])),''])
 lines.extend(['[node name="MirageBaked" type="Node3D"]','','[node name="Architecture" parent="." instance=ExtResource("1")]','','[node name="Floor" type="StaticBody3D" parent="."]','collision_layer = 1','collision_mask = 0','','[node name="Collision" type="CollisionShape3D" parent="Floor"]','position = Vector3(0, 0, 0)','shape = SubResource("FloorShape")',''])
 for i,b in enumerate(blockers):
  lines.extend(['[node name="%s_%d" type="StaticBody3D" parent="."]'%(b['kind'],i),'position = Vector3(%s)'%', '.join(map(str,b['position'])),'rotation = Vector3(0, %s, 0)'%b['rotation'],'collision_layer = 1','collision_mask = 0','','[node name="Collision" type="CollisionShape3D" parent="%s_%d"]'%(b['kind'],i),'shape = SubResource("B%d")'%i,''])
 write_text_atomic(OUT/'mirage_baked.tscn','\n'.join(lines),encoding='utf-8')
 print(json.dumps(meta['manifest'],ensure_ascii=False));print('Collision bodies',len(blockers),'floor area',floor.area,'walkable cells',int(inside.sum()))
if __name__=='__main__':
 raise SystemExit('Retired NAV-inferred layout: use tools/build_source_map.py and tools/bake_source_map.py. This historical generator must not overwrite the source-accurate map.')
