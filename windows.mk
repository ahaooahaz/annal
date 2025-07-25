SHELL = cmd.exe
TARGETS = wezterm nushell rime

env: $(TARGETS)

wezterm:
	powershell -Command \
	'robocopy "configs\\wezterm\\" "$$env:USERPROFILE\\.config\\wezterm\\" /E /IS /R:0 /W:0 /V ; $$true'

nushell:
	powershell -Command \
	'robocopy "configs\\nushell\\" "$$env:USERPROFILE\\AppData\\Roaming\\nushell\\" /E /IS /R:0 /W:0 /V ; $$true'

rime:
	powershell -Command \
	'robocopy "configs\\rime\\" "$$env:USERPROFILE\\AppData\\Roaming\\Rime\\" /E /IS /R:0 /W:0 /V ; $$true'
