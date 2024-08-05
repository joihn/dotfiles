#!/bin/sh
sleep 0.2
export DISPLAY=":1"
Y_POS=$(xdotool getwindowgeometry $(xdotool getactivewindow) | grep Geometry | awk '{split($2,a,"x"); print a[2]}')
Y_OFFSET=$((Y_POS - 60))
xdotool mousemove --window $(xdotool getactivewindow) 750 $Y_OFFSET click 1
xdotool mousemove --window $(xdotool getactivewindow) 50 50 2> /tmp/error.log
