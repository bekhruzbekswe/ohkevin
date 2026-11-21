# dmgbuild settings for the Oh Kevin disk image (make-dmg.sh passes app, tiff and icon with -D). The Finder layout is written straight
# into the image's .DS_Store: no Finder is scripted and no window is opened.
#   Volume "Oh Kevin"; content area 640 × 400 (the background's size), so a 428-high window with its title bar; the app at 128 (centre 176, 232) and the Applications link at 464, 232;
#   names at 12 pt; toolbar, sidebar, path bar and status bar hidden; background .background/background.tiff (1x and @2x together).
import os

app = defines["app"]
name = os.path.basename(app)

format = "UDZO"
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}
background = defines["tiff"]
icon = defines.get("icon")  # the volume's own icon

show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
window_rect = ((200, 120), (640, 428))  # the window's frame: the 28-point title bar plus the 640 × 400 content the picture and the icon places are drawn for
default_view = "icon-view"
icon_size = 128
text_size = 12
arrange_by = None
icon_locations = {name: (176, 232), "Applications": (464, 232)}
