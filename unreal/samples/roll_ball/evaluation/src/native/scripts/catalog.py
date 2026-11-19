"""The private acceptance ledger. Only GDD Section 6 supplies requirements."""
from runtime import INPUT, ROOT, load, sha, write

ROWS = [
('D1-entry','D1','QUALITY-01','static','Project descriptor and public fixed content are loadable.','entry'),
('D1-build','D1','QUALITY-01','static','The candidate source or content project imports/builds with the bound engine.','build'),
('D1-start','D1','QUALITY-01','static','The normal entry produces a live rendered window without player input.','static-start'),
('D1-contract','D1','QUALITY-01','static','The public read-only provider publishes valid, progressing, truthful snapshots.','static-start'),
('D2-board','D2','LAYOUT-01','dynamic','All fixed wall and floor meshes are assembled in the playable board.','entry'),
('D2-traps','D2','LAYOUT-02','dynamic','Exactly sixteen supplied opening meshes occupy the public trap cells.','entry'),
('D2-ball','D2','MOVEMENT-02','dynamic','The supplied sphere is the actual visible, movable player.','direction-W'),
('D2-exit','D2','LAYOUT-02','dynamic','Start and exit are present and distinguishable at their prescribed cells.','entry'),
('D2-recovery','D2','HAZARD-01','dynamic','A real opening contact can invoke a failure response.','trap'),
('D3-initial','D3','LAYOUT-02','dynamic','Initial play starts at the prescribed center in running state.','entry'),
('D3-directions','D3','MOVEMENT-01','dynamic','Each of W A S D drives in its public screen direction.','directions'),
('D3-coast','D3','MOVEMENT-02','dynamic','Translation is continuous and motion continues after release before slowing.','direction-W'),
('D3-countersteer','D3','MOVEMENT-01','dynamic','A reversal first counter-steers existing momentum instead of instantly reversing it.','countersteer'),
('D3-perimeter','D3','COLLISION-01','dynamic','A meaningful perimeter impact blocks and visibly rebounds, retaining later control.','perimeter'),
('D3-internal','D3','COLLISION-01','dynamic','A meaningful internal-wall impact blocks and visibly rebounds, retaining later control.','internal'),
('D3-safe-rim','D3','HAZARD-01','dynamic','Safe floor and a visibly clear trap rim do not trigger a hit.','rim'),
('D3-opening','D3','HAZARD-01','dynamic','The visible opening, rather than the entire trap cell, initiates recovery.','trap'),
('D3-hit-count','D3','HAZARD-02','dynamic','An uninterrupted contact increments the existing count exactly once.','trap'),
('D3-hit-time','D3','HAZARD-02','dynamic','Trap feedback lasts within the publicly specified 0.75 to 2.0 second interval.','trap'),
('D3-hit-lock','D3','HAZARD-01','dynamic','Normal movement input has no control during recovery; passive falling is allowed.','trap'),
('D3-reset','D3','HAZARD-02','dynamic','Natural recovery restores the start center and removes old linear/angular velocity.','trap'),
('D3-repeat-hit','D3','HAZARD-01','dynamic','A separate later opening contact starts another single transaction.','repeat-trap'),
('D3-goal','D3','GOAL-01','dynamic','Only visible exit contact completes, once; earlier route cells remain running.','journey'),
('D3-terminal','D3','GOAL-02','dynamic','Completed state, ball and hit count remain stable through ordinary movement attempts.','journey'),
('D4-journey','D4','QUALITY-02','dynamic','A complete normal-input journey connects entry, navigation and exit.','journey'),
('D4-resume','D4','HAZARD-02','dynamic','After natural trap recovery, ordinary steering works again.','trap'),
('D4-restart-running','D4','RESTART-01','dynamic','R during running restores the same clean run within two seconds.','restart-running'),
('D4-restart-trap','D4','RESTART-01','dynamic','R during recovery restores a clean run and cancels later stale recovery.','restart-trap'),
('D4-restart-terminal','D4','RESTART-01','dynamic','R after completion restores a clean, controllable run.','restart-terminal'),
('D4-restart-repeat','D4','RESTART-01','dynamic','Repeated individual R presses leave one healthy current run without duplicates.','restart-repeat'),
('D4-reopen','D4','REOPEN-01','dynamic','After prior play and process closure, a genuinely new process starts fresh.','reopen'),
('D4-exit-running','D4','EXIT-01','dynamic','Esc during running closes normally.','exit-running'),
('D4-exit-trap','D4','EXIT-01','dynamic','Esc during recovery closes normally.','exit-trap'),
('D4-exit-terminal','D4','EXIT-01','dynamic','Esc after completion closes normally.','exit-terminal'),
('D5-running','D5','UI-01','dynamic','Running HUD is visibly readable and agrees with current state.','entry'),
('D5-trap','D5','UI-01','dynamic','Trap feedback and its updated count are visibly readable and agree with state.','trap'),
('D5-complete','D5','UI-01','dynamic','Completion feedback persists visibly and agrees with state.','journey'),
('D5-restart','D5','UI-01','dynamic','R - RESTART remains discoverable and the reset HUD shows zero hits.','restart-running'),
('D5-camera','D5','CAMERA-01','dynamic','Full-board framing, orientation and readability survive movement, mouse motion and lifecycle changes.','camera'),
('D5-roll','D5','MOVEMENT-02','dynamic','Volume, shading and horizontal-axis rolling rotation are visible.','direction-W'),
]

SUPPORT={
 'QUALITY-03':['D5-running','D5-trap','D5-complete','D5-restart'],
 'QUALITY-04':['D5-running','D5-trap','D5-roll'],
 'QUALITY-05':['D1-build','D1-start','D4-journey'],
 'QUALITY-06':['D3-repeat-hit','D4-restart-repeat','D4-reopen']}

def catalog():
    return dict(version='4.0.0',generation='legacy',source='../input/GDD.md Section 6',gdd_sha256=sha(INPUT/'GDD.md'),
        dimensions={'D1':10,'D2':30,'D3':20,'D4':20,'D5':10,'D6':10},
        checkpoints=[dict(id=i,dimension=d,requirement=r,stage=s,assertion=a,trajectory=t,
                          visible_review_required=s=='dynamic') for i,d,r,s,a,t in ROWS],
        support_requirements=SUPPORT,formula='dimension maximum * passed checkpoints / all checkpoints',
        incomplete_review_policy='No published score until evidence uncertainty is resolved; never silently fail a control strategy.')

if __name__=='__main__':
    data=catalog();write(ROOT/'catalog/checkpoints.json',data)
    requirements={r for _,_,r,_,_,_ in ROWS}|set(SUPPORT)
    write(ROOT/'catalog/coverage.json',dict(gdd_sha256=data['gdd_sha256'],requirements=[dict(id=r,
        checks=[i for i,_,req,_,_,_ in ROWS if req==r]+SUPPORT.get(r,[])) for r in sorted(requirements)],
        unmapped_gdd_requirements=[]))
    print(len(ROWS),'checkpoints;',len(requirements),'requirements')
