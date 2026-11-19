# Pocket Greenhouse Game Design Document

## 1. Overview

A single-player, fixed-view resource-management game controlled by mouse clicks.
Manage three plots over four days and deliver **2 Sunberry and 1 Moonleaf** using
limited coins and daily water.
Character movement and keyboard input are unnecessary. All required actions
must work through normal left mouse clicks.

## 2. Platform and presentation

Roblox Studio. Recommended resolution: 1280x720, adapting to common window sizes.
Use a fixed camera showing three plots, resources, order, feedback, and every
action button. A 2D ScreenGui or fixed-camera 3D greenhouse is allowed; rules
remain identical.

## 3. Initial state

[STATE-01] Start begins a new round with Day=1, Coins=8, Water=4, Sunberry
Inventory=0, Moonleaf Inventory=0, all three plots empty, no selection, and no
terminal outcome.
[UI-01] The start screen shows title, order target, and Start. It is no longer
needed during gameplay.

## 4. Plot selection

Plot 1/2/3 are mechanically equivalent.
[SELECT-01] Clicking a plot selects it with a clear visual indicator. Clicking
another transfers selection. Selection consumes no resources.

## 5. Crops and planting

| Crop | Cost | Successful watered days to mature | Yield |
|---|---:|---:|---|
| Sunberry | 3 Coins | 2 | 1 Sunberry |
| Moonleaf | 2 Coins | 1 | 1 Moonleaf |

[PLANT-01] With an empty selected plot and enough coins, the corresponding Plant
button deducts the correct cost and creates the crop in its unwatered stage.
[PLANT-02] Reject no selection, occupied plot, or insufficient coins. Preserve
plot, coins, and inventory; show the reason.
[PLANT-03] At most one crop per plot. Both types are distinguishable by visuals
or labels.

## 6. Watering and growth

[WATER-01] With a selected immature crop not watered today, Water consumes 1
water, marks it watered, and gives visual feedback.
[WATER-02] Reject no selection, empty plot, mature crop, already watered today,
or Water=0 without consuming water; show the reason.
[DAY-01] End Day advances each watered immature crop by one stage. Unwatered
crops do not grow, wilt, or disappear. Reset immature crops to dry, advance the
day, and restore Water=4.
[DAY-02] Sunberry matures after two successful watered days; Moonleaf after one.
Further End Day does not alter or remove mature crops.

## 7. Harvest

[HARVEST-01] Harvest a selected mature crop to add one matching inventory item
and empty the plot. Reject empty/immature plots without state change and explain.

## 8. Order and delivery

The fixed order is 2 Sunberry + 1 Moonleaf, with no additional coin/water cost.
[DELIVER-01] Deliver succeeds only with at least those inventories. Premature
delivery preserves inventory, day, and plots and reports missing crops.
[WIN-01] Valid delivery immediately enters won, marks the order complete, and
shows success. Plant, Water, Harvest, End Day, and Deliver no longer change state;
Restart remains usable.

## 9. Deadline and defeat

[LOSE-01] End Day on days 1/2/3 advances normally. On **Day 4**, if the order has
not succeeded, End Day immediately enters lost without Day 5.
Show a clear missed-deadline reason. Only Restart changes gameplay afterward.

## 10. HUD and feedback

[HUD-01] Continuously show Day with Day 4 deadline, Coins, Water, both inventories,
fixed order, and selected plot.
[FEEDBACK-01] Every valid/invalid action gives short, clear visible feedback for
at least 1 second. Audio/particles alone are insufficient.
Examples: Plot 2 watered; Already watered today; Need 1 more Sunberry.

## 11. Restart and Reopen

[RESET-01] Restart works in playing/won/lost and directly creates a new round
matching STATE-01. No stale crops, selection, feedback, or terminal overlay.
[REOPEN-01] Closing and reopening the delivered project returns to the start
screen. No cross-session progress persistence is required.

## 12. Public dashboard

[DASH-01] Provide ReplicatedStorage/BenchmarkDashboard ModuleScript exporting
only GetSnapshot(), matching DASHBOARD_SPEC.md and naming-tables.json.
[DASH-02] Snapshots honestly mirror visible and actual state. Increment revision
after normal gameplay changes. Expose no planting, watering, day advance,
delivery, restart, outcome, or other state-changing methods.

## 13. Presentation freedom

Art style, decoration, animation, sound, UI layout, and internal code may vary.
Do not change values, rules, terminal conditions, or fixed dashboard names.
No random economy, automatic actions, daily countdown, or additional
outcome-changing systems.
