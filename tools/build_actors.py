"""Offline authoring of original faceted character and weapon sculptures.

Read-only art study: middle-ages-battle/tools/build_units.py. These meshes are
original: beveled convex silhouettes, flat normals, vertex paint, rigid joints.
Run Python, then Godot --headless --path . --script res://tools/build_actors.gd.
No mesh generation occurs during a match.
"""
from pathlib import Path
from collections import defaultdict
import math
import json
import re
import hashlib
import numpy as np
import trimesh as tm

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets'
P = {
    'navy': '#294352', 'navylight': '#405c6b', 'vest': '#36413e',
    'vestlight': '#536258', 'rubber': '#262f30', 'steel': '#59666b',
    'edge': '#88928e', 'wood': '#a65f32', 'woodlight': '#c4814b',
    'cloth': '#d1c2a0', 'clothlight': '#e1d3b5', 'pants': '#82664a',
    'leather': '#533d2e', 'scarf': '#a95437', 'scarfedge': '#d08a55',
    'skin': '#cba27a', 'lens': '#93bbb9', 'black': '#1d2528',
    'olive': '#707454', 'oliveedge': '#919277', 'gold': '#cbaa64',
    'red': '#a23c33', 'white': '#e9e0cb', 'orange': '#e99741',
}


def transform(mesh, pos=(0,0,0), rot=(0,0,0)):
    m = tm.transformations.euler_matrix(*rot)
    m[:3,3] = pos
    mesh.apply_transform(m)
    return mesh


def bevel_box(size, pos=(0,0,0), rot=(0,0,0), bevel=.018):
    h = np.array(size) / 2
    b = min(bevel, min(h)*.5)
    points=[]
    for x in (-1,1):
        for y in (-1,1):
            for z in (-1,1):
                sign=np.array((x,y,z))
                for ax in range(3):
                    v=(h-b)*sign
                    v[ax]=h[ax]*sign[ax]
                    points.append(v)
    return transform(tm.convex.convex_hull(points), pos, rot)


def ellipsoid(size, pos=(0,0,0), sub=1, rot=(0,0,0)):
    m=tm.creation.icosphere(subdivisions=sub)
    m.apply_scale(size)
    return transform(m,pos,rot)


def rod(a,b,r,r2=None,n=8):
    a,b=np.array(a),np.array(b)
    d=b-a
    if r2 is None:
        m=tm.creation.cylinder(radius=r,height=np.linalg.norm(d),sections=n)
    else:
        pts=[(rad*math.cos(j*math.tau/n),rad*math.sin(j*math.tau/n),z)
             for z,rad in ((-np.linalg.norm(d)/2,r),(np.linalg.norm(d)/2,r2)) for j in range(n)]
        m=tm.convex.convex_hull(pts)
    mat=tm.geometry.align_vectors((0,0,1),d)
    mat[:3,3]=(a+b)/2
    m.apply_transform(mat)
    return m


def profile(rings,n=10):
    """Elliptical clothing profiles sculpt shoulders/waist rather than boxes."""
    points=[(rx*math.cos(j*math.tau/n),y,rz*math.sin(j*math.tau/n))
            for y,rx,rz in rings for j in range(n)]
    return tm.convex.convex_hull(points)


def plate(points,width=.065):
    """Side silhouette extrusion. Coordinates are y,z in weapon space."""
    return tm.convex.convex_hull([(x,y,z) for x in (-width/2,width/2) for y,z in points])


class Sculpture:
    def __init__(self,name,folder):
        self.name=name
        self.folder=folder
        self.nodes=[]
        self.meshes=defaultdict(list)
        self.materials={}
        self.triangles=0

    def joint(self,name,parent='.',pos=(0,0,0)):
        self.nodes.append(dict(name=name,parent=parent,position=pos))
        return name if parent=='.' else parent+'/'+name

    def add(self,part,mesh,color,metal=False):
        rgb=np.array([int(P[color][i:i+2],16)/255 for i in (1,3,5)])
        # Keep authored sRGB paint. Native material converts for Forward+/Mobile;
        # Compatibility shades in sRGB and intentionally ignores that flag.
        # One color per triangle: deliberate broad, hand-painted-looking planes.
        v=mesh.vertices[mesh.faces].reshape(-1,3)
        ns=np.repeat(mesh.face_normals,3,axis=0)
        shade=.96+.065*np.clip(mesh.face_normals[:,1],-1,1)
        colors=np.repeat(np.column_stack((np.clip(rgb[None,:]*shade[:,None],0,1),np.ones(len(shade)))),3,axis=0)
        self.meshes[(part,'metal' if metal else 'matte')].append((v,ns,colors))
        self.triangles+=len(mesh.faces)

    def b(self,p,size,pos,c,rot=(0,0,0),bevel=.018,metal=False):
        self.add(p,bevel_box(size,pos,rot,bevel),c,metal)

    def e(self,p,size,pos,c,sub=1,rot=(0,0,0),metal=False):
        self.add(p,ellipsoid(size,pos,sub,rot),c,metal)

    def r(self,p,a,b,r,c,r2=None,n=8,metal=False):
        self.add(p,rod(a,b,r,r2,n),c,metal)

    def save(self,metadata=None):
        surfaces=[]
        for (part,mat),chunks in self.meshes.items():
            v,n,c=[np.concatenate([x[i] for x in chunks]) for i in range(3)]
            surfaces.append(dict(part=part,material=mat,vertices=v.round(6).ravel().tolist(),normals=n.round(5).ravel().tolist(),colors=c.round(5).ravel().tolist()))
        dest=OUT/self.folder/'source'
        dest.mkdir(parents=True,exist_ok=True)
        path=dest/(self.name+'.json')
        path.write_text(json.dumps(dict(name=self.name,nodes=self.nodes,surfaces=surfaces,triangles=self.triangles,metadata=metadata or {}),separators=(',',':')),encoding='utf8')
        print(f'{self.folder}/{self.name}: {self.triangles:,} triangles, {len(surfaces)} surfaces')


def character(team):
    ct=team=='ct'
    s=Sculpture(team,'characters')
    rig=s.joint('Rig')
    upper=s.joint('Upper',rig,(0,.88,0))
    head=s.joint('Head',upper,(0,.60,0))
    cloth='navy' if ct else 'cloth'
    bright='navylight' if ct else 'clothlight'
    pants='navy' if ct else 'pants'
    s.add(upper,profile([(-.035,.23,.15),(.11,.27,.18),(.34,.30,.19),(.49,.23,.15)]),cloth)
    # Collar and the angular tactical plate carrier.
    s.r(upper,(0,.43,0),(0,.55,0),.12,'skin',r2=.11)
    s.b(upper,(.50,.40,.12),(0,.245,-.155),'vest',bevel=.052)
    s.b(upper,(.42,.37,.11),(0,.26,.17),'vest',bevel=.045)
    for side in (-1,1):
        s.b(upper,(.075,.27,.07),(side*.19,.40,-.12),'vestlight',rot=(0,0,side*.12))
        s.b(upper,(.07,.26,.07),(side*.18,.40,.14),'vestlight',rot=(0,0,side*.12))
        for y in (.14,.22,.30):
            s.b(upper,(.17,.018,.025),(side*.13,y,-.224),'vestlight',bevel=.004)
        s.b(upper,(.13,.18,.092),(side*.13,.12,-.24),'vestlight',bevel=.022)
        s.b(upper,(.14,.029,.097),(side*.13,.185,-.242),'vest',bevel=.005)
        s.b(upper,(.085,.11,.086),(side*.285,.045,0),'leather',bevel=.019)
    s.b(upper,(.49,.063,.34),(0,.005,0),'rubber',bevel=.012)
    s.b(upper,(.08,.068,.03),(0,.009,-.182),'edge',metal=True)
    # Back hydration pack, webbing and rolled utility pouch.
    s.b(upper,(.29,.34,.14),(0,.25,.255),'navylight' if ct else 'olive',bevel=.05)
    s.b(upper,(.24,.12,.10),(0,.09,.30),'vestlight',bevel=.03)
    s.r(upper,(-.11,.29,.33),(-.11,.37,.33),.015,'rubber')
    s.r(upper,(.13,.28,.32),(.17,.41,.17),.013,'rubber')
    # CT radio / T strapped spare rifle magazine.
    s.b(upper,(.075,.125,.055),(-.22,.355,-.218),'rubber',bevel=.008)
    s.r(upper,(-.22,.40,-.22),(-.22,.61,-.20),.008,'black',n=6)
    if ct:
        s.b(upper,(.145,.046,.021),(0,.355,-.224),'navylight',bevel=.006)
        for xx in (-.04,0,.04):
            s.b(upper,(.018,.025,.01),(xx,.355,-.24),'white',bevel=.002)
    else:
        s.add(upper,profile([(.45,.17,.16),(.53,.15,.15),(.58,.12,.11)]),'scarf')
        s.add(upper,plate([(.5,-.19),(.30,-.22),(.21,-.19),(.38,-.16)],.13),'scarf')
        for yy in (.43,.47,.51):
            s.r(upper,(-.105,yy,-.157),(.10,yy-.012,-.16),.008,'scarfedge',n=6)
    # Deliberately oversized rounded, faceted head, with sculpted face opening.
    s.e(head,(.225,.254,.215),(0,.08,0),'skin' if ct else 'leather',sub=2)
    if ct:
        s.e(head,(.255,.218,.244),(0,.20,.025),'navy',sub=2)
        s.b(head,(.40,.052,.28),(0,.09,-.115),'navylight',bevel=.035)
        s.b(head,(.334,.096,.055),(0,.081,-.215),'rubber',bevel=.025)
        for side in (-1,1):
            s.b(head,(.138,.065,.024),(side*.082,.09,-.246),'lens',bevel=.018)
            s.e(head,(.052,.091,.075),(side*.228,.025,.01),'rubber',sub=1)
            s.e(head,(.045,.075,.061),(side*.26,.025,.01),'navylight',sub=1)
            s.r(head,(side*.16,-.055,-.11),(side*.10,-.13,-.05),.019,'rubber')
        s.e(head,(.14,.115,.12),(0,-.087,-.105),'rubber',sub=1)
        s.r(head,(-.26,-.01,-.02),(-.23,-.06,-.21),.011,'rubber')
        s.r(head,(-.23,-.06,-.21),(-.12,-.07,-.235),.012,'rubber')
        s.b(head,(.085,.048,.11),(0,.40,.04),'vestlight',bevel=.01)
    else:
        s.b(head,(.32,.091,.055),(0,.13,-.194),'skin',bevel=.03)
        for side in (-1,1):
            s.b(head,(.074,.034,.024),(side*.083,.13,-.229),'black',bevel=.008)
            s.b(head,(.09,.02,.02),(side*.079,.177,-.22),'leather',rot=(0,0,side*.12),bevel=.006)
        s.e(head,(.156,.13,.14),(0,-.02,-.115),'pants',sub=1)
        s.r(head,(-.11,-.006,-.218),(.11,-.006,-.218),.011,'leather')
        s.r(head,(-.20,.22,0),(.20,.22,0),.031,'leather')
    for side,label in ((-1,'Left'),(1,'Right')):
        leg=s.joint(label+'Leg',rig,(side*.145,.83,0))
        shin=s.joint(label+'Shin',leg,(0,-.35,.015))
        s.e(leg,(.14,.245,.155),(0,-.17,.025),pants,sub=1)
        s.r(leg,(0,-.09,0),(0,-.35,.01),.125,pants,r2=.095,n=10)
        s.b(leg,(.09,.15,.15),(side*.105,-.16,.008),'navylight' if ct else 'pants',bevel=.024)
        s.b(leg,(.074,.025,.15),(side*.114,-.11,.008),'vestlight',bevel=.004)
        s.e(shin,(.095,.17,.108),(0,-.12,.025),pants,sub=1)
        s.b(shin,(.145,.155,.076),(0,-.018,-.079),'rubber' if ct else 'leather',rot=(.11,0,0),bevel=.029)
        s.b(shin,(.12,.104,.025),(0,-.015,-.117),'vestlight',rot=(.11,0,0),bevel=.019)
        s.r(shin,(0,-.24,.01),(0,-.36,-.01),.105,'rubber' if ct else 'leather',r2=.103,n=8)
        s.b(shin,(.21,.16,.335),(0,-.395,-.068),'rubber' if ct else 'leather',bevel=.046)
        s.b(shin,(.217,.041,.34),(0,-.459,-.069),'black',bevel=.010)
        for zz in (-.12,-.075,-.03):
            s.r(shin,(-.058,-.31,zz),(.058,-.31,zz),.008,'edge' if ct else 'pants',n=6)
        arm=s.joint(label+'Arm',upper,(side*.278,.425,-.005))
        elbow=(side*.074,-.25,-.10)
        s.e(arm,(.131,.133,.14),(side*.022,-.044,-.006),bright,sub=1)
        s.r(arm,(side*.017,-.025,-.01),elbow,.108,cloth,r2=.083,n=9)
        s.e(arm,(.095,.082,.09),elbow,bright,sub=1)
        fore=s.joint(label+'Forearm',arm,elbow)
        # Support hand extends farther along barrel; trigger hand stays near grip.
        hand=(.42,.13,-.47) if side==-1 else (-.225,.14,-.23)
        s.r(fore,(0,0,0),hand,.075,bright,r2=.065,n=8)
        s.e(fore,(.067,.065,.083),hand,'rubber' if ct else 'leather',sub=1)
        s.b(fore,(.082,.052,.077),(hand[0],hand[1]+.031,hand[2]),'vestlight',bevel=.018)
        if not ct:
            s.r(fore,(hand[0]*.72,hand[1]*.72,hand[2]*.72),hand,.063,'skin',r2=.061,n=8)
    s.joint('WeaponSocket',upper,(.11,.315,-.335))
    s.save({'team':team.upper(),'height_m':1.88,'faces':'-Z','original_art':True})


def rifle(s,p,wid):
    wood=wid=='ak47'
    body='black'
    furn='wood' if wood else 'olive' if wid in ('aug','sg556','awp','ssg08','g3sg1') else 'pants' if wid=='scar20' else 'steel'
    sniper=wid in ('awp','ssg08','scar20','g3sg1')
    long={'awp':.94,'ssg08':.79,'scar20':.81,'g3sg1':.92,'galilar':.74,'aug':.63,'famas':.58}.get(wid,.65)
    # Receiver and lower receiver follow a recognizable side profile.
    s.b(p,(.10,.122,.34),(0,.085,-.105),body,bevel=.015,metal=True)
    s.add(p,plate([(.10,.23),(.13,.23),(.10,.11),(.048,.07),(-.045,.10),(-.025,.25)],.079),furn)
    if wood:
        s.add(p,plate([(.145,.17),(.09,.22),(.052,.41),(-.083,.41),(-.077,.32),(.019,.17)],.103),'wood')
        s.b(p,(.109,.125,.024),(0,-.01,.402),'rubber',bevel=.009)
        s.b(p,(.108,.087,.19),(0,.055,-.35),'wood',bevel=.017)
        s.b(p,(.081,.045,.12),(0,.113,-.335),'woodlight',bevel=.014)
        s.r(p,(0,.115,-.32),(0,.115,-.51),.022,'steel',n=8,metal=True)
        curve=[(.008,-.14),(-.08,-.16),(-.17,-.20),(-.255,-.265)]
        for i in range(3):
            y,z=curve[i]; yy,zz=curve[i+1]
            s.add(p,plate([(y,z+.052),(y,z-.052),(yy,zz-.049),(yy,zz+.049)],.064),'steel',True)
        for yy,zz in curve[1:]:
            s.b(p,(.07,.014,.084),(0,yy,zz),'black',rot=(.3,0,0),bevel=.002)
    elif sniper:
        s.add(p,plate([(.05,.34),(.09,.35),(.10,-.32),(.034,-.41),(-.055,-.26),(-.051,.19),(-.14,.31)],.108),furn)
        s.b(p,(.105,.095,.15),(0,-.005,-.135),body,bevel=.01,metal=True)
        s.b(p,(.094,.14,.075),(0,-.10,-.11),'black',bevel=.009)
        s.b(p,(.126,.16,.041),(0,-.025,.36),'rubber',bevel=.016)
        s.r(p,(.08,.11,-.013),(.12,.078,.03),.011,'edge',metal=True)
        s.e(p,(.023,.023,.023),(.124,.078,.03),'black')
        if wid=='awp':
            s.b(p,(.13,.083,.195),(0,.083,.255),'oliveedge',bevel=.025)
            s.b(p,(.104,.07,.23),(0,.001,-.37),'olive',bevel=.02)
        elif wid=='ssg08':
            s.b(p,(.072,.047,.20),(0,.112,.235),'oliveedge',bevel=.014)
            for side in (-1,1):
                s.r(p,(side*.04,.01,-.40),(side*.056,-.018,-.64),.011,'edge',n=6,metal=True)
        elif wid=='scar20':
            s.b(p,(.13,.13,.26),(0,.086,-.33),'pants',bevel=.018)
            s.b(p,(.123,.13,.19),(0,.065,.24),'pants',bevel=.02)
            s.b(p,(.07,.15,.10),(0,-.10,-.12),'black',bevel=.01)
        else:
            s.b(p,(.10,.09,.30),(0,.02,-.32),'olive',bevel=.021)
            s.b(p,(.07,.16,.12),(0,-.12,-.12),'steel',bevel=.009,metal=True)
    else:
        s.r(p,(0,.075,.07),(0,.075,.27),.033,'steel',metal=True)
        s.add(p,plate([(.12,.25),(.12,.35),(-.055,.35),(-.08,.20),(.045,.13)],.078),furn)
        s.b(p,(.094,.17,.027),(0,.027,.35),'rubber',bevel=.01)
        s.b(p,(.10,.105,.235),(0,.082,-.32),furn,bevel=.025)
        for z in (-.26,-.31,-.36,-.41):
            s.b(p,(.118,.028,.027),(0,.088,z),'black',bevel=.003)
        s.add(p,plate([(.00,-.104),(-.015,-.204),(-.21,-.235),(-.23,-.13)],.062),'steel',True)
        if wid in ('aug','famas'):
            s.b(p,(.12,.085,.28),(0,.165,-.03),furn,bevel=.017)
            s.b(p,(.064,.04,.11),(0,.199,-.026),'rubber',bevel=.008)
            s.b(p,(.125,.105,.22),(0,.038,.205),'olive' if wid=='aug' else 'black',bevel=.021)
            s.b(p,(.07,.165,.093),(0,-.08,.14),'steel',bevel=.009,metal=True)
        if wid=='galilar':
            s.b(p,(.113,.075,.30),(0,.075,-.395),'black',bevel=.020)
            s.b(p,(.121,.02,.023),(0,.124,-.41),'edge',bevel=.003,metal=True)
            s.b(p,(.028,.076,.025),(0,.163,-.60),'steel',bevel=.005,metal=True)
    s.add(p,plate([(.026,.052),(-.025,.11),(-.16,.06),(-.145,-.015),(-.012,-.014)],.062),'wood' if wood else 'rubber')
    s.r(p,(0,.082,-.40),(0,.082,-long),.021,'steel',n=10,metal=True)
    s.r(p,(0,.082,-long+.027),(0,.082,-long-.048),.029,'black',n=8)
    s.b(p,(.035,.061,.035),(0,.126,-long+.08),'black',bevel=.004)
    s.b(p,(.035,.045,.032),(0,.16,-.16),'black',bevel=.004)
    if wid=='m4a1_silencer':
        s.r(p,(0,.082,-long),(0,.082,-long-.19),.040,'rubber',n=10)
        long+=.19
    if sniper or wid in ('aug','sg556'):
        s.b(p,(.075,.045,.21),(0,.163,-.13),'black',bevel=.004)
        s.r(p,(0,.229,-.33),(0,.229,.042),.043,'black',n=10)
        s.r(p,(0,.229,-.355),(0,.229,-.292),.067,'steel',n=10,metal=True)
        s.r(p,(0,.229,-.362),(0,.229,-.356),.049,'lens',n=10,metal=True)
        s.r(p,(0,.229,.015),(0,.229,.062),.052,'rubber',n=10)
        s.r(p,(0,.26,-.11),(0,.304,-.11),.029,'steel',metal=True)
    else:
        # Ejection port, charging handle, pins and curved trigger guard.
        s.b(p,(.010,.033,.11),(.054,.091,-.06),'edge',bevel=.003,metal=True)
        for zz in (-.105,.018):
            s.r(p,(.049,.035,zz),(.059,.035,zz),.008,'edge',n=6,metal=True)
    s.r(p,(.0,-.04,-.02),(.0,-.081,-.024),.011,'steel',n=6,metal=True)
    s.r(p,(.0,-.081,-.024),(.0,-.078,-.092),.011,'steel',n=6,metal=True)
    return (0,.082,-long-.053)


def pistol(s,p,wid):
    if wid=='taser':
        s.b(p,(.11,.12,.22),(0,.045,-.09),'orange',bevel=.02)
        s.b(p,(.075,.19,.068),(0,-.079,.00),'rubber',rot=(.18,0,0),bevel=.016)
        s.b(p,(.09,.08,.047),(0,.062,-.214),'black',bevel=.012)
        for x in (-.024,.024):
            s.r(p,(x,.068,-.22),(x,.068,-.248),.013,'edge',n=6,metal=True)
        return (0,.065,-.252)
    silver=wid in ('deagle','revolver','elite')
    long={'deagle':.27,'hkp2000':.21,'fiveseven':.235,'cz75a':.22,'elite':.25,'p250':.19}.get(wid,.19)
    if wid=='revolver': long=.31
    def single(x=0):
        s.b(p,(.073,.072,long+.075),(x,.064,-long*.38),'edge' if silver else 'steel',bevel=.012,metal=True)
        s.b(p,(.063,.040,long),(x,.008,-long*.31),'rubber',bevel=.009)
        if wid=='fiveseven':
            s.b(p,(.077,.047,long*.87),(x,.013,-long*.32),'olive',bevel=.014)
        if wid in ('p250','hkp2000','usp_silencer'):
            s.b(p,(.080,.026,.048),(x,.073,-.038),'black',bevel=.005)
        if wid=='deagle':
            s.b(p,(.084,.025,.165),(x,.105,-.133),'edge',bevel=.004,metal=True)
        grip=plate([(.015,.035),(-.027,.067),(-.163,.035),(-.155,-.041),(-.011,-.035)],.065)
        grip.apply_translation((x,0,0))
        s.add(p,grip,'wood' if wid=='elite' else 'rubber')
        for yy in (-.065,-.093,-.12):
            s.b(p,(.069,.013,.064),(x,yy,.0),'steel' if silver else 'black',rot=(.18,0,0),bevel=.003)
        s.r(p,(x,-.027,-.04),(x,-.061,-.065),.009,'steel',n=6,metal=True)
        s.r(p,(x,-.061,-.065),(x,-.048,-.117),.009,'steel',n=6,metal=True)
        s.r(p,(x,-.048,-.117),(x,.005,-.116),.009,'steel',n=6,metal=True)
        s.b(p,(.031,.02,.022),(x,.109,-long+.025),'black',bevel=.004)
        s.b(p,(.033,.02,.026),(x,.109,.052),'black',bevel=.003)
        for z in (.011,.027,.043):
            s.b(p,(.079,.043,.009),(x,.067,z),'black',bevel=.002)
        s.r(p,(x,.063,-long+.017),(x,.063,-long-.009),.021,'black',n=8)
        if wid=='revolver':
            s.r(p,(x,.037,-.045),(x,.037,-.14),.05,'edge',n=8,metal=True)
        if wid in ('tec9','cz75a'):
            s.b(p,(.055,.13,.055),(x,-.07,-.12),'steel',bevel=.006,metal=True)
    single()
    if wid=='elite': single(-.145)
    if wid=='usp_silencer':
        s.r(p,(0,.063,-long),(0,.063,-long-.165),.031,'black',n=10)
        long+=.165
    if wid=='tec9':
        s.r(p,(0,.063,-long),(0,.063,-long-.14),.036,'steel',n=8,metal=True)
        long+=.14
    return (0,.063,-long-.012)


def smg(s,p,wid):
    p90=wid=='p90'
    s.b(p,(.105,.14,.37 if p90 else .28),(0,.075,-.11),'olive' if p90 else 'steel',bevel=.026,metal=not p90)
    s.b(p,(.064,.16,.068),(0,-.066,.004),'rubber',rot=(.14,0,0),bevel=.012)
    if wid not in ('p90','bizon','mac10'):
        s.b(p,(.07,.235,.059),(0,-.09,-.156),'steel',rot=(.07,0,0),bevel=.01,metal=True)
    if wid=='mac10':
        s.b(p,(.096,.078,.13),(0,.15,-.03),'black',bevel=.016)
        s.b(p,(.06,.16,.059),(0,-.15,.001),'steel',bevel=.007,metal=True)
    if p90:
        s.b(p,(.13,.051,.31),(0,.17,-.115),'gold',bevel=.018)
        s.add(p,plate([(.13,.20),(.12,.04),(-.065,.055),(-.071,.20)],.114),'olive')
        s.b(p,(.034,.045,.13),(0,.208,-.13),'black',bevel=.006)
    elif wid=='bizon':
        s.r(p,(0,-.034,-.25),(0,-.034,-.50),.058,'olive',n=10)
    else:
        for x in (-.039,.039):
            s.r(p,(x,.065,.019),(x,.08,.23),.012,'edge',n=6,metal=True)
        s.b(p,(.104,.133,.029),(0,.041,.239),'rubber',bevel=.01)
    if wid in ('mp7','mp9'):
        s.b(p,(.05,.155,.045),(0,-.033,-.275),'rubber',bevel=.009)
    if wid=='ump45':
        s.b(p,(.108,.082,.15),(0,.065,-.295),'black',bevel=.02)
        for side in (-1,1):
            s.r(p,(side*.04,.077,.09),(side*.05,-.03,.268),.016,'black',n=6)
    long=.38 if wid in ('mac10','mp9','mp7') else .47
    s.r(p,(0,.077,-.23),(0,.077,-long),.025,'black',n=10)
    if wid=='mp5sd':
        s.r(p,(0,.077,-.31),(0,.077,-.60),.044,'rubber',n=10)
        long=.6
    for z in (-.18,-.135,-.09):
        s.b(p,(.113,.044,.019),(0,.09,z),'black',bevel=.004)
    s.b(p,(.034,.039,.027),(0,.164,-.222),'black',bevel=.004)
    return (0,.077,-long-.009)


def shotgun(s,p,wid):
    mag7=wid=='mag7'
    long=.46 if wid=='sawedoff' or mag7 else .79
    s.b(p,(.105,.123,.23),(0,.065,-.13),'steel',bevel=.02,metal=True)
    s.r(p,(0,.08,-.2),(0,.08,-long),.031,'black',n=10)
    s.r(p,(0,.015,-.2),(0,.015,-long+.065),.026,'steel',n=8,metal=True)
    s.add(p,plate([(.08,.017),(.06,.32),(-.115,.32),(-.116,.24),(-.037,.11),(-.093,.058),(-.09,.009)],.091),'wood' if wid in ('nova','sawedoff') else 'rubber')
    s.b(p,(.12,.09,.19),(0,.018,-.35),'wood' if wid=='nova' else 'rubber',bevel=.021)
    for zz in (-.285,-.317,-.348,-.38,-.41):
        s.b(p,(.127,.070,.012),(0,.018,zz),'woodlight' if wid=='nova' else 'steel',bevel=.003)
    if mag7:
        s.b(p,(.083,.175,.09),(0,-.09,-.091),'black',bevel=.008)
    s.b(p,(.036,.027,.024),(0,.119,-long+.04),'orange',bevel=.004)
    return (0,.08,-long-.015)


def machinegun(s,p,wid):
    end=rifle(s,p,'m4a1')
    s.b(p,(.21,.20,.20),(0,-.078,-.13),'olive' if wid=='m249' else 'pants',bevel=.025)
    s.b(p,(.11,.15,.29),(0,.13,-.19),'steel',bevel=.015,metal=True)
    for x in (-.035,0,.035,.070,.105):
        s.r(p,(x,.012,-.255),(x,.012,-.15),.012,'gold',n=6,metal=True)
    for side in (-1,1):
        s.r(p,(side*.033,.045,-.50),(side*.12,-.16,-.57),.014,'black',n=6)
    return end


def gear(s,p,wid):
    if wid in ('armor','helmet'):
        s.b(p,(.37,.41,.17),(0,0,0),'vest',bevel=.044)
        for side in (-1,1):
            s.b(p,(.12,.18,.08),(side*.09,-.035,-.13),'vestlight',bevel=.014)
            s.b(p,(.072,.16,.15),(side*.127,.25,0),'vestlight',bevel=.018)
        if wid=='helmet':
            s.e(p,(.22,.18,.215),(0,.44,0),'navy',sub=2)
    elif wid=='kit':
        s.b(p,(.21,.135,.25),(0,0,0),'olive',bevel=.017)
        s.r(p,(-.06,.09,-.04),(.055,.09,.07),.019,'edge',metal=True)
        s.r(p,(.05,.09,-.045),(-.055,.09,.07),.019,'edge',metal=True)
        s.b(p,(.065,.025,.10),(0,.072,0),'orange',bevel=.003)
    elif wid=='molotov':
        s.r(p,(0,-.14,0),(0,.095,0),.065,'olive',r2=.055,n=9)
        s.r(p,(0,.095,0),(0,.2,0),.028,'olive',n=8)
        s.b(p,(.13,.093,.119),(0,-.015,0),'cloth',bevel=.012)
        s.r(p,(0,.20,0),(.049,.25,-.03),.018,'clothlight',n=6)
    else:
        c='olive' if wid=='hegrenade' else 'red' if wid=='incgrenade' else 'steel'
        s.r(p,(0,-.10,0),(0,.09,0),.06,c,r2=.057,n=10)
        s.r(p,(0,.078,0),(0,.13,0),.04,'black',n=8)
        s.b(p,(.021,.205,.042),(.047,.047,0),'edge',rot=(0,0,-.21),bevel=.004,metal=True)
        s.b(p,(.122,.035,.115),(0,-.04,0),'orange' if wid in ('hegrenade','flashbang') else 'cloth',bevel=.012)
        s.r(p,(-.04,.137,0),(.022,.137,0),.012,'edge',n=6,metal=True)
    return (0,0,0)


ALIASES={'m4a4':'m4a1','m4a1s':'m4a1_silencer','usp':'usp_silencer','usps':'usp_silencer','scout':'ssg08','galil':'galilar','sg553':'sg556','p2000':'hkp2000','dualberettas':'elite','five_seven':'fiveseven','mp5':'mp5sd','he':'hegrenade','smoke':'smokegrenade','flash':'flashbang','incendiary':'incgrenade','defuse':'kit','defuser':'kit','kevlar':'armor','assaultsuit':'helmet'}
WEAPONS=[
 ('glock','Glock-18','pistol','T'),('usp_silencer','USP-S','pistol','CT'),('hkp2000','P2000','pistol','CT'),('p250','P250','pistol','ANY'),('elite','Dual Berettas','pistol','ANY'),('fiveseven','Five-SeveN','pistol','CT'),('tec9','Tec-9','pistol','T'),('cz75a','CZ75-Auto','pistol','ANY'),('deagle','Desert Eagle','pistol','ANY'),('revolver','R8 Revolver','pistol','ANY'),
 ('ak47','AK-47','rifle','T'),('m4a1','M4A4','rifle','CT'),('m4a1_silencer','M4A1-S','rifle','CT'),('galilar','Galil AR','rifle','T'),('famas','FAMAS','rifle','CT'),('aug','AUG','rifle','CT'),('sg556','SG 553','rifle','T'),
 ('ssg08','SSG 08','sniper','ANY'),('awp','AWP','sniper','ANY'),('scar20','SCAR-20','sniper','CT'),('g3sg1','G3SG1','sniper','T'),
 ('mac10','MAC-10','smg','T'),('mp9','MP9','smg','CT'),('mp7','MP7','smg','ANY'),('mp5sd','MP5-SD','smg','ANY'),('ump45','UMP-45','smg','ANY'),('p90','P90','smg','ANY'),('bizon','PP-Bizon','smg','ANY'),
 ('nova','Nova','shotgun','ANY'),('xm1014','XM1014','shotgun','ANY'),('mag7','MAG-7','shotgun','CT'),('sawedoff','Sawed-Off','shotgun','T'),('m249','M249','machinegun','ANY'),('negev','Negev','machinegun','ANY'),('taser','Zeus x27','pistol','ANY'),
 ('hegrenade','高爆手雷','grenade','ANY'),('smokegrenade','烟雾弹','grenade','ANY'),('flashbang','闪光弹','grenade','ANY'),('molotov','燃烧瓶','grenade','T'),('incgrenade','燃烧弹','grenade','CT'),('decoy','诱饵弹','grenade','ANY'),('armor','防弹衣','gear','ANY'),('helmet','防弹衣＋头盔','gear','ANY'),('kit','拆弹工具','gear','CT'),('knife','战术匕首','melee','ANY'),
]


def weapon(wid,cat):
    s=Sculpture(wid,'weapons')
    p=s.joint('Model')
    if cat in ('rifle','sniper'): muzzle=rifle(s,p,wid)
    elif cat=='pistol': muzzle=pistol(s,p,wid)
    elif cat=='smg': muzzle=smg(s,p,wid)
    elif cat=='shotgun': muzzle=shotgun(s,p,wid)
    elif cat=='machinegun': muzzle=machinegun(s,p,wid)
    elif cat=='melee':
        s.r(p,(0,0,.075),(0,0,-.06),.032,'rubber',n=8)
        s.b(p,(.15,.025,.021),(0,0,-.07),'steel',bevel=.006,metal=True)
        s.add(p,plate([(.045,-.081),(.047,-.20),(0,-.40),(-.04,-.16),(-.04,-.081)],.025),'edge',True)
        muzzle=(0,0,-.4)
    else: muzzle=gear(s,p,wid)
    s.joint('Muzzle','.',muzzle)
    s.save({'weapon_id':wid,'category':cat,'muzzle':muzzle,'original_art':True})


def catalog():
    path=OUT/'weapons/source/weapons.vdata'
    if not path.exists():
        raise SystemExit('Download current Valve weapons.vdata mirror into assets/weapons/source/weapons.vdata first.')
    text=path.read_text()
    blocks={m.group(1):m.group(2) for m in re.finditer(r'^\t"?(\w+)"?\s*=\s*\n\t\{(.*?)(?=^\t\})',text,re.M|re.S)}
    def val(body,key,default=None):
        m=re.search(r'\b'+key+r' = ([^\n]+)',body)
        if not m:return default
        st=m.group(1).strip().strip('"')
        if st=='true':return True
        if st=='false':return False
        if st.startswith('['):return float(re.search(r'-?[0-9]+(?:\.[0-9]+)?',st).group(0))
        try:return float(st) if '.' in st else int(st)
        except ValueError:return st
    result=[]
    snapshots=[]
    reloads={'ak47':2.43,'m4a1':2.65,'m4a1_silencer':2.6,'awp':3.25,'ssg08':3.05,'famas':3.1,'galilar':3.0,'glock':2.05,'usp_silencer':2.17,'deagle':2.2,'p90':3.35,'bizon':2.4,'negev':5.2,'m249':5.2,'elite':3.1}
    for wid,name,cat,team in WEAPONS:
        body=blocks.get('weapon_'+wid,blocks.get('weapon_'+wid+'_prefab',''))
        if cat=='gear':
            token={'armor':'item_kevlar','helmet':'item_assaultsuit','kit':'item_defuser'}[wid]
            body=next((b for b in blocks.values() if 'm_szName = "'+token+'"' in b),'')
        price=val(body,'m_nPrice',0)
        mag=val(body,'m_iMaxClip1',0)
        reserve=val(body,'m_nPrimaryReserveAmmoMax',0)
        as_clips=val(body,'m_bReserveAmmoAsClips',cat not in ('shotgun','grenade','gear','melee'))
        if as_clips:reserve*=mag
        shots=round(1/max(.06,val(body,'m_flCycleTime',.2)),3)
        spread={'rifle':.005,'sniper':.0013,'smg':.013,'pistol':.010,'shotgun':.065,'machinegun':.016}.get(cat,.0)
        move={'rifle':.12,'sniper':.21,'smg':.067,'pistol':.09,'shotgun':.06,'machinegun':.16}.get(cat,0.)
        bloom={'rifle':.009,'sniper':.014,'smg':.006,'pistol':.014,'shotgun':.025,'machinegun':.008}.get(cat,0.)
        if wid=='ak47':spread=.0018
        if wid=='m4a1_silencer':spread=.0032
        if wid=='deagle':spread=.0045
        damage=val(body,'m_nDamage',0)
        if cat in ('grenade','gear'):mag=1 if cat=='grenade' else 0;reserve=0
        if cat=='gear':damage=0
        if cat=='melee':mag=1;damage=45;shots=2.0
        dist=val(body,'m_flRange',8192)*.0254
        if cat=='melee':dist=1.65
        d=dict(id=wid,name=name,category=cat,team=team,price=price,damage=damage,magazine=mag,reserve=reserve,fire_rate=shots,reload=reloads.get(wid,3.2 if cat=='sniper' else 2.6 if cat=='rifle' else 2.4 if cat in ('shotgun','smg') else 2.1),spread=spread,move_spread=move,recoil=bloom,automatic=bool(val(body,'m_bIsFullAuto',False)),range=round(dist,2),pellets=int(val(body,'m_nNumBullets',1)),weight={'rifle':3.3,'sniper':5.2,'smg':2.5,'pistol':.9,'shotgun':3.7,'machinegun':7.1,'grenade':.4,'gear':2.5,'melee':.3}[cat],armor_ratio=val(body,'m_flArmorRatio',1.0),max_speed=round(val(body,'m_flMaxSpeed',240)*.0254,3),description={'rifle':'静止点射精准，连续射击后扩散上升','sniper':'右键瞄准后远距离精准射击','smg':'轻巧，近距离移动作战','pistol':'轻型副武器，点击射击','shotgun':'近距离多弹丸，远距离散布明显','machinegun':'大容量弹链，较重','grenade':'装备投掷物，按 G 投掷','gear':'回合装备','melee':'轻装移动与近距离攻击'}[cat])
        result.append(d)
        snapshots.append(dict(id=wid,price=price,damage=damage,magazine=mag,reserve=reserve,reserve_is_clips=as_clips,fire_rate=shots,pellets=d['pellets']))
    indexed={row['id']:row for row in result}
    for wid,expected in {'armor':650,'helmet':1000,'kit':400,'ak47':2700,'m4a1':2900,'famas':1950,'mp7':1400,'awp':4750}.items():
        assert indexed[wid]['price']==expected, f'{wid} price changed or parsing failed: review Valve snapshot before rebaking.'
    assert all(row['price']>0 for row in result if row['id']!='knife')
    (OUT/'weapons/catalog.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf8')
    (OUT/'weapons/source/verified_values.json').write_text(json.dumps(dict(retrieved='2026-09-13',source='https://raw.githubusercontent.com/SteamTracking/GameTracking-CS2/master/game/csgo/pak01_dir/scripts/weapons.vdata',sha256=hashlib.sha256(path.read_bytes()).hexdigest(),values=snapshots),indent=2),encoding='utf8')
    return result


if __name__=='__main__':
    catalog()
    for team in ('ct','t'): character(team)
    for wid,_,cat,_ in WEAPONS:weapon(wid,cat)
