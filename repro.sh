#!/usr/bin/env bash

owner=milahu
repo=git-bug-git-mv-wasteful-transfer-test

remote=https://github.com/$owner/$repo

echo "todo? create new repo \"$repo\" at https://github.com/new"



# this was my original use case
#num_files=275; file_size_mega=20

# ok, this works as expected
#num_files=10; file_size_mega=1

# ok, this works as expected
#num_files=10; file_size_mega=20

# work in progress...
num_files=10; file_size_mega=100

# TODO find the limit of git or github
# when does it start failing to dedupe the blob objects?

# FIXME at some point, "git push" will start failing
cat >/dev/null <<'EOF'
  $ git push
  Enumerating objects: 293, done.
  Counting objects: 100% (293/293), done.
  Delta compression using up to 4 threads
  Compressing objects: 100% (14/14), done.
  error: RPC failed; HTTP 500 curl 22 The requested URL returned error: 500
  send-pack: unexpected disconnect while reading sideband packet
  Writing objects: 100% (290/290), 5.34 GiB | 2.89 MiB/s, done.
  Total 290 (delta 5), reused 0 (delta 0), pack-reused 0
  fatal: the remote end hung up unexpectedly
  Everything up-to-date
EOF



set -e
set -x

# mkdir fails if dir exists
mkdir $repo

cd $repo

git init
git remote add origin $remote

# disable delta compression
echo "*.bin -delta" >.gitattributes
git add .gitattributes
git commit -m init

# force: replace old remote branch
git push origin -u main --force

transfer_size_mega=$((num_files * file_size_mega))

file_size=$((file_size_mega * 1024 * 1024))

# create files
for ((file_id=0; file_id<num_files; file_id++)); do
  olddir=oldpath-$file_id/oldto-$file_id/olddir-$file_id
  mkdir -p $olddir
  oldpath=$olddir/oldname-$file_id.bin
  head -c$file_size /dev/urandom >$oldpath
  git add $oldpath
done
git commit -m "add oldname*"
echo "expected: push $transfer_size_mega MByte"
# Writing objects: 100% (12/12), 10.00 MiB | 789.00 KiB/s, done.
git push origin -u main

# move files
for ((file_id=0; file_id<num_files; file_id++)); do
  newdir=newpath-$file_id/newto-$file_id/newdir-$file_id
  mkdir -p $newdir
  oldpath=$olddir/oldname-$file_id.bin
  newpath=$newdir/newname-$file_id.bin
  git mv $oldpath $newpath
done
git commit -m "mv oldname* newname*"
echo "expected: push about 1 KByte"
# Writing objects: 100% (2/2), 388 bytes | 388.00 KiB/s, done.
git push origin -u main
