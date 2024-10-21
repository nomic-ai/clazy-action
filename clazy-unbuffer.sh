#!/bin/bash
exec unbuffer clazy-standalone $CLAZY_OPTIONS "$@"
