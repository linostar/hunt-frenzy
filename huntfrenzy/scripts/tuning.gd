class_name Tuning
extends Resource
## The run's feel tuning: res://data/tuning.tres (Game.tuning), edited in the inspector. The
## birds, modes and levels are data/*.json; these are the timings and sizes of how a run
## feels, read by Play, RivalController, ScreenShake, the title, the feathers and the screen
## transitions (SceneFlow). The defaults here are the
## shipped values; the .tres lists them too, but the editor drops a line equal to its default
## when it saves, so the .tres may hold only what differs. test_gameplay's
## _test_tuning_values pins every value, so a deliberate change updates it there as well.

## The shipped tuning, loaded once by the Game autoload (Game.tuning: one shared object for
## the whole process, every reader and both test scripts; a test that changes a value puts it
## back, as _test_tuning_values, run first and last, checks).
const PATH := "res://data/tuning.tres"

@export_group("Run")
## Seconds between a wave's start and its first spawn.
@export_range(0.0, 5.0, 0.05, "suffix:s") var wave_lead := 1.0
## Seconds a new backdrop takes to fade in over the old one (within a wave's lead-in).
@export_range(0.0, 5.0, 0.05, "suffix:s") var backdrop_fade_time := 0.8
## A timed run ticks at each of its last this many whole seconds.
@export_range(0, 60) var countdown_seconds := 10
## The run's most frequent sounds (ShotResolver.VARIED_SOUNDS) play each time at a pitch up to this
## much (a fraction) off 1, drawn from an RNG seeded by the run seed.
@export_range(0.0, 0.5, 0.005) var sound_pitch_spread := 0.04

@export_group("Hit stop")
## Seconds a kill stops the world, and for an armored or golden kill.
@export_range(0.0, 0.5, 0.01, "suffix:s") var hit_stop_time := 0.05
@export_range(0.0, 0.5, 0.01, "suffix:s") var hit_stop_heavy_time := 0.09

@export_group("Pop-ups")
## Pop-ups bounce in to popup_bounce_scale (over popup_bounce_time, then back to their size);
## a combo pop-up grows by popup_combo_growth per multiplier step (at most
## popup_combo_scale_max); a penalty pop-up shakes popup_shake either way popup_shakes times
## over popup_shake_time; all rise popup_rise and fade over popup_time.
@export_range(1.0, 3.0, 0.05) var popup_bounce_scale := 1.35
@export_range(0.0, 1.0, 0.01, "suffix:s") var popup_bounce_time := 0.18
@export_range(0.0, 1.0, 0.01) var popup_combo_growth := 0.12
@export_range(1.0, 3.0, 0.05) var popup_combo_scale_max := 1.6
@export_range(0.0, 30.0, 0.5, "suffix:u") var popup_shake := 6.0
@export_range(0, 20) var popup_shakes := 4
@export_range(0.0, 2.0, 0.01, "suffix:s") var popup_shake_time := 0.32
@export_range(0.0, 200.0, 1.0, "suffix:u") var popup_rise := 48.0
@export_range(0.1, 5.0, 0.05, "suffix:s") var popup_time := 0.8

@export_group("Screen shake")
## Screen shake per event: [amplitude in base units, seconds]. The world's offset decays as
## (1 - t / time)^2 and is exactly zero once the time is over. Keep every amplitude within
## ScreenShake.SHAKE_MARGIN, or a shake bares the backdrop's edge.
@export var shakes: Dictionary[String, Array] = {
	"armored kill": [6.0, 0.25], "golden kill": [8.0, 0.3], "decoy hit": [10.0, 0.3], "steal": [7.0, 0.3], "lost wave": [12.0, 0.4],
}
## How fast the shake swings (per second).
@export_range(1.0, 60.0, 0.5, "suffix:Hz") var shake_hz := 18.0

@export_group("Rival")
## Seconds a heckle stays in the rival's bubble.
@export_range(0.5, 10.0, 0.1, "suffix:s") var heckle_time := 2.5
## Seconds (run_clock) the rival sulks after a scored hit, or brags after a miss heckle.
@export_range(0.0, 5.0, 0.1, "suffix:s") var rival_reaction_time := 1.2
## Seconds of run_clock after a steal or a cancelled cue before the rival aims again.
@export_range(0.0, 10.0, 0.1, "suffix:s") var rival_aim_gap := 1.5
## Seconds after the rival's shot (rival_steal) that his laugh (rival_laugh) starts.
@export_range(0.0, 2.0, 0.05, "suffix:s") var rival_laugh_delay := 0.3

@export_group("Feathers")
## A kill's feathers leave at feather_speed_min..max (base units per second) within a
## feather_fan-degree fan around straight up, spinning up to feather_spin radians per second
## either way; gravity pulls them down, drag is the fraction of their speed kept per second,
## and they sway feather_sway units either way at feather_sway_hz while they drift.
@export_range(0.0, 1000.0, 1.0, "suffix:u/s") var feather_speed_min := 160.0
@export_range(0.0, 1000.0, 1.0, "suffix:u/s") var feather_speed_max := 320.0
@export_range(0.0, 360.0, 1.0, "suffix:deg") var feather_fan := 150.0
@export_range(0.0, 30.0, 0.5, "suffix:rad/s") var feather_spin := 6.0
@export_range(0.0, 2000.0, 1.0, "suffix:u/s/s") var feather_gravity := 260.0
@export_range(0.0, 1.0, 0.01) var feather_drag := 0.12
@export_range(0.0, 100.0, 0.5, "suffix:u") var feather_sway := 22.0
@export_range(0.0, 10.0, 0.1, "suffix:Hz") var feather_sway_hz := 1.6
## Each feather lives a seeded feather_life_min..max seconds, fading over its last
## feather_fade_time.
@export_range(0.1, 5.0, 0.05, "suffix:s") var feather_life_min := 0.9
@export_range(0.1, 5.0, 0.05, "suffix:s") var feather_life_max := 1.4
@export_range(0.0, 2.0, 0.05, "suffix:s") var feather_fade_time := 0.35

@export_group("Screen transitions")
## Seconds the marsh-grass wipe (Wipe) takes to rise over the screen, and again to sink away
## (at most 0.4 each: plan AC 3), and the plain fade (reduce motion) each way.
@export_range(0.05, 0.4, 0.01, "suffix:s") var wipe_time := 0.35
@export_range(0.05, 1.0, 0.01, "suffix:s") var fade_time := 0.15

@export_group("Title")
## Seconds between two geese crossing the title's sky (seeded in this range), the most
## crossing at once, and when the first sets off after the title arrives.
@export_range(0.1, 10.0, 0.1, "suffix:s") var title_goose_gap_min := 1.6
@export_range(0.1, 10.0, 0.1, "suffix:s") var title_goose_gap_max := 3.0
@export_range(1, 10) var title_geese_max := 4
@export_range(0.0, 10.0, 0.05, "suffix:s") var title_first_goose_at := 0.1
## The scenery's slow sway: base units either way, seconds per swing (off with reduce motion).
@export_range(0.0, 40.0, 0.5, "suffix:u") var title_drift_amplitude := 10.0
@export_range(1.0, 120.0, 1.0, "suffix:s") var title_drift_period := 24.0
