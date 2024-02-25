#!/usr/bin/env bash

# no. this works as expected
#olddir_depth=0; newdir_depth=$olddir_depth

# yes. this fails to dedupe "git mv"
olddir_depth=1; newdir_depth=$olddir_depth



owner=milahu
repo=git-bug-git-mv-wasteful-transfer-test

remote=https://github.com/$owner/$repo

echo "todo? create new repo \"$repo\" at https://github.com/new"

# no effect
num_files=1; file_size_mega=1

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
  [ -n "$olddir" ] && mkdir -p $olddir
  oldpath=${olddir}oldname-$file_id$file_extension
  head -c$file_size /dev/urandom >$oldpath
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

# move files
# 2 = commit object + root tree object
expected_num_transfer_objects=2
wrong_num_transfer_objects=2
for ((file_id=0; file_id<num_files; file_id++)); do
  olddir=$(get_dir olddir-$file_id $olddir_depth)
  oldpath=${olddir}oldname-$file_id$file_extension
  newdir=$(get_dir newdir-$file_id $newdir_depth)
  expected_num_transfer_objects=$((expected_num_transfer_objects + newdir_depth))
  # +1 for the extra blob object
  wrong_num_transfer_objects=$((wrong_num_transfer_objects + newdir_depth + 1))
  newpath=${newdir}newname-$file_id$file_extension
  [ -n "$newdir" ] && mkdir -p $newdir
  git mv $oldpath $newpath
done
git commit -m "mv oldname* newname*"
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
  echo "stopping git push"; break
done < <(
  while true; do # retry loop
    unbuffer git push origin -u main 2>&1 && break
    echo "git push failed -> retrying" >&2
    sleep 10
  done
)
