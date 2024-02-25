#!/usr/bin/env bash

# no. this works as expected
# only change the basename
olddir_depth=0; newdir_depth=$olddir_depth; change_basename=true

# no. this works as expected
# change 1 dirname
olddir_depth=1; newdir_depth=$olddir_depth; change_basename=false

# no. this works as expected
# move the file 1 level down. note: one depth must be 0
olddir_depth=0; newdir_depth=1; change_basename=false

# yes. this fails to dedupe "git mv"
# move the file 1 level up. note: one depth must be 0
olddir_depth=1; newdir_depth=0; change_basename=false

# yes. this fails to dedupe "git mv"
# change 2 dirnames
olddir_depth=2; newdir_depth=$olddir_depth; change_basename=false

# yes. this fails to dedupe "git mv"
# change 1 dirname and basename
olddir_depth=1; newdir_depth=$olddir_depth; change_basename=true



# no effect
const_path_prefix=
#const_path_prefix=a/b/c/



# no effect. same problem with copy
move_or_copy=move
#move_or_copy=copy



use_text_files=false
#use_text_files=true # TODO base64




owner=milahu
repo=git-bug-git-mv-wasteful-transfer-test

remote=https://github.com/$owner/$repo

echo "todo? create new repo \"$repo\" at https://github.com/new"

# no effect
num_files=1; file_size_mega=1
num_files=1; file_size_mega=10 # make the blob transfer more noticable

transfer_size_mega=$((num_files * file_size_mega))

file_size=$((file_size_mega * 1024 * 1024))

# no effect
file_extension=.bin
#file_extension=.txt

# no effect
disable_delta_compression=false
#disable_delta_compression=true

# debug
continue_move_files=false
# continue an interrupted run after the first "git push"
#continue_move_files=true

stop_git_push=false
#stop_git_push=true # avoid large transfers

set -e
set -x

# check dependencies
command -v git
command -v head # coreutils
command -v unbuffer # expect

function get_dir() {
  local prefix=$1
  local depth=$2
  dir=
  for d in $(seq 1 $depth); do
    dir+=$prefix-$d/
  done
  echo $dir
}

if ! $continue_move_files; then
# mkdir fails if dir exists
mkdir $repo
fi

cd $repo

if ! $continue_move_files; then

git init
git remote add origin $remote

echo "test" >readme.txt
git add readme.txt
git commit -m "add readme.txt"

# disable delta compression
if $disable_delta_compression; then
  echo "*$file_extension -delta" >.gitattributes
  git add .gitattributes
  git commit -m "add .gitattributes"
fi

while true; do # retry loop
  # force: replace old remote branch
  git push origin -u main --force && break
  echo "git push failed -> retrying"
  sleep 10
done

# create files
for ((file_id=0; file_id<num_files; file_id++)); do
  olddir=$(get_dir olddir-$file_id $olddir_depth)
  oldname=oldname-$file_id$file_extension
  oldpath=$const_path_prefix$olddir$oldname
  mkdir -p $(dirname $oldpath)
  # FIXME mkdir
  if $use_text_files; then
    cat /dev/urandom | base64 | head -c$file_size >$oldpath
  else
    cat /dev/urandom | head -c$file_size >$oldpath
  fi
  git add $oldpath
done
git commit -m "add oldname*"
echo "expected: push $transfer_size_mega MByte"
# Writing objects: 100% (12/12), 10.00 MiB | 789.00 KiB/s, done.
while true; do # retry loop
  git push origin -u main && break
  echo "git push failed -> retrying"
  sleep 10
done

fi # end of: if ! $continue_move_files

const_path_prefix_depth=$(echo "$const_path_prefix" | tr -c -d / | wc -c)

# move files
# FIXME expected_num_transfer_trees is wrong in some cases
expected_num_transfer_trees=0
wrong_num_transfer_trees=0
for ((file_id=0; file_id<num_files; file_id++)); do
  olddir=$(get_dir olddir-$file_id $olddir_depth)
  oldname=oldname-$file_id$file_extension
  oldpath=$const_path_prefix$olddir$oldname
  newdir=$(get_dir newdir-$file_id $newdir_depth)
  if $change_basename; then
    newname=newname-$file_id$file_extension
    expected_num_transfer_trees=$((expected_num_transfer_trees + const_path_prefix_depth + newdir_depth))
    # +1 for the extra blob object
    wrong_num_transfer_trees=$((wrong_num_transfer_trees + const_path_prefix_depth + newdir_depth + 1))
  else
    newname=$oldname
    # -1 because the last tree stays constant
    expected_num_transfer_trees=$((expected_num_transfer_trees + const_path_prefix_depth + newdir_depth - 1))
    # +1 for the extra blob object
    wrong_num_transfer_trees=$((wrong_num_transfer_trees + const_path_prefix_depth + newdir_depth + 1 - 1))
  fi
  newpath=$const_path_prefix$newdir$newname
  mkdir -p $(dirname $newpath)
  case "$move_or_copy" in
    move)
      git mv $oldpath $newpath
      ;;
    copy)
      cp $oldpath $newpath
      git add $newpath
      ;;
  esac
done
# +1 for the root tree object
# +1 for the commit object
expected_num_transfer_objects=$((expected_num_transfer_trees + 2))
wrong_num_transfer_objects=$((wrong_num_transfer_trees + 2))
case "$move_or_copy" in
  move)
    git commit -m "mv oldname* newname*"
    ;;
  copy)
    git commit -m "cp oldname* newname*"
    ;;
esac
echo "expected: push about 1 KByte"
echo "expected_num_transfer_objects: $expected_num_transfer_objects"
echo "wrong_num_transfer_objects: $wrong_num_transfer_objects"

# Writing objects: 100% (2/2), 388 bytes | 388.00 KiB/s, done.
# this should take a few seconds to upload 1KB
set +x
found_transfer=false
while read -r -d$'\r' line; do
  echo "$line"
  $found_transfer && continue
  [[ "${line:0:16}" != "Writing objects:" ]] && continue
  # line: 'Writing objects:  11% (5/42), 5.03 MiB | 1.86 MiB/s'
  echo "# writing objects line: ${line@Q}"
  num_transfer_objects=$(echo "$line" | sed -E 's|^Writing objects.*?% \([0-9]+/([0-9]+)\).*$|\1|')
  echo "# num_transfer_objects: $num_transfer_objects"
  if (( num_transfer_objects == expected_num_transfer_objects )); then
    echo "# pass: $num_transfer_objects == $expected_num_transfer_objects"
  else
    echo "# fail: $num_transfer_objects != $expected_num_transfer_objects"
  fi
  found_transfer=true
  if $stop_git_push; then
    echo "stopping git push"; break
  fi
done < <(
  while true; do # retry loop
    unbuffer git push origin -u main 2>&1 && break
    echo "git push failed -> retrying" >&2
    sleep 10
  done
)
