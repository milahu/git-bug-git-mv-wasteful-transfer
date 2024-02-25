#!/usr/bin/env bash

tempdir=$(mktemp -d /run/user/$UID/git-mv-bug.XXXXXXXXXX)
cd $tempdir

good_cases=(
  # change basename
  "path_a=file_a; path_b=file_b"
  "path_a=dir/file_a; path_b=dir/file_b"
  # change dirname
  "path_a=dir_a/file; path_b=dir_b/file"
  # move the file down
  "path_a=file; path_b=dir/file"
  "path_a=file; path_b=dir1/dir2/file"
  "path_a=file; path_b=dir1/dir2/dir3/file"
  # move the file down and change basename
  "path_a=file_a; path_b=dir/file_b"
  "path_a=file_a; path_b=dir1/dir2/file_b"
  "path_a=file_a; path_b=dir1/dir2/dir3/file_b"
)

bad_cases=(
  # move the file up
  "path_a=dir/file; path_b=file"
  "path_a=dir1/dir2/file; path_b=file"
  "path_a=dir1/dir2/dir3/file; path_b=file"
  # move the file up and change basename
  "path_a=dir/file_a; path_b=file_b"
  "path_a=dir1/dir2/file_a; path_b=file_b"
  "path_a=dir1/dir2/dir3/file_a; path_b=file_b"
  # change 2 dirnames
  "path_a=dir1a/dir2a/file; path_b=dir1b/dir2b/file"
  # change 1 dirname and basename
  "path_a=dir1a/file_a; path_b=dir1b/file_b"
)

function git_pull() {
  unbuffer git -C $dst_repo pull file://$src_repo main \
  2>&1 | tr $'\r' $'\n' | grep -o -E "Unpacking objects.*done\." | cut -d' ' -f5-6
}

# the file size must be much larger than the tree and commit objects
# which have about 500 bytes, so the 500 bytes disappear by rounding
# example: 1.000500 MB -> 1.00 MB
file_size=$((1 * 1024 * 1024))

for test_case in "${good_cases[@]}" "${bad_cases[@]}"; do
  src_repo=$PWD/src_repo; dst_repo=$PWD/dst_repo
  mkdir -p $src_repo; mkdir -p $dst_repo
  git -C $src_repo init -q; git -C $dst_repo init -q
  eval "$test_case"
  mkdir -p $src_repo/$(dirname $path_a)
  mkdir -p $src_repo/$(dirname $path_b)
  cat /dev/urandom | head -c$file_size >$src_repo/$path_a
  git -C $src_repo add $path_a
  git -C $src_repo commit -m "add file" -q
  transfer_size_1=$(git_pull)
  git -C $src_repo mv $path_a $path_b
  git -C $src_repo commit -m "mv file" -q
  transfer_size_2=$(git_pull)
  if [[ "$transfer_size_1" == "$transfer_size_2" ]]
  then echo "FAIL: $transfer_size_1 == $transfer_size_2 # $test_case"
  else echo "pass: $transfer_size_1 != $transfer_size_2 # $test_case"
  fi
  rm -rf $src_repo; rm -rf $dst_repo
done

cd ..
rm -rf $tempdir
