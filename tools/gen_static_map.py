# -*- coding: utf-8 -*-
"""Generate deterministic static map source files for War State.
The generated .model.json files are consumed by real Rojo 7.7.0. Nothing is generated on PlayerAdded.
"""
from __future__ import annotations
import json, math, random, sys
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent
CONFIG=ROOT/"src/ReplicatedStorage/Shared/Config"
OUT=ROOT/"src/Workspace/Map"
MAT={"SmoothPlastic":272,"Neon":288,"Wood":512,"WoodPlanks":528,"Slate":800,"Concrete":816,"Pebble":864,"Rock":896,"Metal":1088,"Grass":1280,"LeafyGrass":1284,"Sand":1296,"Ground":1360,"Asphalt":1376}
SIDE={"N":(0,-1),"E":(1,0),"S":(0,1),"W":(-1,0)}
IDENTITY=[[1,0,0],[0,1,0],[0,0,1]]
FLAT_CYLINDER=[[0,-1,0],[1,0,0],[0,0,1]]
def r(v): return round(float(v),3)
def rot_y(a):
    c,s=math.cos(a),math.sin(a)
    return [[r(c),0,r(s)],[0,1,0],[r(-s),0,r(c)]]
def part(name,size,pos,color,material="SmoothPlastic",orientation=None,collide=True,transparency=None,shape=None,query=True,shadow=True,attributes=None,children=None,class_name="Part"):
    props={"Anchored":True,"CanCollide":bool(collide),"CanTouch":False,"Size":{"Vector3":[r(size[0]),r(size[1]),r(size[2])]},"CFrame":{"CFrame":{"position":[r(pos[0]),r(pos[1]),r(pos[2])],"orientation":orientation or IDENTITY}},"Color":{"Color3":[r(color[0]),r(color[1]),r(color[2])]},"Material":{"Enum":MAT[material]},"TopSurface":{"Enum":0},"BottomSurface":{"Enum":0}}
    if transparency is not None: props["Transparency"]=r(transparency)
    if not query: props["CanQuery"]=False
    if not shadow: props["CastShadow"]=False
    if shape is not None: props["Shape"]={"Enum":shape}
    n={"Name":name,"ClassName":class_name,"Properties":props}
    if attributes: n["Attributes"]=attributes
    if children: n["Children"]=children
    return n
def model(name,children,attributes=None,class_name="Model"):
    n={"Name":name,"ClassName":class_name,"Children":children}
    if attributes:n["Attributes"]=attributes
    return n
def strip(name,ax,az,bx,bz,width,thick,top,color,material,**kw):
    dx,dz=bx-ax,bz-az; L=math.hypot(dx,dz); yaw=math.atan2(-dx,-dz)
    return part(name,(width,thick,L),((ax+bx)/2,top-thick/2,(az+bz)/2),color,material,orientation=rot_y(yaw),**kw)
def plot_bounds(game,p):
    t=game["Territory"]; h=t["Size"]/2
    return {"index":p["Index"],"cx":p["CenterX"],"cz":p["CenterZ"],"minX":p["CenterX"]-h,"minZ":p["CenterZ"]-h,"size":t["Size"],"y":t["SurfaceY"],"side":p["ExitSide"]}
def plot_exit(game,placement,b):
    tile=placement["RoadTileSize"]; tiles=b["size"]//tile; mid=tiles//2; side=b["side"]
    ix,iz={"N":(mid,0),"S":(mid,tiles-1),"E":(tiles-1,mid),"W":(0,mid)}[side]
    tx=b["minX"]+(ix+.5)*tile; tz=b["minZ"]+(iz+.5)*tile; vx,vz=SIDE[side]
    rim=game["Territory"]["RimWidth"]; edge_x,edge_z=b["cx"]+vx*b["size"]/2,b["cz"]+vz*b["size"]/2
    if vx==0: edge_x=tx
    else: edge_z=tz
    rim_x,rim_z=edge_x+vx*rim,edge_z+vz*rim
    c=game["Map"]["CentralIsland"]; ch=c["Size"]/2; land_x,land_z=rim_x,rim_z
    if side=="S": land_z=c["CenterZ"]-ch+c["BeachWidth"]
    elif side=="N": land_z=c["CenterZ"]+ch-c["BeachWidth"]
    elif side=="E": land_x=c["CenterX"]-ch+c["BeachWidth"]
    else: land_x=c["CenterX"]+ch-c["BeachWidth"]
    return {"side":side,"ix":ix,"iz":iz,"edge":(edge_x,edge_z),"rim":(rim_x,rim_z),"land":(land_x,land_z)}
def build_bridge(game,ex,y):
    m=game["Map"]; w=m["BridgeWidth"]; base_y=m["BaseY"]; (sx,sz),(lx,lz)=ex["rim"],ex["land"]; vx,vz=SIDE[ex["side"]]; px,pz=-vz,vx
    kids=[strip("Deck",sx,sz,lx,lz,w,.9,y+.1,m["BridgeColor"],"Concrete"),strip("Lane",sx,sz,lx,lz,w-1.6,.06,y+.16,m["BridgeAsphaltColor"],"Asphalt",collide=False)]
    for sg in (-1,1):
        ox,oz=px*sg*(w/2-.3),pz*sg*(w/2-.3); kids.append(strip("Curb",sx+ox,sz+oz,lx+ox,lz+oz,.6,.3,y+.4,m["BridgeRailColor"],"Concrete"))
        rx,rz=px*sg*(w/2+.05),pz*sg*(w/2+.05); kids.append(strip("Rail",sx+rx,sz+rz,lx+rx,lz+rz,.25,.25,y+1.5,m["BridgeRailColor"],"Metal"))
    L=math.hypot(lx-sx,lz-sz); posts=max(2,int(L//10));
    for i in range(posts+1):
        f=i/posts; cx,cz=sx+(lx-sx)*f,sz+(lz-sz)*f
        for sg in (-1,1):
            kids.append(part("Post",(.3,1.4,.3),(cx+px*sg*(w/2+.05),y+.8,cz+pz*sg*(w/2+.05)),m["BridgeRailColor"],"Metal",collide=False))
    pillars=max(2,int(L//24))
    for i in range(1,pillars):
        f=i/pillars; cx,cz=sx+(lx-sx)*f,sz+(lz-sz)*f; h=max(1,(y-.8)-base_y)
        kids.append(part("Pillar",(w-1,h,1.6) if vx==0 else (1.6,h,w-1),(cx,base_y+h/2,cz),m["BridgeColor"],"Concrete",shadow=False))
    for end_x,end_z in ((sx,sz),(lx,lz)):
        for sg in (-1,1):
            bx,bz=end_x+px*sg*(w/2+.6),end_z+pz*sg*(w/2+.6)
            kids.append(model("Lamp",[part("Pole",(.25,4,.25),(bx,y+2.1,bz),(.3,.32,.35),"Metal",collide=False),part("Bulb",(.6,.35,.6),(bx,y+4.2,bz),(1,.95,.82),"Neon",collide=False,children=[{"Name":"Light","ClassName":"PointLight","Properties":{"Range":14,"Brightness":.8,"Color":{"Color3":[1,.93,.78]}}}])]))
    return model("Bridge",kids,{"Length":r(L)})
def build_plot(game,placement,p):
    t=game["Territory"]; m=game["Map"]; b=plot_bounds(game,p); y=b["y"]; base=m["BaseY"]; island=t["Size"]+2*t["RimWidth"]
    kids=[part("Rim",(island,(y-.12)-base,island),(b["cx"],(y-.12+base)/2,b["cz"]),t["SandColor"],"Sand"),part("Ground",(t["Size"],t["Thickness"],t["Size"]),(b["cx"],y-t["Thickness"]/2,b["cz"]),t["Color"],"Grass",attributes={"PlotIndex":p["Index"]})]
    bw=t["BorderWidth"]; S=t["Size"]
    for i,(size,(ox,oz)) in enumerate([((S,.06,bw),(0,-S/2+bw/2)),((S,.06,bw),(0,S/2-bw/2)),((bw,.06,S),(-S/2+bw/2,0)),((bw,.06,S),(S/2-bw/2,0))],1): kids.append(part("Border%d"%i,size,(b["cx"]+ox,y+.03,b["cz"]+oz),t["BorderColor"],collide=False,query=False))
    ex=plot_exit(game,placement,b); w=m["BridgeWidth"]; vx,vz=SIDE[ex["side"]]; px,pz=-vz,vx; accent=(.36,.62,.9)
    ek=[strip("ExitLane",*ex["edge"],*ex["rim"],w,.4,y+.08,(.49,.5,.53),"Concrete"),strip("ExitAsphalt",*ex["edge"],*ex["rim"],w-1.6,.05,y+.13,m["BridgeAsphaltColor"],"Asphalt",collide=False)]
    for sg in (-1,1):
        gx,gz=ex["edge"][0]+px*sg*(w/2+.6),ex["edge"][1]+pz*sg*(w/2+.6); ek.append(part("GatePost",(.6,3.4,.6),(gx,y+1.7,gz),accent,collide=False))
    ek.append(part("GateBeam",(w+1.8,.45,.45) if vx==0 else (.45,.45,w+1.8),(ex["edge"][0],y+3.4,ex["edge"][1]),(.97,.98,1),collide=False)); ek.append(build_bridge(game,ex,y))
    kids.append(model("Exit",ek,{"ExitSide":ex["side"],"ExitIx":ex["ix"],"ExitIz":ex["iz"]})); kids.append(part("OwnerSign",(1,1,1),(b["cx"],y+20,b["cz"]),(1,1,1),collide=False,transparency=1,query=False,shadow=False))
    return model("Plot_%d"%p["Index"],kids,{"PlotIndex":p["Index"],"OwnerUserId":0})
def dist_seg(px,pz,ax,az,bx,bz):
    dx,dz=bx-ax,bz-az; L2=dx*dx+dz*dz; t=0 if L2==0 else max(0,min(1,((px-ax)*dx+(pz-az)*dz)/L2)); return math.hypot(px-(ax+t*dx),pz-(az+t*dz))
def build_central(game,placement):
    m=game["Map"]; c=m["CentralIsland"]; d=m["Decorations"]; rng=random.Random(d["Seed"]); cx,cz,size=c["CenterX"],c["CenterZ"],c["Size"]; base=m["BaseY"]; inner=size-2*c["BeachWidth"]; kids=[part("Beach",(size,-.15-base,size),(cx,(-.15+base)/2,cz),game["Territory"]["SandColor"],"Sand"),part("Ground",(inner,-base,inner),(cx,base/2,cz),c["Color"],"Grass")]
    paths=[]; segs=[]; pw=d["PathWidth"]; plaza=c["PlazaRadius"]
    def poly(pts,width):
        for a,b in zip(pts,pts[1:]):
            segs.append((*a,*b)); paths.append(strip("Path",a[0],a[1],b[0],b[1],width,.08,.05,d["PathColor"],"Ground",collide=False)); paths.append(part("PathJoint",(width,.08,width),(b[0],.01,b[1]),d["PathColor"],"Ground",orientation=rot_y(math.pi/4),collide=False))
    for p in m["Plots"]:
        ex=plot_exit(game,placement,plot_bounds(game,p)); lx,lz=ex["land"]; pts=[(lx,lz)]; steps=9
        for i in range(1,steps):
            f=i/steps; x,z=lx+(cx-lx)*f,lz+(cz-lz)*f; jitter=3.5*math.sin(f*math.pi); pts.append((x+rng.uniform(-jitter,jitter),z+rng.uniform(-jitter,jitter)))
        vx,vz=cx-lx,cz-lz; L=math.hypot(vx,vz); pts.append((cx-vx/L*plaza,cz-vz/L*plaza)); poly(pts,pw+rng.uniform(-.3,.4))
    rr=inner*.3; ring=[]
    for i in range(33):
        a=i/32*math.pi*2; rad=rr+rng.uniform(-4,4); ring.append((cx+math.cos(a)*rad,cz+math.sin(a)*rad))
    ring[-1]=ring[0]; poly(ring,pw-.6)
    paths.append(part("Plaza",(.1,plaza*2,plaza*2),(cx,.04,cz),d["PathColor"],"Ground",orientation=FLAT_CYLINDER,shape=2,collide=False)); kids.append(model("Paths",paths,class_name="Folder"))
    lim=inner/2-6; occupied=[]
    def spot(clear):
        for _ in range(500):
            x=cx+rng.uniform(-lim,lim); z=cz+rng.uniform(-lim,lim)
            if math.hypot(x-cx,z-cz)<plaza+8: continue
            if any(dist_seg(x,z,*q)<pw/2+clear for q in segs): continue
            if any(math.hypot(x-ox,z-oz)<clear+orad for ox,oz,orad in occupied): continue
            occupied.append((x,z,clear)); return x,z
    trees=[]
    for i in range(d["Trees"]):
        q=spot(2.5)
        if not q: break
        x,z=q; sc=rng.uniform(.9,1.5); th=2.4*sc; trunk=part("Trunk",(.55*sc,th,.55*sc),(x,th/2,z),(.59,.44,.31),"Wood",collide=False); pcs=[trunk]
        if i%3==0:
            col=(.33,.55+rng.randint(0,24)/255,.36)
            for k,(wd,ht) in enumerate(((2.6,1.3),(1.9,1.2),(1.1,1.1))): pcs.append(part("Needles",(wd*sc,ht*sc,wd*sc),(x,th+(0.4+k*1.05)*sc,z),col,orientation=rot_y(rng.uniform(0,1.5)),collide=False))
        else:
            col=(.44+rng.randint(0,24)/400,.64+rng.randint(0,24)/255,.38); top=(min(1,col[0]+.06),min(1,col[1]+.06),min(1,col[2]+.06)); pcs += [part("Leaves",(2.4*sc,1.7*sc,2.4*sc),(x,th+.6*sc,z),col,orientation=rot_y(rng.uniform(0,1.5)),collide=False),part("LeavesTop",(1.5*sc,1.1*sc,1.5*sc),(x,th+1.8*sc,z),top,orientation=rot_y(rng.uniform(0,1.5)),collide=False)]
        trees.append(model("Tree",pcs))
    bushes=[]
    for _ in range(d["Bushes"]):
        q=spot(1.2)
        if not q: break
        x,z=q; sc=rng.uniform(.7,1.2); col=(.38,.6+rng.uniform(0,.08),.34); pcs=[part("Bush",(1.4*sc,.8*sc,1.2*sc),(x,.4*sc,z),col,"LeafyGrass",orientation=rot_y(rng.uniform(0,3)),collide=False)]
        if rng.random()<.5: pcs.append(part("Bush",(.9*sc,.6*sc,.9*sc),(x+.5*sc,.5*sc,z+.3*sc),(col[0]+.05,col[1]+.05,col[2]),"LeafyGrass",collide=False))
        bushes.append(model("Bush",pcs))
    rocks=[]
    for _ in range(d["Rocks"]):
        q=spot(1.6)
        if not q: break
        x,z=q; sc=rng.uniform(.7,1.7); g=rng.uniform(.62,.74); pcs=[part("Rock",(1.6*sc,.9*sc,1.3*sc),(x,.3*sc,z),(g,g+.01,g+.03),"Slate",orientation=rot_y(rng.uniform(0,3)))]
        if rng.random()<.4: pcs.append(part("Pebble",(.7*sc,.4*sc,.6*sc),(x+1.1*sc,.15*sc,z-.4*sc),(g-.05,g-.04,g-.02),"Slate",orientation=rot_y(rng.uniform(0,3)),collide=False))
        rocks.append(model("Rock",pcs))
    kids += [model("Trees",trees,class_name="Folder"),model("Bushes",bushes,class_name="Folder"),model("Rocks",rocks,class_name="Folder"),{"Name":"LobbySpawn","ClassName":"SpawnLocation","Properties":{"Anchored":True,"Neutral":True,"Duration":0,"CanTouch":True,"Size":{"Vector3":[8,.4,8]},"CFrame":{"CFrame":{"position":[0,.2,0],"orientation":IDENTITY}},"Color":{"Color3":[.8,.9,1]},"Material":{"Enum":MAT["SmoothPlastic"]},"TopSurface":{"Enum":0}}}]
    return model("CentralIsland",kids,{"Purpose":"Future land battles"})
def build_boundaries(game):
    bd=game["Map"]["Boundary"]; h,half,th=bd["Height"],bd["HalfSize"],bd["Thickness"]; y=game["Map"]["BaseY"]-6+h/2; span=half*2+th*2; kids=[]
    for n,size,pos in [("North",(span,h,th),(0,y,-half-th/2)),("South",(span,h,th),(0,y,half+th/2)),("West",(th,h,span),(-half-th/2,y,0)),("East",(th,h,span),(half+th/2,y,0))]: kids.append(part(n,size,pos,(1,1,1),transparency=1,query=False,shadow=False))
    return model("Boundaries",kids,{"HalfSize":half,"Invisible":True})
def generate():
    game=json.loads((CONFIG/"GameConfig.json").read_text()); placement=json.loads((CONFIG/"PlacementConfig.json").read_text()); files={"CentralIsland.model.json":build_central(game,placement),"Boundaries.model.json":build_boundaries(game)}
    for p in game["Map"]["Plots"]: files[f"Plots/Plot_{p['Index']}.model.json"]=build_plot(game,placement,p)
    return {rel:json.dumps({k:v for k,v in node.items() if k!="Name"},separators=(",",":"),sort_keys=False)+"\n" for rel,node in files.items()}
def count_parts(n): return (1 if n.get("ClassName") in ("Part","SpawnLocation") else 0)+sum(count_parts(c) for c in n.get("Children",[]))
def main():
    files=generate(); OUT.mkdir(parents=True,exist_ok=True); total=0
    if '--check' in sys.argv:
        stale=[r for r,t in files.items() if not (OUT/r).is_file() or (OUT/r).read_text()!=t]
        print('static map up to date' if not stale else 'STALE static map files: '+str(stale)); return 0 if not stale else 1
    for rel,text in files.items():
        p=OUT/rel; p.parent.mkdir(parents=True,exist_ok=True); p.write_text(text); total+=count_parts(json.loads(text))
    print(f'generated {len(files)} static map files / {total} parts'); return 0
if __name__=='__main__': sys.exit(main())
