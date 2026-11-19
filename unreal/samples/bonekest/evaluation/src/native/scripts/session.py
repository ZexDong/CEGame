from pathlib import Path
import json,sys,time,secrets,subprocess,hashlib,math,contextlib
from prepare import EV,TASK,REPO
from runtime import Player,write,load,sha,CandidateError,InfrastructureError
from semantics import *

class Session:
    def __init__(self,project,engine,root,identity_value,adapter):
        self.root=Path(root);self.adapter=adapter;self.identity=identity_value
        budget=load(EV/'budget.json');self.p=Player(REPO,project,engine,self.root,serial_limit=budget['session_watchdog_seconds']);self.results={};self.captures={};self.native_samples=[];self.case_name='static';self.counter=0;self.fixture_seq=0
        self.nonce=secrets.token_hex(24);self.fixture_dir=self.root/'userdata/private-fixture';self.fixture_dir.mkdir(parents=True)
        write(self.fixture_dir/'authorization.json',{'nonce':self.nonce,'candidate_identity':identity_value})
        self.budget=budget;self.catalog=load(EV/'checkpoint-catalog.json')['checkpoints'];self.baseline=None
    def state(self):return self.p.state()
    def native(self):
        path=self.fixture_dir/'latest.json';deadline=time.perf_counter()+2;requested=time.time()
        while True:
            try:
                n=load(path)
                if n['pid']==self.p.process_id and n['candidate_identity']==self.identity and path.stat().st_mtime>=requested:
                    self.native_samples.append({'case':self.case_name,'state':n});return n['state']
            except (OSError,ValueError,KeyError):pass
            if time.perf_counter()>deadline:raise InfrastructureError('PRIVATE_NATIVE_PROBE_UNAVAILABLE')
            self.p.stop_event.wait(.03)
    def snap(self,label,capture=True):
        self.counter+=1;key=f'{self.case_name}-{self.counter:03}-{label}'
        s=self.state();n=self.native();write(self.root/f'states/{key}.json',s);write(self.root/f'native/{key}.json',n)
        if capture:self.captures[key]=self.p.capture(key)
        return s,n,key
    def check(self,key,condition,reason,proof=None):
        if key in self.results:raise InfrastructureError('DUPLICATE_CHECKPOINT_RESULT:'+key)
        row=next((x for x in self.catalog if x['id']==key),None)
        if row is None:raise InfrastructureError('UNKNOWN_CHECKPOINT:'+key)
        self.results[key]={'id':key,'dimension':row['dimension'],'status':'pass' if condition else 'fail','reason_code':'CONFIRMED' if condition else reason,'reason':reason,'attribution':'candidate','case':self.case_name,'evidence':proof or {'state_samples':'samples-stream.jsonl','input_receipts':'actions.json','native_samples':'native-samples.jsonl','captures':[k for k in self.captures if k.startswith(self.case_name+'-')]}}
        print(key,self.results[key]['status'],flush=True)
    def restart(self):
        s=self.state()
        if s['phase']=='menu':self.p.click_target('easy')
        elif s['phase']=='not_ready':raise CandidateError('TARGET_GAMEPLAY_UNIMPLEMENTED')
        else:self.p.press('R',80)
        old=s['round_id'];s=self.p.wait(lambda x:x['round_id']!=old and x['phase']=='exploring',15,stable=.15,reason='RESTART_DID_NOT_SETTLE')
        # Setup isolation is a public lifecycle action, never a private reset call.
        self.p.observe(.3);return s
    def to_menu(self):
        s=self.state()
        if s['phase']=='menu':return s
        if s['phase']=='not_ready':raise CandidateError('TARGET_MENU_UNIMPLEMENTED')
        if s['phase'] not in ('paused','won','lost'):self.p.press('Escape',80);self.p.wait(lambda s:s['phase']=='paused',3)
        self.p.click_target('main_menu');return self.p.wait(lambda s:s['phase']=='menu',6)
    def set_seed(self,text):
        self.to_menu();self.p.click_target('seed_input')
        # Backspace uses the field's public actual value; it assumes no private UI structure.
        value=self.p.target('seed_input').get('attributes',{}).get('value','')
        for _ in range(len(value)+1):self.p.press('Backspace',30)
        for c in str(text):
            key={' ':'Space','-':'OemMinus','.':'OemPeriod'}.get(c,c.upper());self.p.press(key,30)
        return self.state()
    def setup(self,**fields):
        before=self.state();native_before=self.native();self.fixture_seq+=1
        request={'sequence':self.fixture_seq,'nonce':self.nonce,'operation':'apply','semantic_state':fields}
        temp=self.fixture_dir/'request.tmp';write(temp,request);replace_until=time.perf_counter()+1
        while True:
            try:temp.replace(self.fixture_dir/'request.json');break
            except PermissionError:
                if time.perf_counter()>replace_until:raise InfrastructureError('FIXTURE_REQUEST_SHARING_CONFLICT')
                self.p.stop_event.wait(.015)
        receipt_path=self.fixture_dir/f'receipt-{self.fixture_seq}.json';end=time.perf_counter()+3
        while not receipt_path.exists():
            if time.perf_counter()>end:raise InfrastructureError('FIXTURE_RECEIPT_TIMEOUT')
            self.p.stop_event.wait(.02)
        receipt=load(receipt_path);write(self.root/f'setup/{self.fixture_seq:04}-receipt.json',receipt)
        if not receipt.get('applied'):raise InfrastructureError('FIXTURE_MAPPING_REJECTED:'+receipt.get('reason','unknown'))
        after=self.p.wait(lambda s:s['snapshot_id']>before['snapshot_id'],2);self.p.observe(.13);after=self.state()
        if after['round_id']!=before['round_id'] or after['slots']['room_changes']!=before['slots']['room_changes']:raise InfrastructureError('FIXTURE_CHANGED_NONALLOWLISTED_IDENTITY_OR_TURN')
        for k in ('lives','scrolls','coins'):
            if after['slots'][k]!=fields.get(k,before['slots'][k]):raise InfrastructureError('FIXTURE_RESOURCE_NOT_ESTABLISHED:'+k)
        if 'room' in fields and cell(after)!=tuple(fields['room']):raise InfrastructureError('FIXTURE_ROOM_NOT_ESTABLISHED')
        if 'monster_room' in fields and monster(after)!=tuple(fields['monster_room']):raise InfrastructureError('FIXTURE_MONSTER_NOT_ESTABLISHED')
        if 'keys' in fields and {c for c in COLORS if after['slots'][c+'_key']}!=set(fields['keys']):raise InfrastructureError('FIXTURE_KEYS_NOT_ESTABLISHED')
        write(self.root/f'setup/{self.fixture_seq:04}-verified.json',{'fields':fields,'before':before,'after':after,'native_before':native_before,'native_after':self.native()})
        # One synchronous scene capture proves the precursor scene actually exists.
        self.snap(f'setup-{self.fixture_seq}')
        return after
    def safe_monster(self,s,room):
        ds=distances(s,room);return max(ds,key=lambda c:ds[c])
    def move(self,selector,done,seconds=8):
        deadline=time.perf_counter()+seconds;held=set();last=None;stalled=0
        try:
            while time.perf_counter()<deadline:
                s=self.state()
                if done(s):return s
                if s['phase']!='exploring':self.p.stop_event.wait(.03);continue
                player=one(s,'player');target=selector(s)
                if target is None:raise CandidateError('PUBLIC_MOVEMENT_TARGET_UNAVAILABLE')
                nav=self.native().get('navigation',{});key=target['kind']+(':'+target.get('attributes',{})['slot'] if target.get('attributes',{}).get('slot') else '')
                a=nav.get('player') or (centre(player['rect']) if player.get('rect') else None)
                b=nav.get(target.get('id')) or nav.get(key) or (centre(target['rect']) if target.get('rect') else None)
                if a is None or b is None:raise InfrastructureError('MOVEMENT_REQUIRES_REVIEWED_SCREEN_OR_POSITION_MAPPING')
                if target.get('_outward') and nav.get('center'):
                    origin=nav['center'];vx,vy=b[0]-origin[0],b[1]-origin[1];norm=max(.001,math.hypot(vx,vy));b=[b[0]+vx/norm*.055,b[1]+vy/norm*.055]
                dx,dy=b[0]-a[0],b[1]-a[1]
                desired=set()
                if abs(dx)>.010:desired.add('D' if dx>0 else 'A')
                if abs(dy)>.014:desired.add('S' if dy>0 else 'W')
                if not desired:
                    # Continue across the target's boundary using the last approach.
                    desired=held or {'W'}
                for key in held-desired:self.p.rpc('up',key=key);self.p.held.discard(key)
                for key in desired-held:self.p.rpc('down',key=key);self.p.held.add(key)
                held=desired
                self.p.observe(.06)
            raise CandidateError('MOVEMENT_TARGET_NOT_REACHED')
        finally:
            for key in list(held):self.p.rpc('up',key=key);self.p.held.discard(key)
    def cross(self,slot,seconds=8):
        before=self.state();count=before['slots']['room_changes']
        def target(s):
            t=next((t for t in s['targets'] if t['kind']=='passage' and t.get('attributes',{}).get('slot')==slot and t.get('visible')),None)
            if not t:return None
            room=rooms(s)[cell(s)];origin=centre(room.get('rect',[.45,.45,.1,.1]));dest=centre(t['rect']);dx,dy=dest[0]-origin[0],dest[1]-origin[1];norm=max(.001,math.hypot(dx,dy))
            # The visible passage marks the doorway, not necessarily the far
            # crossing plane. Aim just beyond it along its public room-centre ray.
            r=list(t['rect']);r[0]+=dx/norm*.055;r[1]+=dy/norm*.055
            return {**t,'rect':r,'_outward':True}
        self.move(target,lambda s:s['slots']['room_changes']>count or s['phase']=='transition',seconds)
        return self.p.wait(lambda s:s['phase'] in ('exploring','recovering','won','lost') and s['slots']['room_changes']>count,3)
    def pickup(self,pickup):
        ident=pickup['id']
        return self.move(lambda s:next((e for e in entities(s,'pickup') if e['id']==ident),None),lambda s:any(e['id']==ident and e['state']=='consumed' for e in entities(s,'pickup')),8)
    def final(self,rejection_color=None):
        def done(s):
            if s['phase'] in ('won','lost'):return True
            if rejection_color:
                words=' '.join(self.strings()).lower()
                return rejection_color in words and any(word in words for word in ('missing','need','require'))
            return False
        return self.move(lambda s:next((t for t in s['targets'] if t['kind']=='final_portal'),None),done,5)
    def strings(self,native=None):
        n=native or self.native();return [x['text'] for x in n.get('renderer',{}).get('commands',[]) if x['kind']=='text' and x['alpha']>.1]
    def assets(self,native=None):
        n=native or self.native();return {x['asset'] for x in n.get('rendered_components',[]) if x['recently_rendered']}|{x['asset'] for x in n.get('renderer',{}).get('commands',[]) if x['alpha']>.1}
    def run_case(self,name,func):
        self.case_name=name;self.p.case=name;b=self.budget['cases'][name]
        # Logical high-level movement may send many correcting key edges. The
        # high-level action budget is tracked by cases; low-level safety has a
        # separately declared allowance and remains bounded by serial time.
        self.p.set_case_budget(name,b['max_serial_seconds'],b['max_actions']*8)
        begin=len(self.p.actions)
        try:func(self)
        except (CandidateError,AssertionError,ValueError,KeyError,StopIteration) as e:
            write(self.root/f'cases/{name}-fault.json',{'attribution':'candidate','type':type(e).__name__,'reason':str(e)})
            for check in b['checks']:
                if check not in self.results:
                    row=next(r for r in self.catalog if r['id']==check);self.results[check]={'id':check,'dimension':row['dimension'],'status':'unreachable','reason_code':'CANDIDATE_PREREQUISITE_FAILURE','reason':str(e),'attribution':'candidate','case':name,'evidence':f'cases/{name}-fault.json'}
        finally:
            write(self.root/f'cases/{name}.json',{'case':name,'actions':self.p.actions[begin:],'checks':{k:v for k,v in self.results.items() if v.get('case')==name}})
            self.p.case_budget=None
        for check in b['checks']:
            if check not in self.results:raise InfrastructureError('CASE_DID_NOT_DECIDE_DECLARED_CHECK:'+check)
    def close(self):
        try:self.p.case_budget=None;self.p.close()
        finally:
            write(self.root/'checks.json',list(self.results.values()))
            with (self.root/'native-samples.jsonl').open('w',encoding='utf-8') as f:
                for row in self.native_samples:f.write(json.dumps(row,separators=(',',':'))+'\n')
