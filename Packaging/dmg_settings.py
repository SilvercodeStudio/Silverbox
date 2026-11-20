# dmgbuild settings for Silverbox's disk image. scripts/dist.sh runs it from the repository's
# root, as:
#
#   dmgbuild -s Packaging/dmg_settings.py -D app=<Silverbox.app> Silverbox <file>.dmg
#
# dmgbuild finds background@2x.png beside background.png and joins the two into one HiDPI TIFF
# with tiffutil. The window size and the icon positions must match make_dmg_background.py,
# which draws the arrow between the icons.

import os.path

application = defines["app"]  # noqa: F821 (dmgbuild supplies defines)
appname = os.path.basename(application)

format = "ULFO"  # LZFSE: smaller and faster to open than UDZO
filesystem = "HFS+"
files = [application]
symlinks = {"Applications": "/Applications"}
# No hide_extensions: the flag it sets on the app is Finder information, which fails
# codesign --verify --strict ("detritus"). Finder leaves out ".app" anyway, unless the user
# has it show every extension.
icon = os.path.join(application, "Contents/Resources/AppIcon.icns")  # the volume's icon

background = "Packaging/background.png"

# Finder counts the title bar (32 points) in the height.
window_rect = ((200, 140), (660, 432))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False

icon_size = 128
text_size = 13
show_icon_preview = False
include_icon_view_settings = "auto"
include_list_view_settings = False
arrange_by = None

icon_locations = {
    appname: (180, 180),
    "Applications": (480, 180),
}
