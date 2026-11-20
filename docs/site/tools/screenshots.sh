#!/bin/zsh
# Takes the site's screenshots again, after the app's look changes:
#
#   make site-shots                             every scene, light then dark
#   make site-shots SCENES='library details'    some of them
#   make site-shots APPEARANCES=dark            one appearance
#
# For each scene in docs/site/tools/scenes, in each appearance, the script starts the Debug app
# with the scene's launch arguments, on your own collections (LIBRARY=<folder> uses that one
# instead): a search, a selected game, a scrolled inspector, a sheet, a Settings tab. Take a
# region screenshot (Shift-Command-4) a little larger than the main window, with desktop all
# around it, then quit the app (Command-Q). With "capture": "window", the script asks for a
# screenshot of that window alone instead (Shift-Command-4, Space, then Option-click it). The
# script finds the new screenshot in your screenshot folder, makes the site's images from it with
# shot.swift, and starts the next one. The app's settings are put back after each run, so a
# scene changes nothing.
#
# The captures are kept in build/site-shots, so a crop can be made again by hand. The <img>
# heights in the page follow the new images, and the link preview follows the dark library.
set -euo pipefail

repo=${0:A:h:h:h:h}
app=${APP:?set APP to the Debug Silverbox.app (make site-shots does)}
scene_dir=$repo/docs/site/tools/scenes
images=$repo/docs/site/images
keep=$repo/build/site-shots
domain=app.getsilverbox.Silverbox
mkdir -p $keep

# The scenes in the order of the page, then any others.
order=(library welcome details game-info display-sound)
all=($order ${${${(f)"$(ls $scene_dir/*.json)"}:t:r}:|order})
scenes=(${@:-${=SCENES:-$all}})
appearances=(${=APPEARANCES:-light dark})
for scene in $scenes; do
    [[ -f $scene_dir/$scene.json ]] || { echo "No scene $scene_dir/$scene.json" >&2; exit 1; }
done

# Where Shift-Command-4 saves: the setting in Screenshot's Options, else the Desktop. SHOTS names
# another folder.
shots=${SHOTS:-$(defaults read com.apple.screencapture location 2>/dev/null || echo ~/Desktop)}
shots=${~shots}

if pgrep -xq Silverbox; then
    echo "Quit Silverbox first: the scenes run with its settings, and put them back after." >&2
    exit 1
fi
scratch=$(mktemp -d -t silverbox-shots)
# The app's settings (its defaults domain), put back after each scene and at the end.
defaults export $domain $scratch/defaults.plist 2>/dev/null || : >$scratch/defaults.plist
function restore_settings {
    if [[ -s $scratch/defaults.plist ]]; then
        defaults import $domain $scratch/defaults.plist
    else
        defaults delete $domain >/dev/null 2>&1 || true
    fi
}
trap 'restore_settings; [[ $scratch == */silverbox-shots.* ]] && rm -r -- $scratch' EXIT

# A key of a scene file, or the default.
function scene_value {
    plutil -extract $2 raw -o - $scene_dir/$1.json 2>/dev/null || echo ${3:-}
}

# The newest PNG in the screenshot folder made since the marker, waiting for it a while:
# with the floating thumbnail on, macOS writes the file a few seconds after the capture.
function new_capture {
    local marker=$1
    local -a newest
    for _ in {1..30}; do
        newest=($shots/*.png(N.om[1]))
        if (( $#newest )) && [[ $newest[1] -nt $marker ]]; then
            echo $newest[1]
            return
        fi
        sleep 0.5
    done
}

# Sets the page's <img> height for the image to the new image's, at its largest width.
function update_heights {
    local name=$1 width=$2 height
    [[ -f $images/$name-dark-$width.webp ]] || return 0
    height=$(sips -g pixelHeight $images/$name-dark-$width.webp | awk '/pixelHeight/ {print $2}')
    NAME=$name WIDTH=$width HEIGHT=$height perl -i -pe \
        's/height="\d+"/height="$ENV{HEIGHT}"/ if /src="images\/\Q$ENV{NAME}\E-dark-\Q$ENV{WIDTH}\E\.webp"/' \
        $repo/docs/site/index.html
}

library=()
[[ -z ${LIBRARY:-} ]] || library=(-libraryPath $LIBRARY)

echo "Scenes: $scenes"
for scene in $scenes; do
    capture=$(scene_value $scene capture region)
    widths=$(scene_value $scene widths 2400,1200)
    # The arguments as a shell would split them, so a quoted title stays one argument.
    arguments=(${(Q)${(z)$(scene_value $scene arguments)}})
    if [[ $capture == window ]]; then
        how="a screenshot of that window alone (⇧⌘4, Space, then ⌥-click it)"
        crop=(--widths $widths)
    else
        how="a region screenshot (⇧⌘4) a little larger than the main window, with desktop all around it"
        crop=(--widths $widths --radius $(scene_value $scene radius 36))
    fi
    for appearance in $appearances; do
        while true; do
            marker=$scratch/marker
            touch $marker
            sleep 1
            echo "\n$scene ($appearance): take $how, then quit Silverbox (⌘Q; close a sheet first, Esc)."
            # Through Launch Services, which brings the app to the front (started as a plain
            # process, it stays behind the Terminal); -n for a new copy, -W to wait until it quits.
            open -n -W -a $app --stdout $scratch/app.log --stderr $scratch/app.log \
                --args -ApplePersistenceIgnoreState YES -appearance $appearance -musicEnabled 0 \
                -windowSize $(scene_value $scene windowSize 1320x840) $library $arguments || true
            restore_settings
            shot=$(new_capture $marker)
            if [[ -n $shot ]]; then
                mv $shot $keep/$scene-$appearance.png
                swift $repo/docs/site/tools/shot.swift $keep/$scene-$appearance.png $images/$scene-$appearance $crop
                if [[ $scene-$appearance == library-dark ]]; then
                    swift $repo/docs/site/tools/og-image.swift $images/library-dark-2400.webp $images/og-image.jpg
                fi
                break
            fi
            read "answer?No new screenshot in $shots. Again, skip, or quit? [a/s/q] "
            case $answer in
            s*) break ;;
            q*) exit 1 ;;
            esac
        done
    done
    update_heights $scene ${widths%%,*}
done
echo "\nDone. The captures are in $keep; check the page with make site."
