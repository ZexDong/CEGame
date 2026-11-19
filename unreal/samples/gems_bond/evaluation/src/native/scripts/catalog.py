"""Single scoring catalogue. Equal checkpoint weights within each dimension."""
CHECKS={}
def add(id,dim,req,question,cases,review=False):
    CHECKS[id]={'id':id,'dimension':dim,'stage':'static' if dim=='D1' else 'dynamic','requirements':req.split(),
                'question':question,'cases':cases.split(),'visible_review':review}
add('project','D1','QUALITY-01','Can the declared UE project and entry be resolved?','static')
add('engine','D1','QUALITY-01','Does the installed engine match the public identity?','static')
add('build','D1','QUALITY-01 QUALITY-05','Does a clean assessment copy compile successfully?','static')
add('startup','D1','QUALITY-01','Does the normal entry produce a healthy client without input?','static')
add('observation','D1','QUALITY-01 QUALITY-04','Does the public read-only snapshot pass its self-check?','static')
add('opening_content','D2','SCENE-01 SCENE-02 VISUAL-01 VISUAL-03','Are the crystal, deposits and assembled 3D forest actually visible?','opening',True)
for kind in ['mine','archer','cannon','wall']:
    add('content_'+kind,'D2','BUILD-01 BUILD-03 VISUAL-01','Can a '+kind+' be built through its normal controls?','build_'+kind,True)
add('inspection_content','D2','INSPECT-01 SELL-01','Can a player inspect and sell a structure?','sale',True)
for k in ['archer','cannon']:
    add('tiers_'+k,'D2','UPGRADE-01 VISUAL-01','Can both higher '+k+' tiers be reached and seen?','upgrade_'+k+'_2 upgrade_'+k+'_3',True)
add('enemy_content','D2','ENEMY-01 ENEMY-02 VISUAL-02','Do all five animated enemy species appear with their tier variants?','enemy_matrix',True)
add('weapons_content','D2','ARCHER-01 ARCHER-02 CANNON-01 CANNON-02 VISUAL-04','Do both towers release visible distinct projectiles and impacts?','archer_combat cannon_combat',True)
add('schedule_content','D2','WAVE-03','Do all 25 scheduled wave entries occur?',' '.join('wave_'+str(n) for n in range(1,26)))
add('endless_content','D2','WAVE-05','Does survival continue beyond the fixed schedule?','wave_26 wave_30')
add('income_content','D2','ECONOMY-02','Can a living mine produce spendable income?','income')
add('pause_speed_content','D2','SPEED-01 PAUSE-01','Can speed and pause be used in a running round?','speed pause')
add('defeat_content','D2','DEFEAT-01 DEFEAT-02','Can normal enemy play reach a Game Over state?','lifecycle',True)
add('feedback_content','D2','VISUAL-04 AUDIO-01','Are spatial construction, upgrade, impact, income effects and representative event audio present?','build_archer upgrade_archer_2 archer_combat cannon_combat income audio',True)
add('initial_rules','D3','START-01 SCENE-02','Does the initial board/economy match every public opening value?','opening')
add('selection_rules','D3','SELECT-01 SELECT-02 SELECT-03','Do selection, replacement, hover and cancellation leave gameplay untouched?','selection',True)
add('purchase_rules','D3','BUILD-01 COMBAT-01','Do purchases charge once, construct once and retain build selection?','build_mine build_archer build_cannon build_wall repeat_build')
add('placement_rules','D3','BUILD-02 BUILD-03 SCENE-02','Are occupied, crystal, deposit, soil and unaffordable purchases rejected safely?','placement exact_funds unaffordable')
add('price_rules','D3','ECONOMY-01','Do per-type living counts determine current prices after build/sale/destruction?','repeat_build sale destruction')
add('income_rules','D3','ECONOMY-02','Do independent mines pay only on full cycles at the current completed-wave rate?','income income_removed')
add('inspect_rules','D3','INSPECT-01','Does inspection leave wallet and ownership unchanged and expose current values?','sale')
add('upgrade_rules','D3','UPGRADE-01','Do both tower upgrade transactions use the correct tier price and stats?','upgrade_archer_2 upgrade_archer_3 upgrade_cannon_2 upgrade_cannon_3')
add('upgrade_health','D3','UPGRADE-02','Does a damaged upgrade preserve health percentage?','upgrade_archer_2 upgrade_cannon_2')
add('upgrade_rejection','D3','UPGRADE-03','Are unaffordable, constructing, non-tower and maximum-tier upgrades harmless?','upgrade_reject')
add('refund_rules','D3','SELL-01','Does sale refund half the placement amount once, excluding upgrades?','sale income_removed')
add('regeneration_rules','D3','HEALTH-01','Does living health regenerate at 2/s with clamping and pause lock?','regeneration pause')
add('destruction_rules','D3','HEALTH-02','Does destruction remove ownership/actions/blockers without refund?','destruction')
add('gate_rules','D3','WAVE-01','Does only the first accepted mine start the two-second gate?','gate build_mine')
add('wave_schedule_rules','D3','WAVE-02 WAVE-03','Do all compositions, tiers, edges and evenly spaced emissions follow the public table?',' '.join('wave_'+str(n) for n in range(1,26)))
add('wave_clear_rules','D3','WAVE-04','Does clearance wait for no unspawned/living enemies and increment once?','clear rest')
add('endless_rules','D3','WAVE-05','Are endless integer counts, tiers, duration and edges correct?','wave_26 wave_30')
add('seed_rules','D3','RANDOM-01 QUALITY-06','Do identical seeded restarts reproduce choices without changing balance?','seed')
add('ground_rules','D3','ENEMY-01','Do ground species move at public speeds and stop at living obstructions?','enemy_matrix obstruction')
add('flight_rules','D3','ENEMY-02','Do flyers bypass buildings and stay above ground?','enemy_matrix flight')
add('melee_rules','D3','ENEMY-03','Does contact apply the correct damage at no more than one hit per second?','melee')
add('death_rules','D3','ENEMY-04','Does a killed enemy stop attacking and award its bounty exactly once?','death')
add('archer_targeting','D3','ARCHER-01','Does the archer select the nearest living ground/flying target in range without idle bursts?','archer_combat archer_flight range')
add('arrow_rules','D3','ARCHER-02','Does an arrow travel before a single impact and safely expire/block?','archer_combat projectile_block')
add('cannon_targeting','D3','CANNON-01','Does the cannon target ground enemies and reject flyers?','cannon_combat cannon_flight')
add('splash_rules','D3','CANNON-02','Does one finite-travel cannon impact damage each in-radius ground enemy once?','cannon_combat splash_boundary')
add('projectile_lifecycle','D3','COMBAT-01','Do released projectiles survive source removal and retain release-time values?','projectile_sale')
add('cooldown_upgrade','D3','COMBAT-01','Does an upgrade preserve an already pending cooldown?','cooldown_upgrade')
add('speed_rules','D3','SPEED-01','Does held F apply 3x and release restore 1x?','speed')
add('pause_rules','D3','PAUSE-01','Does pause freeze every gameplay value and resume the same progress?','pause')
add('defeat_rules','D3','DEFEAT-01 DEFEAT-02','Does lethal crystal damage clamp to zero and lock gameplay?','lifecycle terminal_priority')
add('flow','D4','QUALITY-02 QUALITY-05 WAVE-01 DEFEAT-01','Does a normal mine-to-combat-to-defeat journey remain connected?','lifecycle')
for phase in ['preparing','countdown','combat','rest','paused','defeated']:
    add('restart_'+phase,'D4','RESTART-01 START-01','Does normal R restore a fresh round from '+phase+' without changing process?','restart_'+phase)
add('restart_inflight','D4','RESTART-01 COMBAT-01','Does Restart isolate projectiles, delayed income and held inputs?','restart_inflight')
add('reopen','D4','RESTART-02 QUALITY-01 QUALITY-06','Does a new process start fresh after changed progress?','reopen')
add('repeat_round','D4','RESTART-01 QUALITY-06','Do repeated restarts preserve unique identities and stable opening progress?','seed')
add('ui_build','D5','UI-01 SELECT-01 SELECT-02 SELECT-03 QUALITY-03','Are build choices, prices, selected state, valid/invalid preview and cancellation readable and actionable?','selection build_archer placement',True)
add('ui_context','D5','INSPECT-01 UI-01 UPGRADE-03','Are details, costs, disabled upgrade and sale controls visible and operable?','sale upgrade_reject',True)
add('ui_feedback','D5','UI-03 QUALITY-04','Do positive/rejected actions show timely feedback without click-through?','build_archer placement',True)
add('ui_health','D5','UI-02 QUALITY-04','Do health bars agree with damage/regeneration and disappear with removed objects?','regeneration destruction',True)
add('ui_lifecycle','D5','UI-01 PAUSE-01 DEFEAT-01 QUALITY-03','Are pause/result controls and progress understandable and usable?','pause lifecycle',True)
add('ui_resolutions','D5','UI-01 SCENE-01 QUALITY-03','Are all cells and critical controls reachable at both supported resolutions?','resolution',True)
add('audio_mute','D5','AUDIO-01 QUALITY-04','Can background and event audio be muted and restored while gameplay and visual feedback remain usable?','audio',True)

# Independent table rows and input boundaries supplement the same score owners.
for row in CHECKS.values():
    if row['id'] in ['melee_rules','death_rules']:
        row['cases'] += [f'contact_{k}_{t}' for k in ['slime','skeleton','orc','bat','dragon'] for t in [1,2,3]]
    if row['id']=='upgrade_rules':row['cases'] += [f'weapon_{k}_{t}' for k in ['archer','cannon'] for t in [2,3]]
    if row['id']=='refund_rules':row['cases'].append('refund_upgrade')
    if row['id']=='destruction_rules':row['cases'] += ['destroy_during_sell','destroy_during_upgrade']
    if row['id']=='placement_rules':row['cases'].append('enemy_placement')
    if row['id'] in ['purchase_rules','selection_rules','pause_rules','speed_rules']:row['cases'].append('input_boundaries')

# Revision 1.1.2 adds evidence to existing owners; no new score weight.
CHECKS['upgrade_rejection']['cases'] += ['review_reject_'+reason for reason in ['unaffordable','maximum','construction','mine','wall']]
for kind in ['archer','cannon']:
    CHECKS[kind+'_targeting']['cases'].append('review_nearest_'+kind)
    CHECKS['projectile_lifecycle']['cases'] += ['review_projectile_'+op+'_'+kind for op in ['upgrade','sale']]
    CHECKS['weapons_content']['cases'].append('review_visible_'+kind)
    CHECKS['feedback_content']['cases'].append('review_visible_'+kind)
CHECKS['income_rules']['cases'].append('review_income_purchase')
CHECKS['upgrade_rules']['cases'].append('review_upgrade_single_click')
