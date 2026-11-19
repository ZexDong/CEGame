"""Real keyboard/mouse campaign acceptance; plans use only public parameters."""
import argparse
import copy
import json
from pathlib import Path
from framework.macos_evaluation.host import write
from .session import Session
from .match3_model import Model

def verify(s,model,expected):
    snapshot=s.state();slots=snapshot['slots']
    assert slots['score']==sum(expected.colors)*10
    assert slots['moves_used']==expected.moves
    assert slots['rng_cursor']==expected.rng
    assert slots['ice_layers_remaining']==sum(expected.ice)
    actual={(e['cell'][0],e['cell'][1]):model.names.index(e['kind'][4:]) for e in snapshot['entities'] if e['kind'].startswith('gem_')}
    assert actual=={(x,y):expected.board[x][y] for x in range(15) for y in range(10) if expected.board[x][y] is not None}
    for i,name in enumerate(model.names):assert slots['cleared_'+name]==expected.colors[i]

def move(s,model,state,direction,mouse=False,pause_busy=False):
    expected=model.step(state,direction)
    if mouse:
        t=next(t for t in s.state()['targets'] if t['kind']=='board_surface');x,y,w,h=t['rect'];start=[x+w/2,y+h/2]
        dx,dy={'left':(-1,0),'right':(1,0),'up':(0,1),'down':(0,-1)}[direction]
        s.drag(start,[start[0]+dx*w/9,start[1]+dy*h/6])
    else:s.press(direction,seconds=.12,settle=.02)
    if pause_busy:
        s.wait(lambda v:v['slots']['busy']==1,2);s.press('pause',seconds=.06,settle=.03)
        s.wait(lambda v:v['phase']=='paused');before=copy.deepcopy(s.state())
        s.delay(.4);s.press('left');after=s.state()
        assert after['slots']==before['slots'] and after['entities']==before['entities']
        s.capture('paused-during-chain');s.click('pause_resume')
    s.wait(lambda v:v['phase'] in ('level_clear','campaign_won','lost') or v['slots']['moves_used']==expected.moves and v['slots']['busy']==0,30)
    if s.state()['phase']!='campaign_won':verify(s,model,expected)
    return expected

def main():
    p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);p.add_argument('--candidate',type=Path);a=p.parse_args()
    s=Session('defold_match3_swipe_v2',a.output,a.candidate);checks=[]
    try:
        s.start();s.capture('menu');s.click('menu_new_campaign');s.wait(lambda v:v['phase']=='playing')
        s.mark('D2.MENU','D2.BOARD','D5.MENU','D5.HUD')
        b=next(t for t in s.state()['targets'] if t['kind']=='board_surface')['rect'];x,y,w,h=b
        s.drag([x+w/2,y+h/2],[x+w/2+w/30,y+h/2])
        s.drag([x-w/60,y+h/2],[x+w/6,y+h/2])
        assert s.state()['slots']['moves_used']==0
        checks.append('short and outside-origin drags do not consume a move');s.mark('D3.GESTURE')
        totals=0
        for index in (1,2,3):
            model=Model(s.spec,index);state=model.initial();route,final=model.route();verify(s,model,state)
            s.capture('chapter-'+str(index)+'-initial')
            if index==2:
                s.press('right');s.wait(lambda v:v['slots']['busy']==0,30)
                for _ in range(2):
                    serial=s.state()['slots']['run_serial'];s.press('restart');s.wait(lambda v:v['slots']['run_serial']==serial+1 and v['phase']=='playing');verify(s,model,state)
                assert s.state()['slots']['cleared_levels']==1;checks.append('current-level retry preserves committed level 1');s.mark('D4.RETRY')
            for i,direction in enumerate(route):
                state=move(s,model,state,direction,mouse=index==2 and i==0,pause_busy=index==1 and i==0)
                if index==1 and i==0:s.mark('D2.INPUT','D3.CASCADE','D3.PAUSE','D5.PAUSE')
                if index==2 and i==0:s.mark('D2.POINTER')
            expected_phase='campaign_won' if index==3 else 'level_clear'
            s.wait(lambda v:v['phase']==expected_phase);s.capture('chapter-'+str(index)+'-complete')
            profile=json.loads((s.profile/'campaign-v2.json').read_text());totals+=sum(final.colors)*10
            assert profile['cleared_levels']==index and len(profile['completed_results'])==index
            assert profile['completed_results'][-1]['score']==sum(final.colors)*10
            assert s.state()['slots']['campaign_score']==totals
            checks.append('normal chapter '+str(index)+' objectives and one commit')
            if index==1:s.mark('D2.RESULTS','D3.GOALS','D5.RESULT')
            elif index==2:s.mark('D2.CHAPTERS','D3.ICE')
            else:s.mark('D3.STONE','D4.CHAPTERS','D4.SUCCESS')
            print('CHAPTER',index,'score',sum(final.colors)*10,'saved',index,flush=True)
            if index==1:
                s.click('return_menu');s.click('menu_exit',exit_expected=True);s.process.wait(timeout=5);assert s.process.returncode==0
                s.launch();assert s.state()['phase']=='menu' and s.state()['slots']['run_serial']==0 and s.state()['slots']['saved_levels']==1
                s.capture('reopened-after-chapter-1');s.click('menu_continue');s.wait(lambda v:v['phase']=='playing' and v['slots']['level_index']==2)
                checks.append('close/reopen and Continue restores chapter 2 entry');s.mark('D4.REOPEN')
            elif index==2:
                s.click('next_level');s.wait(lambda v:v['phase']=='playing' and v['slots']['level_index']==3)
                assert not any(t['kind']=='next_level' for t in s.state()['targets'])
        s.click('campaign_new');s.wait(lambda v:any(t['kind']=='new_cancel' for t in v['targets']));s.click('new_cancel')
        assert s.state()['phase']=='campaign_won' and s.state()['slots']['saved_levels']==3
        s.click('exit_button',exit_expected=True);s.process.wait(timeout=5);assert s.process.returncode==0;s.launch()
        s.click('menu_continue');assert s.state()['phase']=='campaign_won' and s.state()['slots']['run_serial']==0
        s.capture('completed-campaign-reopened');checks.append('cancel New Campaign and completed Continue preserve summary');s.mark('D4.ORDER')
        s.click('campaign_new');s.click('new_confirm');s.wait(lambda v:v['phase']=='playing')
        model=Model(s.spec,1);state=model.initial()
        for _ in range(12):
            direction=min(('left','right','up','down'),key=lambda d:sum(model.step(state,d).colors))
            state=move(s,model,state,direction)
            if s.state()['phase']=='lost':break
        assert s.state()['phase']=='lost' and s.state()['slots']['cleared_levels']==0
        s.capture('normal-loss');s.click('level_retry');s.wait(lambda v:v['phase']=='playing');verify(s,model,model.initial())
        checks.append('ordinary 12-move loss and retry; new campaign clears progress');s.mark('D4.FAILURE','D4.RESET')
        write(s.output/'acceptance.json',{'sample':s.sample.name,'status':'passed','scope':'native candidate playtest, not a score','checks':checks,'campaign_score':totals})
        print('MATCH3 NATIVE ACCEPTANCE PASSED',flush=True)
    finally:s.close()

if __name__=='__main__':main()
