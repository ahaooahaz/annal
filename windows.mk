SHELL = cmd.exe
TARGETS = wezterm nushell rime autohotkey

env: $(TARGETS)

wezterm:
	powershell -Command \
	'robocopy "configs\\wezterm\\" "$$env:USERPROFILE\\.config\\wezterm\\" /E /IS /R:0 /W:0 /V ; $$true'

nushell:
	powershell -Command \
	'robocopy "configs\\nushell\\" "$$env:USERPROFILE\\AppData\\Roaming\\nushell\\" /E /IS /R:0 /W:0 /V ; $$true'

rime:
	-git clone git@github.com:iDvel/rime-ice.git plugins/rime-ice
	powershell -Command \
    "robocopy 'configs\rime' 'plugins\rime-ice\' /E /IS /R:0 /W:0 /V ; $$true"
	powershell -Command \
	"robocopy 'plugins\rime-ice' $$env:USERPROFILE'\AppData\Roaming\Rime\' /E /IS /R:0 /W:0 /V ; $$true"

autohotkey:
	powershell -Command \
	"robocopy 'configs\autohotkey' $$env:USERPROFILE'\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup' /E /IS /R:0 /W:0 /V ; $$true"
