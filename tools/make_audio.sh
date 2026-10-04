#!/usr/bin/env bash
# Synthesizes SYNAPSE-2076's music and sound effects from scratch with ffmpeg
# (oscillators, noise and filters; no samples or outside recordings) and
# writes them as Ogg Vorbis into assets/audio/music and assets/audio/sfx.
#
#   tools/make_audio.sh                   # render everything, then print the level report
#   tools/make_audio.sh era_2 swipe_left  # render only these sounds
#   tools/make_audio.sh --report          # report on the files on disk, render nothing
#   FFMPEG=/opt/ffmpeg/bin/ffmpeg AUDIO_OUT=/tmp/audio tools/make_audio.sh
#
# Deterministic: noise comes from seeded generators and the encoder runs in
# bit-exact mode, so one ffmpeg build always writes the same files.
#
# Loops. Every oscillator, LFO and note pattern completes a whole number of
# cycles in LOOP seconds (frequencies are rounded to multiples of 1/LOOP Hz)
# and noise beds repeat every LOOP seconds. Two periods are rendered through
# the effects (reverb, echoes, filters) and only the second is kept, so the
# loop's tail runs into its head with matched phase: no fade, no click. The
# report compares the jump at the loop point with the steps between
# neighboring samples elsewhere in the file ("seam ok" when it is no larger).
#
# Levels. Loops sit at MUSIC_LUFS integrated loudness; each effect is scaled
# to its own maximum momentary loudness (a quiet tap, a louder alert);
# nothing goes above CEILING dBTP. Effects end in a short fade.
#
# After changing the sounds, run `godot --headless --path . --import` and
# commit the .ogg files with their .import files (the loops keep loop=true).
set -euo pipefail

FFMPEG="${FFMPEG:-ffmpeg}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${AUDIO_OUT:-${ROOT}/assets/audio}"
RATE=44100
## Loop length in seconds: 32 beats at 80 BPM.
LOOP=24
MUSIC_LUFS=-24
## Highest true peak allowed in any file (dBTP).
CEILING=-1.5
MUSIC_QUALITY=0
SFX_QUALITY=4

MUSIC=(era_1 era_2 era_3)
SFX=(card_appear swipe_left swipe_right option_select execute headline_ping alert era_upgrade
	goal_met goal_missed deal tap page_turn fallout)

WORK="$(mktemp -d)"
if [[ -n "${KEEP_WORK:-}" ]]; then
	echo "Intermediate files: ${WORK}"
else
	trap 'rm -rf "${WORK}"' EXIT
fi

ff() {
	"${FFMPEG}" -hide_banner -nostdin -loglevel error -y "$@"
}

# --- Note and expression helpers ---------------------------------------------------------
#
# Expressions are ffmpeg aevalsrc expressions. Templates use the symbol T for
# time so that a layer can be evaluated at a delay (see `at`); st()/ld()
# registers keep state from sample to sample (envelopes, filters):
#   0-5  chord sections (`sections`)    6-8  pulses and glints
#   9    struck tones (`strike`)        1-4  or 5-8  noise filters (`svf`, effects only)

## note NAME -> frequency in Hz (A4 = 440, equal temperament) rounded to a
## whole number of cycles per loop. NAME is a letter, an optional # or b and
## an octave: C4, F#3, Bb2.
note() {
	awk -v name="$1" -v loop="${LOOP}" 'BEGIN {
		semis["C"] = 0; semis["D"] = 2; semis["E"] = 4; semis["F"] = 5; semis["G"] = 7; semis["A"] = 9; semis["B"] = 11
		letter = substr(name, 1, 1); rest = substr(name, 2); shift = 0
		if (substr(rest, 1, 1) == "#") { shift = 1; rest = substr(rest, 2) }
		else if (substr(rest, 1, 1) == "b") { shift = -1; rest = substr(rest, 2) }
		midi = 12 * (rest + 1) + semis[letter] + shift
		f = 440 * 2 ^ ((midi - 69) / 12)
		printf "%.9f", int(f * loop + 0.5) / loop
	}'
}

## calc EXPR -> the value of an awk arithmetic expression.
calc() {
	awk "BEGIN { printf \"%.9f\", $1 }"
}

## phase FREQ -> a start phase (radians) spread by the golden ratio, so
## stacked partials never all peak at once.
phase() {
	awk -v f="$1" 'BEGIN { x = f * 0.6180339887; printf "%.4f", (x - int(x)) * 6.283185 }'
}

## partials FREQ PHASE A1 A2 ... -> harmonics h*FREQ with amplitudes Ah.
partials() {
	local f=$1 p=$2 out="" h=1 a
	shift 2
	for a in "$@"; do
		if [[ "${a}" != 0 ]]; then
			out+="${out:++}${a}*sin(${h}*(2*PI*${f}*T+${p}))"
		fi
		h=$((h + 1))
	done
	printf '(%s)' "${out}"
}

## pad_voice NOTE SIDE A1 A2 ... -> a soft tone plus a quieter copy detuned
## by 1-3 cycles per loop (sharp on the left, SIDE 1; flat on the right,
## SIDE -1), which beats slowly against it.
pad_voice() {
	local name=$1 side=$2 f p detune
	shift 2
	f=$(note "${name}")
	p=$(phase "${f}")
	detune=$(awk -v f="${f}" -v s="${side}" -v loop="${LOOP}" 'BEGIN { k = (int(f) % 3) + 1; printf "%.9f", f + s * k / loop }')
	printf '(%s+0.45*%s)' "$(partials "${f}" "${p}" "$@")" "$(partials "${detune}" "$(calc "${p} + 1.3")" 1 0.2)"
}

## at TIME EXPR -> EXPR with the time symbol T replaced by TIME.
at() {
	local time=$1 expr=$2
	printf '%s' "${expr//T/${time}}"
}

## sections SPAN FADE EXPR... -> the loop cut into SPAN-second sections, the
## k-th playing the k-th EXPR (at most four), with raised-cosine crossfades
## of FADE seconds centered on the section edges (neighbors sum to one).
sections() {
	local span=$1 fade=$2 k=0 expr body="" start end
	shift 2
	local out="st(0,mod(T,${LOOP}))"
	for expr in "$@"; do
		start=$(calc "${k} * ${span} - ${fade} / 2")
		end=$(calc "${span} + ${fade}")
		out+=";st(5,mod(ld(0)-(${start}),${LOOP}))"
		out+=";st($((k + 1)),if(lt(ld(5),${fade}),sin(PI/2*ld(5)/${fade})^2,if(lt(ld(5),${span}),1,if(lt(ld(5),${end}),cos(PI/2*(ld(5)-${span})/${fade})^2,0))))"
		body+="${body:++}if(gt(ld($((k + 1))),0),ld($((k + 1)))*(${expr}),0)"
		k=$((k + 1))
	done
	printf '(%s;%s)' "${out}" "${body}"
}

## lookup INDEX_EXPR VALUE... -> VALUE number INDEX_EXPR (0-based); "-" is 0.
lookup() {
	local index=$1 i=0 value out="" close=""
	shift
	for value in "$@"; do
		[[ "${value}" == "-" ]] && value=0
		if [[ $i -lt $(($# - 1)) ]]; then
			out+="if(eq(${index},${i}),${value},"
			close+=")"
		else
			out+="${value}"
		fi
		i=$((i + 1))
	done
	printf '%s%s' "${out}" "${close}"
}

## strike ONSET FREQ ATTACK RATIO:AMP:DECAY... -> a struck tone (bell, glass,
## pluck) that starts at ONSET seconds: partials at FREQ*RATIO, each decaying
## with its own time constant. Uses register 9 and the time symbol t.
strike() {
	local onset=$1 f=$2 attack=$3 out="" spec ratio amp decay
	shift 3
	for spec in "$@"; do
		IFS=: read -r ratio amp decay <<<"${spec}"
		out+="${out:++}${amp}*exp(-ld(9)/${decay})*sin(2*PI*$(calc "${f} * ${ratio}")*ld(9))"
	done
	printf 'if(gte(t,%s),(st(9,t-%s);(1-exp(-ld(9)/%s))*(%s)),0)' "${onset}" "${onset}" "${attack}" "${out}"
}

## glide F_START F_END TAU -> the phase (radians) of a tone sliding
## exponentially from F_START to F_END Hz with time constant TAU.
glide() {
	printf '(2*PI*(%s*t+(%s-%s)*%s*(1-exp(-t/%s))))' "$2" "$1" "$2" "$3" "$3"
}

## svf CUTOFF DAMPING BASE -> white noise through a state-variable filter
## (registers BASE..BASE+3), band-pass output. CUTOFF is an expression (Hz).
svf() {
	local fc=$1 damp=$2 b=$3
	printf '(st(%d,2*sin(PI*min(%s,8000)/%d));st(%d,ld(%d)+ld(%d)*ld(%d));st(%d,random(0)*2-1-ld(%d)-%s*ld(%d));st(%d,ld(%d)+ld(%d)*ld(%d));ld(%d))' \
		$((b + 2)) "${fc}" "${RATE}" \
		"${b}" "${b}" $((b + 2)) $((b + 1)) \
		$((b + 3)) "${b}" "${damp}" $((b + 1)) \
		$((b + 1)) $((b + 1)) $((b + 2)) $((b + 3)) \
		$((b + 1))
}

## smooth X A B -> 0 for X <= A, 1 for X >= B, smoothstep between.
smooth() {
	printf '(clip((%s-(%s))/((%s)-(%s)),0,1)^2*(3-2*clip((%s-(%s))/((%s)-(%s)),0,1)))' "$1" "$2" "$3" "$2" "$1" "$2" "$3" "$2"
}

## stereo_ir SECONDS DECAY_SHORT DECAY_LONG -> a decorrelated stereo impulse
## response: noise with two exponential decays.
stereo_ir() {
	local d=$1 short=$2 long=$3
	local body="(0.62*exp(-t/${short})+0.38*exp(-t/${long}))*(1-exp(-t/0.004))"
	printf "aevalsrc=exprs='(random(0)*2-1)*%s|if(eq(n,0),st(1,987654321),0);(random(1)*2-1)*%s':d=%s:s=%s:c=stereo" \
		"${body}" "${body}" "${d}" "${RATE}"
}

## noise_bed SEED LOW HIGH GAIN -> LOOP seconds of pink noise band-passed to
## LOW..HIGH Hz and repeated once (two periods), mono.
noise_bed() {
	local seed=$1 low=$2 high=$3 gain=$4
	printf "anoisesrc=d=%s:c=pink:r=%s:a=1:seed=%s,aloop=loop=1:size=%s,highpass=f=%s:p=2,lowpass=f=%s:p=2,volume=%s" \
		"${LOOP}" "${RATE}" "${seed}" "$((LOOP * RATE))" "${low}" "${high}" "${gain}"
}

## stereo_bed NAME SEED LOW HIGH GAIN TREMOLO_HZ DEPTH -> "[NAME]": two
## decorrelated noise beds with a slow tremolo, joined into stereo.
stereo_bed() {
	local name=$1 seed=$2 low=$3 high=$4 gain=$5 rate=$6 depth=$7
	printf '%s,tremolo=f=%s:d=%s[%sl];%s,tremolo=f=%s:d=%s[%sr];[%sl][%sr]join=inputs=2:channel_layout=stereo[%s]' \
		"$(noise_bed "${seed}" "${low}" "${high}" "${gain}")" "${rate}" "${depth}" "${name}" \
		"$(noise_bed $((seed + 1)) "${low}" "${high}" "${gain}")" "${rate}" "${depth}" "${name}" \
		"${name}" "${name}" "${name}"
}

# --- Rendering, measuring and encoding ------------------------------------------------------

## render_loop NAME LEFT RIGHT BED_GRAPH WET IR_SECONDS IR_SHORT IR_LONG IR_LOWPASS
## LEFT and RIGHT are channel expressions in t; BED_GRAPH adds layers that
## end in [bed] (stereo, two periods). Mixes them, adds a convolution reverb,
## keeps the second period and writes WORK/NAME.wav. (amerge lines streams up
## sample by sample; amix would start the dry branch while afir buffers.)
render_loop() {
	local name=$1 left=$2 right=$3 bed=$4 wet=$5 ir_d=$6 ir_short=$7 ir_long=$8 ir_low=$9
	local graph="aevalsrc=exprs='${left}|${right}':d=$((LOOP * 2)):s=${RATE}:c=stereo[tone]"
	graph+=";${bed}"
	graph+=";[tone][bed]amerge=inputs=2,pan=stereo|c0=c0+c2|c1=c1+c3,lowpass=f=9000[dry0]"
	graph+=";[dry0]asplit=2[dry][send]"
	graph+=";$(stereo_ir "${ir_d}" "${ir_short}" "${ir_long}"),highpass=f=160,lowpass=f=${ir_low}[ir]"
	graph+=";[send][ir]afir=gtype=gn:irfmt=input[wet]"
	graph+=";[dry][wet]amerge=inputs=2,pan=stereo|c0=c0+${wet}*c2|c1=c1+${wet}*c3,highpass=f=28"
	graph+=",atrim=start=${LOOP}:end=$((LOOP * 2)),asetpts=PTS-STARTPTS[out]"
	printf '%s\n' "${graph}" >"${WORK}/${name}.graph"
	ff -filter_complex "${graph}" -map "[out]" -c:a pcm_f32le -ar "${RATE}" "${WORK}/${name}.wav"
}

## render_sfx NAME DURATION FADE EXPR [STEREO_RIGHT_EXPR] -> WORK/NAME.wav:
## the expression (mono, or stereo when a right channel is given),
## high-passed, fading out over the last FADE seconds.
render_sfx() {
	local name=$1 d=$2 fade=$3 left=$4 right=${5:-} exprs layout=mono
	exprs="${left}"
	if [[ -n "${right}" ]]; then
		exprs="${left}|${right}"
		layout=stereo
	fi
	local graph
	graph="aevalsrc=exprs='${exprs}':d=${d}:s=${RATE}:c=${layout},highpass=f=35,afade=t=out:st=$(calc "${d} - ${fade}"):d=${fade}[out]"
	printf '%s\n' "${graph}" >"${WORK}/${name}.graph"
	ff -filter_complex "${graph}" -map "[out]" -c:a pcm_f32le -ar "${RATE}" "${WORK}/${name}.wav"
}

## measure FILE -> "INTEGRATED MOMENTARY_MAX TRUE_PEAK SAMPLE_PEAK" (LUFS, LUFS, dBTP, dBFS).
measure() {
	"${FFMPEG}" -hide_banner -nostdin -nostats -i "$1" -af "apad=pad_dur=0.5,ebur128=framelog=info:peak=true+sample" -f null - 2>&1 |
		awk '
			/ M:/ && match($0, /M: *-?[0-9.]+/) {
				value = substr($0, RSTART + 2, RLENGTH - 2) + 0
				if (seen == 0 || value > momentary) { momentary = value; seen = 1 }
			}
			/Integrated loudness:/ { section = "I" }
			/Sample peak:/ { section = "S" }
			/True peak:/ { section = "T" }
			section == "I" && $1 == "I:" { integrated = $2 }
			section == "S" && $1 == "Peak:" { sample = $2 }
			section == "T" && $1 == "Peak:" { truepeak = $2 }
			END { printf "%s %s %s %s\n", integrated, momentary, truepeak, sample }'
}

## normalize IN OUT TARGET KIND -> scales IN so that its integrated (KIND=I)
## or maximum momentary (KIND=M) loudness reaches TARGET LUFS, never letting
## the true peak pass CEILING (with 0.3 dB to spare for the encoder).
normalize() {
	local in=$1 out=$2 target=$3 kind=$4 levels gain
	levels=$(measure "${in}")
	gain=$(awk -v l="${levels}" -v target="${target}" -v kind="${kind}" -v ceiling="${CEILING}" 'BEGIN {
		split(l, v, " ")
		loud = (kind == "I") ? v[1] : v[2]
		g = target - loud
		if (v[3] + g > ceiling - 0.3) g = ceiling - 0.3 - v[3]
		printf "%.2f", g
	}')
	ff -i "${in}" -af "volume=${gain}dB" -c:a pcm_f32le "${out}"
}

## encode IN OUT QUALITY -> bit-exact Ogg Vorbis without metadata.
encode() {
	ff -i "$1" -map_metadata -1 -fflags +bitexact -flags:a +bitexact -c:a libvorbis -q:a "$3" "$2"
}

## seam FILE -> "JUMP TYPICAL": the largest step from the last frame back to
## the first (over both channels) and the 99.9th percentile of the steps
## between neighboring frames.
seam() {
	"${FFMPEG}" -hide_banner -nostdin -loglevel error -i "$1" -f s16le -ac 2 -acodec pcm_s16le - |
		od -An -v -t d2 -w4 |
		awk '
			NR == 1 { first_l = $1; first_r = $2 }
			NR > 1 { dl = $1 - pl; dr = $2 - pr; d = (dl < 0 ? -dl : dl); e = (dr < 0 ? -dr : dr); count[(d > e ? d : e)]++; n++ }
			{ pl = $1; pr = $2 }
			END {
				jl = pl - first_l; jr = pr - first_r
				jl = (jl < 0 ? -jl : jl); jr = (jr < 0 ? -jr : jr)
				rank = int(n * 0.999); total = 0
				for (v = 0; v <= 65536; v++) { total += count[v]; if (total >= rank) { typical = v; break } }
				printf "%d %d\n", (jl > jr ? jl : jr), typical
			}'
}

## frames FILE -> decoded length in sample frames.
frames() {
	"${FFMPEG}" -hide_banner -nostdin -loglevel error -i "$1" -f s16le -ac 1 -acodec pcm_s16le - | wc -c | awk '{ print $1 / 2 }'
}

# --- Music ------------------------------------------------------------------------------------

## Era I (2026-2035): a clean, calm synth pad in D major, Dmaj9 - Bm9 -
## Gmaj9 - Em9/A, six seconds each at 80 BPM, breathing gently on every
## beat, over a soft eighth-note pulse that echoes left and right.
music_era_1() {
	local chords=("F#3 A3 C#4 E4" "F#3 A3 C#4 D4" "F#3 A3 B3 D4" "G3 B3 D4 E4")
	local basses=(D2 B1 G1 A1) tops=(F#5 C#5 D5 E5) pulses=(D4 B3 G3 A3)
	local side k n f channels=()
	for side in 1 -1; do
		local parts=()
		for k in 0 1 2 3; do
			local voices=""
			for n in ${chords[k]}; do
				voices+="${voices:++}$(pad_voice "${n}" "${side}" 1 0.42 0.2 0.1 0.055 0.03)"
			done
			f=$(note "${basses[k]}")
			voices+="+0.85*$(partials "${f}" 0 1 0.45 0.15)"
			f=$(note "${tops[k]}")
			voices+="+1.0*$(partials "${f}" "$(phase "${f}")" 1 0.12 0.04)*(0.7+0.3*sin(2*PI*T/12+${side}))"
			parts+=("${voices}")
		done
		# The pad dips a little on every beat (0.75 s), like a slow heartbeat.
		channels+=("0.07*(1-0.16*(0.5+0.5*cos(2*PI*T/0.75))^3)*$(sections 6 1.6 "${parts[@]}")")
	done
	# Eighth notes on the chord's root, accented on the beat.
	local pitch
	pitch=$(lookup "ld(7)" "$(note "${pulses[0]}")" "$(note "${pulses[1]}")" "$(note "${pulses[2]}")" "$(note "${pulses[3]}")")
	local pulse="(st(6,mod(T,0.375));st(7,floor(mod(T,${LOOP})/6));st(8,${pitch});if(mod(floor(T/0.375+0.0001),2),0.55,1)*(1-exp(-ld(6)/0.005))*exp(-ld(6)/0.09)*min(1,(0.375-ld(6))/0.02)*(sin(2*PI*ld(8)*T)+0.45*sin(4*PI*ld(8)*T)+0.2*sin(6*PI*ld(8)*T)+0.08*sin(8*PI*ld(8)*T)))"
	local left right
	left="$(at t "${channels[0]}")+0.12*($(at t "${pulse}")+0.32*$(at "(t-0.75)" "${pulse}"))"
	right="$(at t "${channels[1]}")+0.12*($(at t "${pulse}")+0.32*$(at "(t-0.5625)" "${pulse}"))"
	render_loop era_1 "${left}" "${right}" "$(stereo_bed bed 11 2600 9000 0.16 0.125 0.5)" 0.5 3.0 0.25 0.6 5200
}

## glint VOICE PITCHES... -> a glass-like strike every two seconds (voice 0 on
## even seconds, voice 1 on odd ones) at the pitch listed for that second of
## the loop ("-" rests); each rings out and fades before the next.
glint() {
	local voice=$1
	shift
	local pitch
	pitch=$(lookup "ld(7)" "$@")
	printf '(st(6,mod(T-%s,2));st(7,mod(floor((T-%s)/2)*2+%s,%s));st(8,%s);gt(ld(8),0)*(1-exp(-ld(6)/0.002))*(1-%s)*(exp(-ld(6)/0.55)*sin(2*PI*ld(8)*ld(6))+0.28*exp(-ld(6)/0.2)*sin(4*PI*ld(8)*ld(6))+0.1*exp(-ld(6)/0.09)*sin(6*PI*ld(8)*ld(6))+0.06*exp(-ld(6)/0.05)*sin(2*PI*4.2*ld(8)*ld(6))))' \
		"${voice}" "${voice}" "${voice}" "${LOOP}" "${pitch}" "$(smooth "ld(6)" 1.7 1.98)"
}

## Era II (2036-2049): warmer, in A-flat: Abmaj9 - Fm11 - Dbmaj9(#11) -
## Eb6/9sus under a shimmer of high partials that swell and fade at their own
## rates, with slow arpeggiated glints passing left and right.
music_era_2() {
	local chords=("Eb3 G3 Bb3 C4" "Eb3 Ab3 Bb3 C4" "F3 G3 C4 Eb4" "F3 Bb3 C4 Eb4")
	local basses=(Ab1 F1 Db2 Eb2)
	local melody=(Eb6 C6 G6 Bb5 - C6 Ab5 C6 Eb6 F6 - Eb6 F5 Ab5 C6 Db6 - C6 Bb5 Eb6 F6 Bb6 - -)
	local side k n f channels=()
	local hz=()
	for n in "${melody[@]}"; do
		if [[ "${n}" == "-" ]]; then hz+=("-"); else hz+=("$(note "${n}")"); fi
	done
	for side in 1 -1; do
		local parts=()
		for k in 0 1 2 3; do
			local voices=""
			for n in ${chords[k]}; do
				voices+="${voices:++}$(pad_voice "${n}" "${side}" 1 0.5 0.32 0.2 0.12 0.07)"
			done
			f=$(note "${basses[k]}")
			voices+="+0.8*$(partials "${f}" 0 1 0.5 0.25)"
			parts+=("${voices}")
		done
		# Shimmer: Eb6 F6 Bb6 C7 fit every chord; each swells on its own cycle.
		local shimmer="" i=0 periods=(8 6 4.8 12)
		for n in Eb6 F6 Bb6 C7; do
			f=$(note "${n}")
			shimmer+="${shimmer:++}(0.5-0.5*cos(2*PI*T/${periods[i]}+${side}*$((i + 1))))^2*sin(2*PI*${f}*T+$(phase "${f}"))"
			i=$((i + 1))
		done
		channels+=("0.06*$(sections 6 2.0 "${parts[@]}")+0.022*(${shimmer})")
	done
	local g0 g1
	g0=$(glint 0 "${hz[@]}")
	g1=$(glint 1 "${hz[@]}")
	local left right
	left="$(at t "${channels[0]}")+0.12*(0.85*$(at t "${g0}")+0.45*$(at t "${g1}")+0.3*$(at "(t-0.75)" "${g1}"))"
	right="$(at t "${channels[1]}")+0.12*(0.45*$(at t "${g0}")+0.85*$(at t "${g1}")+0.3*$(at "(t-0.75)" "${g0}"))"
	render_loop era_2 "${left}" "${right}" "$(stereo_bed bed 21 3000 9500 0.13 0.25 0.6)" 0.6 3.5 0.3 0.8 6000
}

## Era III (2050-2076): an eerie, luminous drone on D. Its natural harmonics
## (the 7th, 9th, 11th and 13th) bloom and fade on long cycles, slightly
## detuned pairs beat slowly (every 2, 3, 4 and 6 seconds), a high voice
## warbles, and a low breath of noise moves underneath.
music_era_3() {
	local side channels=()
	local d2 a2 d4 gs4 d6 d7
	d2=$(note D2); a2=$(note A2); d4=$(note D4); gs4=$(note G#4); d6=$(note D6); d7=$(note D7)
	for side in 1 -1; do
		local s2=$(( side > 0 ? 1 : 2 ))
		local expr=""
		# Drone: root and fifth, each against a twin a fraction of a hertz away.
		expr+="0.3*($(partials "${d2}" 0.3 1 0.5 0.33 0.22 0.12)+0.8*$(partials "$(calc "${d2} + 0.25")" 1.9 1 0.4 0.2))"
		expr+="+0.2*($(partials "${a2}" 1.1 1 0.35 0.15)+0.8*$(partials "$(calc "${a2} + ${s2} / 6")" 2.6 1 0.3))"
		# Beating mids: D4 against a twin 0.5 Hz away; G#4 (the tritone) 1/3 Hz away.
		expr+="+0.32*(0.6+0.4*sin(2*PI*T/24+${side}))*(sin(2*PI*${d4}*T)+sin(2*PI*$(calc "${d4} + 0.5")*T+0.7))"
		expr+="+0.26*(0.5-0.5*cos(2*PI*T/12))*(sin(2*PI*${gs4}*T+1.3)+sin(2*PI*$(calc "${gs4} + ${s2} / 3")*T+2.1))"
		# Natural harmonics of D2 bloom in and out.
		local h i=0 periods=(24 12 8 24) offsets=(0 1.2 2.4 3.14)
		for h in 7 9 11 13; do
			expr+="+0.26*(0.5-0.5*cos(2*PI*T/${periods[i]}+${offsets[i]}+${side}*0.4))^2*sin(2*PI*$(calc "${d2} * ${h}")*T+$(phase "$(calc "${d2} * ${h}")"))"
			i=$((i + 1))
		done
		# A high voice that warbles, and a faint glassy pair far above.
		expr+="+0.1*(0.5-0.5*cos(2*PI*T/8+${side}))*sin(2*PI*${d6}*T+0.9*sin(2*PI*T/6))"
		expr+="+0.045*(sin(2*PI*${d7}*T)+sin(2*PI*$(calc "${d7} + 0.125")*T+${side}))"
		channels+=("0.12*(${expr})")
	done
	render_loop era_3 "$(at t "${channels[0]}")" "$(at t "${channels[1]}")" "$(stereo_bed bed 31 280 1400 0.11 0.125 0.7)" 0.7 4.5 0.45 1.4 4200
}

# --- Sound effects ------------------------------------------------------------------------------

## Target maximum momentary loudness (LUFS) per effect: interface ticks sit
## low, news in the middle, warnings on top.
sfx_target() {
	case "$1" in
		tap) echo -30 ;;
		option_select | page_turn) echo -27 ;;
		card_appear | swipe_left | swipe_right) echo -26 ;;
		headline_ping | goal_missed) echo -23 ;;
		execute | deal) echo -22 ;;
		goal_met | fallout) echo -21 ;;
		era_upgrade) echo -20 ;;
		alert) echo -18 ;;
		*) echo -24 ;;
	esac
}

## A soft tick: a short high blip over a lower one and a breath of noise.
sfx_tap() {
	render_sfx tap 0.09 0.02 "(1-exp(-t/0.0006))*(0.55*exp(-t/0.012)*sin(2*PI*1760*t)+0.35*exp(-t/0.02)*sin(2*PI*880*t)+0.2*exp(-t/0.004)*(random(0)*2-1))"
}

## A rounded wooden tock with a glassy fifth.
sfx_option_select() {
	render_sfx option_select 0.24 0.04 "$(strike 0 "$(note E5)" 0.001 1:0.7:0.05 1.5:0.35:0.03 3:0.15:0.015)"
}

## The crisis card arrives: an airy upward swoosh and a soft chime.
sfx_card_appear() {
	local swoosh
	swoosh="$(svf "600*5^(min(t,0.26)/0.26)" 0.7 1)*if(lt(t,0.18),$(smooth t 0 0.18),exp(-(t-0.18)/0.09))"
	render_sfx card_appear 0.6 0.08 "0.5*${swoosh}+0.3*$(strike 0.12 "$(note C6)" 0.002 1:1:0.17 1.5:0.55:0.12 2:0.2:0.06)"
}

## A swipe: a whoosh that falls (left) or rises (right) and pans to its side.
swipe() {
	local name=$1 from=$2 to=$3 near=$4 far=$5
	local whoosh
	whoosh="$(svf "${from}*(${to}/${from})^(min(t,0.28)/0.28)" 0.55 1)*$(smooth t 0 0.04)*(1-$(smooth t 0.1 0.31))"
	render_sfx "${name}" 0.33 0.03 "(${near})*${whoosh}" "(${far})*${whoosh}"
}

sfx_swipe_left() {
	swipe swipe_left 2600 650 "0.75+0.25*t/0.33" "0.75-0.5*t/0.33"
}

sfx_swipe_right() {
	swipe swipe_right 650 2600 "0.75-0.5*t/0.33" "0.75+0.25*t/0.33"
}

## Directives sent: a low thump and a rising two-note chime.
sfx_execute() {
	local thump
	thump="exp(-t/0.12)*(1-exp(-t/0.003))*(sin($(glide 120 55 0.05))+0.4*sin(2*$(glide 120 55 0.05)))"
	render_sfx execute 0.85 0.12 "0.6*${thump}+0.4*$(strike 0 "$(note E5)" 0.002 1:1:0.28 2:0.25:0.12 3:0.08:0.06)+0.42*$(strike 0.085 "$(note B5)" 0.002 1:1:0.3 2:0.22:0.12 3:0.07:0.06)"
}

## A newsroom ping: one bell strike with a faint echo.
sfx_headline_ping() {
	local bell
	bell="$(note E6) 0.0015 1:1:0.32 2:0.2:0.14 2.76:0.1:0.08 5.4:0.05:0.04"
	# shellcheck disable=SC2086
	render_sfx headline_ping 0.85 0.12 "$(strike 0 ${bell})+0.28*$(strike 0.13 ${bell})"
}

## A critical threshold: two tones alternating four times, firm but rounded.
sfx_alert() {
	local beep
	beep="st(6,mod(t,0.22));st(7,if(mod(floor(t/0.22),2),$(note F5),$(note A5)));lt(t,0.86)*$(smooth "ld(6)" 0 0.006)*(1-$(smooth "ld(6)" 0.145 0.17))"
	render_sfx alert 0.92 0.04 "(${beep})*(sin(2*PI*ld(7)*t)+0.1*sin(4*PI*ld(7)*t)+0.25*sin(6*PI*ld(7)*t)+0.08*sin(10*PI*ld(7)*t)+0.3*sin(2*PI*220*t))"
}

## The interface upgrades to a new era: a rising sweep over a noise riser
## that blooms into a bright chord.
sfx_era_upgrade() {
	local rise=1.25 f0=180 f1=1760 sweep riser bloom
	local k
	k=$(calc "2 * 3.14159265 * ${f0} * ${rise} / log(${f1} / ${f0})")
	sweep="if(lt(t,${rise}),(0.2+0.8*(t/${rise}))*(sin(${k}*(exp(t/${rise}*log(${f1}/${f0}))-1))+0.3*sin(2*${k}*(exp(t/${rise}*log(${f1}/${f0}))-1)))*(1-$(smooth t 1.15 "${rise}")),0)"
	riser="$(svf "400*15^(min(t,${rise})/${rise})" 0.6 1)*(t/${rise})^2*(1-$(smooth t 1.1 1.32))"
	bloom="$(strike 1.18 "$(note A5)" 0.004 1:1:0.26 2:0.2:0.12)+$(strike 1.18 "$(note C#6)" 0.004 1:0.8:0.25 2:0.15:0.11)+$(strike 1.18 "$(note E6)" 0.004 1:0.7:0.24 2:0.12:0.1)"
	render_sfx era_upgrade 1.6 0.15 "0.35*${sweep}+0.5*${riser}+0.4*(${bloom})"
}

## An era goal met: a bright two-note chime, a fifth apart.
sfx_goal_met() {
	render_sfx goal_met 0.95 0.12 "0.5*$(strike 0 "$(note C6)" 0.0015 1:1:0.35 2:0.3:0.15 3:0.1:0.08 4:0.04:0.05)+0.55*$(strike 0.12 "$(note G6)" 0.0015 1:1:0.38 2:0.3:0.15 3:0.1:0.08 4:0.04:0.05)"
}

## An era goal missed: one soft low tone that sinks a whole step.
sfx_goal_missed() {
	local p
	p=$(glide "$(note G3)" "$(note F3)" 0.25)
	render_sfx goal_missed 0.8 0.1 "$(smooth t 0 0.025)*exp(-t/0.3)*(sin(${p})+0.45*sin(2*${p})+0.22*sin(3*${p})+0.1*sin(4*${p}))"
}

## A deal struck: a soft clasp, two notes together, then a third above.
sfx_deal() {
	local clasp
	clasp="exp(-t/0.04)*(1-exp(-t/0.002))*sin($(glide 150 110 0.03))"
	render_sfx deal 0.95 0.12 "0.45*${clasp}+0.32*$(strike 0.01 "$(note G5)" 0.002 1:1:0.4 2:0.2:0.14 3:0.06:0.07)+0.3*$(strike 0.01 "$(note B5)" 0.002 1:1:0.38 2:0.2:0.13 3:0.06:0.07)+0.34*$(strike 0.13 "$(note D6)" 0.002 1:1:0.4 2:0.18:0.14 3:0.05:0.07)"
}

## A page turns: two papery swishes with a flutter.
sfx_page_turn() {
	local swish
	swish="$(svf "2800+1400*sin(2*PI*3*t)" 1.1 1)*(0.75+0.25*sin(2*PI*31*t)*sin(2*PI*47*t))"
	render_sfx page_turn 0.5 0.04 "${swish}*(0.55*$(smooth t 0.01 0.06)*(1-$(smooth t 0.12 0.2))+$(smooth t 0.15 0.24)*(1-$(smooth t 0.3 0.46)))"
}

## A crisis broke: a dull, heavy thud with a short rumble. The low boom has
## a muffled knock and a crumble of noise above it, so phone speakers, which
## drop everything under ~200 Hz, still carry the hit.
sfx_fallout() {
	local p thud knock
	p=$(glide 95 42 0.07)
	thud="exp(-t/0.22)*(1-exp(-t/0.004))*(sin(${p})+0.45*sin(2*${p})+0.2*sin(3*${p}))"
	p=$(glide 260 190 0.05)
	knock="exp(-t/0.07)*(1-exp(-t/0.003))*(sin(${p})+0.5*sin(2*${p})+0.25*sin(3*${p}))"
	render_sfx fallout 0.8 0.1 "0.7*${thud}+0.45*${knock}+0.4*$(svf 420 1.3 1)*exp(-t/0.045)+0.14*$(svf 160 0.9 5)*exp(-t/0.3)"
}

# --- Main -------------------------------------------------------------------------------------

report_line() {
	local file=$1 kind=$2 levels size length extra=""
	levels=$(measure "${file}")
	size=$(stat -c %s "${file}")
	length=$(frames "${file}")
	if [[ "${kind}" == music ]]; then
		extra=$(seam "${file}" | awk '{ printf "seam %d vs %d (%s)", $1, $2, ($1 <= $2 ? "ok" : "CHECK") }')
	fi
	awk -v f="${kind}/$(basename "${file}")" -v l="${levels}" -v s="${size}" -v n="${length}" -v r="${RATE}" -v x="${extra}" 'BEGIN {
		split(l, v, " ")
		printf "%-24s %6.3f s %6.1f KB  I %6.1f  M max %6.1f LUFS  true peak %5.1f dBTP  %s\n", f, n / r, s / 1024, v[1], v[2], v[3], x
	}'
}

build_one() {
	local name=$1
	case " ${MUSIC[*]} " in
		*" ${name} "*)
			"music_${name}"
			mkdir -p "${OUT}/music"
			normalize "${WORK}/${name}.wav" "${WORK}/${name}.norm.wav" "${MUSIC_LUFS}" I
			encode "${WORK}/${name}.norm.wav" "${OUT}/music/${name}.ogg" "${MUSIC_QUALITY}"
			return
			;;
	esac
	if ! declare -F "sfx_${name}" >/dev/null; then
		echo "Unknown sound '${name}'. Music: ${MUSIC[*]}. Effects: ${SFX[*]}." >&2
		exit 2
	fi
	"sfx_${name}"
	mkdir -p "${OUT}/sfx"
	normalize "${WORK}/${name}.wav" "${WORK}/${name}.norm.wav" "$(sfx_target "${name}")" M
	encode "${WORK}/${name}.norm.wav" "${OUT}/sfx/${name}.ogg" "${SFX_QUALITY}"
}

report() {
	local total=0 name file
	echo "== Levels"
	for name in "${MUSIC[@]}"; do
		file="${OUT}/music/${name}.ogg"
		if [[ -f "${file}" ]]; then
			report_line "${file}" music
			total=$((total + $(stat -c %s "${file}")))
		fi
	done
	for name in "${SFX[@]}"; do
		file="${OUT}/sfx/${name}.ogg"
		if [[ -f "${file}" ]]; then
			report_line "${file}" sfx
			total=$((total + $(stat -c %s "${file}")))
		fi
	done
	awk -v t="${total}" 'BEGIN { printf "Total %.1f KB\n", t / 1024 }'
}

main() {
	if ! command -v "${FFMPEG}" >/dev/null 2>&1; then
		echo "ffmpeg not found (looked for '${FFMPEG}'). Set FFMPEG=/path/to/ffmpeg." >&2
		exit 2
	fi
	if [[ $# -gt 0 && "$1" == "--report" ]]; then
		report
		return
	fi
	local names=("$@")
	if [[ $# -eq 0 ]]; then
		names=("${MUSIC[@]}" "${SFX[@]}")
	fi
	local name
	for name in "${names[@]}"; do
		echo "== ${name}"
		build_one "${name}"
	done
	report
}

main "$@"
