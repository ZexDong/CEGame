# Match3 v2 Public levels and rules

The only source of parameters is campaign.json; Top-level world Definition 15×10, Six-color order, 900×600 Chessboard area[30,60,900,600]And the color extractor. level array uses 1 start index, grid coordinates[0,0]in the lower left. 

| level | seed | remote initial value | disk | All success conditions |
|---|---:|---:|---|---|
| 1 score | 7301 | 12 | 150 gems, no ice / stone | score≥8000 |
| 2 ice | 9403 | 18 | 150 gems, 12 ice grids in total 18 layers | score≥6000 and total number of ice layers 0 |
| 3 mixed | 12107 | 24 | 144 gems+6 Stones, 6 double-layer ice grids | ice layer 0, red removal≥40 and blue removal≥40 |

## initial release and supplement

Draw the color shilling s=(16807×s) mod 2147483647, Retake s mod 6, Get the color order world.colors. Use your own for each level seed, Retry Restore the initial cursor of this level; Next The cursor of the previous level will not be inherited. 
Initial press y Increment, Same as y within x incrementally generate non-stone grids; stones do not draw colors, Does not consume the sequence. If the new color forms a triple with two consecutive ones on the left or two consecutive ones on the lower side, the color drawing will be discarded and re-drawed, The stone interrupts the continuity. The ice layer does not affect the color drawing. The first set cannot be automatically cleared or scored. 
Remove and press x Incrementally process columns; Each column is divided by stones into non-connected vertical non-stone segments, Process according to the lowest segment y Process from small to large. The surviving gems in the segment are compacted downwards and the relative order is retained, Extract new gems upwards according to the lowest space, Do not refuse to replenish three consecutive blocks. Cannot fall through the stones into another segment. 

## A full direction action

direction pressed Or start from within the board, Triggered once when the spindle displacement reaches 64 The drag of logical pixels is only accepted once; The absolute value of the main axis is the same and the level is taken. busy/ Pause / The result does not receive or queue the action; Short drag and external drag are invalid. If there is no legal exchange, one step is still deducted and the board is maintained. 
When moving to the left x Descending order, Other directions x Ascending order; The same x when the inside is downward y Descending order, the rest y Ascending order. for the gems that are not used this time and the adjacent gems in the target direction, After the trial replacement, at least one endpoint forms a≥3 horizontal / vertical continuous line of the same color to be accepted; otherwise restored. exchange; Subsequent judgment uses the disk that has accepted the exchange. Stones, Out of bounds and used gems cannot participate in the exchange. 

## Batch, Line rewards, Ice layer and color quota

Normal matching takes the union of all the maximum horizontal / vertical continuous line length≥3 ; stone separation line, The cross grid is only cleared once. Normal 4 Continuous generation corresponds to the entire row / Column rewards; ≥5 Rewards for continuous generation of the line and adjacent lines on both sides, Cross-border truncation, Duplicate line deduplication. 
Processing order: Normal removal batches→Segmented compaction and replenishment→Queued lines Road Reward Batch→Compacting and Replenishing→Looking for normal matches again. The bonus applies to all non-stone hexes along the entire specified line, Including the other side of the stone, But the stone itself is not removed. Reward batches do not generate new line rewards. Until there are no normal matches, No reward queue, The animation is stable only after it ends; Cannot be artificially truncated for chains that still need to be settled. 

The same batch, Each gem instance is only removed / Scored once, score Add 10, Add its original color count 1; New supplementary instances have new ID. cascade_index Only remove the batch according to the actual non-empty Increment, Each action restarts from 0 Counter; No matching actions remain 0. score=10×This level cleared_total, The sum of the six-color count=cleared_total. 
The ice layer is fixed in the grid, Does not follow swap or gravity. Decrease when the gems in this grid are cleared in this batch 1 layers; Cross-matching in the same batch, Repeated lines are only subtracted once. New If the supplementary gems are cleared in the next batch, can be reduced by one level, Therefore, one action may clear two levels. The ice layer does not prevent the transposition / Matching / Whereabouts; The stone does not have an ice layer. 
Color quota statistics All actual removals in this level, Including rewards and chains; The excess value is recorded truthfully, Not cut off according to the target. Stones, Ice layer and animation are not counted as gem removal. 

## Judgment and record

This level will be considered successful after stabilization goals Get Logical AND: minimum_score Lower limit(0 means no additional score threshold), clear_all_ice(false means no such goal)and color_quotas All color targets in. If all conditions are met, the level will be judged as successful; Otherwise the remaining steps 0 are lost. If there are still steps left and are not completed, continue. No shuffling on failure, No additional steps, No submission. 
completed_results Each entry contains level_index, score, moves_used, cleared_total, cleared_by_color Six-color count. campaign_score=sum(score), campaign_moves_used=sum(moves_used), Only submitted records are counted. The current disk is frozen when the level is completed; The final battle summary removes the activity disk and displays the cumulative results. 
Validate the normal success and failure paths of every level using normal player input. State injection or temporary changes to target values cannot substitute for gameplay validation.
