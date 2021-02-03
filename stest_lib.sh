fail() {
  printf '%s\n' "$1"
  exit 1
}

load_module() {
  cd "$LOADER_DIR"
  sudo "./$LOADER" $* || fail "Failed to load module."
  cd "$CWD"
}

unload_module() {
  cd "$LOADER_DIR"
  sudo "./$UNLOADER" || fail "Failed to unload module"
  cd "$CWD"
}

man_ascii() {
  # TIL man has some UTF-8 chars, need to convert to ASCII
  man "$1" | iconv -t ascii//TRANSLIT
}

cleanup() {
  rm -f "$TMP0" "$TMP1" "$TMP2"
  cd "$LOADER_DIR"
  sudo "./$UNLOADER" &> /dev/null && echo "Module unloaded."
}

ERRNUM_CORRECT=0
ERRNUM_MISMATCH=1
ERRNUM_TIMEOUT=2
ERRNUM_RTOUT=3
ERRNUM_WTOUT=4
ERRNUM_FCESUCC=5
ERRNUM_FCEFAIL=6
ERRNUM_FLMMATCH=7
ERRNUM_WRERR=8
ERRNUM_RDERR=9
ERRNUM_EXPFAIL=10
ERRNUM_POLLNOR=11
ERRNUM_POLLNOW=12
ERRNUM_POLLFAIL=13
ERRNUM_POLLTOUT=14
ERRNUM_POLLW=15
ERRNUM_POLLR=16

code2reason() {
  # I know, I know, literal integers as enums are
  # bad practice. But bash is the embodiment of 
  # bad practice anyway! :P
  case "$1" in
    $ERRNUM_CORRECT)
      echo -n "Should be correct... What?"
      ;;
    $ERRNUM_MISMATCH)
      echo -n "Output mismatch"
      ;;
    $ERRNUM_TIMEOUT)
      echo -n "Timeout, maybe sleeping forever?"
      ;;
    $ERRNUM_RTOUT)
      echo -n "Reader timed out."
      ;;
    $ERRNUM_WTOUT)
      echo -n "Writer timed out."
      ;;
    $ERRNUM_FCESUCC)
      echo -n "Expected $FILTER_CNTL to succeed, but it failed (returned 1)"
      ;;
    $ERRNUM_FCEFAIL)
      echo -n "Expected $FILTER_CNTL to fail, but it succeeded (returned 0)"
      ;;
    $ERRNUM_FLMMATCH)
      echo -n "Output mismatch, files dumped into $OUTPUT_DUMP and $EXPECTED_DUMP"
      ;;
    $ERRNUM_WRERR)
      echo -n "Writer failed."
      ;;
    $ERRNUM_RDERR)
      echo -n "Reader failed."
      ;;
    $ERRNUM_EXPFAIL)
      echo -n "Expected call to fail, but it succeeded (return 0)"
      ;;
    $ERRNUM_POLLR)
      echo -n "Expected polled device to not be readable, but it is"
      ;;
    $ERRNUM_POLLNOR)
      echo -n "Expected polled device to be readable, but it is not"
      ;;
    $ERRNUM_POLLW)
      echo -n "Expected polled device to not be writable, but it is"
      ;;
    $ERRNUM_POLLNOW)
      echo -n "Expected polled device to be writable, but it is not"
      ;;
    $ERRNUM_POLLFAIL)
      echo -n "$POLL_DEV failed."
      ;;
    $ERRNUM_POLLTOUT)
      echo -n "$POLL_DEV timed out."
      ;;
    *)
      echo -n "Unknown error code"
      ;;
  esac
}

gdev() {
  echo -n "/dev/$DEVICE_PREFIX$1"
}

file_size() {
  stat --printf="%s" "$1"
}

prepare_c_file() {
  local name="$1"
  if [ -e "$name" ]; then
    return 0
  fi
  [ -e "$name.c" ] || fail "Where did you put my $name.c file? I can't find it :/"
  echo "Compiling $name.c..."
  gcc "$name.c" -o "$name" || fail "Compilation failed!"
  echo "Successfully compiled $name.c"
}

prepare_c_utils() {
  prepare_c_file "$FILTER_CNTL"
  prepare_c_file "$POLL_DEV"
}

filter_cntl() {
  "./$FILTER_CNTL" "$(gdev $1)" "${@:2}"
}

rand_string() {
  # print a random string containing n alphanumeric/whitespace chars
  tr -dc 'A-Za-z0-9 \n\t' </dev/urandom | head -c "$1"
}

poll_test_f() {
  local device=$(gdev $1) rd="$2" wr="$3"
  "./$POLL_DEV" "$device" "$POLL_TIMEOUT" > $TMP0
  
  if [[ $? != 0 ]]; then
    return $ERRNUM_POLLFAIL
  fi

  if grep 'poll timed out' $TMP0 &> /dev/null; then
    return $ERRNUM_POLLTOUT
  fi

  if [[ $rd != 0 ]] && ! grep 'for reading' $TMP0 &> /dev/null; then
    return $ERRNUM_POLLNOR
  fi
  
  if [[ $rd == 0 ]] && grep 'for reading' $TMP0 &> /dev/null; then
    return $ERRNUM_POLLR
  fi
  
  if [[ $wr != 0 ]] && ! grep 'for writing' $TMP0 &> /dev/null; then
    return $ERRNUM_POLLNOW
  fi
  
  if [[ $wr == 0 ]] && grep 'for writing' $TMP0 &> /dev/null; then
    return $ERRNUM_POLLW
  fi

  return 0
}

poll_test() {
  test_execute poll_test_f "$1" "$2" "$3"
}

io_poll_test_f() {
  # same as poll test, but write/read n bytes before
  local in="$1" n="$2" devno="$3" rd="$4" wr="$5" device="$(gdev $3)" str
  
  if [[ $in != 0 ]]; then
    str=$(rand_string $n)
    timeout "$BLK_TIMEOUT" printf '%s' "$str" > "$device"
    ret=$?
    if [[ $ret == 124 ]]; then
      return $ERRNUM_WTOUT
    elif [[ $ret != 0 ]]; then
      return $ERRNUM_WRERR
    fi
  else
    timeout "$BLK_TIMEOUT" head -c "$n" "$device" > /dev/null
    ret=$?
    if [[ $ret == 124 ]]; then
      return $ERRNUM_RTOUT
    elif [[ $ret != 0 ]]; then
      return $ERRNUM_RDERR
    fi
  fi

  poll_test_f "$devno" "$rd" "$wr"
  return
}

io_poll_test() {
  test_execute io_poll_test_f "$1" "$2" "$3" "$4" "$5"
}

string_test_f() {
  local device=$(gdev "$1") input="$2" expected="$3"
  timeout "$BLK_TIMEOUT" printf '%s' "$input" > "$device"
  if [[ $? == 124 ]]; then
    return $ERRNUM_WTOUT
  fi
  timeout "$BLK_TIMEOUT" head -c ${#expected} "$device" > "$TMP0"
  if [[ $? == 124 ]]; then
    return $ERRNUM_RTOUT
  fi
  if ! [[ "$expected" == "$(<$TMP0)" ]]; then
    ln -f $TMP0 "$OUTPUT_DUMP"
    printf '%s' "$expected" > "$EXPECTED_DUMP"
    return $ERRNUM_FLMMATCH
  fi
  return 0
}

MOTIVATIONALS=( "Nice!" "Good work!" "Amazing!" "Superb job." "Good going." "Perfect." "Coolio." "Dazzling!" "Pride++" "What a rockstar!" "Are you a 10x programmer!?" )

motivate() {
  local idx=$(($RANDOM % ${#MOTIVATIONALS[@]}))
  echo -n "${MOTIVATIONALS[$idx]}"
}

testcase() {
  printf "%s" "$1"
  if [[ $RELOAD_EVERY == 1 ]]; then
    load_module
  fi
}

FAIL_ON_TEST=1 # flag for failing on the test, temporarily change for nonblocking
test_execute() { # all tests should call this eventually
  ((TOTAL+=1))
  if $1 "${@:2}"; then
    echo "Passed! $(motivate)"
    ((PASSED+=1))
  else
    echo "Failed: $(code2reason $?)"
    ((FAILED+=1))
    if [[ $FAIL_ON_TEST == 1 ]]; then
      exit 1
    fi
  fi
  echo
  # Maybe unload the module on end
  if [[ $RELOAD_EVERY == 1 ]]; then
    unload_module
  fi
  sleep $TEST_WAIT
}

string_test() {
  test_execute string_test_f "$1" "$2" "$3"
}

string_test_same() {
  string_test "$1" "$2" "$2"
}

file_test_f() {
  # Useful for testing random bytes since strings don't like null bytes
  # NOTE: clobbers the input file!
  local device=$(gdev "$1") input="$2" expected="$3" ret
  timeout "$BLK_TIMEOUT" cp "$input" "$device"
  ret=$?
  if [[ $ret == 124 ]]; then
    return $ERRNUM_WTOUT
  elif [[ $ret != 0 ]]; then
    return $ERRNUM_WRERR
  fi

  local size=$(file_size "$input")
  timeout "$BLK_TIMEOUT" head -c $size "$device" > "$input"
  ret=$?
  if [[ $ret == 124 ]]; then
    return $ERRNUM_RTOUT
  elif [[ $ret != 0 ]]; then
    return $ERRNUM_RDERR
  fi

  if ! cmp -s "$input" "$expected"; then
    ln -f "$input" "$OUTPUT_DUMP" 
    ln -f "$expected" "$EXPECTED_DUMP"
    return $ERRNUM_FLMMATCH
  fi

  return 0
}

file_test() {
  test_execute file_test_f "$1" "$2" "$3"
}

file_test_same() {
  file_test "$1" "$2" "$2"
}

big_file_test_f() {
  local device=$(gdev "$1") file="$2" outfile="$3" expected="$4" ret read_blk="$5"

  timeout -k 5s $MAN_TIMEOUT dd if="$file" of="$device" bs=4095 status=none & # background job to write
  wrpid=$!

  # start the reader with timeout
  local fs=$(file_size "$expected")
  if [[ $read_blk != 0 ]]; then
    timeout -k 5s $MAN_TIMEOUT dd if="$device" of="$outfile" bs=4095 iflag=count_bytes count=$fs status=none
  else
    head -c "$fs" "$device" > "$outfile"
  fi
  ret=$?
  if [[ $ret == 124 ]]; then
    return $ERRNUM_RTOUT
  elif [[ $ret != 0 ]]; then
    return $ERRNUM_RDERR
  fi

  # wait for the writer
  wait $wrpid
  ret=$?
  if [[ $ret == 124 ]]; then
    return $ERRNUM_WTOUT
  elif [[ $ret != 0 ]]; then
    return $ERRNUM_WRERR
  fi

  if ! cmp -s "$outfile" "$expected"; then
    ln -f "$outfile" "$OUTPUT_DUMP" 
    ln -f "$expected" "$EXPECTED_DUMP"
    return $ERRNUM_FLMMATCH
  fi

  return 0
}

big_file_test() {
  test_execute big_file_test_f "$1" "$2" "$3" "$4" "$5" # 5 is optional, 1 to read once 
}

filter_cntl_test_f() {
  local expected_ret="$1"
  filter_cntl ${@:2} &> /dev/null
  if [[ $? != $expected_ret ]]; then
    if [[ $expected_ret == 0 ]]; then
      return $ERRNUM_FCESUCC
    else
      return $ERRNUM_FCEFAIL
    fi
  fi
  return 0
}

filter_cntl_test() {
  test_execute filter_cntl_test_f $*
}

filter_wpush_n_test_f() {
  local device="$1" n="$2"
  for ((i=0; i<$n; i++)); do
    if ! filter_cntl "$device" w push upper; then
      return $ERRNUM_FCESUCC
    fi
  done
}

filter_wpush_n_test() {
  test_execute filter_wpush_n_test_f "$1" "$2"
}

fail_write_test_f() {
  rand_string 8192 > $TMP0
  timeout "$BLK_TIMEOUT" head -c 8192 $TMP0 > $(gdev "$1")
  ret=$?
  if [[ $ret == 124 ]]; then
    return $ERRNUM_TIMEOUT
  elif [[ $ret == 0 ]]; then
    return $ERRNUM_EXPFAIL
  fi
  return 0
}

fail_write_test() {
  test_execute fail_write_test_f "$1"
}

repl() {
  # short helper for char replication
  printf "$1"'%.0s' $(seq 1 $2)
}

section_begin() {
  # Careful! Messes with global variables
  start_passed=$PASSED
  start_total=$TOTAL
  local name="$1"
  local rem=$(($SECTION_HEADER_SIZE - ${#name} - 2))
  local reml=$(($rem / 2))
  local remr=$(($rem - $reml))
  echo "$(repl '*' $reml) $name $(repl '*' $remr)"
}

SECTION_MOTIVATIONALS=( "Aren't you awesome?" "ADVANCED UNIX'ING HARD!" "Another bunch bites the dust." "Achievement unlocked <*.*>" "=== LEVEL CLEARED ===" "Brutal!" "Even this one? Wish I had some sound effects!" )

SECT_COUNTER=0
section_motivate() {
  echo -n ${SECTION_MOTIVATIONALS[$SECT_COUNTER]}
}

section_end() {
  local passed=$(($PASSED - $start_passed)) total=$(($TOTAL - $start_total))
  echo "Passed $passed/$total tests."
  if ((passed == total)); then
    echo "Section complete! $(section_motivate)"
  else
    echo "Some tests in the section seem to have failed. $AUTHOR's fault for sure!"
  fi
  echo "$(repl '*' $SECTION_HEADER_SIZE)"
  ((SECT_COUNTER+=1))
}
