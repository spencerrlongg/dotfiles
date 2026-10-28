-- Open in Nvim.app: a droplet that macOS uses as the default app for dev file types
-- (set with duti by install.sh). It hands the files to ~/.local/bin/open-in-nvim,
-- which opens them in nvim in a new window of the most recently used tmux session.
on open theFiles
	set fileArgs to ""
	repeat with theFile in theFiles
		set fileArgs to fileArgs & " " & quoted form of POSIX path of theFile
	end repeat
	do shell script "~/.local/bin/open-in-nvim" & fileArgs
end open
