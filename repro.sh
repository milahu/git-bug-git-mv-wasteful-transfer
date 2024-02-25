#!/usr/bin/env bash

owner=milahu
repo=git-bug-git-mv-wasteful-transfer-test

remote=https://github.com/$owner/$repo

echo "todo? create new repo \"$repo\" at https://github.com/new"



# this was my original use case
#num_files=275; file_size_mega=20

# no. this works as expected
#num_files=10; file_size_mega=1

# no. this works as expected
#num_files=10; file_size_mega=20

# yes. this fails to dedupe "git mv"
#num_files=10; file_size_mega=100
cat >/dev/null <<'EOF'
  remote: warning: See https://gh.io/lfs for more information.
  remote: warning: File oldpath-4/oldto-4/olddir-4/oldname-4.bin is 100.00 MB; this is larger than GitHub's recommended maximum file size of 50.00 MB
  remote: warning: GH001: Large files detected. You may want to try Git Large File Storage - https://git-lfs.github.com.

  expected: push 1000 MByte
  + git push origin -u main
  Enumerating objects: 43, done.
  Counting objects: 100% (43/43), done.
  Delta compression using up to 4 threads
  Compressing objects: 100% (2/2), done.
  Writing objects: 100% (42/42), 1000.08 MiB | 466.00 KiB/s, done.
  Total 42 (delta 0), reused 0 (delta 0), pack-reused 0

  expected: push about 1 KByte
  + git push origin -u main
  Enumerating objects: 43, done.
  Counting objects: 100% (43/43), done.
  Delta compression using up to 4 threads
  Compressing objects: 100% (2/2), done.
  Writing objects: 100% (42/42), 1000.08 MiB | 1.56 MiB/s, done.
  Total 42 (delta 0), reused 0 (delta 0), pack-reused 0
EOF

# work in progress ...
num_files=50; file_size_mega=20

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

transfer_size_mega=$((num_files * file_size_mega))

file_size=$((file_size_mega * 1024 * 1024))

continue_move_files=false
# continue an interrupted run after the first "git push"
#continue_move_files=true

set -e
set -x

if ! $continue_move_files; then
# mkdir fails if dir exists
mkdir $repo
fi

cd $repo

if ! $continue_move_files; then

git init
git remote add origin $remote

# disable delta compression
echo "*.bin -delta" >.gitattributes
git add .gitattributes
git commit -m init

# force: replace old remote branch
git push origin -u main --force

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

fi # end of: if ! $continue_move_files

# move files
for ((file_id=0; file_id<num_files; file_id++)); do
  olddir=oldpath-$file_id/oldto-$file_id/olddir-$file_id
  oldpath=$olddir/oldname-$file_id.bin
  newdir=newpath-$file_id/newto-$file_id/newdir-$file_id
  newpath=$newdir/newname-$file_id.bin
  mkdir -p $newdir
  git mv $oldpath $newpath
done
git commit -m "mv oldname* newname*"
echo "expected: push about 1 KByte"
# Writing objects: 100% (2/2), 388 bytes | 388.00 KiB/s, done.
git push origin -u main
