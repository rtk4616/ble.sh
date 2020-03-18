#!/bin/bash

function ble-measure/.loop {
  eval "function _target { $2; }"
  local _i _n=$1
  for ((_i=0;_i<_n;_i++)); do
    _target
  done
}

## @fn ble-measure/.time command
##   @var[in]  n
##   @var[out] utot
##     計測にかかった総時間を返します。
##   @var[out] usec
##     1評価当たりの時間を返します。
if [[ $ZSH_VERSION ]]; then
  _ble_measure_resolution=1000 # [usec]
  function ble-measure/.time {
    local result
    result=$({ time ( ble-measure/.loop "$n" "$*" ; ) } 2>&1 )
    #local result=$({ time ( ble-measure/.loop "$n" "$*" &>/dev/null); } 2>&1)
    result=${result##*cpu }
    local rex='(([0-9]+):)?([0-9]+)\.([0-9]+) total$'
    if [[ $result =~ $rex ]]; then
      if [[ -o KSH_ARRAYS ]]; then
        local m=${match[1]} s=${match[2]} ms=${match[3]}
      else
        local m=${match[1]} s=${match[2]} ms=${match[3]}
      fi
      m=${m:-0} ms=${ms}000; ms=${ms:0:3}
     
      ((utot=((10#$m*60+10#$s)*1000+10#$ms)*1000,
        usec=utot/n))
      return 0
    else
      echo "ble-measure: failed to read the result of \`time': $result." >&2
      utot=0 usec=0
      return 1
    fi
  }
elif [[ $0 != osh ]] && ((BASH_VERSINFO[0]>=5)); then
  _ble_measure_resolution=1 # [usec]
  function ble-measure/.time {
    local command="$*"
    local time1=${EPOCHREALTIME//.}
    ble-measure/.loop "$n" "$*" &>/dev/null
    local time2=${EPOCHREALTIME//.}
    ((utot=time2-time1,usec=utot/n))
    ((utot>0))
  }
else
  _ble_measure_resolution=1000 # [usec]
  function ble-measure/.time {
    utot=0 usec=0
    local word utot1 usec1
    local head=
    for word in $({ time ble-measure/.loop "$n" "$*" &>/dev/null;} 2>&1); do
      local rex='(([0-9])+m)?([0-9]+)(\.([0-9]+))?s'
      if [[ $word =~  $rex ]]; then
        local m=${BASH_REMATCH[2]}
        local s=${BASH_REMATCH[3]}
        local ms=${BASH_REMATCH[5]}000; ms=${ms::3}
        
        ((utot1=((10#$m*60+10#$s)*1000+10#$ms)*1000,
          usec1=utot1/n))
        # printf '  %-5s%9dus/op\n' "$head" "$usec1"
        (((utot1>utot)&&(utot=utot1),
          (usec1>usec)&&(usec=usec1)))
        head=
      else
        head="$head$word "
      fi
    done

    [[ $utot1 ]]
  }
fi

_ble_measure_base= # [nsec]
_ble_measure_base_nestcost=0 # [nsec/10]
_ble_measure_count=1 # 同じ倍率で _ble_measure_count 回計測して最小を取る。
_ble_measure_threshold=100000 # 一回の計測が threshold [usec] 以上になるようにする

## 関数 ble-measure/calibrate
function ble-measure/calibrate.0 { local a; ble-measure a=1; }
function ble-measure/calibrate.1 { ble-measure/calibrate.0; }
function ble-measure/calibrate.2 { ble-measure/calibrate.1; }
function ble-measure/calibrate.3 { ble-measure/calibrate.2; }
function ble-measure/calibrate.4 { ble-measure/calibrate.3; }
function ble-measure/calibrate.5 { ble-measure/calibrate.4; }
function ble-measure/calibrate.6 { ble-measure/calibrate.5; }
function ble-measure/calibrate.7 { ble-measure/calibrate.6; }
function ble-measure/calibrate.8 { ble-measure/calibrate.7; }
function ble-measure/calibrate.9 { ble-measure/calibrate.8; }
function ble-measure/calibrate.A { ble-measure/calibrate.9; }
function ble-measure/calibrate.assign2 { local a b; ble-measure 'a=1; b=2'; }
function ble-measure/calibrate {
  local ret nsec
  _ble_measure_base=0
  _ble_measure_base_nestcost=0

  # nest0: calibrate.0 の ble-measure 内部での ${#FUNCNAME[*]}
  local nest0=$((${#FUNCNAME[@]}+2))
  local nestA=$((nest0+10))
  ble-measure/calibrate.0 &>/dev/null; local x0=$nsec
  ble-measure/calibrate.A &>/dev/null; local xA=$nsec
  ble-measure/calibrate.assign2 &>/dev/null; local y0=$nsec

  local nest_cost=$((xA-x0))
  local nest_base=$((x0-nest_cost*nest0/10))
  _ble_measure_base=$((nest_base-(y0-x0)))
  _ble_measure_base_nestcost=$nest_cost
}

## 関数 ble-measure/.read-arguments args
##   @var[out] flags
##   @var[out] command count
function ble-measure/.read-arguments {
  while [[ $1 == -* ]]; do
    local arg=$1; shift
    case $arg in
    (--) break ;;
    (--help) flags=h$flags ;;
    (--*)
      ble/util/print "ble-measure: unrecognized option '$arg'."
      flags=E$flags ;;
    (-?*)
      local i c
      for ((i=1;i<${#arg};i++)); do
        c=${arg:i:1}
        case $c in
        (q) flags=q$flags ;;
        ([ca])
          [[ $c == a ]] && flags=a$flags
          if ((i+1<${#arg})); then
            count=${arg:i+1}; break
          elif (($#)); then
            count=$1; shift
          else
            ble/util/print "ble-measure: missing option argument for '-$c'."
            flags=E$flags
          fi ;;
        (*)
          ble/util/print "ble-measure: unrecognized option '-$c'."
          flags=E$flags ;;
        esac
      done ;;
    (-)
      ble/util/print "ble-measure: unrecognized option '$arg'."
      flags=E$flags ;;
    esac
  done
  command="$*"
  [[ $flags != *E* ]]
}

## 関数 ble-measure command
##   command を繰り返し実行する事によりその実行時間を計測します。
##   @var[out] ret
##     実行時間を usec 単位で返します。
##   @var[out] nsec
##     実行時間を nsec 単位で返します。
function ble-measure {
  if [[ ! $_ble_measure_base ]]; then
    _ble_measure_base=0 nsec=0
    # : よりも a=1 の方が速い様だ
    local a
    ble-measure -qc3 'a=1' 
    # hp2019 上での評価 (assign=4695 nestcost=619 base=3113)
    _ble_measure_base=$((nsec*663/1000))
    _ble_measure_base_nestcost=$((nsec*132/1000))
  fi

  local flags= command= count=$_ble_measure_count
  ble-measure/.read-arguments "$@" || return
  if [[ $flags == *h* ]]; then
    ble/util/print 'usage: ble-measure [-q|-ac COUNT] command'
    ble/util/print '  Measure the time of command.'
    return
  fi

  local prev_n= prev_utot=
  local -i n
  for n in {1,10,100,1000,10000}\*{1,2,5}; do
    [[ $prev_n ]] && ((n/prev_n<=10 && prev_utot*n/prev_n<_ble_measure_threshold*2/5 && n!=50000)) && continue

    local utot=0 usec=0
    [[ $flags != *q* ]] && printf '%s (x%d)...' "$command" "$n" >&2
    ble-measure/.time "$command" || return 1
    [[ $flags != *q* ]] && printf '\r\e[2K' >&2

    prev_n=$n prev_utot=$utot

    ((utot >= _ble_measure_threshold)) || continue

    # 繰り返し計測して最小値 (-a の時は平均値) を採用
    if [[ $count ]]; then
      local min_utot=$utot sum_utot=$utot sum_count=1 i
      for ((i=2;i<=count;i++)); do
        [[ $flags != *q* ]] && printf '%s' "$command (x$n $i/$count)..." >&2
        if ble-measure/.time "$command"; then
          ((utot<min_utot)) && min_utot=$utot
          ((sum_utot+=utot,sum_count++))
        fi
        [[ $flags != *q* ]] && printf '\r\e[2K' >&2
      done
      if [[ $flags == *a* ]]; then
        ((utot=sum_utot/sum_count))
      else
        utot=$min_utot
      fi
    fi

    local nsec0=$((_ble_measure_base+_ble_measure_base_nestcost*${#FUNCNAME[*]}/10))
    if [[ $flags != *q* ]]; then
      local reso=$_ble_measure_resolution
      local awk=ble/bin/awk
      type "$awk" &>/dev/null || awk=awk
      "$awk" -v utot=$utot -v nsec0=$nsec0 -v n=$n -v reso=$reso -v title="$command (x$n)" \
             ' function genround(x, mod) { return int(x / mod + 0.5) * mod; }
          BEGIN { printf("%12.3f usec/eval: %s\n", genround(utot / n - nsec0 / 1000, reso / 10.0 / n), title); exit }'
    fi
    ((ret=utot/n))
    if ((n>=1000)); then
      ((nsec=utot/(n/1000)))
    else
      ((nsec=utot*1000/n))
    fi
    ((ret-=nsec0/1000,nsec-=nsec0))
    return
  done
}
