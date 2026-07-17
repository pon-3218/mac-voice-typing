import os

app_path = os.path.abspath(defines["app_path"])
app_name = os.path.basename(app_path)

files = [app_path]
symlinks = {"Applications": "/Applications"}

window_rect = ((120, 120), (640, 280))
icon_size = 128
text_size = 14
icon_locations = {
    app_name: (165, 140),
    "Applications": (475, 140),
}

background = os.path.abspath(defines["background_path"])
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
show_item_info = False
arrange_by = None
format = "UDZO"
compression_level = 9
