#!/usr/bin/env sh
#
# Prompts you for keywords to your local files, directories or DuckDuckGo search and launches them respectively.
# Dependencies: grep, sed, find, awk, file, xargs, ed

MAXDEPTH=6
HOME_DIR=/home/maxine
SEARCHLIST=/tmp/searchlist
HISTORYLIST=/tmp/historylist

#========================================================
# Modify this section according to your preference
#========================================================
launch() {
   # If the selection does not exist in the history file, add it
   grep -q -F "$1" $HISTORYLIST
   if [ $? -ne 0 ]; then
      echo "$1" >>$HISTORYLIST
   fi

   #====================================================
   # Find out the mimetype of the file you wannna launch
   # Mimetype documentation/list:
   # https://www.iana.org/assignments/media-types/media-types.xhtml
   #====================================================
   TYPE=$(file --mime-type "$*" -bL)
   case $TYPE in
   #================================================
   # Mimetype of the file with wildcard
   #================================================
   video/*)
      #================================================
      # Launch using your favorite programs or program
      # in variable like $TERMINAL or $EXPLORER
      #================================================
      mpv "$*"
      ;;
   text/* | inode/x-empty | application/json | application/octet-stream)
      "$TERMINAL" -e "$EDITOR" "$*"
      ;;
   inode/directory)
      "$EXPLORER" "$*"
      ;;
   application/pdf | application/epub+zip | image/*)
      "$BROWSER" "$*"
      ;;
   #================================================
   # Default case
   #================================================
   *)
      "$TERMINAL" cat "$*"
      ;;
   esac

   # update history file AFTER launching so as to not
   # cause a delay in opening the program
   move_lines_from_history

}

search_n_launch() {
   LOC=$(echo "$1" | sed -e "s|~|$HOME_DIR|g;s|\.\.||g")
   RESULT=$(grep "$LOC" $SEARCHLIST | head -1)
   if [ -n "$RESULT" ]; then
      launch "$RESULT"
   else
      "$BROWSER" "duckduckgo.com/?q=$*"
   fi
}

get_config() {
   while IFS= read -r line; do
      case $line in
         [[:alnum:]]* | /*) echo "$line" ;;
      esac
   done < "$1"
}

move_lines_from_history() {
   while IFS= read -r line; do
      (
         echo H
         echo "?$line?m0"
         echo "w"
         echo "q"
      ) | ed -s $SEARCHLIST
   done <$HISTORYLIST
}

dmenu_search() {
   # get the folder before home to change it to ~/
   HDIR=$(echo "$HOME_DIR" | awk -F / '{print $NF}')
   QUERY=$(awk -F / -v HDIR=$HDIR '{
	if (NF > 4)
		if ($(NF - 2) == HDIR)
			printf "~/%s/%s\n", $(NF - 1), $NF
		else if ($(NF - 3) == HDIR)
			printf "~/%s/%s/%s\n", $(NF - 2), $(NF - 1), $NF
		else if ($(NF - 4) == HDIR)
			printf "~/%s/%s/%s/%s\n", $(NF - 3), $(NF - 2), $(NF - 1), $NF
		else
			printf "../%s/%s/%s/%s\n", $(NF - 3), $(NF - 2), $(NF - 1), $NF
		}' "$SEARCHLIST" | "$1") &&
      search_n_launch "$QUERY"
}

run_dmenu() {
   dmenu -i
}

run_rofi() {
   rofi -sort true -sorting-method fzf -dmenu -i -p "Bolt Launch"
}

tmux_search() {
   if pidof tmux; then
      tmux new-window
   else
      tmux new-session -d \; switch-client
   fi
   if pidof "$TERMINAL"; then
      [ "$(pidof "$TERMINAL")" != "$(xdo pid)" ] &&
         xdo activate -N Alacritty
   else
      "$TERMINAL" -e tmux attach &
   fi
   tmux send "$0 --fzf-search" "Enter"
}

fzf_search() {
   QUERY=$(awk -F / '{print $(NF-2)"/"$(NF-1)"/"$NF}' "$SEARCHLIST" |
      fzf -e -i \
         --reverse \
         --border \
         --margin 5%,10% \
         --info hidden \
         --bind=tab:down,btab:up \
         --prompt "launch ") &&
      search_n_launch "$QUERY"
}

watch() {
   grep -v "^#" ~/.config/bolt/paths |
      xargs inotifywait -m -r -e create,delete,move |
      while read -r line; do
         generate
      done &
}

generate() {
   FILTERS=$(get_config ~/.config/bolt/filters | awk '{printf "%s\\|",$0;}' | sed -e 's/|\./|\\./g' -e 's/\\|$//g')
   get_config ~/.config/bolt/paths |
      xargs -I% find % -maxdepth $MAXDEPTH \
         ! -regex ".*\($FILTERS\).*" >"$SEARCHLIST"
   move_lines_from_history
}

while :; do
   case $1 in
      --generate) generate ;;
      --tmux-search) tmux_search ;;
      --fzf-search) fzf_search ;;
      --launch) launch "$2" ;;
      --rofi-search)
         dmenu_search "run_rofi"
         ;;
      --dmenu-search) dmenu_search "run_dmenu" ;;
      --watch) watch ;;
   *) break ;;
   esac
   shift
done
