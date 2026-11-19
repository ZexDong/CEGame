"""Independent session/input evaluator. Retained projects are never edited."""
import argparse,copy,hashlib,json,math,os,re,shutil,subprocess,time,traceback
from pathlib import Path
import xml.etree.ElementTree as ET
from PIL import Image,ImageStat
EXCLUDED={".git","Library","Temp","TempHost","Logs","UserSettings","obj","Obj","bin","__pycache__"}
def write(path,value):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(value,ensure_ascii=False,indent=2),encoding="utf-8")
def digest(root):
    return [{"path":p.relative_to(root).as_posix(),"sha256":hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(root.rglob("*")) if p.is_file() and not set(p.relative_to(root).parts)&EXCLUDED]
def evaluator_digest(root):
    return digest(root)
class ProductError(Exception):pass
class InfrastructureError(Exception):pass
def nums(x):
    out={}
    for v in x or []:
        if v["name"] in out or not math.isfinite(v["value"]):raise ProductError("Duplicate/nonfinite number")
        out[v["name"]]=v["value"]
    return out
def n(s,key):
    try:return nums(s["values"])[key]
    except KeyError:raise ProductError("Missing published field "+key)
def sn(s,key,value):
    for row in s["values"]:
        if row["name"]==key:row["value"]=value;return
    raise ProductError("Cannot edit missing published field "+key)
def actor(s,id):
    found=[a for a in s["actors"] if a["id"]==id]
    if len(found)!=1:raise ProductError("Required real actor identity absent/duplicate: "+id)
    return found[0]
def pos(a,x,y,z=0):a["position"]={"x":x,"y":y,"z":z}
def xyz(a):return tuple(a["position"][k] for k in ("x","y","z"))
def distance(a,b):return math.dist(xyz(a),xyz(b))
def public(s):
    q=copy.deepcopy(s);q.pop("opaqueData",None)
    q["values"].sort(key=lambda x:x["name"]);q["actors"].sort(key=lambda x:x["id"])
    for a in q["actors"]:a["values"].sort(key=lambda x:x["name"])
    return q
def equivalent(a,b):
    # Unity stores poses as float32. Decimal fixture coordinates must not
    # become candidate defects merely because their JSON round-trip expands.
    if isinstance(a,(int,float)) and isinstance(b,(int,float)):return math.isclose(a,b,rel_tol=1e-6,abs_tol=1e-4)
    if type(a)!=type(b):return False
    if isinstance(a,dict):return a.keys()==b.keys() and all(equivalent(a[k],b[k]) for k in a)
    if isinstance(a,list):return len(a)==len(b) and all(equivalent(x,y) for x,y in zip(a,b))
    return a==b
def text(r):
    return re.sub(r"<[^>]+>",""," ".join(x.get("text") or "" for x in r.get("ui") or [] if x["active"] and x["color"]["a"]>.1 and x.get("shaderValid",False)))
def fact(r,id):
    return next((a for a in r.get("actors") or [] if a["id"]==id),{})
def visible(r,id):
    a=fact(r,id)
    return bool(a.get("active") and a.get("onScreen") and (a.get("renderers",0)>0 or a.get("graphics")))
def visible_number(r,value):
    return any(abs(float(x)-value)<=(.51 if value!=int(value) else 1e-6) for x in re.findall(r"(?<![\d.])\d+(?:\.\d+)?(?![\d.])",text(r)))
def hud_number(r,label,value):
    # Semantic currency icons are ordinary readable HUDs, not missing labels.
    aliases={"stars":r"stars?|★|☆|⭐","potions":r"potions?|flasks?|pot|🧪|⚗","shield":r"shield|shd|🛡"}
    token="(?:"+aliases.get(label,re.escape(label))+r")\ufe0f?"
    number=r"(\d+(?:\.\d+)?)";rendered=text(r)
    candidates=re.findall(token+r"\s*[::]?\s*"+number,rendered,re.I)+re.findall(number+r"\s*"+token,rendered,re.I)
    return any(abs(float(x)-value)<=(.51 if label=="shield" else 1e-6) for x in candidates)

class Player:
    def __init__(self,exe,folder,clear):
        self.exe,self.folder,self.serial=exe,folder,0;folder.mkdir(parents=True)
        self.process=subprocess.Popen([str(exe),"-screen-width","1280","-screen-height","720","-screen-fullscreen","0","-logFile",str(folder/"player.log"),"--session-eval-root",str(folder),"--session-eval-clear","yes" if clear else "no"],creationflags=subprocess.CREATE_NO_WINDOW)
        self.last=self.call("observe",timeout=90)
    def call(self,action,timeout=30,**args):
        self.serial+=1;request=dict(id=self.serial,action=action,seconds=.04);request.update(args)
        write(self.folder/"request.tmp",request);os.replace(self.folder/"request.tmp",self.folder/("request-%d.json"%self.serial))
        end=time.monotonic()+timeout
        while time.monotonic()<end:
            if self.process.poll() is not None:raise InfrastructureError("Player exited before reply: "+str(self.folder))
            try:
                r=json.loads((self.folder/("reply-%d.json"%self.serial)).read_text(encoding="utf-8-sig"))
                if r["id"]==self.serial:
                    with (self.folder/"receipts.jsonl").open("a",encoding="utf-8") as f:f.write(json.dumps(dict(request=request,reply=r),ensure_ascii=False)+"\n")
                    self.last=r
                    if r["status"]=="PRODUCT_ERROR":raise ProductError(r["error"])
                    if r["status"]!="OK":raise InfrastructureError(r.get("error","Host error"))
                    return r
            except (FileNotFoundError,PermissionError,json.JSONDecodeError):pass
            time.sleep(.02)
        raise InfrastructureError("IPC response timeout: "+action)
    def close(self):
        if self.process.poll() is None:
            self.serial+=1;write(self.folder/"request.tmp",dict(id=self.serial,action="quit",seconds=0));os.replace(self.folder/"request.tmp",self.folder/("request-%d.json"%self.serial))
            try:self.process.wait(timeout=15)
            except subprocess.TimeoutExpired:self.process.kill();self.process.wait()

class Evaluation:
    def __init__(self,ev,project,output,editor,bridge=True,reuse=None):
        self.ev,self.project,self.out,self.editor,self.bridge=ev,project,output,editor,bridge
        self.rules=json.loads((ev/"rules.json").read_text(encoding="utf-8-sig"));self.game=self.rules["game"]
        # Expected content is evaluator-owned and hash-bound, never selected by
        # a candidate's editable copy of the public input files.
        self.model=json.loads((ev/"spec/SESSION_MODEL.json").read_text(encoding="utf-8-sig"));self.content=json.loads((ev/"spec/CONTENT.json").read_text(encoding="utf-8-sig"))
        self.leaves={r["id"]:dict(id=r["id"],dimension=r["dimension"],state="INCONCLUSIVE_EVALUATOR",observations=[]) for r in self.rules["leaves"]}
        self.p=None;self.context="";self.failure=None;self.xml={};self.reuse=reuse
    def record(self,id,state,detail):
        row=self.leaves[id]
        # Every declared sub-obligation is required; a later successful case
        # cannot hide a previously observed failure or provider uncertainty.
        old=row["state"] if row["observations"] else "PASS"
        priority={"PASS":0,"BLOCKED_BY_PRODUCT":1,"FAIL_OBSERVED":2,"INCONCLUSIVE_EVALUATOR":3}
        row["state"]=max((old,state),key=lambda q:priority[q])
        last=self.p.last if self.p else {}
        row["observations"].append(dict(scenario=self.context,state=state,detail=detail,receipt_id=self.p.serial if self.p else None,process_id=last.get("processId"),frame=last.get("frame"),input_events=last.get("inputEvents")))
    def check(self,id,okay,detail):self.record(id,"PASS" if okay else "FAIL_OBSERVED",detail)
    def scenario(self,name,ids,fn):
        self.context=name
        try:fn()
        except (ProductError,InfrastructureError) as ex:
            for id in ids:self.record(id,"BLOCKED_BY_PRODUCT" if isinstance(ex,ProductError) else "INCONCLUSIVE_EVALUATOR",str(ex))
        except Exception:
            for id in ids:self.record(id,"INCONCLUSIVE_EVALUATOR",traceback.format_exc())
        self.save()
    def validate(self,r):
        if r.get("serviceError"):raise ProductError(r["serviceError"])
        s=r.get("save")
        if not s:raise ProductError("Required service returned no snapshot")
        if s.get("contract")!="game-session/v1" or s.get("contentVersion")!=self.model["contentVersion"] or s.get("entryId") not in self.model["entries"] or s.get("phase") not in self.model["phases"]:raise ProductError("Snapshot identity/phase is not published vocabulary")
        values=nums(s.get("values"))
        if set(values)!={x["name"] for x in self.model["values"]}:raise ProductError("Wrong published top-level numeric set")
        for rule in self.model["values"]:
            v=values[rule["name"]]
            if not rule["minimum"]<=v<=rule["maximum"] or rule["integer"] and v!=int(v):raise ProductError("Number range violation: "+rule["name"])
        kinds={x["kind"]:x["states"] for x in self.model["actorKinds"]};ids=set();objects=set()
        for a in s.get("actors") or []:
            if a["id"] in ids:raise ProductError("Duplicate actor identity")
            ids.add(a["id"]);nums(a["values"])
            if a["kind"] not in kinds or a["state"] not in kinds[a["kind"]] or a["entryId"]!=s["entryId"] or a["facing"] not in [-1,1]:raise ProductError("Invalid actor vocabulary")
            if a["present"]:
                f=fact(r,a["id"])
                if not f or f.get("error") or not f.get("active"):raise ProductError("Present actor has no real active root: "+a["id"])
                if math.dist(xyz(a),xyz(f))>.025:raise ProductError("Public pose disagrees with actual transform: "+a["id"])
                if f["instanceId"] in objects:raise ProductError("Two IDs alias one reporting object")
                objects.add(f["instanceId"])
        return s
    def validate_schema(self,r):
        s=self.validate(r)
        fields=(
            {"enemy":{"hp","damage","potions","energy","infection","infection_turns"},"beetle":{"hp","damage","potions","energy","infection","infection_turns"}} if self.game=="fungus" else
            {"cell":{"hp","clock"},"enemy":{"hp","attack_clock","jumped"},"projectile":{"damage","speed"}} if self.game=="glitch" else
            {"racer":{"vx","vy","vz"}})
        for a in s.get("actors") or []:
            if set(nums(a.get("values")))!=fields.get(a["kind"],set()):
                raise ProductError("Published actor numeric set missing/extra: "+a["id"])
        return s
    def fresh(self,entry=None):
        self.p.call("reset",seconds=0)
        r=self.p.call("open",entry=entry or self.model["entries"][0],seed=20261029,seconds=0)
        before=self.validate(r);after=self.validate(self.p.call("observe",seconds=.12))
        if not equivalent(public(before),public(after)):raise ProductError("Completed entry advanced before release")
        # Distinguish malformed *candidate-owned* initial output from an
        # invalid author edit. Otherwise a bad pending-wave state was being
        # mislabeled "Author invented pending old wave".
        try:self.legal_setup(before)
        except InfrastructureError as ex:raise ProductError("Candidate normal entry violates published state rules: "+str(ex)) from ex
        return r
    def setup(self,edit,entry=None):
        r=self.fresh(entry);save=copy.deepcopy(self.validate(r));save["actors"]=[a for a in save["actors"] if a["kind"]!="control"]
        return self.restore_preparation(save,edit)
    def setup_from_snapshot(self,source,edit):
        # A genuine candidate-owned, recently damaged history can establish a
        # cooldown without inventing implementation-private opaque fields.
        save=copy.deepcopy(source);save["actors"]=[a for a in save["actors"] if a["kind"]!="control"]
        self.p.call("reset",seconds=0)
        return self.restore_preparation(save,edit)
    def restore_preparation(self,save,edit):
        edit(save);self.legal_setup(save)
        r=self.p.call("restore",save=save,seconds=0);actual=self.validate(r)
        # Published control identities can legitimately change with phase/loadout.
        expected=public(save);actual=public(actual)
        for q in [expected,actual]:q["actors"]=[a for a in q["actors"] if a["kind"]!="control"]
        if not equivalent(expected,actual):raise ProductError("Legal public edits did not round-trip")
        self.p.call("begin",seconds=0);return r
    def legal_setup(self,s):
        # The author-owned validation is separate from acceptance of Restore.
        if s["phase"]!="playing":raise InfrastructureError("Author fixture must not set scored terminal outcome")
        if self.game=="fungus":
            floor=self.content["floors"][int(n(s,"floor"))-1];live=set()
            if n(s,"hp")<=0 or (n(s,"infection")==0)!=(n(s,"infection_turns")==0):raise InfrastructureError("Illegal author HP/infection")
            for a in s["actors"]:
                if a["kind"]=="enemy":
                    definition=next((e for e in floor["enemies"] if e["id"]==a["id"]),None)
                    if definition is None or not 0<=n(a,"hp")<=definition["hp"] or n(a,"damage")!=definition["damage"] or n(a,"potions")!=definition["potions"]:
                        raise InfrastructureError("Author fixture changed fixed enemy identity/tuning")
                if a["kind"] in ["player","enemy","beetle"] and a["present"]:
                    x,y,z=xyz(a)
                    if int(x)!=x or int(y)!=y or z!=0 or not 0<=x<12 or not 0<=y<10 or floor["rows"][9-int(y)][int(x)]=="#" or (x,y) in live:raise InfrastructureError("Illegal author grid overlap/wall")
                    live.add((x,y))
            if n(s,"kills")!=sum(a["kind"]=="enemy" and not a["present"] for a in s["actors"]):raise InfrastructureError("Author kill history mismatch")
        elif self.game=="glitch":
            level=self.content["levels"][int(n(s,"level"))-1];spawn=int(n(s,"spawn_index"))
            if n(s,"lives")<=0 or spawn>len(level["waves"]):raise InfrastructureError("Illegal author lives/spawn count")
            for i,w in enumerate(level["waves"]):
                a=actor(s,w["id"])
                if i>=spawn and (a["state"]!="pending" or w["time"]<n(s,"elapsed")):raise InfrastructureError("Author invented pending old wave")
                if a["position"]["y"]!=w["lane"]+1:raise InfrastructureError("Author fixture changed fixed enemy lane")
        else:
            tr=self.content["tracks"][int(n(s,"track"))-1];car=self.content["vehicles"][int(n(s,"vehicle"))];a=actor(s,"racer")
            if not 0<n(s,"shield")<=car["shield"] or n(s,"next_gate")>=3 or abs(a["position"]["x"])>5.5 or not 2<=a["position"]["z"]<=tr["length"]+2:raise InfrastructureError("Illegal author race state")
            if abs(a["position"]["y"]-self.height(tr,a["position"]["z"])-car["hover_height"])>.15:raise InfrastructureError("Author racer is not hovering on current terrain")
    def key(self,key,seconds=.02,**args):
        r=self.p.call("key",key=key,seconds=seconds,**args)
        if not r.get("inputDelivered"):raise InfrastructureError("Keyboard event delivery not independently verified")
        return r
    def click(self,id=None,label=None,seconds=.04):
        r=self.p.call("click",actor=id,label=label,seconds=seconds)
        if not r.get("inputDelivered"):raise InfrastructureError("Mouse event delivery/raycast not verified")
        return r
    def start(self):
        # Labels/layout are not specified implementation details. Use the
        # published identity to locate the genuine ordinary Start control.
        r=self.p.last
        if not r.get("serviceError") and any(a["id"]=="start" and a["present"] for a in (r.get("save") or {}).get("actors",[])):
            return self.click("start")
        return self.click(label="Play|New Game|Start|Begin|Start Race|New Expedition")
    def return_menu(self):
        # Menu may legitimately be exposed only on the pause screen.
        s=self.p.last.get("save") or {}
        present=any(a["id"]=="menu" and a["present"] for a in s.get("actors",[]))
        if not present and s.get("phase")=="playing":self.key("Escape")
        return self.click("menu")
    def idle(self,seconds=.1,**kw):return self.p.call("observe",seconds=seconds,**kw)
    @staticmethod
    def height(t,z):
        if z<t["ramp_start"] or z>t["ramp_end"]:return 0
        return (z-t["ramp_start"])/(t["ramp_peak"]-t["ramp_start"])*t["ramp_height"] if z<t["ramp_peak"] else (t["ramp_end"]-z)/(t["ramp_end"]-t["ramp_peak"])*t["ramp_height"]
    def race_setup(self,s,z=2,x=0,speed=0,vehicle=0,gate=0,shield=None):
        t=self.content["tracks"][int(n(s,"track"))-1];v=self.content["vehicles"][vehicle]
        sn(s,"vehicle",vehicle);sn(s,"shield",v["shield"] if shield is None else shield);sn(s,"countdown",0);sn(s,"speed",speed);sn(s,"next_gate",gate);sn(s,"boost",0);sn(s,"steer",0)
        a=actor(s,"racer");pos(a,x,self.height(t,z)+v["hover_height"],z);sn(a,"vx",0);sn(a,"vy",0);sn(a,"vz",speed)
        for i in range(3):actor(s,"gate_"+str(i))["state"]="passed" if i<gate else "pending"
        bonus=100*sum(a["kind"]=="ring" and a["state"]=="collected" for a in s["actors"])
        sn(s,"score",bonus+(math.floor(z-2) if n(s,"mode")==1 else 0))
    def race_contact(self,entry=None):
        ob=self.content["tracks"][0]["obstacles"][0]
        self.setup(lambda s:self.race_setup(s,z=ob["z"]-6,x=ob["x"],speed=10),entry)
        r=self.key("W",.04,label="hold");s=self.validate(r);deadline=time.monotonic()+2
        while n(s,"shield")==100 and time.monotonic()<deadline:r=self.idle(.04);s=self.validate(r)
        if n(s,"shield")>=100:raise ProductError("Real normal approach did not produce required contact")
        self.contact_observed_time=r["time"]
        self.p.call("release",seconds=0)
        return self.validate(self.p.last)
    def polyrace(self):
        def motion():
            self.fresh();self.p.call("begin",seconds=0);s=self.validate(self.key("W",.25))
            self.check("d3.motion",n(s,"speed")==0 and actor(s,"racer")["position"]["z"]==2 and n(s,"elapsed")==0,"Countdown blocks racing input")
            for entry in self.model["entries"]:
                for v in self.content["vehicles"]:
                    self.setup(lambda s:self.race_setup(s,vehicle=v["id"]),entry)
                    r0=self.key("W",.08,label="hold");s0=self.validate(r0)
                    r=self.idle(.2);s=self.validate(r)
                    self.check("d2.motion",actor(s,"racer")["position"]["z"]>2 and visible(r,"racer") and n(s,"vehicle")==v["id"],"Every track/mode/craft has actual motion")
                    dt=n(s,"elapsed")-n(s0,"elapsed");dv=n(s,"speed")-n(s0,"speed")
                    if dt<=0:raise ProductError("Elapsed time did not advance during held throttle")
                    self.check("d3.motion",abs(dv-v["acceleration"]*dt)<=max(.15,.08*v["acceleration"]*dt),"Craft-specific acceleration over two observations with throttle continuously held; excludes pre-input and release frames")
                    self.p.call("release",seconds=0)
            self.setup(lambda s:self.race_setup(s,speed=12));s=self.validate(self.key("S",.25));self.check("d3.motion",n(s,"speed")<9,"Brake decelerates actual velocity")
            self.setup(lambda s:self.race_setup(s));r=self.key("D",.25);s=self.validate(r);self.check("d3.motion",actor(s,"racer")["position"]["x"]>.8 and xyz(actor(s,"racer"))==xyz(fact(r,"racer")),"Steering changes actual craft transform")
        self.scenario("tracks crafts countdown acceleration steering brake",["d2.motion","d3.motion"],motion)
        def boost():
            self.setup(lambda s:self.race_setup(s))
            r0=self.key("W,LeftShift",.08,label="hold");s0=self.validate(r0)
            r=self.idle(.2,capture="boost.png");s=self.validate(r)
            self.check("d2.boost",n(s,"boost")==1 and visible(r,"racer"),"Held normal Shift produces actual boosted racing")
            dt=n(s,"elapsed")-n(s0,"elapsed");dv=n(s,"speed")-n(s0,"speed");expected=self.content["vehicles"][0]["acceleration"]*1.5*dt
            self.check("d3.boost",dt>0 and n(s,"shield")==100 and abs(dv-expected)<=max(.15,.08*expected),"Boosted acceleration over continuously held observations is1.5x; no continuous shield drain")
            self.p.call("release",seconds=0)
            for boosting,cost in [(False,15),(True,30)]:
                def edit(s):
                    # Leave enough real approach distance that IPC between begin
                    # and input cannot cause an unboosted pre-input collision.
                    ob=self.content["tracks"][0]["obstacles"][0];self.race_setup(s,z=ob["z"]-6,x=ob["x"],speed=10)
                self.setup(edit);r=self.key("W,LeftShift" if boosting else "W",.04,label="hold");s=self.validate(r)
                deadline=time.monotonic()+2
                while n(s,"shield")==100 and time.monotonic()<deadline:
                    r=self.idle(.04);s=self.validate(r)
                self.check("d3.boost",abs(n(s,"shield")-(100-cost))<.05,"Boosted spatial collision doubles normal shield debit")
                self.check("d2.shield",n(s,"shield")<100 and visible(r,"racer"),"Visible actual craft/obstacle contact causes shield loss")
                self.check("d5.feedback",bool(re.search("shield|impact|collision|damage",text(r),re.I)) and hud_number(r,"shield",n(s,"shield")),"Impact has actual truthful HUD/feedback, independent of cost correctness")
                self.p.call("release",seconds=0)
        self.scenario("boost and doubled contact cost",["d2.boost","d3.boost","d2.shield","d5.feedback"],boost)
        def shields():
            s=self.race_contact();debit=n(s,"shield")
            self.key("A,S",.42,label="hold");self.p.call("release",seconds=0)
            s=self.validate(self.idle(.3))
            if self.p.last["time"]-self.contact_observed_time>=1.7:raise InfrastructureError("Cooldown probe exceeded known recent-contact window")
            self.check("d3.shield",n(s,"shield")==debit,"No regeneration within2s of a real normal-input collision; no assumed opaque initial timer")
            s=self.validate(self.idle(2));self.check("d3.shield",debit<n(s,"shield")<=100,"Delayed regeneration after leaving contact respects capacity")
            def loss(s):
                ob=self.content["tracks"][0]["obstacles"][0];self.race_setup(s,z=ob["z"]-2,x=ob["x"],speed=15,shield=10)
            self.setup(loss);r=self.key("W",.18);s=self.validate(r);self.check("d3.shield",n(s,"shield")==0 and s["phase"]=="lost","Lethal physical contact enters defeat")
            self.check("d4.journey",s["phase"]=="lost","Race has reachable real defeat")
            r=self.click("restart");s=self.validate(r);self.check("d4.restart",n(s,"shield")==100 and n(s,"speed")==0 and n(s,"countdown")>2,"Defeat retry restores a clean countdown and vehicle")
        self.scenario("shield delay capacity and loss",["d3.shield","d4.journey","d4.restart"],shields)
        def terrain():
            for track in self.content["tracks"]:
                z=track["ramp_peak"]-.8
                self.setup(lambda s:self.race_setup(s,z=z,speed=5,gate=1),"track_%d_time"%track["id"]);r=self.key("W",.2);s=self.validate(r);a=actor(s,"racer")
                self.check("d2.terrain",visible(r,"racer") and a["position"]["y"]>2 and bool(fact(r,"road").get("renderers")),"Real raised ramp and hovering craft")
                self.check("d3.terrain",abs(a["position"]["y"]-self.height(track,a["position"]["z"])-1)<.15,"Actual craft follows published ramp height")
            for gate in range(3):
                tr=self.content["tracks"][0]
                self.setup(lambda s:self.race_setup(s,z=tr["gates"][gate]-.7,speed=10,gate=gate));r=self.key("W",.12);s=self.validate(r)
                self.check("d3.terrain",n(s,"next_gate")==gate+1 and actor(s,"gate_"+str(gate))["state"]=="passed","Normal forward crossing passes correct ordered gate")
        self.scenario("ramps and ordered gate planes",["d2.terrain","d3.terrain"],terrain)
        def pickups():
            ring=self.content["tracks"][0]["rings"][0]
            # Establish the damage cooldown with actual input, then preserve
            # that candidate's opaque timer while legally positioning a pickup
            # approach. A fresh full-shield entry need not start its regen delay.
            history=self.race_contact("track_1_distance")
            def approach(s):
                self.race_setup(s,z=ring["z"]-2,x=ring["x"],speed=8,shield=60)
                sn(s,"score",math.floor(ring["z"]-4))
            self.setup_from_snapshot(history,approach);r=self.key("W",.2);s=self.validate(r)
            if r["time"]-self.contact_observed_time>=1.7:raise InfrastructureError("Pickup preparation exceeded real contact cooldown window")
            self.check("d2.pickups",actor(s,"ring_0")["state"]=="collected" and not fact(r,"ring_0").get("active",False),"Real ring disappears after spatial collection")
            bonus=lambda s:n(s,"score")-math.floor(actor(s,"racer")["position"]["z"]-2)
            self.check("d3.pickups",bonus(s)==100 and abs(n(s,"shield")-70)<.05,"Exactly100 ring bonus above published Distance Sprint distance score, and10 shield without regen confound")
            self.check("d5.hud",visible_number(r,n(s,"score")) and hud_number(r,"shield",n(s,"shield")),"HUD truthfully displays actual points/shield independently of mechanic correctness")
            after=self.validate(self.key("W",.15));self.check("d3.pickups",bonus(after)==100,"Already collected ring cannot reward twice despite increasing distance points")
            def wrong(s):
                self.race_setup(s,z=ring["z"]-2,x=3,speed=8);sn(s,"score",math.floor(ring["z"]-4))
            self.setup(wrong,"track_1_distance");s=self.validate(self.key("W",.2));self.check("d3.pickups",actor(s,"ring_0")["state"]=="active" and bonus(s)==0,"Wrong-lane pass grants no ring bonus; ordinary distance points allowed")
        self.scenario("spatial collectible and one-shot reward",["d2.pickups","d3.pickups","d5.hud"],pickups)
        def race():
            for entry in self.model["entries"]:
                tr=self.content["tracks"][int(entry.split("_")[1])-1]
                def edit(s):self.race_setup(s,z=tr["length"]-.7,speed=10,gate=2);sn(s,"elapsed",12)
                self.setup(edit,entry);r=self.key("W",.12,capture=entry+"-finish.png");s=self.validate(r)
                self.check("d2.race",s["phase"]=="won" and n(s,"best_time")>0,"All finite track/mode outcomes and record")
                self.check("d4.journey",s["phase"]=="won","Final gate causes legitimate finish")
                if int(n(s,"track"))<3:
                    r=self.click("next");ss=self.validate(r);self.check("d4.journey",n(ss,"track")==n(s,"track")+1 and n(ss,"countdown")>2,"Next enters adjacent track normally")
            tr=self.content["tracks"][0];self.setup(lambda s:self.race_setup(s,z=tr["length"]-.7,speed=10,gate=0));s=self.validate(self.key("W",.12));self.check("d3.race",s["phase"]=="playing" and n(s,"next_gate")==0,"Missing earlier gates prevents finish")
            def timeout(s):self.race_setup(s);sn(s,"elapsed",self.content["tracks"][0]["time_limit"]-.1)
            self.setup(timeout,"track_1_distance");s=self.validate(self.idle(.25));self.check("d3.race",s["phase"]=="lost","Distance Sprint timeout is real defeat")
            r=self.click("restart");s=self.validate(r);self.check("d4.restart",n(s,"elapsed")==0 and n(s,"countdown")>2 and n(s,"next_gate")==0,"Timeout retry resets race lifecycle")
        self.scenario("six finite races final gates next timeout",["d2.race","d3.race","d4.journey","d4.restart"],race)
    def lifecycle(self):
        def natural_start():
            self.p.call("reset");r=self.idle(.05,capture="menu.png")
            if not r.get("ui"):
                self.record("d5.controls","FAIL_OBSERVED","Required real uGUI control/text delivery is absent; this does not assert that arbitrary IMGUI pixels contain no text")
                self.record("d5.overlays","BLOCKED_BY_PRODUCT","No required uGUI presentation available for instruction/overlay observation; do not misreport IMGUI text as visibly absent")
                self.leaves["d5.overlays"]["observations"][-1]["blocked_by"]=["d5.controls"]
            else:
                self.check("d5.overlays",bool(re.search("move|wasd|arrow|select|acceler|shift|click|instructions|controls|help",text(r),re.I)),"Menu presents control instructions or a discoverable instructions control; no fixed wording/layout")
            r=self.start();s=self.validate(r)
            self.check("d4.entry",s["phase"]=="playing","Natural button enters actual game")
            self.check("d5.controls",s["phase"]=="playing","Normal mouse hit real visible Start button and caused its advertised transition")
        self.scenario("natural menu and start",["d4.entry","d5.controls"],natural_start)
        def ensure_play():
            if (self.p.last.get("save") or {}).get("phase")!="playing":
                self.fresh();self.p.call("begin",seconds=0)
        def pause_flow():
            ensure_play()
            if self.game=="fungus":self.key("D")
            elif self.game=="polyrace":self.idle(3.1);self.key("W",.15)
            else:self.idle(.15)
            r=self.click("pause");before=self.validate(r)
            if self.game!="glitch":after=self.validate(self.key("D",.2))
            else:after=self.validate(self.idle(.25))
            # Rendering/controls may change but gameplay must not.
            def state(s):return {k:v for k,v in public(s).items() if k!="actors"}|{"actors":[a for a in public(s)["actors"] if a["kind"]!="control"]}
            self.check("d4.pause",before["phase"]=="paused" and state(before)==state(after),"Pause freezes real state despite delivered input/time")
            self.check("d5.overlays",bool(re.search("paus",text(self.p.last),re.I)),"Pause overlay visible")
            r=self.click("resume");self.check("d4.pause",self.validate(r)["phase"]=="playing","Ordinary Resume releases pause")
            r=self.key("Escape");self.check("d4.pause",self.validate(r)["phase"]=="paused","Escape also pauses normally")
        self.scenario("independent pause resume escape",["d4.pause","d5.overlays"],pause_flow)
        def paused_restart():
            if (self.p.last.get("save") or {}).get("phase")!="paused":
                ensure_play();self.key("Escape")
            r=self.click("restart");s=self.validate(r)
            self.check("d4.restart",s["phase"]=="playing" and (n(s,"turn")==0 if self.game=="fungus" else n(s,"stars")==300 if self.game=="glitch" else n(s,"countdown")>2),"Paused Retry clears local state")
        self.scenario("independent paused restart",["d4.restart"],paused_restart)
        def menu_return():
            ensure_play();self.return_menu();r=self.start()
            self.check("d4.entry",self.validate(r)["phase"]=="playing","Ordinary play/pause to Menu to Start without duplicate roots")
        self.scenario("independent ordinary menu return",["d4.entry"],menu_return)
        def services():
            r=self.fresh();self.validate_schema(r);self.p.call("detach");self.p.call("invalid")
            # This check is the engineering service-delivery checkpoint, not
            # a separate source-structure/extra-interface requirement.
            self.check("d1.service",True,"Detached capture and atomically rejected invalid service requests")
        self.scenario("service deep-copy and rejection",["d1.service"],services)
        def reopen():
            if self.game=="fungus":
                self.fresh("floor_2");self.p.call("begin",seconds=0);self.key("D");self.click("save");old=copy.deepcopy(self.validate(self.p.last))
            elif self.game=="glitch":
                def win(s):
                    a=self.garden_target(s,x=3,hp=20,typ="lizard");self.defend(s,int(a["position"]["y"])-1,0,"cactus",.9)
                self.setup(win,"level_1");self.idle(.65);old=copy.deepcopy(self.validate(self.p.last))
                if old["phase"]!="won":raise ProductError("Cannot earn completion to establish reopen precondition")
                self.return_menu();self.click("options");self.click("volume");old_volume=n(self.validate(self.p.last),"volume");self.click("return")
            else:
                tr=self.content["tracks"][0]
                def win(s):self.race_setup(s,z=tr["length"]-.7,speed=10,gate=2);sn(s,"elapsed",12)
                self.setup(win,"track_1_time");self.key("W",.12);old=copy.deepcopy(self.validate(self.p.last))
                if old["phase"]!="won":raise ProductError("Cannot earn race record to establish reopen precondition")
            oldpid=self.p.process.pid;self.p.close();self.p=Player(self.out/"player/Game.exe",self.out/"process-2",False);r=self.idle(.05,capture="reopen.png");s=self.validate(r)
            okay=s["phase"]=="menu" and self.p.process.pid!=oldpid
            if self.game=="fungus":
                r=self.click("continue");s=self.validate(r);okay=okay and s["entryId"]==old["entryId"] and n(s,"hp")==n(old,"hp") and n(s,"potions")==n(old,"potions") and xyz(actor(s,"player"))==xyz(actor(old,"player"))
            else:
                okay=okay and int(n(s,"completed_mask"))&1!=0
                if self.game=="glitch":okay=okay and n(s,"volume")==old_volume
                else:
                    earned=n(old,"best_time");labels=text(r)
                    shown=bool(re.search(r"record|best",labels,re.I)) and any(abs(float(x)-earned)<=.011 for x in re.findall(r"\d+\.\d+",labels))
                    okay=okay and earned>0 and (abs(n(s,"best_time")-earned)<.011 or shown)
            self.check("d4.reopen",okay,"Old PID exited; new player opens title with actual earned/manual persistent state")
        self.scenario("real close new PID persistence",["d4.reopen"],reopen)
    def reference_frame(self):
        def capture():
            if self.game=="fungus":
                self.fresh("floor_2");self.p.call("begin",seconds=0);self.key("D");r=self.key("Period",capture="main-play.png")
            elif self.game=="glitch":
                def edit(s):
                    self.garden_history(s);sn(s,"elapsed",20);sn(s,"stars",250)
                    self.defend(s,0,1,"cactus",.5);self.defend(s,1,0,"trophy",2);self.defend(s,3,1,"gnome",1);self.defend(s,2,4,"gravestone")
                    level=self.content["levels"][0]
                    for i,w in enumerate(level["waves"][:5]):
                        a=actor(s,w["id"]);a["present"]=True;a["state"]=w["type"];pos(a,6+i*.6,w["lane"]+1);sn(a,"hp",100 if w["type"]=="lizard" else 120)
                self.setup(edit);r=self.idle(.15,capture="main-play.png")
            else:
                self.setup(lambda s:self.race_setup(s,z=10,speed=20,shield=70));r=self.key("W,LeftShift",.1,label="hold",capture="main-play.png");self.p.call("release",seconds=0)
            shutil.copyfile(r["screenshot"],self.out/"main-play.png");write(self.out/"main-play-state.json",dict(state=self.rules["d6"]["state"],receipt=r["id"],process_id=r["processId"],frame=r["frame"],save=r.get("save")))
        try:capture()
        except ProductError as ex:
            reason=str(ex)
            try:
                # Restore failure must not force D6 to judge a menu when this
                # independent, public normal chapter entry still works.
                self.p.call("reset",seconds=0)
                entry="floor_2" if self.game=="fungus" else self.model["entries"][0]
                self.p.call("open",entry=entry,seed=20261029,seconds=0)
                self.p.call("begin",seconds=0)
                if self.game=="fungus":
                    self.key("D");r=self.key("Period",capture="main-play-chapter-fallback.png")
                elif self.game=="polyrace":
                    self.idle(3.1);r=self.key("W,LeftShift",.1,label="hold",capture="main-play-chapter-fallback.png");self.p.call("release",seconds=0)
                else:r=self.idle(min(3,self.content["levels"][0]["waves"][0]["time"]+.2),capture="main-play-chapter-fallback.png")
                if (r.get("save") or {}).get("phase")!="playing":raise ProductError("Chapter fallback did not establish play")
                state="public-normal-entry-without-edited-restore"
            except ProductError as second:
                reason+="; "+str(second)
                try:
                    self.p.call("reset",seconds=0);self.idle(.05);self.start()
                    r=self.idle(.3,capture="main-play-fallback.png");state="predeclared-natural-start-fallback"
                except ProductError as third:
                    r=self.idle(.05,capture="main-play-fallback.png");state="fallback-product-blocked";reason+="; "+str(third)
            shutil.copyfile(r["screenshot"],self.out/"main-play.png");write(self.out/"main-play-state.json",dict(state=state,reason=reason,process_id=r["processId"],frame=r["frame"]))
    def build(self):
        if self.reuse:
            binding=json.loads((self.reuse/"binding.json").read_text(encoding="utf-8"))
            if binding["candidate"]!=digest(self.project):raise InfrastructureError("Reuse source does not match unchanged candidate")
            prior={x["path"]:x["sha256"] for x in binding["evaluator"]}
            for part in ["Host.cs","Build.cs"]:
                if prior.get("host/"+part)!=hashlib.sha256((self.ev/"host"/part).read_bytes()).hexdigest():raise InfrastructureError("Reused player has a different observation/build host")
            shutil.copytree(self.reuse/"player",self.out/"player")
            shutil.copyfile(self.reuse/"build.log",self.out/"build.log")
            write(self.out/"build-reuse.json",dict(source=str(self.reuse),candidate_match=True,host_match=True,scope="Repeated execution, not a new cold import"))
            self.context="static engineering unchanged build reuse"
            prior_score=json.loads((self.reuse/"automatic-score.json").read_text(encoding="utf-8"))
            for id in ["d1.import","d1.scene"]:
                row=next(x for x in prior_score["leaves"] if x["id"]==id);self.record(id,row["state"],"Unchanged source/build hash bound to earlier cold import")
            return True
        scratch=self.out/"scratch";shutil.copytree(self.project,scratch,ignore=shutil.ignore_patterns(*EXCLUDED))
        h=scratch/"Assets/__GameCreateEvaluation";(h/"Editor").mkdir(parents=True)
        shutil.copyfile(self.ev/"host/Host.cs",h/"Host.cs");shutil.copyfile(self.ev/"host/Build.cs",h/"Editor/Build.cs")
        write(h/"GameCreate.OpenEvaluation.asmdef",dict(name="GameCreate.OpenEvaluation",references=["GameCreate.Session","Unity.InputSystem","Unity.ugui"]))
        write(h/"Editor/GameCreate.OpenEvaluation.Editor.asmdef",dict(name="GameCreate.OpenEvaluation.Editor",includePlatforms=["Editor"]))
        (self.out/"player").mkdir()
        env=os.environ.copy();env.update(GAMECREATE_EVAL_OUTPUT=str(self.out/"player"),GAMECREATE_EVAL_IDENTITY="complex-"+hashlib.sha256(str(self.out).encode()).hexdigest()[:18])
        argv=[self.editor,"-batchmode","-quit","-projectPath",str(scratch),"-executeMethod","GameCreate.OpenEvaluation.Build.Player","-logFile",str(self.out/"build.log")]
        start=time.time();p=subprocess.Popen(argv,env=env,creationflags=subprocess.CREATE_NO_WINDOW)
        try:code=p.wait(timeout=900)
        except subprocess.TimeoutExpired:p.kill();p.wait();raise InfrastructureError("Owned build exceeded900s")
        write(self.out/"build-execution.json",dict(pid=p.pid,exit_code=code,seconds=time.time()-start,argv=argv))
        log=(self.out/"build.log").read_text(encoding="utf-8-sig",errors="replace")
        if re.search(r"Assets[/\\]__GameCreateEvaluation[^\r\n]*error CS",log):raise InfrastructureError("Evaluator host compilation failed")
        compiled=not re.search(r"error CS\d+|Scripts have compiler errors",log);scene=(self.project/"Assets/Game/Scenes/Game.unity").exists()
        settings=(self.project/"ProjectSettings/EditorBuildSettings.asset").read_text(encoding="utf-8-sig") if (self.project/"ProjectSettings/EditorBuildSettings.asset").exists() else ""
        self.context="static engineering"
        self.check("d1.import",compiled,"Pinned cold import/script compiler result")
        self.check("d1.scene",scene and bool(re.search(r"enabled: 1\s+path: Assets/Game/Scenes/Game\.unity",settings)),"Actual final scene and normal enabled entry")
        if code==0 and (self.out/"player/Game.exe").exists():return True
        if not compiled or not scene:
            for id,row in self.leaves.items():
                if not row["observations"]:self.record(id,"BLOCKED_BY_PRODUCT","Verified candidate compile/scene/build defect prevents required runtime delivery")
            return False
        raise InfrastructureError("Build failed without verified candidate cause")
    def nunit_bridge(self):
        # NUnit asserts the actual evidence states in a clean harness project;
        # never compile the candidate just to assert a known compile failure.
        bridge=self.out/"nunit-project";bridge.mkdir()
        for part in ["Packages","ProjectSettings"]:shutil.copytree(self.project/part,bridge/part)
        test=bridge/"Assets/EvidenceTests";test.mkdir(parents=True)
        shutil.copyfile(self.ev/"host/EvaluationEvidenceTests.cs",test/"EvaluationEvidenceTests.cs")
        write(test/"EvidenceTests.asmdef",dict(name="GameCreate.EvidenceTests",includePlatforms=["Editor"],optionalUnityReferences=["TestAssemblies"]))
        env=os.environ.copy();env["GAMECREATE_EVIDENCE_FILE"]=str(self.out/"checkpoint-evidence.json")
        argv=[self.editor,"-batchmode","-projectPath",str(bridge),"-runTests","-testPlatform","EditMode","-testFilter","EvaluationEvidenceTests","-testResults",str(self.out/"nunit.xml"),"-logFile",str(self.out/"nunit.log")]
        p=subprocess.Popen(argv,env=env,creationflags=subprocess.CREATE_NO_WINDOW)
        try:code=p.wait(timeout=600)
        except subprocess.TimeoutExpired:p.kill();p.wait();raise InfrastructureError("NUnit evidence bridge exceeded600s")
        write(self.out/"nunit-execution.json",dict(pid=p.pid,exit_code=code,argv=argv))
        if not (self.out/"nunit.xml").exists():raise InfrastructureError("NUnit produced no fresh XML")
        cases=list(ET.parse(self.out/"nunit.xml").getroot().iter("test-case"))
        for id in self.leaves:
            found=[x for x in cases if x.get("name")==id]
            if len(found)!=1:raise InfrastructureError("NUnit checkpoint missing/duplicate: "+id)
            self.xml[id]=found[0].get("result")
            expected="Passed" if self.leaves[id]["state"]=="PASS" else "Inconclusive" if self.leaves[id]["state"]=="INCONCLUSIVE_EVALUATOR" else "Failed"
            if self.xml[id]!=expected:raise InfrastructureError("NUnit result disagrees with raw observation, including skips: "+id)
    def save(self):
        if not self.out.exists():return
        report=dict(schema_version="1.0",sample=self.rules["sample_id"],sample_id=self.rules["sample_id"],sample_version="1.0.0",evaluator_version=self.rules["evaluator_version"],leaves=list(self.leaves.values()),infrastructure_error=self.failure)
        write(self.out/"checkpoint-evidence.json",report)
        dimensions={};blocked=observed=0
        for d,maximum in self.rules["dimensions"].items():
            if d=="D6":dimensions[d]=None;continue
            rows=[v for v in self.leaves.values() if v["dimension"]==d]
            weights={v["id"]:next(q for q in self.rules["leaves"] if q["id"]==v["id"]).get("max_score",maximum/len(rows)) for v in rows}
            dimensions[d]=None if any(r["state"]=="INCONCLUSIVE_EVALUATOR" for r in rows) else round(sum(weights[r["id"]] for r in rows if r["state"]=="PASS"),6)
            blocked+=sum(weights[r["id"]] for r in rows if r["state"]=="BLOCKED_BY_PRODUCT")
            observed+=sum(weights[r["id"]] for r in rows if r["state"]=="FAIL_OBSERVED")
        automatic_complete=self.bridge and not getattr(self,"only_cases",None) and len(self.xml)==len(self.leaves) and not self.failure and all(r["state"]!="INCONCLUSIVE_EVALUATOR" for r in self.leaves.values())
        report.update(dimensions=dimensions,d1_d5_total=round(sum(v for k,v in dimensions.items() if k!="D6"),6) if all(v is not None for k,v in dimensions.items() if k!="D6") else None,total=None,final_score=None,max_score=100,evaluation_valid=False,classification="incomplete",reason="D6 and final evidence merge required" if automatic_complete else "Automatic evidence or NUnit bridge incomplete",automatic_complete=automatic_complete,status="awaiting_d6" if automatic_complete and not self.failure else "diagnostic_not_final",blocked_by_product_weight=round(blocked,6),observed_failure_weight=round(observed,6),nunit_results=self.xml)
        write(self.out/"automatic-score.json",report)
        write(self.out/"score.json",report)
    def run(self):
        self.out.mkdir(parents=True,exist_ok=False);before=digest(self.project);write(self.out/"binding.json",dict(candidate=before,evaluator=digest(self.ev),editor=self.editor))
        try:
            if self.build():
                self.p=Player(self.out/"player/Game.exe",self.out/"process-1",True);r=self.idle(.05,capture="first-frame.png")
                self.context="static startup"
                log=(self.p.folder/"player.log").read_text(encoding="utf-8-sig",errors="replace")
                frame=Image.open(r["screenshot"]).convert("RGB")
                # Scene/UI observation failures are adjudicated separately.
                # A visible startup is not a failed player just because its UI
                # was not enumerated (e.g. a noncompliant IMGUI-only product).
                rendered=frame.width>=64 and frame.height>=64 and max(ImageStat.Stat(frame.crop((0,0,frame.width,frame.height-24))).stddev)>.5
                self.check("d1.runtime",rendered and not re.search("NullReferenceException|MissingReferenceException|TypeLoadException",log),"Actual standalone framebuffer renders without blocking startup exception; UI/service compliance scored independently")
                def catalogue():
                    self.validate_schema(r);self.check("d1.service",set(r.get("entries") or [])==set(self.model["entries"]),"One required versioned service and valid published catalogue")
                self.scenario("published service delivery",["d1.service"],catalogue)
                self.lifecycle()
                getattr(self,self.game)()
                self.reference_frame()
        except Exception:self.failure=traceback.format_exc()
        finally:
            if self.p:self.p.close()
            if digest(self.project)!=before:self.failure="Retained candidate changed during evaluation"
            self.save()
        if self.bridge:
            try:self.nunit_bridge()
            except Exception:self.failure=traceback.format_exc()
            self.save()
        print(json.dumps(json.loads((self.out/"score.json").read_text(encoding="utf-8"))["dimensions"]),flush=True)
